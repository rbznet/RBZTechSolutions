function Get-RBZNetworkFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $up = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
        if($up.Count){$out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapters' -Status 'Healthy' -Summary (($up | ForEach-Object {"$($_.Name) ($($_.LinkSpeed))"}) -join '; ')))}
        else {$out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapters' -Status 'Warning' -Summary 'No active physical network adapter detected.'))}
    } catch {}

    try {
        $ping = Test-Connection -ComputerName $Config.network.internetTestHost -Count 1 -Quiet -ErrorAction Stop
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet reachability' -Status $(if($ping){'Healthy'}else{'Warning'}) -Summary $(if($ping){"Reachable: $($Config.network.internetTestHost)"}else{"Unable to reach $($Config.network.internetTestHost)"})))
    } catch { $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet reachability' -Status 'Warning' -Summary 'Internet reachability test failed.')) }

    try {
        Resolve-DnsName -Name $Config.network.dnsTestName -ErrorAction Stop | Out-Null
        $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Healthy' -Summary "Resolved $($Config.network.dnsTestName) successfully."))
    } catch { $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Warning' -Summary "Could not resolve $($Config.network.dnsTestName)." -Recommendation 'Check DNS settings and network connectivity.')) }
    return $out
}
Export-ModuleMember -Function Get-RBZNetworkFindings
