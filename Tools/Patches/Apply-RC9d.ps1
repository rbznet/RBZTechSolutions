$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'

foreach($p in @($servicePath,$mainPath)){
    if(-not(Test-Path -LiteralPath $p)){throw "Required file not found: $p"}
}

$service=Get-Content -Raw $servicePath
$main=Get-Content -Raw $mainPath

if($service -match 'RBZ080RC9D_RESTART_REQUIRED'){
    Write-Host 'RBZ PC Health v0.8.0 RC9d is already applied.' -ForegroundColor Yellow
    exit 0
}

if($service -notmatch 'RBZ080RC9_REPAIR_EXPANSION'){
    throw 'RC9d requires RC9 to be applied first.'
}

# ---------------------------------------------------------------------------
# 1. Replace network reset action with restart-aware result handling.
# ---------------------------------------------------------------------------
$oldNet=@'
            'ResetNetworkStack' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Windows network stack' -Message 'Resetting Winsock and TCP/IP...' -Started $started -Indeterminate:$true

                $winsock=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('winsock','reset') -ProgressPath $ProgressPath -Stage 'Winsock reset'
                $ip=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('int','ip','reset') -ProgressPath $ProgressPath -Stage 'TCP/IP reset'
                $ok=($winsock.ExitCode -eq 0 -and $ip.ExitCode -eq 0)

                $result.Success=$ok
                $result.RequiresRestart=$true
                $result.Summary=$(if($ok){'Windows network stack reset completed. Restart Windows to finish the repair.'}else{'One or more Windows network stack reset commands failed.'})
                $result.Details="Winsock exit: $($winsock.ExitCode)`n$($winsock.Output)`n`nTCP/IP exit: $($ip.ExitCode)`n$($ip.Output)"
                $result.VerificationCategory='Network'
                $result.VerificationCheck='Windows network stack'
                $result.VerificationStatus=$(if($ok){'Recommend'}else{'Warning'})
                $result.VerificationSummary=$(if($ok){'Network stack reset completed; a Windows restart is required before final verification.'}else{'Network stack reset did not complete successfully.'})
                $result.VerificationDetails=$result.Details
            }
'@

$newNet=@'
            # RBZ080RC9D_RESTART_REQUIRED
            'ResetNetworkStack' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Windows network stack' -Message 'Resetting Winsock and TCP/IP...' -Started $started -Indeterminate:$true

                $winsock=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('winsock','reset') -ProgressPath $ProgressPath -Stage 'Winsock reset'
                $ip=Invoke-RBZNativeCommand -FilePath 'netsh.exe' -Arguments @('int','ip','reset') -ProgressPath $ProgressPath -Stage 'TCP/IP reset'

                $winsockText=[string]$winsock.Output
                $ipText=[string]$ip.Output

                $winsockProcessed=(
                    $winsockText -match '(?i)successfully reset the winsock catalog' -or
                    $winsockText -match '(?i)restart the computer'
                )

                $ipProcessed=(
                    $ipText -match '(?im)^\s*Resetting .*OK!' -or
                    $ipText -match '(?i)restart the computer to complete this action'
                )

                $knownAccessDeniedOnly=(
                    $ipText -match '(?i)access is denied' -and
                    $ipText -match '(?im)^\s*Resetting .*OK!'
                )

                $restartRequested=(
                    $winsockText -match '(?i)restart the computer' -or
                    $ipText -match '(?i)restart the computer'
                )

                # Treat the common netsh behaviour as processed/restart-required
                # even when netsh returns exit code 1 because one protected item
                # reports Access Denied. A true failure is when the reset did not
                # materially process at all.
                $processed=(
                    $winsockProcessed -and
                    $ipProcessed -and
                    ($knownAccessDeniedOnly -or $ip.ExitCode -eq 0 -or $restartRequested)
                )

                $trueFailure=(-not $processed)

                $result.Success=(-not $trueFailure)
                $result.RequiresRestart=$processed
                $result.Summary=$(if($processed){
                    'Windows network stack reset was processed. Restart Windows to complete the repair.'
                }else{
                    'Windows network stack reset could not be processed successfully.'
                })

                $result.Details=@"
Winsock exit code: $($winsock.ExitCode)
Winsock processed: $winsockProcessed

$winsockText

TCP/IP exit code: $($ip.ExitCode)
TCP/IP processed: $ipProcessed
Known Access Denied pattern detected: $knownAccessDeniedOnly

