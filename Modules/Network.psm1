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
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Warning' `
                -Summary 'No active physical network adapter detected.'))
        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Adapter inventory' -Status 'Info' `
            -Summary 'Network adapter details unavailable.' -Details $_.Exception.Message))
    }

    if(-not $Config.scan.networkTests){ return $out }

    try {
        $resolved = @(Resolve-DnsName -Name $Config.network.dnsTestName -Type A -ErrorAction Stop | Where-Object IPAddress)
        $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Healthy' `
            -Summary "Resolved $($Config.network.dnsTestName) successfully." `
            -Details "Addresses: $($resolved.IPAddress -join ', ')"))
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Warning' `
            -Summary "Could not resolve $($Config.network.dnsTestName)." -Details $_.Exception.Message `
            -Recommendation 'Check DNS server configuration and network connectivity.'))
    }

    try {
        $tcp = Test-NetConnection -ComputerName $Config.network.connectivityHost `
            -Port ([int]$Config.network.connectivityPort) -WarningAction SilentlyContinue
        $tcpOk = [bool]$tcp.TcpTestSucceeded
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' `
            -Status $(if($tcpOk){'Healthy'}else{'Warning'}) `
            -Summary $(if($tcpOk){"TCP 443 connectivity confirmed to $($Config.network.connectivityHost)."}else{"Unable to establish TCP 443 connectivity to $($Config.network.connectivityHost)."}) `
            -Details "Remote address: $($tcp.RemoteAddress)`nSource address: $($tcp.SourceAddress)" `
            -Recommendation $(if(-not $tcpOk){'Check internet access, firewall, proxy, VPN, or upstream routing.'}else{''})))
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' -Status 'Warning' `
            -Summary 'TCP 443 connectivity test failed.' -Details $_.Exception.Message `
            -Recommendation 'Check internet access, firewall, proxy, VPN, or upstream routing.'))
    }

    try {
        $response = Invoke-WebRequest -Uri $Config.network.httpConnectivityUrl -UseBasicParsing `
            -TimeoutSec ([int]$Config.network.timeoutSeconds) -ErrorAction Stop
        $body = [string]$response.Content
        $expected = [string]$Config.network.httpExpectedContent
        $match = $body.Trim() -eq $expected
        $state = if($match){'Healthy'}else{'Recommend'}
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Microsoft connectivity test' -Status $state `
            -Summary $(if($match){'Microsoft connectivity test returned the expected response.'}else{'Microsoft connectivity endpoint responded, but the content was unexpected.'}) `
            -Details "URL: $($Config.network.httpConnectivityUrl)`nHTTP status: $($response.StatusCode)`nExpected: $expected`nReceived: $($body.Trim())" `
            -Recommendation $(if(-not $match){'A captive portal, proxy, filtering service, or redirect may be altering the connectivity-test response.'}else{''})))
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Microsoft connectivity test' -Status 'Warning' `
            -Summary 'Microsoft HTTP connectivity test failed.' -Details $_.Exception.ToString() `
            -Recommendation 'Check internet access, captive portal, proxy, filtering, or HTTP connectivity.'))
    }

    $tcpClient = $null
    $ssl = $null
    try {
        $hostName = [string]$Config.network.httpsTestHost
        $port = [int]$Config.network.httpsTestPort
        $script:tlsPolicyErrors = [System.Net.Security.SslPolicyErrors]::None
        $script:tlsRemoteCert = $null

        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $async = $tcpClient.BeginConnect($hostName,$port,$null,$null)
        if(-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds([int]$Config.network.timeoutSeconds))){
            throw "Timed out connecting to $hostName`:$port."
        }
        $tcpClient.EndConnect($async)

        $callback = {
            param($sender,$certificate,$chain,$sslPolicyErrors)
            $script:tlsPolicyErrors = $sslPolicyErrors
            $script:tlsRemoteCert = $certificate
            return $true
        }

        $ssl = New-Object System.Net.Security.SslStream($tcpClient.GetStream(),$false,$callback)
        $ssl.AuthenticateAsClient($hostName)

        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $chainValid = $chain.Build($cert)
        $chainStatuses = @($chain.ChainStatus | ForEach-Object {$_.Status.ToString()}) -join ', '
        if([string]::IsNullOrWhiteSpace($chainStatuses)){$chainStatuses='None'}

        $sanText = ''
        try {
            $san = $cert.Extensions | Where-Object {$_.Oid.Value -eq '2.5.29.17'} | Select-Object -First 1
            if($san){$sanText=$san.Format($true)}
        } catch {}

        $policyOk = $script:tlsPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None
        $state = if($chainValid -and $policyOk){'Healthy'}else{'Warning'}
        $summary = if($state -eq 'Healthy'){
            "TLS handshake and certificate validation succeeded for $hostName."
        } else {
            "TLS handshake succeeded, but certificate validation reported $($script:tlsPolicyErrors)."
        }

        $details = @(
            "Host: $hostName"
            "TLS protocol: $($ssl.SslProtocol)"
            "Certificate subject: $($cert.Subject)"
            "Certificate issuer: $($cert.Issuer)"
            "Valid from: $($cert.NotBefore)"
            "Valid to: $($cert.NotAfter)"
            "Thumbprint: $($cert.Thumbprint)"
            "Policy errors: $($script:tlsPolicyErrors)"
            "Chain valid: $chainValid"
            "Chain status: $chainStatuses"
            $(if($sanText){"Subject Alternative Names:`n$sanText"}else{'Subject Alternative Names: unavailable'})
        ) -join "`n"

        $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS/TLS validation' -Status $state `
            -Summary $summary -Details $details `
            -Recommendation $(if($state -ne 'Healthy'){'Review certificate hostname, chain, trusted roots, system time, proxy/TLS inspection, or security software.'}else{''})))
    } catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS/TLS validation' -Status 'Warning' `
            -Summary 'TLS handshake/certificate diagnostic failed.' -Details $_.Exception.ToString() `
            -Recommendation 'Review internet connectivity, certificate trust, system time, proxy/TLS inspection, or security software.'))
    } finally {
        if($ssl){$ssl.Dispose()}
        if($tcpClient){$tcpClient.Dispose()}
    }

    return $out
}
Export-ModuleMember -Function Get-RBZNetworkFindings
