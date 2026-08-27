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

Assert-RBZAdministrator

$tempRoot = Join-Path $env:TEMP 'RBZ-PC-Health-RC'
$zipPath = Join-Path $tempRoot 'RBZTechSolutions-main.zip'
$extractPath = Join-Path $tempRoot 'package'

if(Test-Path -LiteralPath $tempRoot){
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$archiveUrl = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"

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

# Basic sanity checks so we do not launch a partial/incorrect archive.
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
Write-Host "Path: $repoRoot" -ForegroundColor DarkGray

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry.FullName