$ipText

Restart required: $restartRequested

Interpretation:
RBZ treats the known netsh Access Denied pattern as restart-required when the Winsock/TCP-IP reset was otherwise processed. A restart is still required before final verification.
"@

                $result.VerificationCategory='Network'
                $result.VerificationCheck='Windows network stack'

                if($processed){
                    $result.VerificationStatus='Recommend'
                    $result.VerificationSummary='Restart Required - Winsock and TCP/IP reset were processed. Restart Windows, then run Verify Repairs.'
                }else{
                    $result.VerificationStatus='Warning'
                    $result.VerificationSummary='Network stack reset did not process successfully.'
                }

                $result.VerificationDetails=$result.Details
            }
'@

if(-not $service.Contains($oldNet)){
    throw 'RC9d network reset action block was not found. Make sure RC9 is applied.'
}
$service=$service.Replace($oldNet,$newNet)

# ---------------------------------------------------------------------------
# 2. Add persistent restart-required banner/state in the GUI.
#    It is session-level and is set when an action result RequiresRestart=True.
# ---------------------------------------------------------------------------

# Add a banner row above footer content by replacing footer Border opening.
$footerOld=@'
<Border Grid.Row="4" Margin="18,10,18,14">
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<ProgressBar Name="Progress" Height="10" Minimum="0" Maximum="100" IsIndeterminate="False" Visibility="Collapsed"/>
<Grid Grid.Row="1" Margin="0,8,0,0">
'@

$footerNew=@'
<Border Grid.Row="4" Margin="18,10,18,14">
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

<Border Name="RestartRequiredBanner"
        Grid.Row="0"
        Background="#FEF3C7"
        BorderBrush="#F59E0B"
        BorderThickness="1"
        CornerRadius="4"
        Padding="10,7"
        Margin="0,0,0,8"
        Visibility="Collapsed">
<TextBlock Name="RestartRequiredText"
           Text="Restart required to complete one or more repairs."
           Foreground="#92400E"
           FontWeight="SemiBold"/>
</Border>

<ProgressBar Grid.Row="1" Name="Progress" Height="10" Minimum="0" Maximum="100" IsIndeterminate="False" Visibility="Collapsed"/>
<Grid Grid.Row="2" Margin="0,8,0,0">
'@

if(-not $main.Contains($footerOld)){
    throw 'RC9d footer layout marker not found.'
}
$main=$main.Replace($footerOld,$footerNew)

# Add names to FindName list.
$findOld="'ActionElapsedText','BaselineScoreText'"
$findNew="'ActionElapsedText','RestartRequiredBanner','RestartRequiredText','BaselineScoreText'"
if(-not $main.Contains($findOld)){
    throw 'RC9d control binding marker not found.'
}
$main=$main.Replace($findOld,$findNew)

# Initialize restart flag after theme/session setup marker.
$initMarker="$script:Theme='Light'"
$initReplacement="$script:Theme='Light'`r`n$script:RestartRequired=$false"
if(-not $main.Contains($initMarker)){
    throw 'RC9d initialization marker not found.'
}
$main=$main.Replace($initMarker,$initReplacement)

# When a repair result requires restart, show the banner.
$logOld=@'
            $ActionLogBox.AppendText(
                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                "$($r.Summary)$verifyText$detailText`r`n`r`n"
            )
'@

$logNew=@'
            $ActionLogBox.AppendText(
                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                "$($r.Summary)$verifyText$detailText`r`n`r`n"
            )

            if([bool]$r.RequiresRestart){
                $script:RestartRequired=$true
                $RestartRequiredText.Text="Restart required to complete: $($a.Name). Restart Windows, then run Verify Repairs."
                $RestartRequiredBanner.Visibility='Visible'
            }
'@

if(-not $main.Contains($logOld)){
    throw 'RC9d Repair Centre post-action marker not found.'
}
$main=$main.Replace($logOld,$logNew)

Set-Content -LiteralPath $servicePath -Value $service -Encoding UTF8
Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC9d applied.' -ForegroundColor Green
Write-Host 'Network reset now reports Restart Required for the known netsh Access Denied pattern.' -ForegroundColor Cyan
Write-Host 'A restart-required banner is shown after actions that require Windows restart.' -ForegroundColor Cyan
Write-Host 'No automatic restart is performed.' -ForegroundColor DarkGray
