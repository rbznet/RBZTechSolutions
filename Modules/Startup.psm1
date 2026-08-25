function Get-RBZStartupTarget {
    param([string]$Command)

    if([string]::IsNullOrWhiteSpace($Command)){return $null}

    $expanded=[Environment]::ExpandEnvironmentVariables($Command.Trim())

    # Quoted executable path.
    if($expanded -match '^\s*"([^"]+\.exe)"'){
        return $matches[1]
    }

    # Unquoted executable path/token.
    if($expanded -match '^\s*([^\r\n]+?\.exe)(?:\s|$)'){
        return $matches[1].Trim()
    }

    $null
}

function Get-RBZStartupFindings {
    param($Config)

    $out=[System.Collections.Generic.List[object]]::new()

    # ---------------------------------------------------------------------
    # Startup applications
    # ---------------------------------------------------------------------
    try {
        $items=@(
            Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
            Sort-Object Name,User,Location
        )

        $limit=[int]$Config.thresholds.startupCountRecommend
        $status=if($items.Count -gt $limit){'Recommend'}else{'Info'}

        $detailLines=[System.Collections.Generic.List[string]]::new()

        foreach($item in $items){
            $name=if($item.Name){[string]$item.Name}else{'Unnamed startup item'}
            $location=if($item.Location){[string]$item.Location}else{'Unknown location'}
            $user=if($item.User){[string]$item.User}else{'Unknown user'}
            $target=Get-RBZStartupTarget -Command ([string]$item.Command)

            $detailLines.Add("$name | User: $user | Location: $location")
            if(-not [string]::IsNullOrWhiteSpace([string]$target)){
                $detailLines.Add("Target: $target")
            }
            $detailLines.Add("Command: $($item.Command)")
            $detailLines.Add('')
        }

        $out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status $status `
            -Summary "$($items.Count) startup command(s) detected." `
            -Details (($detailLines -join "`n").Trim()) `
            -Value $items.Count `
            -Recommendation $(if($status -eq 'Recommend'){
                'Review unnecessary startup applications with the customer before disabling anything.'
            }else{
                'Review the detailed list if startup performance is a concern.'
            })))

        # Identify exact repeated startup commands. Duplicates are advisory:
        # they can be intentional, so they never become a Warning.
        $duplicates=@(
            $items |
            Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.Command)} |
            Group-Object {([string]$_.Command).Trim().ToLowerInvariant()} |
            Where-Object Count -gt 1 |
            Sort-Object Count -Descending
        )

        if($duplicates.Count -gt 0){
            $dupLines=[System.Collections.Generic.List[string]]::new()

            foreach($group in $duplicates){
                $sample=$group.Group | Select-Object -First 1
                $names=@(
                    $group.Group |
                    ForEach-Object {
                        if($_.Name){[string]$_.Name}else{'Unnamed startup item'}
                    } |
                    Sort-Object -Unique
                )

                $dupLines.Add("$($group.Count)x | $($names -join ', ')")
                $dupLines.Add('')
                $dupLines.Add('Command:')
                $dupLines.Add([string]$sample.Command)
                $dupLines.Add('')
                $dupLines.Add('Registrations:')

                foreach($registration in @($group.Group | Sort-Object Location,User,Name)){
                    $regName=if($registration.Name){[string]$registration.Name}else{'Unnamed startup item'}
                    $regLocation=if($registration.Location){[string]$registration.Location}else{'Unknown location'}
                    $regUser=if($registration.User){[string]$registration.User}else{'Unknown user'}
                    $dupLines.Add("$regLocation | User: $regUser | Name: $regName")
                }

                $dupLines.Add('')
            }

            $out.Add((New-RBZFinding -Category 'Startup' -Name 'Duplicate startup commands' -Status 'Info' `
                -Summary "$($duplicates.Count) duplicated startup command group(s) detected." `
                -Details (($dupLines -join "`n").Trim()) `
                -Value $duplicates.Count `
                -Recommendation 'Informational only. Confirm whether duplicate startup registrations are intentional before disabling or deleting anything.'))
        }
    }
    catch {
        $out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status 'Info' `
            -Summary 'Startup application inventory unavailable.' `
            -Details $_.Exception.Message))
    }

    # ---------------------------------------------------------------------
    # Core Windows service health
    #
    # Only explicitly configured core services are assessed as health
    # findings. RBZ deliberately does not flag every Automatic-but-stopped
    # service because Windows trigger-start services can be stopped normally.
    # ---------------------------------------------------------------------
    try {
        if([bool]$Config.services.enabled){
            $configuredNames=@($Config.services.monitoredCoreServices)
            $services=@(Get-CimInstance Win32_Service -ErrorAction Stop)

            $byName=@{}
            foreach($svc in $services){
                $byName[[string]$svc.Name]=$svc
            }

            $problems=[System.Collections.Generic.List[object]]::new()
            $missing=[System.Collections.Generic.List[string]]::new()

            foreach($name in $configuredNames){
                $serviceName=[string]$name
                if([string]::IsNullOrWhiteSpace($serviceName)){continue}

                if(-not $byName.ContainsKey($serviceName)){
                    $missing.Add($serviceName)
                    continue
                }

                $svc=$byName[$serviceName]

                # Disabled core services are always significant.
                if([string]$svc.StartMode -eq 'Disabled'){
                    $problems.Add([pscustomobject]@{
                        Name=$svc.Name
                        DisplayName=$svc.DisplayName
                        State=$svc.State
                        StartMode=$svc.StartMode
                        Severity='Warning'
                        Reason='Core Windows service is disabled.'
                    })
                    continue
                }

                # A monitored Auto service not running is actionable.
                if([string]$svc.StartMode -eq 'Auto' -and [string]$svc.State -ne 'Running'){
                    $problems.Add([pscustomobject]@{
                        Name=$svc.Name
                        DisplayName=$svc.DisplayName
                        State=$svc.State
                        StartMode=$svc.StartMode
                        Severity='Warning'
                        Reason='Core Windows service is configured for Automatic start but is not running.'
                    })
                }
            }

            if($problems.Count -eq 0){
                $out.Add((New-RBZFinding -Category 'System' -Name 'Core Windows services' -Status 'Healthy' `
                    -Summary "$($configuredNames.Count) monitored core service(s) show no actionable stopped/disabled state." `
                    -Details $(if($missing.Count -gt 0){
                        "Not present on this Windows installation: $($missing -join ', ')"
                    }else{''})))
            }
            else{
                $problemLines=@(
                    $problems |
                    Sort-Object DisplayName |
                    ForEach-Object {
                        "$($_.DisplayName) [$($_.Name)] | State: $($_.State) | Start: $($_.StartMode)`n$($_.Reason)"
                    }
                )

                $out.Add((New-RBZFinding -Category 'System' -Name 'Core Windows services' -Status 'Warning' `
                    -Summary "$($problems.Count) monitored core Windows service(s) require attention." `
                    -Details ($problemLines -join "`n`n") `
                    -Value $problems.Count `
                    -Recommendation 'Review the affected service configuration, dependencies, recent changes and Windows event logs before changing startup type.'))
            }

            if($missing.Count -gt 0 -and [bool]$Config.services.reportMissingAsInfo){
                $out.Add((New-RBZFinding -Category 'System' -Name 'Monitored services not present' -Status 'Info' `
                    -Summary "$($missing.Count) configured service name(s) are not present on this Windows installation." `
                    -Details ($missing -join "`n") `
                    -Recommendation 'This can be normal across Windows editions or configurations; no action is required unless the service is expected on this device.'))
            }

            # Advisory inventory of non-Microsoft automatic services that are
            # stopped. This does NOT reduce health because third-party services
            # can legitimately be trigger-start/demand-behaviour services.
            if([bool]$Config.services.reportStoppedThirdPartyAutoAsInfo){
                $thirdPartyStopped=@(
                    $services |
                    Where-Object {
                        $_.StartMode -eq 'Auto' -and
                        $_.State -ne 'Running' -and
                        $_.PathName -and
                        $_.PathName -notmatch '(?i)\\Windows\\|\\System32\\|svchost\.exe'
                    } |
                    Sort-Object DisplayName
                )

                if($thirdPartyStopped.Count -gt 0){
                    $lines=@(
                        $thirdPartyStopped |
                        Select-Object -First 20 |
                        ForEach-Object {
                            "$($_.DisplayName) [$($_.Name)] | State: $($_.State) | Start: $($_.StartMode)`nPath: $($_.PathName)"
                        }
                    )

                    $out.Add((New-RBZFinding -Category 'System' -Name 'Stopped third-party automatic services' -Status 'Info' `
                        -Summary "$($thirdPartyStopped.Count) third-party automatic service(s) are currently not running." `
                        -Details ($lines -join "`n`n") `
                        -Value $thirdPartyStopped.Count `
                        -Recommendation 'This is informational. Investigate only if the related application or device is malfunctioning.'))
                }
            }
        }
    }
    catch {
        $out.Add((New-RBZFinding -Category 'System' -Name 'Core Windows services' -Status 'Info' `
            -Summary 'Windows service health inventory was unavailable.' `
            -Details $_.Exception.Message))
    }

    return $out
}

Export-ModuleMember -Function Get-RBZStartupFindings
