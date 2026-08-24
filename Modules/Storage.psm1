function Get-RBZStorageFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $system = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        if ($system.Size) {
            $freePct = [math]::Round(($system.FreeSpace / $system.Size) * 100,1)
            $freeGB = [math]::Round($system.FreeSpace / 1GB,1)
            $sizeGB = [math]::Round($system.Size / 1GB,1)
            $state = if($freePct -lt [double]$Config.thresholds.systemDriveFreePercentCritical){'Critical'}elseif($freePct -lt [double]$Config.thresholds.systemDriveFreePercentWarning){'Warning'}else{'Healthy'}
            $out.Add((New-RBZFinding -Category 'Storage' -Name 'System drive free space' -Status $state `
                -Summary "$freePct% free on $($env:SystemDrive) ($freeGB GB of $sizeGB GB)" -Value $freePct `
                -Recommendation $(if($state -ne 'Healthy'){'Free disk space before Windows updates or large application installs.'}else{''})))
        }
    } catch {}

    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object UniqueId -Unique)
        foreach($d in $disks) {
            $state = if($d.HealthStatus -eq 'Healthy' -and ($d.OperationalStatus -contains 'OK')){'Healthy'}else{'Warning'}
            $sizeGB = if($d.Size){[math]::Round($d.Size/1GB,1)}else{$null}
            $details = @(
                "Friendly name: $($d.FriendlyName)"
                "Media type: $($d.MediaType)"
                "Bus type: $($d.BusType)"
                "Size: $sizeGB GB"
                "Health: $($d.HealthStatus)"
                "Operational: $($d.OperationalStatus -join ', ')"
                "Firmware: $($d.FirmwareVersion)"
                "Serial: $($d.SerialNumber)"
            ) -join "`n"
            $out.Add((New-RBZFinding -Category 'Storage' -Name "Drive: $($d.FriendlyName)" -Status $state `
                -Summary "$($d.MediaType) | $sizeGB GB | Health: $($d.HealthStatus)" -Details $details `
                -Value $d.MediaType -Recommendation $(if($state -ne 'Healthy'){'Back up important data and investigate drive health before making changes.'}else{''})))
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Storage' -Name 'Physical disk health' -Status 'Info' -Summary 'Physical disk health data was unavailable.' -Details $_.Exception.Message))
    }
    return $out
}
Export-ModuleMember -Function Get-RBZStorageFindings

