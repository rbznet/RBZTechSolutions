$ErrorActionPreference='Stop'

# RBZ PC Health v0.8.0 RC9
# Repair Centre: Update, network and Store actions + conservative context mapping.

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'
$priorityPath=Join-Path $repoRoot 'Modules\Priority.psm1'
$configPath=Join-Path $repoRoot 'Config\settings.json'

foreach($p in @($servicePath,$priorityPath,$configPath)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file not found: $p"}
}

$service=Get-Content -Raw $servicePath
$priority=Get-Content -Raw $priorityPath
$config=Get-Content -Raw $configPath

if($service -match 'RBZ080RC9_REPAIR_EXPANSION'){
    Write-Host 'RBZ PC Health v0.8.0 RC9 is already applied.' -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# ACTION DEFINITIONS
# ---------------------------------------------------------------------------
$actionMarker=@'
    if($Config.remediation.allowTempCleanup){
'@

$actionInsert=@'
    # RBZ080RC9_REPAIR_EXPANSION
    if($Config.remediation.allowTriggerWindowsUpdateScan){
        $actions.Add((New-RBZAction -Id 'TriggerWindowsUpdateScan' -Name 'Trigger Windows Update scan' -Category 'Updates' -Risk 'Low' `
            -Description 'Requests a fresh Windows Update detection scan. The scan continues asynchronously; RBZ does not claim that updates were downloaded or installed.'))
    }

    if($Config.remediation.allowClearWindowsUpdateDownloadCache){
        $actions.Add((New-RBZAction -Id 'ClearWindowsUpdateDownloadCache' -Name 'Clear Windows Update download cache' -Category 'Updates' -Risk 'Medium' `
            -Description 'Stops update services, clears only SoftwareDistribution\Download, restarts services and verifies service recovery. Windows Update history and policy are not reset.'))
    }

    if($Config.remediation.allowRepairWindowsUpdateComponents){
        $actions.Add((New-RBZAction -Id 'RepairWindowsUpdateComponents' -Name 'Repair Windows Update components' -Category 'Updates' -Risk 'Medium' `
            -Description 'Resets SoftwareDistribution and Catroot2 by renaming them, then restarts Windows Update services. This is more invasive and should follow lower-risk update actions.'))
    }

    if($Config.remediation.allowResetNetworkStack){
        $actions.Add((New-RBZAction -Id 'ResetNetworkStack' -Name 'Reset Windows network stack' -Category 'Network' -Risk 'Medium' -RequiresRestart $true `
            -Description 'Runs Winsock and TCP/IP stack reset commands. A Windows restart is required and VPN/custom networking may need review afterwards.'))
    }

    if($Config.remediation.allowResetMicrosoftStoreCache){
        $actions.Add((New-RBZAction -Id 'ResetMicrosoftStoreCache' -Name 'Reset Microsoft Store cache' -Category 'Windows' -Risk 'Low' `
            -Description 'Runs the Windows Store cache reset tool. It does not uninstall Store applications.'))
    }

    if($Config.remediation.allowTempCleanup){
'@

if(-not $service.Contains($actionMarker)){throw 'RC9 action-definition marker not found.'}
$service=$service.Replace($actionMarker,$actionInsert)

# ---------------------------------------------------------------------------
# ACTION IMPLEMENTATIONS - insert before TempCleanup
# ---------------------------------------------------------------------------
$implMarker="            'TempCleanup' {"

$impl=@'
            'TriggerWindowsUpdateScan' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Trigger Windows Update scan' -Message 'Requesting fresh update detection...' -Started $started -Indeterminate:$true

                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                if($wu -and $wu.StartType -ne 'Disabled' -and $wu.Status -ne 'Running'){
                    Start-Service wuauserv -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }

                $methods=[System.Collections.Generic.List[string]]::new()
                $requested=$false
                $errors=[System.Collections.Generic.List[string]]::new()

                try{
                    $autoUpdate=New-Object -ComObject Microsoft.Update.AutoUpdate
                    $autoUpdate.DetectNow()
                    $methods.Add('Microsoft.Update.AutoUpdate.DetectNow')
                    $requested=$true
                }catch{
                    $errors.Add("COM DetectNow: $($_.Exception.Message)")
                }

                $uso=Join-Path $env:SystemRoot 'System32\UsoClient.exe'
                if(Test-Path $uso){
                    try{
                        $r=Invoke-RBZNativeCommand -FilePath $uso -Arguments @('StartScan') -ProgressPath $ProgressPath -Stage 'Windows Update StartScan'
                        $methods.Add("UsoClient StartScan (exit $($r.ExitCode))")
                        # UsoClient is asynchronous and often returns no useful output.
                        $requested=$true
                    }catch{
                        $errors.Add("UsoClient StartScan: $($_.Exception.Message)")
                    }
                }

                Start-Sleep -Seconds 2
                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceState=if($wu){[string]$wu.Status}else{'Unavailable'}

                $result.Success=$requested
                $result.Summary=$(if($requested){'Windows Update scan request was submitted.'}else{'Windows Update scan request could not be submitted.'})
                $result.Details=@"
Methods attempted:
$($methods -join "`n")

Errors:
$($errors -join "`n")

Windows Update service state: $serviceState

Windows Update detection continues asynchronously. This action does not mean that updates were downloaded or installed.
"@
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update scan request'
                $result.VerificationStatus=$(if($requested){'Info'}else{'Warning'})
                $result.VerificationSummary=$(if($requested){'A fresh Windows Update detection request was submitted.'}else{'A fresh Windows Update detection request could not be submitted.'})
                $result.VerificationDetails=$result.Details
            }

            'ClearWindowsUpdateDownloadCache' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Clear Windows Update download cache' -Message 'Stopping update services...' -Started $started -Indeterminate:$true

                $downloadPath=Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
                $services=@('bits','wuauserv')
                $log=[System.Collections.Generic.List[string]]::new()
                $stopped=[System.Collections.Generic.List[string]]::new()

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$log.Add("$n : not installed");continue}
                    if($svc.Status -eq 'Running'){
                        try{Stop-Service $n -Force -ErrorAction Stop;$stopped.Add($n);$log.Add("$n : stopped")}
                        catch{throw "Could not stop $n. $($_.Exception.Message)"}
                    }else{$log.Add("$n : already $($svc.Status)")}
                }

                $before=0L;$after=0L;$deleted=0;$skipped=0
                if(Test-Path $downloadPath){
                    try{
                        $sum=(Get-ChildItem $downloadPath -File -Recurse -Force -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
                        if($null -ne $sum){$before=[long]$sum}
                    }catch{}

                    foreach($item in @(Get-ChildItem $downloadPath -Force -ErrorAction SilentlyContinue)){
                        try{Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop;$deleted++}
                        catch{$skipped++}
                    }

                    try{
                        $sum=(Get-ChildItem $downloadPath -File -Recurse -Force -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
                        if($null -ne $sum){$after=[long]$sum}
                    }catch{}
                }

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if($svc -and $svc.StartType -ne 'Disabled'){
                        try{
                            if($svc.Status -ne 'Running'){Start-Service $n -ErrorAction Stop;Start-Sleep -Milliseconds 500}
                            $svc=Get-Service $n -ErrorAction Stop
                            $log.Add("$n : final $($svc.Status)")
                        }catch{$log.Add("$n : restart error - $($_.Exception.Message)")}
                    }
                }

                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceOk=($null -eq $wu -or $wu.StartType -eq 'Disabled' -or $wu.Status -eq 'Running')
                $recovered=[math]::Max(0,$before-$after)

                $result.BytesRecovered=$recovered
                $result.Success=($serviceOk -and $skipped -eq 0)
                $result.Summary=$(if($result.Success){"Windows Update download cache cleared. Approximately {0:N2} MB removed." -f ($recovered/1MB)}else{'Windows Update download cache cleanup completed with items requiring review.'})
                $result.Details="Path: $downloadPath`nItems removed: $deleted`nItems skipped: $skipped`nBytes before: $before`nBytes after: $after`n`n$($log -join "`n")"
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update download cache'
                $result.VerificationStatus=$(if($result.Success){'Healthy'}else{'Recommend'})
                $result.VerificationSummary=$result.Summary
                $result.VerificationDetails=$result.Details
            }

            'RepairWindowsUpdateComponents' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Repair Windows Update components' -Message 'Stopping Windows Update services...' -Started $started -Indeterminate:$true

                $services=@('bits','wuauserv','cryptsvc')
                $log=[System.Collections.Generic.List[string]]::new()
                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$log.Add("$n : not installed");continue}
                    if($svc.Status -eq 'Running'){
                        try{Stop-Service $n -Force -ErrorAction Stop;$log.Add("$n : stopped")}
                        catch{throw "Could not stop $n. $($_.Exception.Message)"}
                    }else{$log.Add("$n : already $($svc.Status)")}
                }

                $stamp=(Get-Date).ToString('yyyyMMdd-HHmmss')
                $targets=@(
                    [pscustomobject]@{Path=(Join-Path $env:SystemRoot 'SoftwareDistribution');Name="SoftwareDistribution.rbz-$stamp"},
                    [pscustomobject]@{Path=(Join-Path $env:SystemRoot 'System32\catroot2');Name="catroot2.rbz-$stamp"}
                )

                foreach($t in $targets){
                    if(Test-Path $t.Path){
                        $parent=Split-Path -Parent $t.Path
                        try{
                            Rename-Item -LiteralPath $t.Path -NewName $t.Name -ErrorAction Stop
                            $log.Add("$($t.Path) -> $(Join-Path $parent $t.Name)")
                        }catch{
                            throw "Could not reset $($t.Path). $($_.Exception.Message)"
                        }
                    }else{
                        $log.Add("$($t.Path) : not present")
                    }
                }

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if($svc -and $svc.StartType -ne 'Disabled'){
                        try{
                            Start-Service $n -ErrorAction Stop
                            Start-Sleep -Milliseconds 750
                            $svc=Get-Service $n -ErrorAction Stop
                            $log.Add("$n : final $($svc.Status)")
                        }catch{$log.Add("$n : restart error - $($_.Exception.Message)")}
                    }
                }

                Start-Sleep -Seconds 2
                $sdExists=Test-Path (Join-Path $env:SystemRoot 'SoftwareDistribution')
                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceOk=($null -eq $wu -or $wu.StartType -eq 'Disabled' -or $wu.Status -eq 'Running')
                $verified=($sdExists -and $serviceOk)

                $result.Success=$verified
                $result.Summary=$(if($verified){'Windows Update components were reset and service recovery was verified.'}else{'Windows Update component reset completed, but recovery could not be fully verified.'})
                $result.Details=($log -join "`n")
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update components'
                $result.VerificationStatus=$(if($verified){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$result.Summary
                $result.VerificationDetails=$result.Details
            }

            'ResetNetworkStack' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Windows network stack' -Message 'Resetting Winsock and TCP/IP...' -Started $started -Indeterminate:$true

                $winsock=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('winsock','reset') -ProgressPath $ProgressPath -Stage 'Winsock reset'
                $ip=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('int','ip','reset') -ProgressPath $ProgressPath -Stage 'TCP/IP reset'
                $ok=($winsock.ExitCode -eq 0 -and $ip.ExitCode -eq 0)

                $result.Success=$ok
                $result.RequiresRestart=$true
                $result.Summary=$(if($ok){'Windows network stack reset completed. Restart Windows to finish the repair.'}else{'One or more Windows network stack reset commands failed.'})
                $result.Details="Winsock exit: $($winsock.ExitCode)`n$($winsock.Output)`n`nTCP/IP exit: $($ip.ExitCode)`n$($ip.Output)"
                $result.VerificationCategory='Network'
                $result.VerificationCheck='Windows network stack'
                $result.VerificationStatus=$(if($ok){'Recommend'}else{'Warning'})
                $result.VerificationSummary=$(if($ok){'Network stack reset completed; a Windows restart is required before final verification.'}else{'Network stack reset did not complete successfully.'})
                $result.VerificationDetails=$result.Details
            }

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

$idx=$service.IndexOf($implMarker)
if($idx -lt 0){throw 'RC9 action implementation marker not found.'}
$service=$service.Substring(0,$idx)+$impl+$service.Substring($idx)

# ---------------------------------------------------------------------------
# CONFIG FLAGS
# ---------------------------------------------------------------------------
$configMarker='                        "allowRestartWindowsUpdateServices":  true,'
$configInsert=@'
                        "allowRestartWindowsUpdateServices":  true,
                        "allowTriggerWindowsUpdateScan":  true,
                        "allowClearWindowsUpdateDownloadCache":  true,
                        "allowRepairWindowsUpdateComponents":  true,
                        "allowResetNetworkStack":  true,
                        "allowResetMicrosoftStoreCache":  true,
'@
if(-not $config.Contains($configMarker)){throw 'RC9 settings marker not found.'}
$config=$config.Replace($configMarker,$configInsert)

# ---------------------------------------------------------------------------
# PRIORITY / CONTEXT MAPPING
# Keep conservative: map to the least invasive matching action first.
# ---------------------------------------------------------------------------
$oldUpdates=@'
    if($category -eq 'Updates' -or $text -match 'windows update|pending update'){
        $result.ActionName='Review and install Windows Updates'
        $result.ActionText='Open Windows Update, review pending/failed updates, install appropriate updates, restart if required, then run another RBZ scan.'
        $result.Guidance='The current Repair Centre does not have a dedicated Windows Update install/repair action, so this remains manual.'
        return [pscustomobject]$result
    }
'@

$newUpdates=@'
    # RBZ080RC9_CONTEXT_MAPPING
    if($category -eq 'Updates' -or $text -match 'windows update|pending update'){
        $result.ActionType='Repair Centre'

        if($text -match 'pending update|updates? available|pending updates'){
            $result.ActionId='TriggerWindowsUpdateScan'
            $result.ActionName='Trigger Windows Update scan'
            $result.ActionText='Open Repair Centre and request a fresh Windows Update detection scan.'
            $result.Guidance='RBZ submits the detection request but does not automatically download or install updates.'
        }
        elseif($text -match 'fail|error|recent update failures|failed update'){
            $result.ActionId='RestartWindowsUpdateServices'
            $result.ActionName='Restart Windows Update services'
            $result.ActionText='Open Repair Centre and try the low-risk Windows Update service restart before deeper cache/component resets.'
            $result.Guidance='RBZ maps update failures to the least invasive Repair Centre action first. Deeper update repair remains technician-selected.'
        }
        else{
            $result.ActionId='TriggerWindowsUpdateScan'
            $result.ActionName='Trigger Windows Update scan'
            $result.ActionText='Open Repair Centre and request a fresh Windows Update detection scan.'
            $result.Guidance='This is the least invasive Windows Update action and does not alter update policy.'
        }

        $result.CanOpenRepairCentre=$true
        return [pscustomobject]$result
    }
'@

if(-not $priority.Contains($oldUpdates)){throw 'RC9 Priority Updates mapping marker not found.'}
$priority=$priority.Replace($oldUpdates,$newUpdates)

$oldNetwork=@'
    if($category -eq 'Network'){
        $result.ActionName='Investigate network configuration'
        $result.ActionText='Use the adapter, gateway, DNS, TCP and TLS evidence to isolate local configuration, Wi-Fi/Ethernet, router, VPN, proxy or upstream problems before changing settings.'
        $result.Guidance='RC3 does not perform blanket Winsock/IP/DNS resets because those can disrupt managed or VPN configurations.'
        return [pscustomobject]$result
    }
'@

$newNetwork=@'
    if($category -eq 'Network'){
        if($text -match 'dns resolution|resolver|dns cache'){
            $result.ActionType='Repair Centre'
            $result.ActionId='FlushDnsCache'
            $result.ActionName='Flush DNS resolver cache'
            $result.ActionText='Open Repair Centre and review the low-risk DNS resolver cache flush action.'
            $result.CanOpenRepairCentre=$true
            $result.Guidance='RBZ maps DNS-resolution findings to cache flush only. It does not automatically reset adapters, DNS servers or the full network stack.'
        }else{
            $result.ActionName='Investigate network configuration'
            $result.ActionText='Use the adapter, gateway, DNS, TCP and TLS evidence to isolate local configuration, Wi-Fi/Ethernet, router, VPN, proxy or upstream problems before changing settings.'
            $result.Guidance='The Medium-risk network stack reset remains technician-selected because it can affect VPN/custom networking and requires a restart.'
        }
        return [pscustomobject]$result
    }
'@

if(-not $priority.Contains($oldNetwork)){throw 'RC9 Priority Network mapping marker not found.'}
$priority=$priority.Replace($oldNetwork,$newNetwork)

Set-Content -LiteralPath $servicePath -Value $service -Encoding UTF8
Set-Content -LiteralPath $priorityPath -Value $priority -Encoding UTF8
Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC9 applied.' -ForegroundColor Green
Write-Host 'Added Windows Update scan/cache/component repair, network stack reset and Microsoft Store cache reset.' -ForegroundColor Cyan
Write-Host 'Technician Priorities now maps update/DNS findings to conservative Repair Centre actions.' -ForegroundColor Cyan
Write-Host 'No action is auto-selected or auto-run.' -ForegroundColor DarkGray
