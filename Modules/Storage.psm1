function Get-RBZStorageFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    $system = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    if ($system.Size) {
        $freePct = [math]::Round(($system.FreeSpace / $system.Size) * 100,1)
        $state = if($freePct -lt [double]$Config.thresholds.systemDriveFreePercentCritical){'Critical'}elseif($freePct -lt [double]$Config.thresholds.systemDriveFreePercentWarning){'Warning'}else{'Healthy'}
        $out.Add((New-RBZFinding -Category 'Storage' -Name 'System drive free space' -Status $state -Summary "$freePct% free on $($env:SystemDrive)" -Value $freePct -Recommendation $(if($state -ne 'Healthy'){'Free disk space before Windows updates or large application installs.'}else{''})))
    }
    try {
        Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            $state = if($_.HealthStatus -eq 'Healthy'){'Healthy'}else{'Warning'}
            $out.Add((New-RBZFinding -Category 'Storage' -Name "Drive: $($_.FriendlyName)" -Status $state -Summary "Health: $($_.HealthStatus); Operational: $($_.OperationalStatus -join ', ')" -Value $_.MediaType -Recommendation $(if($state -ne 'Healthy'){'Back up important data and investigate drive health.'}else{''})))
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Storage' -Name 'Physical disk health' -Status 'Info' -Summary 'PhysicalDisk health data was unavailable on this device.'))
    }
    return $out
}
Export-ModuleMember -Function Get-RBZStorageFindings
