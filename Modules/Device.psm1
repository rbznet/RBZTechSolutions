function Get-RBZDeviceFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $bad = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Status -notin @('OK','Unknown'))
        if($bad.Count -eq 0){$out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Healthy' -Summary 'No present Plug and Play devices reported a problem.'))}
        else {$out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Warning' -Summary "$($bad.Count) device(s) reported a non-OK status." -Recommendation 'Review Device Manager for driver or hardware issues.'))}
    } catch {$out.Add((New-RBZFinding -Category 'Devices' -Name 'Device Manager' -Status 'Info' -Summary 'PnP device status unavailable.'))}
    return $out
}
Export-ModuleMember -Function Get-RBZDeviceFindings
