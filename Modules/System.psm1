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
            -Recommendation $(if($upState -ne 'Healthy'){'Restart the device to complete pending maintenance and servicing.'}else{''})))

        $out.Add((New-RBZFinding -Category 'System' -Name 'BIOS' -Status 'Info' `
            -Summary "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" `
            -Details "Release date: $($bios.ReleaseDate)`nSerial number: $($bios.SerialNumber)`nBaseboard: $($base.Manufacturer) $($base.Product)"))
    } catch {
        $out.Add((New-RBZFinding -Category 'System' -Name 'System inventory' -Status 'Warning' `
            -Summary 'Some system inventory data could not be collected.' -Details $_.Exception.Message))
    }

    if($Config.scan.windowsTime){
        try {
            $service = Get-Service W32Time -ErrorAction Stop

            $source = (& w32tm.exe /query /source 2>&1 | Out-String).Trim()
            $statusText = (& w32tm.exe /query /status 2>&1 | Out-String).Trim()

            $notSync = $false
            $leap = ''
            $stratum = ''
            $lastSync = ''

            foreach($line in ($statusText -split "`r?`n")){
                if($line -match '^\s*Leap Indicator\s*:\s*(.+)$'){
                    $leap = $Matches[1].Trim()
                    if($leap -match 'not synchronized'){ $notSync = $true }
                }
                elseif($line -match '^\s*Stratum\s*:\s*(.+)$'){ $stratum = $Matches[1].Trim() }
                elseif($line -match '^\s*Last Successful Sync Time\s*:\s*(.+)$'){ $lastSync = $Matches[1].Trim() }
            }

            if($source -match 'Local CMOS Clock'){ $notSync = $true }
            if($lastSync -match 'unspecified|never|N/A'){ $notSync = $true }

            $state = if($service.Status -ne 'Running'){
                'Warning'
            } elseif($notSync){
                'Warning'
            } else {
                'Healthy'
            }

            $summary = if($state -eq 'Healthy'){
                "Windows Time is synchronized. Source: $source"
            } else {
                "Windows Time is not synchronized correctly. Source: $source"
            }

            $details = @(
                "Service: $($service.Status)"
                "Start type: $($service.StartType)"
                "Source: $source"
                "Leap indicator: $leap"
                "Stratum: $stratum"
                "Last successful sync: $lastSync"
                ""
                "Raw status:"
                $statusText
            ) -join "`n"

            $out.Add((New-RBZFinding -Category 'System' -Name 'Windows Time synchronisation' -Status $state `
                -Summary $summary -Details $details `
                -Recommendation $(if($state -ne 'Healthy'){'Check Windows Time service, NTP configuration, domain policy, firewall/UDP 123 connectivity, and then resynchronise the clock.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'System' -Name 'Windows Time synchronisation' -Status 'Info' `
                -Summary 'Windows Time synchronisation status could not be determined.' -Details $_.Exception.ToString()))
        }
    }

    return $out
}
Export-ModuleMember -Function Get-RBZSystemFindings
