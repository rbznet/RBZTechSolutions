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
                $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Healthy' -Summary "$($adapter.Name) ($($adapter.LinkSpeed))" -Details $details))
            }
        } else {$out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Warning' -Summary 'No active physical network adapter detected.'))}
    } catch {$out.Add((New-RBZFinding -Category 'Network' -Name 'Adapter inventory' -Status 'Info' -Summary 'Network adapter details unavailable.' -Details $_.Exception.Message))}

    if($Config.scan.networkTests){
        $dnsOk=$false
        try {
            $resolved=@(Resolve-DnsName -Name $Config.network.dnsTestName -Type A -ErrorAction Stop | Where-Object IPAddress)
            $ips=($resolved.IPAddress -join ', '); $dnsOk=$true
            $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Healthy' -Summary "Resolved $($Config.network.dnsTestName) successfully." -Details "Addresses: $ips"))
        } catch {$out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Warning' -Summary "Could not resolve $($Config.network.dnsTestName)." -Details $_.Exception.Message -Recommendation 'Check DNS server configuration and network connectivity.'))}

        $tcpOk=$false
        try {
            $tcp=Test-NetConnection -ComputerName $Config.network.connectivityHost -Port ([int]$Config.network.connectivityPort) -WarningAction SilentlyContinue
            $tcpOk=[bool]$tcp.TcpTestSucceeded
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' -Status $(if($tcpOk){'Healthy'}else{'Warning'}) -Summary $(if($tcpOk){"TCP 443 connectivity confirmed to $($Config.network.connectivityHost)."}else{"Unable to establish TCP 443 connectivity to $($Config.network.connectivityHost)."}) -Details "Remote address: $($tcp.RemoteAddress)`nSource address: $($tcp.SourceAddress)" -Recommendation $(if(-not $tcpOk){'Check internet access, firewall, proxy, VPN, or upstream routing.'}else{''})))
        } catch {$out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' -Status 'Warning' -Summary 'TCP 443 connectivity test failed.' -Details $_.Exception.Message -Recommendation 'Check internet access, firewall, proxy, VPN, or upstream routing.'))}

        try {
            $response=Invoke-WebRequest -Uri $Config.network.httpsTestUrl -UseBasicParsing -TimeoutSec ([int]$Config.network.timeoutSeconds) -ErrorAction Stop
            $ok=$response.StatusCode -ge 200 -and $response.StatusCode -lt 400
            $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS validation' -Status $(if($ok){'Healthy'}else{'Recommend'}) -Summary $(if($ok){"HTTPS certificate/session validation succeeded (HTTP $($response.StatusCode))."}else{"HTTPS endpoint returned HTTP $($response.StatusCode)."}) -Details "Test URL: $($Config.network.httpsTestUrl)"))
        } catch {
            $msg=$_.Exception.Message; $trustFailure=$msg -match 'trust relationship|certificate|SSL/TLS|secure channel'
            if($trustFailure -and $tcpOk -and $dnsOk){
                $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS validation' -Status 'Recommend' -Summary 'Internet path is available, but HTTPS trust validation failed.' -Details $msg -Recommendation 'Review proxy/TLS inspection and trusted root certificates. This does not necessarily indicate loss of internet connectivity.'))
            } else {
                $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS validation' -Status 'Warning' -Summary 'HTTPS connectivity/validation test failed.' -Details $msg -Recommendation 'Confirm internet access, proxy settings, captive portal, firewall policy, and certificate trust.'))
            }
        }
    }
    return $out
}
Export-ModuleMember -Function Get-RBZNetworkFindings
