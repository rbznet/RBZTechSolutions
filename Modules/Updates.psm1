function Get-RBZUpdateFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $svc = Get-Service wuauserv -ErrorAction Stop
        $state = if($svc.StartType -eq 'Disabled'){'Warning'}else{'Healthy'}
        $out.Add((New-RBZFinding -Category 'Updates' -Name 'Windows Update service' -Status $state -Summary "Status=$($svc.Status); StartType=$($svc.StartType)" -Recommendation $(if($state -eq 'Warning'){'Windows Update is disabled; review policy or service configuration.'}else{''})))
    } catch {$out.Add((New-RBZFinding -Category 'Updates' -Name 'Windows Update service' -Status 'Info' -Summary 'Windows Update service status unavailable.'))}

    $pending = $false
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    )
    foreach($p in $paths){if(Test-Path $p){$pending=$true}}
    $out.Add((New-RBZFinding -Category 'Updates' -Name 'Pending restart' -Status $(if($pending){'Warning'}else{'Healthy'}) -Summary $(if($pending){'Windows indicates a restart is pending.'}else{'No common pending-restart indicators detected.'}) -Recommendation $(if($pending){'Restart the device after confirming with the customer.'}else{''})))
    return $out
}
Export-ModuleMember -Function Get-RBZUpdateFindings
