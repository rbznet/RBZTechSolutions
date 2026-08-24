function Get-RBZDeviceFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $bad = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Status -notin @('OK','Unknown'))
        if($bad.Count -eq 0){
            $out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Healthy' `
                -Summary 'No present Plug and Play devices reported a problem.'))
        } else {
            foreach($dev in $bad){
                $problemCode = $null
                try {
                    $prop = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop
                    $problemCode = $prop.Data
                } catch {}
                $details = "Device: $($dev.FriendlyName)`nClass: $($dev.Class)`nStatus: $($dev.Status)`nProblem code: $problemCode`nInstance ID: $($dev.InstanceId)"
                $out.Add((New-RBZFinding -Category 'Devices' -Name $dev.FriendlyName -Status 'Warning' `
                    -Summary "Device Manager reports status '$($dev.Status)'$(if($null -ne $problemCode){" (Code $problemCode)"})." `
                    -Details $details -Value $problemCode `
                    -Recommendation 'Review the device driver, hardware status, and vendor support information.'))
            }
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Info' -Summary 'PnP device status unavailable.' -Details $_.Exception.Message))
    }
    return $out
}
Export-ModuleMember -Function Get-RBZDeviceFindings
