function Get-RBZGatewayPingResult {
    param(
        [string]$Gateway,
        [int]$Count=4
    )

    if([string]::IsNullOrWhiteSpace($Gateway)){return $null}

    try {
        $responses=@(Test-Connection -ComputerName $Gateway -Count $Count -ErrorAction SilentlyContinue)
        $received=$responses.Count
        $lossPct=[math]::Round((($Count-$received)/[double]$Count)*100,0)

        $avg=$null
        $min=$null
        $max=$null

        if($received -gt 0){
            $times=@($responses | ForEach-Object {[double]$_.ResponseTime})
            $avg=[math]::Round((($times | Measure-Object -Average).Average),1)
            $min=[math]::Round((($times | Measure-Object -Minimum).Minimum),1)
            $max=[math]::Round((($times | Measure-Object -Maximum).Maximum),1)
        }

        [pscustomobject]@{
            Sent=$Count
            Received=$received
            LossPercent=$lossPct
            AverageMs=$avg
            MinimumMs=$min
            MaximumMs=$max
        }
    }
    catch {$null}
}

function Get-RBZNetworkFindings {
    param($Config)

    $out=[System.Collections.Generic.List[object]]::new()
    $activeAdapters=[System.Collections.Generic.List[object]]::new()

    # ---------------------------------------------------------------------
    # Adapter/IP configuration
    # ---------------------------------------------------------------------
    try {
        $up=@(
            Get-NetAdapter -Physical -ErrorAction Stop |
            Where-Object Status -eq 'Up' |
            Sort-Object ifIndex
        )

        if($up.Count){
            foreach($adapter in $up){
                $ip=Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
                $ipInterface=Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
                $dnsObj=Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

                $ipv4=@($ip.IPv4Address | ForEach-Object {$_.IPAddress} | Where-Object {$_})
                $gateways=@($ip.IPv4DefaultGateway | ForEach-Object {$_.NextHop} | Where-Object {$_})
                $dnsServers=@($dnsObj.ServerAddresses | Where-Object {$_})

                $dhcp=if($null -ne $ipInterface){[string]$ipInterface.Dhcp}else{'Unknown'}
                $metric=if($null -ne $ipInterface){$ipInterface.InterfaceMetric}else{$null}
                $connectionProfile=$null
                try {
                    $connectionProfile=Get-NetConnectionProfile -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | Select-Object -First 1
                } catch {}

                $state='Healthy'
                $issues=[System.Collections.Generic.List[string]]::new()

                if($ipv4.Count -eq 0){
                    $state='Warning'
                    $issues.Add('No IPv4 address is assigned.')
                }

                $apipa=@($ipv4 | Where-Object {$_ -like '169.254.*'})
                if($apipa.Count -gt 0){
                    $state='Warning'
                    $issues.Add('An APIPA 169.254.x.x address is present, usually indicating DHCP/configuration failure.')
                }

                if($dnsServers.Count -eq 0){
                    $state='Warning'
                    $issues.Add('No IPv4 DNS server is configured.')
                }

                $summary="$($adapter.Name) ($($adapter.LinkSpeed))"
                if($ipv4.Count -gt 0){$summary+=" | IPv4: $($ipv4 -join ', ')"}

                $details=[System.Collections.Generic.List[string]]::new()
                $details.Add("Adapter: $($adapter.Name)")
                $details.Add("Description: $($adapter.InterfaceDescription)")
                $details.Add("Interface index: $($adapter.ifIndex)")
                $details.Add("Link speed: $($adapter.LinkSpeed)")
                $details.Add("MAC address: $($adapter.MacAddress)")
                $details.Add("IPv4: $(if($ipv4.Count){$ipv4 -join ', '}else{'None'})")
                $details.Add("Gateway: $(if($gateways.Count){$gateways -join ', '}else{'None'})")
                $details.Add("DNS: $(if($dnsServers.Count){$dnsServers -join ', '}else{'None'})")
                $details.Add("DHCP: $dhcp")
                if($null -ne $metric){$details.Add("Interface metric: $metric")}
                if($null -ne $connectionProfile){
                    $details.Add("Network profile: $($connectionProfile.NetworkCategory)")
                    if($connectionProfile.Name){$details.Add("Network name: $($connectionProfile.Name)")}
                }
                if($issues.Count -gt 0){
                    $details.Add('')
                    $details.Add('Detected configuration issue(s):')
                    foreach($issue in $issues){$details.Add("- $issue")}
                }

                $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status $state `
                    -Summary $summary `
                    -Details ($details -join "`n") `
                    -Recommendation $(if($state -ne 'Healthy'){
                        'Review adapter IPv4, DHCP and DNS configuration before troubleshooting upstream connectivity.'
                    }else{''})))

                $activeAdapters.Add([pscustomobject]@{
                    Adapter=$adapter
                    IPv4=$ipv4
                    Gateways=$gateways
                    DnsServers=$dnsServers
                    Dhcp=$dhcp
                })
            }
        }
        else{
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Active adapter' -Status 'Warning' `
                -Summary 'No active physical network adapter detected.'))
        }
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Adapter inventory' -Status 'Info' `
            -Summary 'Network adapter details unavailable.' `
            -Details $_.Exception.Message))
    }

    if(-not $Config.scan.networkTests){return $out}

    # ---------------------------------------------------------------------
    # Default gateway configuration/reachability.
    # ICMP failure is Info because many routers/firewalls intentionally
    # suppress ping while routing traffic normally.
    # ---------------------------------------------------------------------
    try {
        $allGateways=@(
            $activeAdapters |
            ForEach-Object {$_.Gateways} |
            Where-Object {$_} |
            Sort-Object -Unique
        )

        if($activeAdapters.Count -gt 0 -and $allGateways.Count -eq 0){
            $out.Add((New-RBZFinding -Category 'Network' -Name 'Default gateway' -Status 'Recommend' `
                -Summary 'No IPv4 default gateway is configured on an active physical adapter.' `
                -Recommendation 'Check DHCP/static IPv4 configuration. A gateway may be unnecessary only on intentionally isolated networks.'))
        }
        elseif($allGateways.Count -gt 0){
            $pingCount=[int]$Config.network.gatewayPingCount
            if($pingCount -lt 1){$pingCount=4}

            foreach($gateway in $allGateways){
                $ping=Get-RBZGatewayPingResult -Gateway $gateway -Count $pingCount

                if($null -eq $ping){
                    $out.Add((New-RBZFinding -Category 'Network' -Name 'Default gateway' -Status 'Info' `
                        -Summary "Gateway $gateway is configured; ICMP latency test was unavailable." `
                        -Details "Gateway: $gateway" `
                        -Recommendation 'ICMP may be blocked. Use the TCP/HTTP connectivity results to judge actual routing/internet access.'))
                    continue
                }

                if($ping.Received -eq 0){
                    $out.Add((New-RBZFinding -Category 'Network' -Name 'Default gateway' -Status 'Info' `
                        -Summary "Gateway $gateway is configured but did not reply to ICMP echo requests." `
                        -Details "Gateway: $gateway`nSent: $($ping.Sent)`nReceived: 0`nPacket loss: 100%" `
                        -Recommendation 'This is informational because routers can block ICMP. If TCP/internet checks also fail, investigate the local gateway or network path.'))
                }
                else{
                    $latencyWarn=[double]$Config.network.gatewayLatencyWarningMs
                    if($latencyWarn -lt 1){$latencyWarn=50}

                    $lossWarn=[double]$Config.network.gatewayPacketLossWarningPercent
                    if($lossWarn -lt 1){$lossWarn=25}

                    $state=if($ping.LossPercent -ge $lossWarn -or $ping.AverageMs -ge $latencyWarn){
                        'Recommend'
                    }else{
                        'Healthy'
                    }

                    $out.Add((New-RBZFinding -Category 'Network' -Name 'Default gateway' -Status $state `
                        -Summary "Gateway $gateway | Avg: $($ping.AverageMs) ms | Loss: $($ping.LossPercent)%" `
                        -Details "Gateway: $gateway`nSent: $($ping.Sent)`nReceived: $($ping.Received)`nPacket loss: $($ping.LossPercent)%`nMinimum: $($ping.MinimumMs) ms`nAverage: $($ping.AverageMs) ms`nMaximum: $($ping.MaximumMs) ms" `
                        -Recommendation $(if($state -eq 'Recommend'){
                            'Elevated local-gateway latency or packet loss was observed. Retest before concluding there is a fault, then review Wi-Fi/Ethernet quality, cabling, switch/router load or local congestion.'
                        }else{''})))
                }
            }
        }
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Default gateway' -Status 'Info' `
            -Summary 'Default-gateway diagnostic was unavailable.' `
            -Details $_.Exception.Message))
    }

    # ---------------------------------------------------------------------
    # DNS configuration
    # ---------------------------------------------------------------------
    try {
        $dnsConfigured=@(
            $activeAdapters |
            ForEach-Object {$_.DnsServers} |
            Where-Object {$_} |
            Sort-Object -Unique
        )

        if($activeAdapters.Count -gt 0){
            if($dnsConfigured.Count -eq 0){
                $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS configuration' -Status 'Warning' `
                    -Summary 'No IPv4 DNS server is configured on an active physical adapter.' `
                    -Recommendation 'Check DHCP/static DNS configuration.'))
            }
            else{
                $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS configuration' -Status 'Healthy' `
                    -Summary "$($dnsConfigured.Count) unique IPv4 DNS server(s) configured." `
                    -Details "DNS servers:`n$($dnsConfigured -join "`n")"))
            }
        }
    }
    catch {}

    # DNS resolution with elapsed timing.
    try {
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $resolved=@(
            Resolve-DnsName -Name $Config.network.dnsTestName -Type A -ErrorAction Stop |
            Where-Object IPAddress
        )
        $sw.Stop()
        $dnsMs=[math]::Round($sw.Elapsed.TotalMilliseconds,0)

        $dnsWarn=[double]$Config.network.dnsLatencyWarningMs
        if($dnsWarn -lt 1){$dnsWarn=1000}

        $state=if($dnsMs -ge $dnsWarn){'Recommend'}else{'Healthy'}

        $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status $state `
            -Summary "Resolved $($Config.network.dnsTestName) successfully in $dnsMs ms." `
            -Details "Addresses: $($resolved.IPAddress -join ', ')`nResolution time: $dnsMs ms" `
            -Recommendation $(if($state -eq 'Recommend'){
                'DNS resolution was slower than the configured advisory threshold. Retest before changing DNS settings.'
            }else{''})))
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'DNS resolution' -Status 'Warning' `
            -Summary "Could not resolve $($Config.network.dnsTestName)." `
            -Details $_.Exception.Message `
            -Recommendation 'Check DNS server configuration and network connectivity.'))
    }

    # ---------------------------------------------------------------------
    # Existing internet TCP path test.
    # ---------------------------------------------------------------------
    try {
        $tcp=Test-NetConnection -ComputerName $Config.network.connectivityHost `
            -Port ([int]$Config.network.connectivityPort) -WarningAction SilentlyContinue

        $tcpOk=[bool]$tcp.TcpTestSucceeded

        $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' `
            -Status $(if($tcpOk){'Healthy'}else{'Warning'}) `
            -Summary $(if($tcpOk){
                "TCP 443 connectivity confirmed to $($Config.network.connectivityHost)."
            }else{
                "Unable to establish TCP 443 connectivity to $($Config.network.connectivityHost)."
            }) `
            -Details "Remote address: $($tcp.RemoteAddress)`nSource address: $($tcp.SourceAddress)" `
            -Recommendation $(if(-not $tcpOk){
                'Check internet access, firewall, proxy, VPN, or upstream routing.'
            }else{''})))
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Internet path (TCP 443)' -Status 'Warning' `
            -Summary 'TCP 443 connectivity test failed.' `
            -Details $_.Exception.Message `
            -Recommendation 'Check internet access, firewall, proxy, VPN, or upstream routing.'))
    }

    # Microsoft connectivity endpoint.
    try {
        $response=Invoke-WebRequest -Uri $Config.network.httpConnectivityUrl -UseBasicParsing `
            -TimeoutSec ([int]$Config.network.timeoutSeconds) -ErrorAction Stop

        $body=[string]$response.Content
        $expected=[string]$Config.network.httpExpectedContent
        $match=$body.Trim() -eq $expected
        $state=if($match){'Healthy'}else{'Recommend'}

        $out.Add((New-RBZFinding -Category 'Network' -Name 'Microsoft connectivity test' -Status $state `
            -Summary $(if($match){
                'Microsoft connectivity test returned the expected response.'
            }else{
                'Microsoft connectivity endpoint responded, but the content was unexpected.'
            }) `
            -Details "URL: $($Config.network.httpConnectivityUrl)`nHTTP status: $($response.StatusCode)`nExpected: $expected`nReceived: $($body.Trim())" `
            -Recommendation $(if(-not $match){
                'A captive portal, proxy, filtering service, or redirect may be altering the connectivity-test response.'
            }else{''})))
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'Microsoft connectivity test' -Status 'Warning' `
            -Summary 'Microsoft HTTP connectivity test failed.' `
            -Details $_.Exception.ToString() `
            -Recommendation 'Check internet access, captive portal, proxy, filtering, or HTTP connectivity.'))
    }

    # HTTPS/TLS validation.
    $tcpClient=$null
    $ssl=$null

    try {
        $hostName=[string]$Config.network.httpsTestHost
        $port=[int]$Config.network.httpsTestPort
        $script:tlsPolicyErrors=[System.Net.Security.SslPolicyErrors]::None
        $script:tlsRemoteCert=$null

        $tcpClient=New-Object System.Net.Sockets.TcpClient
        $async=$tcpClient.BeginConnect($hostName,$port,$null,$null)

        if(-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds([int]$Config.network.timeoutSeconds))){
            throw "Timed out connecting to $hostName`:$port."
        }

        $tcpClient.EndConnect($async)

        $callback={
            param($sender,$certificate,$chain,$sslPolicyErrors)
            $script:tlsPolicyErrors=$sslPolicyErrors
            $script:tlsRemoteCert=$certificate
            return $true
        }

        $ssl=New-Object System.Net.Security.SslStream($tcpClient.GetStream(),$false,$callback)
        $ssl.AuthenticateAsClient($hostName)

        $cert=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $chain=New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode=[System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $chainValid=$chain.Build($cert)

        $chainStatuses=@(
            $chain.ChainStatus |
            ForEach-Object {$_.Status.ToString()}
        ) -join ', '

        if([string]::IsNullOrWhiteSpace($chainStatuses)){$chainStatuses='None'}

        $sanText=''
        try {
            $san=$cert.Extensions |
                Where-Object {$_.Oid.Value -eq '2.5.29.17'} |
                Select-Object -First 1

            if($san){$sanText=$san.Format($true)}
        }
        catch {}

        $policyOk=$script:tlsPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None
        $state=if($chainValid -and $policyOk){'Healthy'}else{'Warning'}

        $summary=if($state -eq 'Healthy'){
            "TLS handshake and certificate validation succeeded for $hostName."
        }else{
            "TLS handshake succeeded, but certificate validation reported $($script:tlsPolicyErrors)."
        }

        $details=@(
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
            -Summary $summary `
            -Details $details `
            -Recommendation $(if($state -ne 'Healthy'){
                'Review certificate hostname, chain, trusted roots, system time, proxy/TLS inspection, or security software.'
            }else{''})))
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Network' -Name 'HTTPS/TLS validation' -Status 'Warning' `
            -Summary 'TLS handshake/certificate diagnostic failed.' `
            -Details $_.Exception.ToString() `
            -Recommendation 'Review internet connectivity, certificate trust, system time, proxy/TLS inspection, or security software.'))
    }
    finally {
        if($ssl){$ssl.Dispose()}
        if($tcpClient){$tcpClient.Dispose()}
    }

    return $out
}

Export-ModuleMember -Function Get-RBZNetworkFindings
