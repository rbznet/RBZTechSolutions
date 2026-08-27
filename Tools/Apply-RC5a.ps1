$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$appPath=Join-Path $repoRoot 'RBZHealth.ps1'
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'

foreach($p in @($appPath,$servicePath)){
    if(-not(Test-Path $p)){throw "Required file not found: $p"}
}

$app=Get-Content -Raw $appPath
$svc=Get-Content -Raw $servicePath

if($app -notmatch 'RBZ080RC5_REPAIR_WORKFLOW'){
    throw 'RC5a requires the RC5 Repair Centre workflow to be applied first.'
}

if($svc -match 'RBZ080RC5A_NATIVE_EXITCODE'){
    Write-Host 'RBZ PC Health v0.8.0 RC5a already applied.' -ForegroundColor Yellow
    exit 0
}

# -------------------------------------------------------------------------
# SERVICE MODULE
# -------------------------------------------------------------------------

# Capture the native process exit code after WaitForExit + Refresh and never
# return a blank/null exit code.
$oldNative=@'
        $p.WaitForExit()
        $out=''
        if(Test-Path $stdout){$out += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
        if(Test-Path $stderr){$out += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}

        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Percent 100 -Message 'Finished.' -Started $started -Indeterminate:$false

        [pscustomobject]@{
            ExitCode=$p.ExitCode
            Output=$out.Trim()
            Elapsed=((Get-Date)-$started)
        }
'@

$newNative=@'
        $p.WaitForExit()
        $p.Refresh()

        # RBZ080RC5A_NATIVE_EXITCODE
        $nativeExitCode=1
        try{
            if($null -ne $p.ExitCode){
                $nativeExitCode=[int]$p.ExitCode
            }
        }catch{
            $nativeExitCode=1
        }

        $out=''
        if(Test-Path $stdout){$out += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
        if(Test-Path $stderr){$out += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}

        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Percent 100 -Message 'Command finished.' -Started $started -Indeterminate:$false

        [pscustomobject]@{
            ExitCode=$nativeExitCode
            Output=$out.Trim()
            Elapsed=((Get-Date)-$started)
        }
'@

if(-not $svc.Contains($oldNative)){throw 'RC5a: native-command completion block not found.'}
$svc=$svc.Replace($oldNative,$newNative)

# Replace Windows Time action with post-action source/status verification.
$oldTime=@'
            'WindowsTimeResync' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation' -Message 'Checking Windows Time service...' -Started $started -Indeterminate:$true
                $svc=Get-Service W32Time -ErrorAction Stop
                if($svc.StartType -eq 'Disabled'){throw 'Windows Time service is disabled. RBZ PC Health will not change a Disabled service automatically.'}
                if($svc.Status -ne 'Running'){Start-Service W32Time -ErrorAction Stop;Start-Sleep -Seconds 1}

                $r=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync','/rediscover') -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation'
                $source=(& w32tm.exe /query /source 2>&1 | Out-String).Trim()
                $status=(& w32tm.exe /query /status 2>&1 | Out-String).Trim()

                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'Windows Time resynchronisation completed successfully.'}else{"Windows Time resynchronisation returned exit code $($r.ExitCode)."})
                $result.Details="Resync output:`n$($r.Output)`n`nSource:`n$source`n`nStatus:`n$status"
                $result.VerificationCategory='System'
                $result.VerificationCheck='Windows Time synchronisation'
                $result.VerificationStatus=$(if($r.ExitCode -eq 0){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($r.ExitCode -eq 0){"Windows Time resynchronised. Source: $source"}else{'Windows Time resynchronisation did not complete successfully.'})
            }
'@

$newTime=@'
            'WindowsTimeResync' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation' -Message 'Checking Windows Time service...' -Started $started -Indeterminate:$true

                $timeService=Get-Service W32Time -ErrorAction Stop
                if($timeService.StartType -eq 'Disabled'){
                    throw 'Windows Time service is disabled. RBZ PC Health will not change a Disabled service automatically.'
                }

                if($timeService.Status -ne 'Running'){
                    Start-Service W32Time -ErrorAction Stop
                    Start-Sleep -Seconds 1
                }

                $r=Invoke-RBZNativeCommand `
                    -FilePath 'w32tm.exe' `
                    -Arguments @('/resync','/rediscover') `
                    -ProgressPath $ProgressPath `
                    -Stage 'Windows Time resynchronisation'

                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Verifying Windows Time' -Message 'Reading time source and synchronisation status...' -Started $started -Indeterminate:$true

                $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'

                $source=[string]$sourceQuery.Output
                $status=[string]$statusQuery.Output

                $sourceValid=(
                    $sourceQuery.ExitCode -eq 0 -and
                    -not [string]::IsNullOrWhiteSpace($source) -and
                    $source -notmatch '(?i)local cmos clock|free-running system clock'
                )

                $statusValid=(
                    $statusQuery.ExitCode -eq 0 -and
                    -not [string]::IsNullOrWhiteSpace($status) -and
                    $status -notmatch '(?im)^\s*Leap Indicator:\s*3'
                )

                $resyncCommandSucceeded=($r.ExitCode -eq 0)
                $verified=($resyncCommandSucceeded -and $sourceValid -and $statusValid)

                $result.Success=$verified

                if($verified){
                    $result.Summary='Windows Time resynchronisation completed and was verified.'
                    $result.VerificationStatus='Healthy'
                    $result.VerificationSummary="Windows Time is synchronised. Source: $source"
                }
                elseif(-not $resyncCommandSucceeded){
                    $result.Summary="Windows Time resynchronisation failed with exit code $($r.ExitCode)."
                    $result.VerificationStatus='Warning'
                    $result.VerificationSummary="Windows Time resynchronisation command failed. Source after attempt: $source"
                }
                else{
                    $result.Summary='Windows Time resynchronisation command completed, but synchronisation could not be verified.'
                    $result.VerificationStatus='Warning'
                    $result.VerificationSummary="Windows Time remains unverified after resync. Source: $source"
                }

                $result.Details=@"
