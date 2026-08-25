[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

# Resolve the repository root automatically.
# Works whether build-release.ps1 lives in the repository root
# or inside the Tools subfolder.
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'RBZHealth.ps1'))) {
        $RepoRoot = $PSScriptRoot
    }
    elseif ($PSScriptRoot) {
        $parent = Split-Path -Parent $PSScriptRoot
        if ($parent -and (Test-Path (Join-Path $parent 'RBZHealth.ps1'))) {
            $RepoRoot = $parent
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not (Test-Path $RepoRoot)) {
    throw "Repository root could not be resolved automatically. Pass -RepoRoot explicitly."
}

$RepoRoot = (Resolve-Path $RepoRoot).Path

$EntryPoint = Join-Path $RepoRoot 'RBZHealth.ps1'

if (-not (Test-Path $EntryPoint)) {
    throw "RBZHealth.ps1 was not found at repository root: $RepoRoot"
}

$Dist = Join-Path $RepoRoot 'dist'
$Stage = Join-Path $env:TEMP "RBZ-PC-Health-$Version-build"
$ZipName = "RBZ-PC-Health-$Version.zip"
$HashName = "RBZ-PC-Health-$Version.sha256"
$ZipPath = Join-Path $Dist $ZipName
$HashPath = Join-Path $Dist $HashName

New-Item -ItemType Directory -Path $Dist -Force | Out-Null

if (Test-Path $Stage) {
    Remove-Item $Stage -Recurse -Force
}
New-Item -ItemType Directory -Path $Stage -Force | Out-Null

Write-Host "Building RBZ PC Health v$Version" -ForegroundColor Cyan
Write-Host "Source: $RepoRoot"
Write-Host "Stage : $Stage"

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

if (-not (Test-Path (Join-Path $Stage 'RBZHealth.ps1'))) {
    throw 'Staged package does not contain RBZHealth.ps1.'
}

# Remove any release notes/scripts that should not recursively contain old
# packages. Docs and Tools are retained because they are small and useful.
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
if (Test-Path $HashPath) {
    Remove-Item $HashPath -Force
}

Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $ZipPath -CompressionLevel Optimal -Force

$hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()
"$hash  $ZipName" | Set-Content -LiteralPath $HashPath -Encoding ASCII

# Verify the hash file we just wrote.
$expected = ((Get-Content -Raw -LiteralPath $HashPath).Trim().Split(' ')[0]).ToUpperInvariant()
$actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToUpperInvariant()

if ($expected -ne $actual) {
    throw "Release verification failed. Expected $expected but calculated $actual."
}

$zipInfo = Get-Item $ZipPath

Write-Host ''
Write-Host 'Release package built successfully.' -ForegroundColor Green
Write-Host "ZIP    : $ZipPath"
Write-Host "SHA256 : $HashPath"
Write-Host "Hash   : $actual"
Write-Host ("Size   : {0:N2} MB" -f ($zipInfo.Length / 1MB))

Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
