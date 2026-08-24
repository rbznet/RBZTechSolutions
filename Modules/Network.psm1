function Get-RBZNetworkFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $up = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
        if($up.Count){
            foreach($adapter in $up){
                $ip = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
                $ipv4 = ($ip.IPv4Address.IPAddress -join ', ')
                $gw = ($ip.IPv4DefaultGateway.NextHop -join ', ')
                $dns = ((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', ')
                $details = "Adapter: $($adapter.Name)`nDescription: $($adapter.InterfaceDescription)`nLink speed: $($adapter.LinkSpeed)`nIPv4: $ipv4`nGateway: $gw`nDNS: $dns"
                $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Healthy' `
                    -Summary "$($adapter.Name) ($($adapter.LinkSpeed))" -Details $details))
            }
        } else {
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Warning' -Summary 'No active physical network adapter detected.'))
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Adapter inventory' -Status 'Info' -Summary 'Network adapter details unavailable.' -Details $_.Exception.Message))
    }

    if($Config.scan.networkTests){
        try {
            $timeout = [int]$Config.network.timeoutSeconds
            $response = Invoke-WebRequest -Uri $Config.network.httpsTestUrl -UseBasicParsing -TimeoutSec $timeout -ErrorAction Stop
            $ok = $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet access (HTTPS)' -Status $(if($ok){'Healthy'}else{'Warning'}) `
                -Summary $(if($ok){"HTTPS connectivity confirmed (HTTP $($response.StatusCode))."}else{"HTTPS test returned HTTP $($response.StatusCode)."}) `
                -Details "Test URL: $($Config.network.httpsTestUrl)"))
        } catch {
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet access (HTTPS)' -Status 'Warning' `
                -Summary 'HTTPS connectivity test failed.' -Details $_.Exception.Message `
                -Recommendation 'Confirm internet access, proxy settings, captive portal, or firewall policy.'))
        }

        try {
            $resolved = @(Resolve-DnsName -Name $Config.network.dnsTestName -Type A -ErrorAction Stop | Where-Object IPAddress)
            $ips = ($resolved.IPAddress -join ', ')
            $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Healthy' `
                -Summary "Resolved $($Config.network.dnsTestName) successfully." -Details "Addresses: $ips"))
        } catch {
            $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Warning' `
                -Summary "Could not resolve $($Config.network.dnsTestName)." -Details $_.Exception.Message `
                -Recommendation 'Check DNS server configuration and network connectivity.'))
        }
    }
    return $out
}
Export-ModuleMember -Function Get-RBZNetworkFindings
