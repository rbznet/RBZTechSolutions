function Get-RBZBatteryFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
        if(-not $bat){$out.Add((New-RBZFinding -Category 'Battery' -Name 'Battery' -Status 'Info' -Summary 'No battery detected; likely a desktop device.')); return $out}
        foreach($b in @($bat)){
            $summary = "Estimated charge remaining: $($b.EstimatedChargeRemaining)%"
            $out.Add((New-RBZFinding -Category 'Battery' -Name 'Battery charge' -Status 'Info' -Summary $summary -Value $b.EstimatedChargeRemaining))
        }
    } catch {$out.Add((New-RBZFinding -Category 'Battery' -Name 'Battery' -Status 'Info' -Summary 'Battery information unavailable.'))}
    return $out
}
Export-ModuleMember -Function Get-RBZBatteryFindings
