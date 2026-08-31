$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bootstrapPath=Join-Path $repoRoot 'bootstrap-rc.ps1'
$settingsPath=Join-Path $repoRoot 'Config\settings.json'

if(-not(Test-Path -LiteralPath $bootstrapPath)){throw "Required file not found: $bootstrapPath"}
if(-not(Test-Path -LiteralPath $settingsPath)){throw "Required file not found: $settingsPath"}

$current=Get-Content -LiteralPath $bootstrapPath -Raw
if($current -match 'RC11: every run gets its own narrowly-scoped temporary session folder'){
    Write-Host 'RBZ PC Health v0.8.0 RC11 is already applied.' -ForegroundColor Yellow
    exit 0
}

$required=@(
    '$Owner = ''rbznet''',
    '$Repo = ''RBZTechSolutions''',
    '$Branch = ''main''',
    'RBZHealth.ps1',
    'RBZ-PC-Health-RC'
)
foreach($fragment in $required){
    if(-not $current.Contains($fragment)){
        throw "RC11 baseline validation failed. Missing expected RC bootstrap capability: $fragment"
    }
}

$replacement=@'
# RBZ PC Health RC bootstrapper
# Test channel: downloads the current GitHub main branch and launches RBZ PC Health.
# Stable bootstrap.ps1 remains release-based.

$Owner = 'rbznet'
$Repo = 'RBZTechSolutions'
$Branch = 'main'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Assert-RBZAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity

    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        throw 'Open PowerShell as Administrator and run the command again.'
    }
}

function Preserve-RBZReports {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    try {
        $source = Join-Path $RepositoryRoot 'Reports'
        if(-not (Test-Path -LiteralPath $source)){ return }

        $reportFiles = @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)
        if($reportFiles.Count -eq 0){ return }

        $documents = [Environment]::GetFolderPath('MyDocuments')
        if([string]::IsNullOrWhiteSpace($documents)){
            $documents = Join-Path $env:USERPROFILE 'Documents'
        }

        $destination = Join-Path $documents 'RBZ PC Health Reports\RC'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        foreach($file in $reportFiles){
            $relative = $file.FullName.Substring($source.Length).TrimStart('\')
            $target = Join-Path $destination $relative
            $targetParent = Split-Path -Parent $target
            if(-not (Test-Path -LiteralPath $targetParent)){
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }

        Write-Host "Preserved $($reportFiles.Count) report file(s): $destination" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "RBZ report preservation failed: $($_.Exception.Message)"
    }
}

function Remove-RBZSessionFolder {
    param([Parameter(Mandatory)][string]$SessionRoot)

    if(-not (Test-Path -LiteralPath $SessionRoot)){ return }

    try {
        Remove-Item -LiteralPath $SessionRoot -Recurse -Force -ErrorAction Stop
        Write-Host "Cleaned RC session folder: $SessionRoot" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "RBZ session cleanup could not remove '$SessionRoot': $($_.Exception.Message)"
    }
}

function Remove-RBZAbandonedSessions {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [int]$OlderThanHours = 24
    )

    if(-not (Test-Path -LiteralPath $BasePath)){ return }
    $cutoff = (Get-Date).AddHours(-1 * [math]::Abs($OlderThanHours))

    foreach($folder in @(Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue)){
        $marker = Join-Path $folder.FullName '.rbz-session'
        if(-not (Test-Path -LiteralPath $marker)){ continue }
        if($folder.LastWriteTime -gt $cutoff){ continue }

        try {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "Removed abandoned RC session: $($folder.Name)" -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "Could not remove abandoned RC session '$($folder.FullName)': $($_.Exception.Message)"
        }
    }
}

Assert-RBZAdministrator

# RC11: every run gets its own narrowly-scoped temporary session folder.
$tempBase = Join-Path $env:TEMP 'RBZ-PC-Health\RC'
$sessionId = [guid]::NewGuid().ToString('N')
$sessionRoot = Join-Path $tempBase $sessionId
$zipPath = Join-Path $sessionRoot 'RBZTechSolutions-main.zip'
$extractPath = Join-Path $sessionRoot 'package'
$sessionMarker = Join-Path $sessionRoot '.rbz-session'
$repoRoot = $null

