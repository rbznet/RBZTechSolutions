function Get-RBZDeviceProblemInfo {
    param([Nullable[int]]$Code)

    $map=@{
        1  = @('Device is not configured correctly.','Warning','Install or reinstall the appropriate device driver.')
        3  = @('The driver may be corrupted, or the system may be low on memory or other resources.','Warning','Restart Windows, then update or reinstall the device driver if the problem persists.')
        10 = @('This device cannot start.','Warning','Update/reinstall the device driver and review device firmware, dependencies and hardware status.')
        12 = @('This device cannot find enough free resources that it can use.','Warning','Review resource conflicts, firmware/BIOS configuration and other devices using the same resources.')
        14 = @('This device cannot work properly until the computer is restarted.','Recommend','Restart Windows and recheck Device Manager.')
        18 = @('The drivers for this device need to be reinstalled.','Warning','Reinstall the device driver from the PC, motherboard or device manufacturer.')
        19 = @('Windows cannot start this hardware device because its configuration information is incomplete or damaged.','Warning','Reinstall the device and driver.')
        21 = @('Windows is removing this device.','Recommend','Allow device removal to complete, restart if required, and rescan Device Manager.')
        22 = @('This device is disabled.','Info','No repair is required if the device was intentionally disabled. Otherwise enable it in Device Manager or firmware.')
        24 = @('This device is not present, is not working properly, or does not have all its drivers installed.','Warning','Check the physical device/connection and reinstall the correct driver.')
        28 = @('Drivers for this device are not installed.','Warning','Install the correct driver from the PC, motherboard or device manufacturer after confirming the hardware ID.')
        29 = @('The device is disabled because its firmware did not provide the required resources.','Warning','Review BIOS/UEFI settings and firmware updates for the device.')
        31 = @('This device is not working properly because Windows cannot load the required drivers.','Warning','Update or reinstall the device driver and review dependent/filter drivers.')
        32 = @('A driver for this device has been disabled and an alternate driver may be providing functionality.','Recommend','Review the installed driver and whether Windows intentionally substituted another driver.')
        37 = @('Windows cannot initialize the device driver for this hardware.','Warning','Reinstall or update the driver and restart Windows.')
        39 = @('Windows cannot load the device driver because the driver may be corrupted or missing.','Warning','Reinstall the correct signed driver and check for damaged driver files.')
        41 = @('Windows loaded the driver but cannot find the hardware device.','Warning','Check the physical device/connection and remove stale device entries if appropriate.')
        43 = @('Windows stopped this device because it reported problems.','Warning','Update the driver/firmware and investigate hardware stability.')
        45 = @('This hardware device is not currently connected to the computer.','Info','No action is required if the device is intentionally disconnected.')
        47 = @('Windows cannot use this device because it has been prepared for safe removal.','Info','Reconnect or restart if the device should still be in use.')
        48 = @('The driver for this device has been blocked from starting because it is known to have problems with Windows.','Warning','Install a newer compatible driver from the device manufacturer.')
        52 = @('Windows cannot verify the digital signature for the drivers required for this device.','Warning','Install a valid signed driver from a trusted manufacturer source.')
    }

    if($null -eq $Code){
        return [pscustomobject]@{
            Meaning='Windows did not expose a Device Manager problem code.'
            Status='Warning'
            Recommendation='Review the device status and installed driver information.'
        }
    }

    if($map.ContainsKey([int]$Code)){
        $x=$map[[int]$Code]
        return [pscustomobject]@{Meaning=$x[0];Status=$x[1];Recommendation=$x[2]}
    }

    [pscustomobject]@{
        Meaning="Device Manager reported problem code $Code."
        Status='Warning'
        Recommendation='Review the Microsoft Device Manager code description and the hardware/vendor support information.'
    }
}

