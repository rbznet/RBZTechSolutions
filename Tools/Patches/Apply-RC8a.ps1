$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$servicePath=Join-Path $repoRoot 'Modules\Service.psm1'
if(-not(Test-Path $servicePath)){throw "Missing $servicePath"}

$service=Get-Content -Raw $servicePath

if($service -match 'RBZ080RC8A_TIME_VERIFY'){
    Write-Host 'RC8a already applied.' -ForegroundColor Yellow
    exit 0
}

if($service -notmatch 'RBZ080RC8_SAFE_REPAIRS'){
    throw 'RC8a requires RC8 to be applied first.'
}

# Add RC8a marker.
$marker="            'WindowsTimeResync' {"
$replacement="            # RBZ080RC8A_TIME_VERIFY`r`n            'WindowsTimeResync' {"
if(-not $service.Contains($marker)){throw 'RC8a Windows Time action marker not found.'}
$service=$service.Replace($marker,$replacement)

# Replace initial verification block.
$old=@'
                $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                $source=[string]$sourceQuery.Output;$status=[string]$statusQuery.Output
                $sourceValid=($sourceQuery.ExitCode -eq 0 -and $source -notmatch '(?i)local cmos clock|free-running system clock' -and -not [string]::IsNullOrWhiteSpace($source))
                $statusValid=($statusQuery.ExitCode -eq 0 -and $status -notmatch '(?im)^\s*Leap Indicator:\s*3' -and -not [string]::IsNullOrWhiteSpace($status))
                $verified=($sourceValid -and $statusValid)
                $fallbackOutput='Not required.'
'@

$new=@'
                $source='';$status='';$verified=$false;$sourceValid=$false;$statusValid=$false
                $verificationAttempts=[System.Collections.Generic.List[string]]::new()

                for($attempt=1;$attempt -le 5;$attempt++){
                    $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                    $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'

                    $source=[string]$sourceQuery.Output
                    $status=[string]$statusQuery.Output

                    $sourceValid=(
                        -not [string]::IsNullOrWhiteSpace($source) -and
                        $source -notmatch '(?i)local cmos clock|free-running system clock|unspecified'
                    )

                    $leapBad=($status -match '(?im)^\s*Leap Indicator\s*:\s*3')
                    $stratumBad=($status -match '(?im)^\s*Stratum\s*:\s*0\b')
                    $lastSyncBad=($status -match '(?im)^\s*Last Successful Sync Time\s*:\s*(unspecified|$)')

                    $statusValid=(
                        -not [string]::IsNullOrWhiteSpace($status) -and
                        $status -match '(?im)^\s*Leap Indicator\s*:\s*[012]\b' -and
                        -not $leapBad -and
                        -not $stratumBad -and
                        -not $lastSyncBad
                    )

                    $verified=($sourceValid -and $statusValid)

                    $verificationAttempts.Add(
                        "Attempt $attempt | SourceExit=$($sourceQuery.ExitCode) StatusExit=$($statusQuery.ExitCode) | Source='$source' | Verified=$verified"
                    )

                    if($verified){break}
                    Start-Sleep -Seconds 2
                }

                $fallbackOutput='Not required.'
'@

if(-not $service.Contains($old)){throw 'RC8a initial verification block not found.'}
$service=$service.Replace($old,$new)

# Replace fallback verification block.
$old2=@'
                    $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                    $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                    $source=[string]$sourceQuery.Output;$status=[string]$statusQuery.Output
                    $sourceValid=($sourceQuery.ExitCode -eq 0 -and $source -notmatch '(?i)local cmos clock|free-running system clock' -and -not [string]::IsNullOrWhiteSpace($source))
                    $statusValid=($statusQuery.ExitCode -eq 0 -and $status -notmatch '(?im)^\s*Leap Indicator:\s*3' -and -not [string]::IsNullOrWhiteSpace($status))
                    $verified=($sourceValid -and $statusValid)
'@

$new2=@'
                    for($attempt=1;$attempt -le 5;$attempt++){
                        $sourceQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                        $statusQuery=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'

                        $source=[string]$sourceQuery.Output
                        $status=[string]$statusQuery.Output

                        $sourceValid=(
                            -not [string]::IsNullOrWhiteSpace($source) -and
                            $source -notmatch '(?i)local cmos clock|free-running system clock|unspecified'
                        )

                        $leapBad=($status -match '(?im)^\s*Leap Indicator\s*:\s*3')
                        $stratumBad=($status -match '(?im)^\s*Stratum\s*:\s*0\b')
                        $lastSyncBad=($status -match '(?im)^\s*Last Successful Sync Time\s*:\s*(unspecified|$)')

                        $statusValid=(
                            -not [string]::IsNullOrWhiteSpace($status) -and
                            $status -match '(?im)^\s*Leap Indicator\s*:\s*[012]\b' -and
                            -not $leapBad -and
                            -not $stratumBad -and
                            -not $lastSyncBad
                        )

                        $verified=($sourceValid -and $statusValid)

                        $verificationAttempts.Add(
                            "Fallback attempt $attempt | SourceExit=$($sourceQuery.ExitCode) StatusExit=$($statusQuery.ExitCode) | Source='$source' | Verified=$verified"
                        )

                        if($verified){break}
                        Start-Sleep -Seconds 2
                    }
'@

if(-not $service.Contains($old2)){throw 'RC8a fallback verification block not found.'}
$service=$service.Replace($old2,$new2)

# Inject verification-attempt log into the existing here-string safely.
$old3=@'
After status:
$status

RBZ did not change the NTP server, registry settings or policy.
'@

$new3=@'
After status:
$status

Verification attempts:
$($verificationAttempts -join "`n")

RBZ did not change the NTP server, registry settings or policy.
'@

if(-not $service.Contains($old3)){throw 'RC8a detail-output marker not found.'}
$service=$service.Replace($old3,$new3)

Set-Content -LiteralPath $servicePath -Value $service -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC8a applied.' -ForegroundColor Green
Write-Host 'Windows Time verification now polls actual status and ignores unreliable query exit-code behaviour.' -ForegroundColor Cyan
Write-Host 'No other Repair Centre actions were changed.' -ForegroundColor DarkGray
