[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$destination = Join-Path $RepoRoot 'Docs\Deploy'
New-Item -ItemType Directory -Path $destination -Force | Out-Null

$files = @(Get-ChildItem -LiteralPath $RepoRoot -File -Filter 'DEPLOY-v0*.txt' -ErrorAction SilentlyContinue)

foreach($file in $files){
    Move-Item -LiteralPath $file.FullName -Destination (Join-Path $destination $file.Name) -Force
    Write-Host "Moved: $($file.Name) -> Docs\Deploy"
}

Write-Host "Deploy-note cleanup complete. Files moved: $($files.Count)"
