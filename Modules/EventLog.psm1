function Get-RBZRecentEvents {
    param(
        [string]$LogName,
        [datetime]$StartTime,
        [string[]]$ProviderName,
        [int[]]$Id
    )

    try {
        $filter=@{LogName=$LogName;StartTime=$StartTime}
        if($ProviderName -and $ProviderName.Count -gt 0){$filter.ProviderName=$ProviderName}
        if($Id -and $Id.Count -gt 0){$filter.Id=$Id}
        @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
    }
    catch {@()}
}

function Format-RBZEventDetails {
    param([object[]]$Events,[int]$Maximum=8)

    if(-not $Events -or $Events.Count -eq 0){return ''}

    $lines=[System.Collections.Generic.List[string]]::new()
    foreach($event in @($Events | Sort-Object TimeCreated -Descending | Select-Object -First $Maximum)){
        $message=[string]$event.Message
        if([string]::IsNullOrWhiteSpace($message)){$message='No event message was returned.'}
        $message=($message -replace "(`r`n|`n|`r)",' ' -replace '\s+',' ').Trim()
        if($message.Length -gt 260){$message=$message.Substring(0,260)+'...'}

        $lines.Add(('{0:yyyy-MM-dd HH:mm} | ID {1} | {2} | {3}' -f `
            $event.TimeCreated,$event.Id,$event.ProviderName,$message))
    }

    $lines -join "`n"
}

function Get-RBZEventLogFindings {
    param($Config)

    $out=[System.Collections.Generic.List[object]]::new()
    if(-not [bool]$Config.scan.eventLogSummary){return $out}

    $lookbackDays=[int]$Config.eventLog.lookbackDays
    if($lookbackDays -lt 1){$lookbackDays=7}
    $dumpLookback=[int]$Config.eventLog.minidumpLookbackDays
    if($dumpLookback -lt 1){$dumpLookback=30}
    $maxDetails=[int]$Config.eventLog.maxEventsInDetails
    if($maxDetails -lt 1){$maxDetails=8}
    $start=(Get-Date).AddDays(-$lookbackDays)

    # Unexpected shutdowns: high-value power/shutdown events only.
    $shutdownEvents=@()
    $shutdownEvents += Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('Microsoft-Windows-Kernel-Power') -Id @(41)
    $shutdownEvents += Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('EventLog') -Id @(6008)
    $shutdownEvents=@($shutdownEvents | Sort-Object RecordId -Unique)

    $shutdownCount=$shutdownEvents.Count
    $shutdownWarn=[int]$Config.eventLog.unexpectedShutdownWarningCount
    if($shutdownWarn -lt 1){$shutdownWarn=2}
    $shutdownStatus=if($shutdownCount -ge $shutdownWarn){'Warning'}elseif($shutdownCount -gt 0){'Recommend'}else{'Healthy'}

    $out.Add((New-RBZFinding -Category 'System' -Name 'Unexpected shutdowns' -Status $shutdownStatus `
        -Summary $(if($shutdownCount -eq 0){"No unexpected shutdown events detected in the last $lookbackDays day(s)."}else{"$shutdownCount unexpected shutdown / Kernel-Power event(s) detected in the last $lookbackDays day(s)."}) `
        -Details (Format-RBZEventDetails -Events $shutdownEvents -Maximum $maxDetails) `
        -Value $shutdownCount `
        -Recommendation $(if($shutdownCount -gt 0){'Review shutdown timing, power stability, thermal conditions and related System log events.'}else{''})))

    # BSOD/BugCheck evidence and recent minidumps.
    $bugchecks=@()
    $bugchecks += Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('Microsoft-Windows-WER-SystemErrorReporting') -Id @(1001)
    $bugchecks += Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('BugCheck') -Id @(1001)
    $bugchecks=@($bugchecks | Sort-Object RecordId -Unique)

    $dumpStart=(Get-Date).AddDays(-$dumpLookback)
    $dumps=@()
    try {
        $dumps=@(
            Get-ChildItem "$env:SystemRoot\Minidump" -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -ge $dumpStart |
            Sort-Object LastWriteTime -Descending
        )
    } catch {}

    $bugCount=$bugchecks.Count
    $dumpCount=$dumps.Count
    $crashStatus=if($bugCount -gt 0 -or $dumpCount -gt 0){'Warning'}else{'Healthy'}

    $crashDetails=[System.Collections.Generic.List[string]]::new()
    $eventText=Format-RBZEventDetails -Events $bugchecks -Maximum $maxDetails
    if(-not [string]::IsNullOrWhiteSpace($eventText)){$crashDetails.Add("BugCheck events:`n$eventText")}
    if($dumpCount -gt 0){
        $dumpLines=@($dumps | Select-Object -First $maxDetails | ForEach-Object {
            '{0:yyyy-MM-dd HH:mm} | {1}' -f $_.LastWriteTime,$_.FullName
        })
        $crashDetails.Add("Minidumps:`n$($dumpLines -join "`n")")
    }

    $out.Add((New-RBZFinding -Category 'System' -Name 'Crash / BSOD history' -Status $crashStatus `
        -Summary $(if($crashStatus -eq 'Healthy'){'No recent BSOD/BugCheck evidence detected.'}else{"$bugCount BugCheck event(s) in $lookbackDays day(s); $dumpCount minidump(s) in $dumpLookback day(s)."}) `
        -Details ($crashDetails -join "`n`n") `
        -Value ($bugCount+$dumpCount) `
        -Recommendation $(if($crashStatus -ne 'Healthy'){'Review dump files, BugCheck codes, drivers, firmware and hardware stability before assuming an application-only fault.'}else{''})))

    # WHEA hardware reports.
    $whea=Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('Microsoft-Windows-WHEA-Logger') -Id @(1,17,18,19,20,46,47)
    $wheaCount=$whea.Count
    $wheaStatus=if($wheaCount -gt 0){'Warning'}else{'Healthy'}

    $out.Add((New-RBZFinding -Category 'System' -Name 'WHEA hardware errors' -Status $wheaStatus `
        -Summary $(if($wheaCount -eq 0){"No WHEA hardware error events detected in the last $lookbackDays day(s)."}else{"$wheaCount WHEA hardware event(s) detected in the last $lookbackDays day(s)."}) `
        -Details (Format-RBZEventDetails -Events $whea -Maximum $maxDetails) `
        -Value $wheaCount `
        -Recommendation $(if($wheaCount -gt 0){'Investigate CPU, memory, PCIe devices, thermals, overclocking/undervolting and firmware. Repeated WHEA events can indicate hardware instability.'}else{''})))

    # Targeted disk/filesystem/controller events.
    # NTFS ID 98 is informational in many cases, including messages such as
    # "Volume ... is healthy. No action is needed." These benign health checks
    # must not be counted as storage faults.
    $storageEvents=[System.Collections.Generic.List[object]]::new()

    foreach($e in @(Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('disk') -Id @(7,51,153))){
        $storageEvents.Add($e)
    }

    foreach($e in @(Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('Microsoft-Windows-Ntfs','Ntfs') -Id @(55,98,140))){
        $message=[string]$e.Message
        $isBenign98=(
            $e.Id -eq 98 -and
            [bool]$Config.eventLog.ignoreHealthyNtfs98 -and
            $message -match '(?i)\bis healthy\b.*\bno action is needed\b'
        )

        if(-not $isBenign98){
            $storageEvents.Add($e)
        }
    }

    foreach($e in @(Get-RBZRecentEvents -LogName 'System' -StartTime $start -ProviderName @('storahci','stornvme') -Id @(129))){
        $storageEvents.Add($e)
    }

    $storageEvents=@($storageEvents | Sort-Object RecordId -Unique)

    $storageCount=$storageEvents.Count
    $storageStatus=if($storageCount -gt 0){'Warning'}else{'Healthy'}

    $out.Add((New-RBZFinding -Category 'Storage' -Name 'Storage event log health' -Status $storageStatus `
        -Summary $(if($storageCount -eq 0){
            "No actionable disk/NTFS/controller errors detected in the last $lookbackDays day(s)."
        }else{
            "$storageCount actionable disk/NTFS/controller error event(s) detected in the last $lookbackDays day(s)."
        }) `
        -Details (Format-RBZEventDetails -Events $storageEvents -Maximum $maxDetails) `
        -Value $storageCount `
        -Recommendation $(if($storageCount -gt 0){
            'Back up important data and review disk health, controller/NVMe drivers, filesystem integrity and vendor diagnostics.'
        }else{''})))

    # Application errors: group by executable so repeated offenders matter more
    # than a mixed set of one-off Event Viewer entries.
    $appCrashes=[System.Collections.Generic.List[object]]::new()
    foreach($e in @(Get-RBZRecentEvents -LogName 'Application' -StartTime $start -ProviderName @('Application Error') -Id @(1000))){
        $appCrashes.Add($e)
    }
    foreach($e in @(Get-RBZRecentEvents -LogName 'Application' -StartTime $start -ProviderName @('Application Hang') -Id @(1002))){
        $appCrashes.Add($e)
    }
    $appCrashes=@($appCrashes | Sort-Object RecordId -Unique)

    $parsed=[System.Collections.Generic.List[object]]::new()

    foreach($e in $appCrashes){
        $message=[string]$e.Message
        $app='Unknown application'
        $module=''
        $exception=''

        if($e.Id -eq 1000){
            $m=[regex]::Match($message,'(?im)^Faulting application name:\s*([^,\r\n]+)')
            if($m.Success){$app=$m.Groups[1].Value.Trim()}

            $m=[regex]::Match($message,'(?im)^Faulting module name:\s*([^,\r\n]+)')
            if($m.Success){$module=$m.Groups[1].Value.Trim()}

            $m=[regex]::Match($message,'(?im)^Exception code:\s*([^\r\n]+)')
            if($m.Success){$exception=$m.Groups[1].Value.Trim()}
        }
        elseif($e.Id -eq 1002){
            $m=[regex]::Match($message,'(?im)^The program\s+([^\s]+)')
            if($m.Success){$app=$m.Groups[1].Value.Trim()}
        }

        $parsed.Add([pscustomobject]@{
            App=$app
            Module=$module
            Exception=$exception
            Event=$e
        })
    }

    $groups=@(
        $parsed |
        Group-Object App |
        Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false}
    )

    $perAppRecommend=[int]$Config.eventLog.applicationPerAppRecommendCount
    if($perAppRecommend -lt 1){$perAppRecommend=3}

    $perAppWarning=[int]$Config.eventLog.applicationPerAppWarningCount
    if($perAppWarning -le $perAppRecommend){$perAppWarning=5}

    $totalRecommend=[int]$Config.eventLog.applicationTotalRecommendCount
    if($totalRecommend -lt 1){$totalRecommend=10}

    $appCount=$appCrashes.Count
    $topCount=if($groups.Count -gt 0){[int]$groups[0].Count}else{0}

    if($topCount -ge $perAppWarning){
        $appStatus='Warning'
    }
    elseif($topCount -ge $perAppRecommend){
        $appStatus='Recommend'
    }
    elseif($appCount -ge $totalRecommend){
        # Many unrelated crashes still deserve attention, but not the same
        # severity as one application repeatedly failing.
        $appStatus='Recommend'
    }
    else{
        $appStatus='Info'
    }

    $groupLines=[System.Collections.Generic.List[string]]::new()
    foreach($group in @($groups | Select-Object -First 8)){
        $items=@($group.Group)
        $moduleSummary=@(
            $items |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Module) } |
            Group-Object Module |
            Sort-Object Count -Descending |
            Select-Object -First 1
        )
        $exceptionSummary=@(
            $items |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Exception) } |
            Group-Object Exception |
            Sort-Object Count -Descending |
            Select-Object -First 1
        )

        $suffix=[System.Collections.Generic.List[string]]::new()
        if($moduleSummary.Count -gt 0){
            $moduleName=[string]$moduleSummary[0].Name
            if(
                -not [string]::IsNullOrWhiteSpace($moduleName) -and
                $moduleName -notmatch '^(?i:unknown|n/a|none)$'
            ){
                $suffix.Add("module=$moduleName x$($moduleSummary[0].Count)")
            }
        }

        if($exceptionSummary.Count -gt 0){
            $exceptionCode=[string]$exceptionSummary[0].Name
            if(
                -not [string]::IsNullOrWhiteSpace($exceptionCode) -and
                $exceptionCode -notmatch '^(?i:0x0+|0+|unknown|n/a|none)$'
            ){
                $suffix.Add("exception=$exceptionCode x$($exceptionSummary[0].Count)")
            }
        }

        $line="$($group.Name): $($group.Count) event(s)"
        if($suffix.Count -gt 0){
            $line+=" | $($suffix -join ' | ')"
        }
        $groupLines.Add($line)
    }

    $rawDetails=Format-RBZEventDetails -Events $appCrashes -Maximum $maxDetails
    $detailsParts=[System.Collections.Generic.List[string]]::new()

    if($groupLines.Count -gt 0){
        $detailsParts.Add("Grouped applications:`n$($groupLines -join "`n")")
    }
    if(-not [string]::IsNullOrWhiteSpace($rawDetails)){
        $detailsParts.Add("Recent event examples:`n$rawDetails")
    }

    $summary=if($appCount -eq 0){
        "No application crash/hang events detected in the last $lookbackDays day(s)."
    }
    elseif($groups.Count -gt 0){
        "$appCount application crash/hang event(s) detected; top recurring application: $($groups[0].Name) ($($groups[0].Count))."
    }
    else{
        "$appCount application crash/hang event(s) detected in the last $lookbackDays day(s)."
    }

    $out.Add((New-RBZFinding -Category 'System' -Name 'Application crash history' -Status $appStatus `
        -Summary $summary `
        -Details ($detailsParts -join "`n`n") `
        -Value $appCount `
        -Recommendation $(if($appStatus -in @('Recommend','Warning')){
            'Review recurring application names, faulting modules and exception codes. Prioritise repeated failures from the same executable over isolated crashes.'
        }else{''})))

    return $out
}

Export-ModuleMember -Function Get-RBZEventLogFindings
