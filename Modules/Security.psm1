function Get-RBZSecurityFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        $disabled = @($profiles | Where-Object Enabled -eq $false)
        $state = if($disabled.Count){'Warning'}else{'Healthy'}
        $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status $state -Summary $(if($disabled.Count){"Disabled profiles: $($disabled.Name -join ', ')"}else{'All firewall profiles are enabled.'}) -Recommendation $(if($disabled.Count){'Review why one or more Windows Firewall profiles are disabled.'}else{''})))
    } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status 'Info' -Summary 'Firewall status unavailable.')) }

    if ($Config.scan.defender) {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $state = if($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled){'Healthy'}else{'Warning'}
            $summary = "Antivirus=$($mp.AntivirusEnabled); Real-time=$($mp.RealTimeProtectionEnabled); Signature age=$($mp.AntivirusSignatureAge) day(s)"
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status $state -Summary $summary -Recommendation $(if($state -ne 'Healthy'){'Review antivirus and real-time protection configuration.'}else{''})))
        } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status 'Info' -Summary 'Defender status unavailable or a third-party antivirus may be installed.')) }
    }
    return $out
}
Export-ModuleMember -Function Get-RBZSecurityFindings
