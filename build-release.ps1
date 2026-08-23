# Run from repository root to create release ZIP + SHA256 file.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$config=Get-Content -Raw (Join-Path $root 'Config\settings.json') | ConvertFrom-Json
$version=$config.app.version
$outDir=Join-Path $root 'dist'; if(Test-Path $outDir){Remove-Item $outDir -Recurse -Force}; New-Item -ItemType Directory $outDir|Out-Null
$zip=Join-Path $outDir "RBZ-PC-Health-$version.zip"
$items=Get-ChildItem $root | Where-Object Name -notin @('.git','dist','Reports')
Compress-Archive -Path $items.FullName -DestinationPath $zip -Force
$hash=(Get-FileHash $zip -Algorithm SHA256).Hash
"$hash  $(Split-Path $zip -Leaf)" | Set-Content -Encoding ASCII (Join-Path $outDir "RBZ-PC-Health-$version.sha256")
Write-Host "Created:`n$zip`n$hash"