Resync exit code: $($r.ExitCode)
Resync output:
$($r.Output)

Source query exit code: $($sourceQuery.ExitCode)
Source:
$source

Status query exit code: $($statusQuery.ExitCode)
Status:
$status
"@

                $result.VerificationCategory='System'
                $result.VerificationCheck='Windows Time synchronisation'
                $result.VerificationDetails=$result.Details
            }
'@

if(-not $svc.Contains($oldTime)){throw 'RC5a: Windows Time action block not found.'}
$svc=$svc.Replace($oldTime,$newTime)

# -------------------------------------------------------------------------
# APP / REPAIR CENTRE UI
# -------------------------------------------------------------------------

# Running-state bar is neutral blue rather than success green.
$startMarker=@'
            $ActionProgressBar.Value=0
            $ActionProgressBar.IsIndeterminate=$true
            $ActionProgressText.Text='Starting...'
'@
$startNew=@'
            $ActionProgressBar.Value=0
            $ActionProgressBar.Foreground='#2563EB'
            $ActionProgressBar.IsIndeterminate=$true
            $ActionProgressText.Text='Starting...'
'@
if(-not $app.Contains($startMarker)){throw 'RC5a: action progress start marker not found.'}
$app=$app.Replace($startMarker,$startNew)

# Result-state UI: green only when successful and verified; amber for warnings;
# red for failed action. 100% means execution finished, while text/colour states
# whether the result was good.
$finishMarker=@'
            $ActionProgressBar.IsIndeterminate=$false
            $ActionProgressBar.Value=100
            $ActionProgressText.Text=$r.Summary
            $ActionElapsedText.Text=((Get-Date)-$actionStarted).ToString('hh\:mm\:ss')
'@

$finishNew=@'
            $ActionProgressBar.IsIndeterminate=$false
            $ActionProgressBar.Value=100

            $verificationWarning=([string]$r.VerificationStatus -in @('Warning','Critical'))

            if([bool]$r.Success -and -not $verificationWarning){
                $ActionProgressBar.Foreground='#16A34A'
                $ActionProgressText.Text="Completed successfully - $($r.Summary)"
                $ActionStatusText.Text="Completed successfully: $($a.Name)"
            }
            elseif([bool]$r.Success -and $verificationWarning){
                $ActionProgressBar.Foreground='#D97706'
                $ActionProgressText.Text="Completed with warning - $($r.Summary)"
                $ActionStatusText.Text="Completed with warning: $($a.Name)"
            }
            else{
                $ActionProgressBar.Foreground='#DC2626'
                $ActionProgressText.Text="Failed - $($r.Summary)"
                $ActionStatusText.Text="Failed: $($a.Name)"
            }

            $ActionElapsedText.Text=((Get-Date)-$actionStarted).ToString('hh\:mm\:ss')
'@
if(-not $app.Contains($finishMarker)){throw 'RC5a: action progress result marker not found.'}
$app=$app.Replace($finishMarker,$finishNew)

# Shorter verification button label so it fits the existing 115px button.
$app=$app.Replace(
    "`$ScanButton.Content='Verify Repairs - Run Full Scan'",
    "`$ScanButton.Content='Verify Repairs'"
)

$app=$app.Replace(
    "use Verify Repairs - Run Full Scan.",
    "use Verify Repairs."
)

# -------------------------------------------------------------------------
# SAFE CANDIDATE PARSING / COMMIT
# -------------------------------------------------------------------------

$appTemp="$appPath.rc5a.tmp"
$svcTemp="$servicePath.rc5a.tmp"
Set-Content -LiteralPath $appTemp -Value $app -Encoding UTF8
Set-Content -LiteralPath $svcTemp -Value $svc -Encoding UTF8

foreach($candidate in @($appTemp,$svcTemp)){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($candidate,[ref]$tokens,[ref]$errors)|Out-Null

    if($errors.Count -gt 0){
        Remove-Item $appTemp,$svcTemp -Force -ErrorAction SilentlyContinue
        $message=($errors|ForEach-Object{"Line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
        throw "RC5a aborted. No production file was replaced because '$candidate' failed parsing:`n$message"
    }
}

Copy-Item $appPath "$appPath.v080rc5a.bak" -Force
Copy-Item $servicePath "$servicePath.v080rc5a.bak" -Force
Move-Item $appTemp $appPath -Force
Move-Item $svcTemp $servicePath -Force

Write-Host 'RBZ PC Health v0.8.0 RC5a repair result handling applied.' -ForegroundColor Green
Write-Host 'RBZHealth.ps1 and Service.psm1 candidate syntax checks passed.' -ForegroundColor Green
Write-Host 'Re-test Windows Time from Technician Priorities -> Repair Centre.' -ForegroundColor Green
