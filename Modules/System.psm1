function Get-RBZSystemFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS
        $base = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
        $uptime = (Get-Date) - $os.LastBootUpTime
        $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB,1)

        $out.Add((New-RBZFinding -Category 'System' -Name 'Windows' -Status 'Info' `
            -Summary "$($os.Caption) build $($os.BuildNumber)" `
            -Details "Version: $($os.Version)`nArchitecture: $($os.OSArchitecture)`nInstalled: $($os.InstallDate)" -Value $os.Version))

        $out.Add((New-RBZFinding -Category 'System' -Name 'Computer' -Status 'Info' `
            -Summary "$($cs.Manufacturer) $($cs.Model)" `
            -Details "Computer name: $env:COMPUTERNAME`nManufacturer: $($cs.Manufacturer)`nModel: $($cs.Model)`nSystem type: $($cs.SystemType)"))

        $out.Add((New-RBZFinding -Category 'System' -Name 'CPU' -Status 'Info' `
            -Summary $cpu.Name.Trim() `
            -Details "Cores: $($cpu.NumberOfCores)`nLogical processors: $($cpu.NumberOfLogicalProcessors)`nMax clock: $($cpu.MaxClockSpeed) MHz"))

        $ramState = if ($ramGB -lt [double]$Config.thresholds.memoryGBWarning) { 'Recommend' } else { 'Healthy' }
        $out.Add((New-RBZFinding -Category 'System' -Name 'Memory' -Status $ramState `
            -Summary "$ramGB GB RAM installed" -Value $ramGB `
            -Recommendation $(if($ramState -ne 'Healthy'){'Consider a memory upgrade if workload or performance warrants it.'}else{''})))

        $upState = if ($uptime.TotalDays -gt [double]$Config.thresholds.uptimeDaysWarning) { 'Recommend' } else { 'Healthy' }
        $out.Add((New-RBZFinding -Category 'System' -Name 'Uptime' -Status $upState `
            -Summary ("{0:N1} days since restart" -f $uptime.TotalDays) -Value $uptime.TotalDays `
            -Recommendation $(if($upState -ne 'Healthy'){'Restart the device to complete maintenance and pending servicing.'}else{''})))

        $out.Add((New-RBZFinding -Category 'System' -Name 'BIOS' -Status 'Info' `
            -Summary "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" `
            -Details "Release date: $($bios.ReleaseDate)`nSerial number: $($bios.SerialNumber)`nBaseboard: $($base.Manufacturer) $($base.Product)"))
    } catch {
        $out.Add((New-RBZFinding -Category 'System' -Name 'System inventory' -Status 'Warning' `
            -Summary 'Some system inventory data could not be collected.' -Details $_.Exception.Message))
    }
    return $out
}
Export-ModuleMember -Function Get-RBZSystemFindings
