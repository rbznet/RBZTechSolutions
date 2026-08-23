function Get-RBZSystemFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $uptime = (Get-Date) - $os.LastBootUpTime
    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB,1)

    $out.Add((New-RBZFinding -Category 'System' -Name 'Windows' -Status 'Info' -Summary "$($os.Caption) build $($os.BuildNumber)" -Value $os.Version))
    $out.Add((New-RBZFinding -Category 'System' -Name 'CPU' -Status 'Info' -Summary $cpu.Name.Trim() -Value $cpu.NumberOfLogicalProcessors))
    $ramState = if ($ramGB -lt [double]$Config.thresholds.memoryGBWarning) { 'Warning' } else { 'Healthy' }
    $out.Add((New-RBZFinding -Category 'System' -Name 'Memory' -Status $ramState -Summary "$ramGB GB RAM installed" -Value $ramGB -Recommendation $(if($ramState -eq 'Warning'){'Consider a memory upgrade if performance is poor.'}else{''})))
    $upState = if ($uptime.TotalDays -gt [double]$Config.thresholds.uptimeDaysWarning) { 'Warning' } else { 'Healthy' }
    $out.Add((New-RBZFinding -Category 'System' -Name 'Uptime' -Status $upState -Summary ("{0:N1} days since restart" -f $uptime.TotalDays) -Value $uptime.TotalDays -Recommendation $(if($upState -eq 'Warning'){'Restart the device to complete pending maintenance and updates.'}else{''})))
    return $out
}
Export-ModuleMember -Function Get-RBZSystemFindings
