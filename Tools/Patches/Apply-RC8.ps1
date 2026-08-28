$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'
$configPath=Join-Path $repoRoot 'Config\settings.json'
if(-not(Test-Path $servicePath)){throw "Missing $servicePath"}
if(-not(Test-Path $configPath)){throw "Missing $configPath"}

$service=Get-Content -Raw $servicePath
$config=Get-Content -Raw $configPath
if($service -match 'RBZ080RC8_SAFE_REPAIRS'){Write-Host 'RC8 already applied.' -ForegroundColor Yellow;exit 0}

# Add new low-risk actions before TempCleanup.
$marker=@'
    if($Config.remediation.allowTempCleanup){
'@
$insert=@'
    # RBZ080RC8_SAFE_REPAIRS
    if($Config.remediation.allowFlushDnsCache){
        $actions.Add((New-RBZAction -Id 'FlushDnsCache' -Name 'Flush DNS resolver cache' -Category 'Network' -Risk 'Low' `
            -Description 'Clears the Windows DNS resolver cache. DNS servers and adapter configuration are not changed.'))
    }

    if($Config.remediation.allowRestartPrintSpooler){
        $actions.Add((New-RBZAction -Id 'RestartPrintSpooler' -Name 'Restart Print Spooler' -Category 'Windows' -Risk 'Low' `
            -Description 'Restarts the Windows Print Spooler and verifies that it returns to Running. Active print jobs may be interrupted.'))
    }

    if($Config.remediation.allowRestartWindowsUpdateServices){
        $actions.Add((New-RBZAction -Id 'RestartWindowsUpdateServices' -Name 'Restart Windows Update services' -Category 'Updates' -Risk 'Low' `
            -Description 'Restarts available Windows Update services without deleting update caches, history or policy.'))
    }

    if($Config.remediation.allowTempCleanup){
'@
if(-not $service.Contains($marker)){throw 'RC8 action insertion marker not found.'}
$service=$service.Replace($marker,$insert)

# Replace current Windows Time action with progressive verified repair.
$start=$service.IndexOf("            'WindowsTimeResync' {")
$end=$service.IndexOf("            'TempCleanup' {",$start)
if($start -lt 0 -or $end -lt 0){throw 'RC8 Windows Time block not found.'}

$newTime=@'
            'WindowsTimeResync' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation' -Message 'Capturing current state...' -Started $started -Indeterminate:$true
                $timeService=Get-Service W32Time -ErrorAction Stop
                if($timeService.StartType -eq 'Disabled'){throw 'Windows Time is Disabled. RBZ will not change a Disabled service automatically.'}
                if($timeService.Status -ne 'Running'){Start-Service W32Time -ErrorAction Stop;Start-Sleep -Seconds 1}

                $beforeSource=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                $beforeStatus=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                $beforePeers=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/peers') -Stage 'Windows Time peers'

                $first=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync') -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation'
                Start-Sleep -Seconds 2

                $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                $source=[string]$sourceQuery.Output;$status=[string]$statusQuery.Output
                $sourceValid=($sourceQuery.ExitCode -eq 0 -and $source -notmatch '(?i)local cmos clock|free-running system clock' -and -not [string]::IsNullOrWhiteSpace($source))
                $statusValid=($statusQuery.ExitCode -eq 0 -and $status -notmatch '(?im)^\s*Leap Indicator:\s*3' -and -not [string]::IsNullOrWhiteSpace($status))
                $verified=($sourceValid -and $statusValid)
                $fallbackOutput='Not required.'

                if(-not $verified){
                    Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time recovery' -Message 'Restarting Windows Time and rediscovering configured source...' -Started $started -Indeterminate:$true
                    Restart-Service W32Time -Force -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $fallback=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync','/rediscover') -ProgressPath $ProgressPath -Stage 'Windows Time rediscovery'
                    $fallbackOutput=$fallback.Output
                    Start-Sleep -Seconds 2
                    $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                    $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                    $source=[string]$sourceQuery.Output;$status=[string]$statusQuery.Output
                    $sourceValid=($sourceQuery.ExitCode -eq 0 -and $source -notmatch '(?i)local cmos clock|free-running system clock' -and -not [string]::IsNullOrWhiteSpace($source))
                    $statusValid=($statusQuery.ExitCode -eq 0 -and $status -notmatch '(?im)^\s*Leap Indicator:\s*3' -and -not [string]::IsNullOrWhiteSpace($status))
                    $verified=($sourceValid -and $statusValid)
                }

                $result.Success=$verified
                $result.Summary=$(if($verified){'Windows Time was resynchronised and verified.'}else{'Windows Time repair completed, but synchronisation could not be verified.'})
                $result.VerificationCategory='System'
                $result.VerificationCheck='Windows Time synchronisation'
                $result.VerificationStatus=$(if($verified){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($verified){"Windows Time is synchronised. Source: $source"}else{"Windows Time remains unsynchronised or unverified. Source: $source"})
                $result.Details=@"
Before source:
$($beforeSource.Output)

Before status:
$($beforeStatus.Output)

Peer state:
$($beforePeers.Output)

Initial resync:
$($first.Output)

Fallback:
$fallbackOutput

After source:
$source

After status:
$status

RBZ did not change the NTP server, registry settings or policy.
"@
                $result.VerificationDetails=$result.Details
            }

'@
$service=$service.Substring(0,$start)+$newTime+$service.Substring($end)

# Add implementations immediately before TempCleanup.
$implMarker="            'TempCleanup' {"
$impl=@'
            'FlushDnsCache' {
                $r=Invoke-RBZNativeCommand -FilePath 'ipconfig.exe' -Arguments @('/flushdns') -ProgressPath $ProgressPath -Stage 'Flush DNS resolver cache'
                $ok=($r.ExitCode -eq 0 -and $r.Output -match '(?i)successfully flushed|dns resolver cache')
                $result.Success=$ok
                $result.Summary=$(if($ok){'Windows DNS resolver cache was flushed successfully.'}else{'DNS cache flush could not be verified.'})
                $result.Details="Exit code: $($r.ExitCode)`n$($r.Output)"
                $result.VerificationCategory='Network';$result.VerificationCheck='DNS resolver cache'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }

            'RestartPrintSpooler' {
                $svc=Get-Service Spooler -ErrorAction Stop;$before=[string]$svc.Status
                Restart-Service Spooler -Force -ErrorAction Stop
                $svc.WaitForStatus('Running',[TimeSpan]::FromSeconds(15));$svc.Refresh()
                $ok=($svc.Status -eq 'Running')
                $result.Success=$ok;$result.Summary=$(if($ok){'Print Spooler restarted and returned to Running.'}else{'Print Spooler restart could not be verified.'})
                $result.Details="Before: $before`nAfter: $($svc.Status)"
                $result.VerificationCategory='Windows';$result.VerificationCheck='Print Spooler'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }

            'RestartWindowsUpdateServices' {
                $names=@('wuauserv','UsoSvc');$lines=[System.Collections.Generic.List[string]]::new();$ok=$true;$seen=0
                foreach($n in $names){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$lines.Add("$n : not installed");continue}
                    $before=[string]$svc.Status
                    try{
                        if($svc.Status -eq 'Running'){Restart-Service $n -Force -ErrorAction Stop}else{Start-Service $n -ErrorAction Stop}
                        Start-Sleep -Milliseconds 500;$svc=Get-Service $n -ErrorAction Stop;$after=[string]$svc.Status;$seen++
                        if($after -ne 'Running'){$ok=$false};$lines.Add("$n : $before -> $after")
                    }catch{$ok=$false;$lines.Add("$n : $before -> ERROR: $($_.Exception.Message)")}
                }
                if($seen -eq 0){$ok=$false}
                $result.Success=$ok;$result.Summary=$(if($ok){'Windows Update services were restarted and verified.'}else{'One or more Windows Update services could not be restarted or verified.'})
                $result.Details=($lines -join "`n")
                $result.VerificationCategory='Updates';$result.VerificationCheck='Windows Update services'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }

'@
$i=$service.IndexOf($implMarker)
if($i -lt 0){throw 'RC8 implementation marker not found.'}
$service=$service.Substring(0,$i)+$impl+$service.Substring($i)

# Config toggles.
$cm='                        "allowWindowsTimeResync":  true,'
$cr=@'
                        "allowWindowsTimeResync":  true,
                        "allowFlushDnsCache":  true,
                        "allowRestartPrintSpooler":  true,
                        "allowRestartWindowsUpdateServices":  true,
'@
if(-not $config.Contains($cm)){throw 'RC8 config marker not found.'}
$config=$config.Replace($cm,$cr)

Set-Content $servicePath -Value $service -Encoding UTF8
Set-Content $configPath -Value $config -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC8 applied.' -ForegroundColor Green
Write-Host 'Added verified DNS flush, Print Spooler restart and Windows Update service restart.' -ForegroundColor Cyan
Write-Host 'Enhanced Windows Time with Before -> Repair -> Verify and controlled fallback.' -ForegroundColor Cyan
Write-Host 'Network adapter/Winsock resets are deliberately excluded because they can drop RDP sessions.' -ForegroundColor DarkGray
