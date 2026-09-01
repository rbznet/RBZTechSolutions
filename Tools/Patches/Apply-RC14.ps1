$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$health=Join-Path $repoRoot 'RBZHealth.ps1'
$builder=Join-Path $repoRoot 'build-release.ps1'

foreach($path in @($health,$builder)){
    if(-not(Test-Path -LiteralPath $path)){throw "Required file not found: $path"}
}

# ---- RBZHealth.ps1: remove latent invalid theme fallback statement ----
$healthText=Get-Content -LiteralPath $health -Raw
if($healthText -notmatch 'RBZ080RC14_THEME_FALLBACK_FIX'){
    $old="if(`$fallback -notin @('Light','Dark')){`$fallback='Light'`r`n=False}"
    if(-not $healthText.Contains($old)){
        $old="if(`$fallback -notin @('Light','Dark')){`$fallback='Light'`n=False}"
    }
    if(-not $healthText.Contains($old)){
        throw 'RC14 could not locate the malformed Get-RBZSavedTheme fallback block.'
    }

    $new=@'
# RBZ080RC14_THEME_FALLBACK_FIX
    if($fallback -notin @('Light','Dark')){$fallback='Light'}
'@.TrimEnd()

    $healthText=$healthText.Replace($old,$new)
    Set-Content -LiteralPath $health -Value $healthText -Encoding UTF8
}

# ---- build-release.ps1: final-package preflight and runtime-only staging ----
$buildText=Get-Content -LiteralPath $builder -Raw
if($buildText -notmatch 'RBZ080RC14_RELEASE_PREFLIGHT'){

$anchor=@'
$EntryPoint = Join-Path $RepoRoot 'RBZHealth.ps1'

if (-not (Test-Path $EntryPoint)) {
    throw "RBZHealth.ps1 was not found at repository root: $RepoRoot"
}
'@

$insert=@'
$EntryPoint = Join-Path $RepoRoot 'RBZHealth.ps1'

if (-not (Test-Path $EntryPoint)) {
    throw "RBZHealth.ps1 was not found at repository root: $RepoRoot"
}

# RBZ080RC14_RELEASE_PREFLIGHT
$SettingsPath = Join-Path $RepoRoot 'Config\settings.json'
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    throw "Config\settings.json was not found: $SettingsPath"
}

try {
    $Settings = (Get-Content -LiteralPath $SettingsPath -Raw) | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Config\settings.json is not valid JSON: $($_.Exception.Message)"
}

if ([string]$Settings.app.version -ne $Version) {
    throw "Release version mismatch. Requested $Version but Config\settings.json contains $($Settings.app.version)."
}

$RequiredRuntimeItems = @(
    'RBZHealth.ps1',
    'Config',
    'Modules',
    'Assets',
    'Reports'
)

foreach ($requiredItem in $RequiredRuntimeItems) {
    $requiredPath = Join-Path $RepoRoot $requiredItem
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required runtime item is missing: $requiredItem"
    }
}

# Parse-check every PowerShell runtime source file before packaging.
$PowerShellFiles = @(
    Get-Item -LiteralPath $EntryPoint
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'Modules') -File -Recurse |
        Where-Object Extension -in @('.ps1','.psm1')
)

foreach ($sourceFile in $PowerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $sourceFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object {
            "$($sourceFile.Name) line $($_.Extent.StartLineNumber): $($_.Message)"
        }) -join "`n"
        throw "PowerShell parser validation failed:`n$details"
    }
}
'@

if(-not $buildText.Contains($anchor)){
    throw 'RC14 could not locate the build-release entry-point validation block.'
}
$buildText=$buildText.Replace($anchor,$insert)

$oldStage=@'
# Files/folders that are source-control/build/development only and should not
# be shipped in the customer package.
$ExcludeDirectories = @(
    '.git',
    '.github',
    'dist'
)

$ExcludeFiles = @(
    '.gitignore',
    '.gitattributes'
)

$items = Get-ChildItem -LiteralPath $RepoRoot -Force

foreach ($item in $items) {
    if ($item.PSIsContainer -and $ExcludeDirectories -contains $item.Name) {
        continue
    }

    if (-not $item.PSIsContainer -and $ExcludeFiles -contains $item.Name) {
        continue
    }

    $destination = Join-Path $Stage $item.Name

    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
    }
}
'@

$newStage=@'
# Ship only the runtime payload required by the stable bootstrap/customer app.
# Development patches, deployment notes, build scripts, and bootstrap scripts
# remain in source control and are intentionally excluded from the release ZIP.
foreach ($itemName in $RequiredRuntimeItems) {
    $source = Join-Path $RepoRoot $itemName
    $destination = Join-Path $Stage $itemName

    if ((Get-Item -LiteralPath $source).PSIsContainer) {
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}
'@

if(-not $buildText.Contains($oldStage)){
    throw 'RC14 could not locate the existing build staging block.'
}
$buildText=$buildText.Replace($oldStage,$newStage)

$oldVerify=@'
if (-not (Test-Path (Join-Path $Stage 'RBZHealth.ps1'))) {
    throw 'Staged package does not contain RBZHealth.ps1.'
}
'@

$newVerify=@'
if (-not (Test-Path (Join-Path $Stage 'RBZHealth.ps1'))) {
    throw 'Staged package does not contain RBZHealth.ps1.'
}

foreach ($requiredItem in $RequiredRuntimeItems) {
    if (-not (Test-Path -LiteralPath (Join-Path $Stage $requiredItem))) {
        throw "Staged package is missing required runtime item: $requiredItem"
    }
}
'@

if(-not $buildText.Contains($oldVerify)){
    throw 'RC14 could not locate staged-package validation.'
}
$buildText=$buildText.Replace($oldVerify,$newVerify)

Set-Content -LiteralPath $builder -Value $buildText -Encoding UTF8
}

# Parse-check both changed scripts.
foreach($path in @($health,$builder)){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$errors
    ) | Out-Null

    if($errors.Count -gt 0){
        $message=($errors | ForEach-Object {
            "$(Split-Path $path -Leaf) line $($_.Extent.StartLineNumber): $($_.Message)"
        }) -join "`n"
        throw "RC14 parser check failed:`n$message"
    }
}

Write-Host 'RBZ PC Health v0.8.0 RC14 applied.' -ForegroundColor Green
Write-Host 'Fixed the latent theme fallback statement.' -ForegroundColor Cyan
Write-Host 'Release builder now validates version, runtime files, and PowerShell syntax.' -ForegroundColor Cyan
Write-Host 'Release ZIP staging is now runtime-only.' -ForegroundColor Cyan
Write-Host 'RBZHealth.ps1 and build-release.ps1 passed parser checks.' -ForegroundColor Cyan