function Get-RBZPnpPropertyValue {
    param([string]$InstanceId,[string]$KeyName)
    try {(Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data}
    catch {$null}
}

function ConvertTo-RBZDriverDate {
    param($Value)
    if($null -eq $Value){return $null}
    try {
        if($Value -is [datetime]){return [datetime]$Value}
        [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)
    } catch {
        try {[datetime]$Value}catch{$null}
    }
}

function Get-RBZDeviceFindings {
    param($Config)

    $out=[System.Collections.Generic.List[object]]::new()
    $driverByDevice=@{}

    try {
        foreach($driver in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)){
            $id=[string]$driver.DeviceID
            if(-not [string]::IsNullOrWhiteSpace($id)){$driverByDevice[$id]=$driver}
        }
    } catch {}

    try {
        $present=@(Get-PnpDevice -PresentOnly -ErrorAction Stop)
        $bad=@($present | Where-Object Status -notin @('OK','Unknown'))

        if($bad.Count -eq 0){
            $out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Healthy' `
                -Summary 'No present Plug and Play devices reported a problem.'))
        } else {
            foreach($dev in $bad){
                $problemCode=$null
                $raw=Get-RBZPnpPropertyValue -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode'
                if($null -ne $raw){try {$problemCode=[int]$raw}catch{}}

                $problem=Get-RBZDeviceProblemInfo -Code $problemCode
                $hardwareIds=@(Get-RBZPnpPropertyValue -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds')
                $compatibleIds=@(Get-RBZPnpPropertyValue -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_CompatibleIds')
                $manufacturer=Get-RBZPnpPropertyValue -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_Manufacturer'

                $driver=$null
                if($driverByDevice.ContainsKey([string]$dev.InstanceId)){$driver=$driverByDevice[[string]$dev.InstanceId]}

                $details=[System.Collections.Generic.List[string]]::new()
                $details.Add("Device: $($dev.FriendlyName)")
                $className=if([string]::IsNullOrWhiteSpace([string]$dev.Class)){'Unassigned'}else{[string]$dev.Class}
                $details.Add("Class: $className")
                $details.Add("Status: $($dev.Status)")
                $details.Add("Problem code: $(if($null -ne $problemCode){$problemCode}else{'Unavailable'})")
                $details.Add("Meaning: $($problem.Meaning)")
                if($manufacturer){$details.Add("Manufacturer: $manufacturer")}
                $details.Add("Instance ID: $($dev.InstanceId)")
                if($hardwareIds.Count -gt 0){$details.Add("Hardware ID: $($hardwareIds[0])")}
                if($compatibleIds.Count -gt 0){$details.Add("Compatible ID: $($compatibleIds[0])")}
                $details.Add('')
                $details.Add('Driver:')

                if($problemCode -eq 28){
                    $details.Add('Provider: Not installed')
                    $details.Add('Version: Not installed')
                } elseif($null -ne $driver) {
                    if($driver.DriverProviderName){$details.Add("Provider: $($driver.DriverProviderName)")}
                    if($driver.DriverVersion){$details.Add("Version: $($driver.DriverVersion)")}
                    $driverDate=ConvertTo-RBZDriverDate $driver.DriverDate
                    if($null -ne $driverDate){$details.Add("Date: $($driverDate.ToString('yyyy-MM-dd'))")}
                    if($driver.InfName){$details.Add("INF: $($driver.InfName)")}
                    if($null -ne $driver.IsSigned){$details.Add("Signed: $($driver.IsSigned)")}
                    if($driver.Signer){$details.Add("Signer: $($driver.Signer)")}
                } else {
                    $details.Add('Installed driver information was not returned by Windows.')
                }

                $summary=if($null -ne $problemCode){"$($problem.Meaning) (Code $problemCode)"}else{"Device Manager reports status '$($dev.Status)'."}

                $out.Add((New-RBZFinding -Category 'Devices' -Name $dev.FriendlyName -Status $problem.Status `
                    -Summary $summary -Details ($details -join "`n") -Value $problemCode `
                    -Recommendation $problem.Recommendation))
            }
        }

        $staleYears=5
        try {
            if($null -ne $Config.devices.staleDriverYears){$staleYears=[int]$Config.devices.staleDriverYears}
        } catch {}
        if($staleYears -lt 1){$staleYears=5}

        $cutoff=(Get-Date).AddYears(-$staleYears)
        $presentIds=@{}
        foreach($dev in $present){$presentIds[[string]$dev.InstanceId]=$dev}

        $old=[System.Collections.Generic.List[object]]::new()
        foreach($entry in $driverByDevice.GetEnumerator()){
            if(-not $presentIds.ContainsKey([string]$entry.Key)){continue}
            $dev=$presentIds[[string]$entry.Key]
            if($dev.Status -ne 'OK'){continue}

            $driver=$entry.Value
            $provider=[string]$driver.DriverProviderName
            if($provider -match '^(?i:Microsoft|Microsoft Corporation)$'){continue}

            $date=ConvertTo-RBZDriverDate $driver.DriverDate
            if($null -eq $date -or $date -ge $cutoff){continue}

            $old.Add([pscustomobject]@{
                Device=$dev.FriendlyName
                Provider=$provider
                Version=[string]$driver.DriverVersion
                Date=$date
            })
        }

        if($old.Count -gt 0){
            $lines=@($old | Sort-Object Date | Select-Object -First 12 | ForEach-Object {
                "$($_.Device) | $($_.Provider) | $($_.Version) | $($_.Date.ToString('yyyy-MM-dd'))"
            })
            $out.Add((New-RBZFinding -Category 'Devices' -Name 'Older third-party drivers' -Status 'Info' `
                -Summary "$($old.Count) present healthy device(s) use a third-party driver older than $staleYears year(s)." `
                -Details ($lines -join "`n") -Value $old.Count `
                -Recommendation 'Driver age alone is not a fault. Review only where the device has stability, compatibility or security concerns.'))
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Info' `
            -Summary 'PnP device status unavailable.' -Details $_.Exception.Message))
    }

    return $out
}

Export-ModuleMember -Function Get-RBZDeviceFindings
