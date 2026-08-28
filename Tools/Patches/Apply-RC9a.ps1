$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
if(-not(Test-Path $mainPath)){throw "Missing $mainPath"}

$main=Get-Content -Raw $mainPath

if($main -match 'RBZ080RC9A_UPDATE_OUTPUT'){
    Write-Host 'RC9a already applied.' -ForegroundColor Yellow
    exit 0
}

$old=@'
            $verifyText=$(if(-not [string]::IsNullOrWhiteSpace([string]$r.VerificationSummary)){"`r`nVerification: $($r.VerificationStatus) - $($r.VerificationSummary)"}else{''})
            $ActionLogBox.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n$($r.Summary)$verifyText`r`n`r`n")
'@

$new=@'
            # RBZ080RC9A_UPDATE_OUTPUT
            $verifyText=$(if(-not [string]::IsNullOrWhiteSpace([string]$r.VerificationSummary)){"`r`nVerification: $($r.VerificationStatus) - $($r.VerificationSummary)"}else{''})

            # Windows Update actions benefit from showing the technical action
            # details directly in the Repair Centre output box. Other actions
            # keep the concise summary/verification presentation.
            $detailText=''
            if([string]$a.Category -eq 'Updates' -and -not [string]::IsNullOrWhiteSpace([string]$r.Details)){
                $detailText="`r`n`r`nWindows Update details:`r`n$($r.Details)"
            }

            $ActionLogBox.AppendText(
                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                "$($r.Summary)$verifyText$detailText`r`n`r`n"
            )
'@

if(-not $main.Contains($old)){throw 'RC9a Repair Centre output marker not found.'}
$main=$main.Replace($old,$new)

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC9a applied.' -ForegroundColor Green
Write-Host 'Repair Centre now displays detailed Windows Update action information in the output box.' -ForegroundColor Cyan
Write-Host 'No repair logic was changed.' -ForegroundColor DarkGray
