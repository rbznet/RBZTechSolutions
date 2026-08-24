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

            $timeParams = Get-ItemProperty `
                'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' `
                -ErrorAction SilentlyContinue

            $ntpClient = Get-ItemProperty `
                'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' `
                -ErrorAction SilentlyContinue

            $timeType = if($timeParams){[string]$timeParams.Type}else{''}
            $ntpServer = if($timeParams){[string]$timeParams.NtpServer}else{''}
            $ntpEnabled = if($ntpClient -and $null -ne $ntpClient.Enabled){[int]$ntpClient.Enabled}else{$null}
            $pollInterval = if($ntpClient -and $null -ne $ntpClient.SpecialPollInterval){[int]$ntpClient.SpecialPollInterval}else{$null}

            $syncTaskState = 'Unavailable'
            $forceTaskState = 'Unavailable'
            try {
                $tasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\Time Synchronization\' -ErrorAction Stop)
                $syncTask = $tasks | Where-Object TaskName -eq 'SynchronizeTime' | Select-Object -First 1
                $forceTask = $tasks | Where-Object TaskName -eq 'ForceSynchronizeTime' | Select-Object -First 1
                if($syncTask){$syncTaskState=[string]$syncTask.State}
                if($forceTask){$forceTaskState=[string]$forceTask.State}
            } catch {}

            $hasValidProvider = $false
            if($timeType -match '^(NTP|NT5DS|AllSync)$'){ $hasValidProvider = $true }

            $hasConfiguredNtp = $false
            if($timeType -eq 'NTP' -and -not [string]::IsNullOrWhiteSpace($ntpServer) -and $ntpEnabled -eq 1){
                $hasConfiguredNtp = $true
            }

            $tasksReady = ($syncTaskState -in @('Ready','Running')) -or ($forceTaskState -in @('Ready','Running'))

            $source = ''
            $statusText = ''
            $leap = ''
            $stratum = ''
            $lastSync = ''
            $w32tmSucceeded = $false
            $explicitNotSync = $false

            if($service.Status -eq 'Running'){
                try {
                    $source = (& w32tm.exe /query /source 2>&1 | Out-String).Trim()
                    $statusText = (& w32tm.exe /query /status 2>&1 | Out-String).Trim()

                    if($LASTEXITCODE -eq 0 -and -not ($statusText -match 'The following error occurred')){
                        $w32tmSucceeded = $true
                    }

                    foreach($line in ($statusText -split "`r?`n")){
                        if($line -match '^\s*Leap Indicator\s*:\s*(.+)$'){
                            $leap = $Matches[1].Trim()
                            if($leap -match 'not synchronized'){ $explicitNotSync = $true }
                        }
                        elseif($line -match '^\s*Stratum\s*:\s*(.+)$'){ $stratum = $Matches[1].Trim() }
                        elseif($line -match '^\s*Last Successful Sync Time\s*:\s*(.+)$'){ $lastSync = $Matches[1].Trim() }
                    }

                    if($source -match 'Local CMOS Clock'){ $explicitNotSync = $true }
                } catch {}
            }

            if($service.StartType -eq 'Disabled'){
                $state = 'Recommend'
                $summary = 'Windows Time service is disabled.'
                $recommendation = 'Review why Windows Time is disabled and restore an appropriate time synchronisation configuration if needed.'
            }
            elseif($service.Status -eq 'Running' -and $explicitNotSync){
                $state = 'Warning'
                $summary = "Windows Time is running but reports that it is not synchronized. Source: $source"
                $recommendation = 'Check NTP configuration, domain policy, firewall/UDP 123 connectivity, and resynchronise the clock.'
            }
            elseif($service.Status -eq 'Running' -and $w32tmSucceeded -and -not $explicitNotSync){
                $state = 'Healthy'
                $summary = "Windows Time is running and synchronized. Source: $source"
                $recommendation = ''
            }
            elseif($service.Status -eq 'Stopped' -and $hasValidProvider -and ($hasConfiguredNtp -or $timeType -in @('NT5DS','AllSync')) -and $tasksReady){
                $state = 'Info'
                $summary = 'Windows Time is configured for synchronization; the service is currently stopped.'
                $recommendation = 'No action required unless the system clock is incorrect or time synchronisation is failing.'
            }
            elseif(-not $hasValidProvider -or ($timeType -eq 'NTP' -and (-not $hasConfiguredNtp))){
                $state = 'Recommend'
                $summary = 'Windows Time configuration is incomplete or disabled.'
                $recommendation = 'Review the Windows Time provider, NTP client settings, and configured time source.'
            }
            else {
                $state = 'Info'
                $summary = 'Windows Time service is not currently running, but no confirmed synchronisation fault was detected.'
                $recommendation = 'Review only if the system clock is incorrect or time synchronisation problems are reported.'
            }

            $details = @(
                "Service: $($service.Status)"
                "Start type: $($service.StartType)"
                "Time provider type: $timeType"
                "NTP server: $ntpServer"
                "NTP client enabled: $ntpEnabled"
                "Special poll interval: $pollInterval"
                "SynchronizeTime task: $syncTaskState"
                "ForceSynchronizeTime task: $forceTaskState"
                $(if($service.Status -eq 'Running'){"Source: $source"}else{'Source: Not queried while service is stopped'})
                $(if($service.Status -eq 'Running'){"Leap indicator: $leap"}else{'Leap indicator: Not queried while service is stopped'})
                $(if($service.Status -eq 'Running'){"Stratum: $stratum"}else{'Stratum: Not queried while service is stopped'})
                $(if($service.Status -eq 'Running'){"Last successful sync: $lastSync"}else{'Last successful sync: Not queried while service is stopped'})
            ) -join "`n"

            $out.Add((New-RBZFinding -Category 'System' -Name 'Windows Time synchronisation' `
                -Status $state -Summary $summary -Details $details -Recommendation $recommendation))
        } catch {
            $out.Add((New-RBZFinding -Category 'System' -Name 'Windows Time synchronisation' -Status 'Info' `
                -Summary 'Windows Time synchronisation status could not be determined.' -Details $_.Exception.ToString()))
        }
    }

    return $out
}
Export-ModuleMember -Function Get-RBZSystemFindings
