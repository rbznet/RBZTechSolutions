function Get-RBZUpdateKind {
    param($Update)
    $title = [string]$Update.Title
    if($title -match 'Security Intelligence Update|Definition Update|Microsoft Defender Antivirus'){ return 'Definition' }
    if($title -match 'Driver|Intel|NVIDIA|AMD|Realtek|Firmware'){ return 'Driver' }
    if($title -match 'Feature update'){ return 'Feature' }
    if($title -match 'Cumulative Update|Security Update|Quality Update|\.NET'){ return 'Quality' }
    return 'Other'
}

function Get-RBZUpdateFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    if($Config.scan.windowsUpdateService){
        try {
            $svc = Get-Service wuauserv -ErrorAction Stop
            $state = if($svc.StartType -eq 'Disabled'){'Warning'}else{'Info'}
            $out.Add((New-RBZFinding -Category 'Updates' -Name 'Windows Update service' -Status $state -Summary "Status=$($svc.Status); StartType=$($svc.StartType)" -Details 'Windows Update is trigger-started on modern Windows versions, so Stopped/Manual is not inherently unhealthy.' -Recommendation $(if($state -eq 'Warning'){'Windows Update is disabled; review policy or service configuration.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'Updates' -Name 'Windows Update service' -Status 'Info' -Summary 'Windows Update service status unavailable.' -Details $_.Exception.Message))
        }
    }

    try {
        $hotfix = Get-HotFix -ErrorAction Stop | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if($hotfix){
            $out.Add((New-RBZFinding -Category 'Updates' -Name 'Latest installed update' -Status 'Info' -Summary "$($hotfix.HotFixID) installed $($hotfix.InstalledOn.ToString('dd MMM yyyy'))" -Details "Description: $($hotfix.Description)`nInstalled by: $($hotfix.InstalledBy)"))
        }
    } catch {}

    if($Config.scan.pendingUpdates){
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
            $updates = @()
            for($i=0;$i -lt $result.Updates.Count;$i++){ $updates += $result.Updates.Item($i) }

            $classified = foreach($u in $updates){
                [pscustomobject]@{ Kind=(Get-RBZUpdateKind $u); Title=$u.Title }
            }

            $actionable = @($classified | Where-Object Kind -ne 'Definition')
            $definitions = @($classified | Where-Object Kind -eq 'Definition')

            if($definitions.Count){
                $out.Add((New-RBZFinding -Category 'Updates' -Name 'Defender intelligence updates' -Status 'Info' -Summary "$($definitions.Count) Microsoft Defender intelligence/definition update(s) available." -Details (($definitions.Title) -join "`n") -Recommendation 'Definition updates are normal and are not treated as a PC health issue.'))
            }

            $status = if($actionable.Count -gt 0){'Recommend'}else{'Healthy'}
            $details = if($actionable.Count){($actionable | ForEach-Object {"[$($_.Kind)] $($_.Title)"}) -join "`n"}else{'No pending quality, feature, driver, or other software updates were returned.'}
            $summary = if($actionable.Count){"$($actionable.Count) actionable Windows software update(s) found."}else{'No actionable Windows software updates found.'}
            $out.Add((New-RBZFinding -Category 'Updates' -Name 'Pending updates' -Status $status -Summary $summary -Details $details -Value $actionable.Count -Recommendation $(if($actionable.Count){'Review and install appropriate Windows updates after confirming reboot expectations with the customer.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'Updates' -Name 'Pending updates' -Status 'Info' -Summary 'Pending update query was unavailable.' -Details $_.Exception.Message))
        }
    }

    try {
        $since = (Get-Date).AddDays(-30)
        $failed = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WindowsUpdateClient/Operational';Level=2;StartTime=$since} -ErrorAction Stop)
        $threshold = [int]$Config.thresholds.failedUpdateEventsWarning
        $status = if($failed.Count -ge $threshold){'Warning'}elseif($failed.Count -gt 0){'Recommend'}else{'Healthy'}
        $details = if($failed.Count){($failed | Select-Object -First 10 | ForEach-Object {"$($_.TimeCreated.ToString('dd MMM yyyy HH:mm')) | Event $($_.Id) | $($_.Message -replace '\r?\n',' ')"}) -join "`n"}else{'No Windows Update error-level events found in the last 30 days.'}
        $out.Add((New-RBZFinding -Category 'Updates' -Name 'Recent update failures' -Status $status -Summary "$($failed.Count) Windows Update error event(s) in the last 30 days." -Details $details -Recommendation $(if($failed.Count){'Review failed update events if Windows Update is repeatedly unsuccessful.'}else{''})))
    } catch {
        $out.Add((New-RBZFinding -Category 'Updates' -Name 'Recent update failures' -Status 'Info' -Summary 'Windows Update event history was unavailable.' -Details $_.Exception.Message))
    }

    $pending = $false
    foreach($p in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')){if(Test-Path $p){$pending=$true}}
    $out.Add((New-RBZFinding -Category 'Updates' -Name 'Pending restart' -Status $(if($pending){'Recommend'}else{'Healthy'}) -Summary $(if($pending){'Windows indicates a restart is pending.'}else{'No common pending-restart indicators detected.'}) -Recommendation $(if($pending){'Restart the device after confirming with the customer.'}else{''})))

    return $out
}
Export-ModuleMember -Function Get-RBZUpdateFindings