New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
Remove-RBZAbandonedSessions -BasePath $tempBase -OlderThanHours 24

New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
Set-Content -LiteralPath $sessionMarker -Value (Get-Date).ToString('o') -Encoding ASCII -Force

$archiveUrl = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"

try {
    Write-Host "Downloading RBZ PC Health RC from GitHub branch '$Branch'..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing

    Write-Host 'Extracting RC package...' -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $entry = Get-ChildItem -LiteralPath $extractPath -Filter 'RBZHealth.ps1' -File -Recurse |
        Select-Object -First 1

    if(-not $entry){
        throw 'RBZHealth.ps1 was not found in the downloaded RC package.'
    }

    $repoRoot = Split-Path -Parent $entry.FullName

    $requiredPaths = @(
        (Join-Path $repoRoot 'Config\settings.json'),
        (Join-Path $repoRoot 'Modules'),
        (Join-Path $repoRoot 'Assets')
    )

    foreach($required in $requiredPaths){
        if(-not (Test-Path -LiteralPath $required)){
            throw "Downloaded RC package is incomplete. Missing: $required"
        }
    }

    try {
        $settings = Get-Content -LiteralPath (Join-Path $repoRoot 'Config\settings.json') -Raw | ConvertFrom-Json
        $version = [string]$settings.app.version
    }
    catch {
        $version = 'unknown'
    }

    Write-Host "RBZ PC Health RC downloaded successfully. Version: $version" -ForegroundColor Green
    Write-Host "Source: $Owner/$Repo [$Branch]" -ForegroundColor DarkGray
    Write-Host "Session: $sessionRoot" -ForegroundColor DarkGray
    Write-Host "Path: $repoRoot" -ForegroundColor DarkGray

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry.FullName

    if($LASTEXITCODE -and $LASTEXITCODE -ne 0){
        Write-Warning "RBZ PC Health exited with code $LASTEXITCODE."
    }
}
finally {
    if($repoRoot){
        Preserve-RBZReports -RepositoryRoot $repoRoot
    }

    Remove-RBZSessionFolder -SessionRoot $sessionRoot

    try {
        if((Test-Path -LiteralPath $tempBase) -and
           @(Get-ChildItem -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue).Count -eq 0){
            Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}
'@

Set-Content -LiteralPath $bootstrapPath -Value $replacement -Encoding UTF8

$settings=Get-Content -LiteralPath $settingsPath -Raw
if($settings -match '"cleanupAfterExit"\s*:\s*false'){
    $updated=[regex]::Replace($settings,'("cleanupAfterExit"\s*:\s*)false','$1true',1)
    Set-Content -LiteralPath $settingsPath -Value $updated -Encoding UTF8
}elseif($settings -notmatch '"cleanupAfterExit"\s*:\s*true'){
    throw 'RC11 could not locate bootstrap.cleanupAfterExit in Config\settings.json.'
}

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $bootstrapPath,[ref]$tokens,[ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $msg=($errors | ForEach-Object {"Line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
    throw "bootstrap-rc.ps1 parser check failed after RC11:`n$msg"
}

try{
    Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json | Out-Null
}catch{
    throw "Config\settings.json validation failed after RC11: $($_.Exception.Message)"
}

Write-Host 'RBZ PC Health v0.8.0 RC11 applied.' -ForegroundColor Green
Write-Host 'RC bootstrap now uses unique TEMP sessions and cleans them after RBZ exits.' -ForegroundColor Cyan
Write-Host 'Generated RC reports are preserved under Documents\RBZ PC Health Reports\RC.' -ForegroundColor Cyan
Write-Host 'bootstrap-rc.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
Write-Host 'Config\settings.json passed JSON validation.' -ForegroundColor Cyan
