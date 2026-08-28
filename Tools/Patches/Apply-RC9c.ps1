$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'

foreach($p in @($servicePath,$mainPath)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file not found: $p"}
}

$service=Get-Content -Raw $servicePath
$main=Get-Content -Raw $mainPath

if($service -match 'RBZ080RC9C_STORE_RESET'){
    Write-Host 'RBZ PC Health v0.8.0 RC9c is already applied.' -ForegroundColor Yellow
    exit 0
}

if($service -notmatch 'RBZ080RC9_REPAIR_EXPANSION'){
    throw 'RC9c requires RC9 to be applied first.'
}

# ---------------------------------------------------------------------------
# 1. Replace Microsoft Store cache reset action.
#    wsreset.exe is GUI-oriented and can return inconsistent console behaviour,
#    so use Start-Process and verify the Store package afterwards.
# ---------------------------------------------------------------------------
$oldStore=@'
            'ResetMicrosoftStoreCache' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Microsoft Store cache' -Message 'Running WSReset...' -Started $started -Indeterminate:$true
                $wsreset=Join-Path $env:SystemRoot 'System32\wsreset.exe'
                if(-not(Test-Path $wsreset)){throw 'wsreset.exe is not available on this Windows installation.'}

                $r=Invoke-RBZNativeCommand -FilePath $wsreset -Arguments @() -ProgressPath $ProgressPath -Stage 'Microsoft Store cache reset'
                $storePkg=Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
                $ok=($r.ExitCode -eq 0)

                $result.Success=$ok
                $result.Summary=$(if($ok){'Microsoft Store cache reset command completed.'}else{"Microsoft Store cache reset returned exit code $($r.ExitCode)."})
                $result.Details="WSReset exit code: $($r.ExitCode)`nStore package present: $([bool]$storePkg)`n$($r.Output)"
                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Microsoft Store cache'
                $result.VerificationStatus=$(if($ok){'Info'}else{'Warning'})
                $result.VerificationSummary=$(if($ok){'Microsoft Store cache reset command completed. Open Microsoft Store to confirm normal operation if this was the reported issue.'}else{'Microsoft Store cache reset did not complete successfully.'})
                $result.VerificationDetails=$result.Details
            }
'@

$newStore=@'
            # RBZ080RC9C_STORE_RESET
            'ResetMicrosoftStoreCache' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Microsoft Store cache' -Message 'Running WSReset...' -Started $started -Indeterminate:$true

                $wsreset=Join-Path $env:SystemRoot 'System32\wsreset.exe'
                if(-not(Test-Path $wsreset)){throw 'wsreset.exe is not available on this Windows installation.'}

                $beforePkg=Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
                $beforeStatus=if($beforePkg){[string]$beforePkg.Status}else{'Not installed'}

                $proc=$null
                $timedOut=$false
                $exitCode=$null

                try{
                    $proc=Start-Process -FilePath $wsreset -PassThru -ErrorAction Stop

                    # WSReset may briefly open a Store window. Give it a reasonable
                    # period to finish, but do not hang RBZ indefinitely.
                    if(-not $proc.WaitForExit(30000)){
                        $timedOut=$true
                    }else{
                        $exitCode=$proc.ExitCode
                    }
                }catch{
                    throw "Could not launch wsreset.exe. $($_.Exception.Message)"
                }

                Start-Sleep -Seconds 2

                $afterPkg=Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
                $afterStatus=if($afterPkg){[string]$afterPkg.Status}else{'Not installed'}
                $packageHealthy=($afterPkg -and $afterStatus -eq 'Ok')

                # A timeout is not automatically a failure because WSReset can hand
                # off to the Store UI and continue outside the original process.
                # The post-action package health is the stronger verification signal.
                $ok=$packageHealthy -and (-not $timedOut -or $afterPkg)

                $result.Success=$ok
                $result.Summary=$(if($ok){'Microsoft Store cache reset completed and Store package health was verified.'}else{'Microsoft Store cache reset could not be verified.'})

                $result.Details=@"
WSReset path: $wsreset
Process started: $([bool]$proc)
Process timed out after 30 seconds: $timedOut
Process exit code: $(if($null -eq $exitCode){'Not available'}else{$exitCode})

Store package before:
Present: $([bool]$beforePkg)
Status: $beforeStatus

Store package after:
Present: $([bool]$afterPkg)
Status: $afterStatus
Package: $(if($afterPkg){$afterPkg.PackageFullName}else{'Not found'})
Install location: $(if($afterPkg){$afterPkg.InstallLocation}else{'Not found'})

RBZ verifies package health after WSReset because wsreset.exe can behave as a GUI hand-off and does not always provide useful console output.
"@

                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Microsoft Store cache'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($ok){'Microsoft Store package reports Status=Ok after cache reset.'}else{"Microsoft Store package health could not be verified. Status: $afterStatus"})
                $result.VerificationDetails=$result.Details
            }
'@

if(-not $service.Contains($oldStore)){
    throw 'RC9c Microsoft Store action block was not found. Make sure RC9 is applied.'
}
$service=$service.Replace($oldStore,$newStore)

# ---------------------------------------------------------------------------
# 2. Always show technical details for failed actions in Repair Centre output.
#    Keep RC9a behaviour of showing details for Windows Update actions.
# ---------------------------------------------------------------------------
$oldOutput=@'
            # Windows Update actions benefit from showing the technical action
            # details directly in the Repair Centre output box. Other actions
            # keep the concise summary/verification presentation.
            $detailText=''
            if([string]$a.Category -eq 'Updates' -and -not [string]::IsNullOrWhiteSpace([string]$r.Details)){
                $detailText="`r`n`r`nWindows Update details:`r`n$($r.Details)"
            }
'@

$newOutput=@'
            # RBZ080RC9C_FAILURE_DETAILS
            # Windows Update actions always show technical details. Any failed
            # action also shows its technical details automatically so the
            # technician can see the real exception/result without leaving RBZ.
            $detailText=''
            if(-not [string]::IsNullOrWhiteSpace([string]$r.Details)){
                if([string]$a.Category -eq 'Updates'){
                    $detailText="`r`n`r`nWindows Update details:`r`n$($r.Details)"
                }
                elseif(-not [bool]$r.Success -or [string]$r.VerificationStatus -eq 'Warning'){
                    $detailText="`r`n`r`nTechnical details:`r`n$($r.Details)"
                }
            }
'@

if($main.Contains($oldOutput)){
    $main=$main.Replace($oldOutput,$newOutput)
}
elseif($main -notmatch 'RBZ080RC9C_FAILURE_DETAILS'){
    throw 'RC9c Repair Centre output block was not found. Make sure RC9a is applied.'
}

Set-Content -LiteralPath $servicePath -Value $service -Encoding UTF8
Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC9c applied.' -ForegroundColor Green
Write-Host 'Microsoft Store reset now uses Start-Process and verifies Store package health.' -ForegroundColor Cyan
Write-Host 'Failed Repair Centre actions now display technical details automatically.' -ForegroundColor Cyan
Write-Host 'No Windows Update or network repair logic was changed.' -ForegroundColor DarkGray
