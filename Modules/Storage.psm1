function ConvertTo-RBZStorageNumber {
    param($Value)
    if($null -eq $Value){return $null}
    try {
        if([string]::IsNullOrWhiteSpace([string]$Value)){return $null}
        [double]$Value
    } catch {$null}
}

function Get-RBZStorageReliability {
    param([Parameter(Mandatory)]$PhysicalDisk)

    try {
        Get-StorageReliabilityCounter -PhysicalDisk $PhysicalDisk -ErrorAction Stop
    }
    catch {$null}
}

function Get-RBZStorageReliabilityStatus {
    param($Reliability,$Config)

    if($null -eq $Reliability){return 'Info'}

    $temperature=ConvertTo-RBZStorageNumber $Reliability.Temperature
    $wear=ConvertTo-RBZStorageNumber $Reliability.Wear
    $readUncorrected=ConvertTo-RBZStorageNumber $Reliability.ReadErrorsUncorrected
    $writeUncorrected=ConvertTo-RBZStorageNumber $Reliability.WriteErrorsUncorrected

    $critical=$false
    $warning=$false

    if($null -ne $temperature){
        if($temperature -ge [double]$Config.storage.temperatureCriticalC){$critical=$true}
        elseif($temperature -ge [double]$Config.storage.temperatureWarningC){$warning=$true}
    }

    if($null -ne $wear){
        if($wear -ge [double]$Config.storage.wearCriticalPercent){$critical=$true}
        elseif($wear -ge [double]$Config.storage.wearWarningPercent){$warning=$true}
    }

    $uncorrectedThreshold=[double]$Config.storage.uncorrectedErrorsWarning
    if(($null -ne $readUncorrected -and $readUncorrected -ge $uncorrectedThreshold) -or
       ($null -ne $writeUncorrected -and $writeUncorrected -ge $uncorrectedThreshold)){
        $warning=$true
    }

    if($critical){'Critical'}
    elseif($warning){'Warning'}
    else{'Healthy'}
}

function Format-RBZStorageReliabilityDetails {
    param($Reliability)

    if($null -eq $Reliability){
        return 'Windows did not expose storage reliability / SMART-style counters for this drive. This is not evidence that the drive is unhealthy; vendor tooling may expose additional data.'
    }

    $fields=[ordered]@{
        'Temperature'              = $(if($null -ne $Reliability.Temperature){"$($Reliability.Temperature) C"}else{$null})
        'Maximum temperature'      = $(if($null -ne $Reliability.TemperatureMax){"$($Reliability.TemperatureMax) C"}else{$null})
        'Wear used'                = $(if($null -ne $Reliability.Wear){"$($Reliability.Wear)%"}else{$null})
        'Power-on hours'           = $Reliability.PowerOnHours
        'Read errors total'        = $Reliability.ReadErrorsTotal
        'Read errors corrected'    = $Reliability.ReadErrorsCorrected
        'Read errors uncorrected'  = $Reliability.ReadErrorsUncorrected
        'Write errors total'       = $Reliability.WriteErrorsTotal
        'Write errors corrected'   = $Reliability.WriteErrorsCorrected
        'Write errors uncorrected' = $Reliability.WriteErrorsUncorrected
        'Read latency max'         = $Reliability.ReadLatencyMax
        'Write latency max'        = $Reliability.WriteLatencyMax
        'Flush latency max'        = $Reliability.FlushLatencyMax
        'Start/stop cycles'        = $Reliability.StartStopCycleCount
        'Load/unload cycles'       = $Reliability.LoadUnloadCycleCount
    }

    $lines=[System.Collections.Generic.List[string]]::new()
    foreach($item in $fields.GetEnumerator()){
        if($null -ne $item.Value -and -not [string]::IsNullOrWhiteSpace([string]$item.Value)){
            $lines.Add("$($item.Key): $($item.Value)")
        }
    }

    if($lines.Count -eq 0){
        'Windows returned a storage reliability object, but the device/driver did not expose useful counters.'
    } else {
        $lines -join "`n"
    }
}

function Get-RBZStorageFindings {
    param($Config)

    $out=[System.Collections.Generic.List[object]]::new()

    try {
        $system=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        if($system.Size){
            $freePct=[math]::Round(($system.FreeSpace/$system.Size)*100,1)
            $freeGB=[math]::Round($system.FreeSpace/1GB,1)
            $sizeGB=[math]::Round($system.Size/1GB,1)

            $state=if($freePct -lt [double]$Config.thresholds.systemDriveFreePercentCritical){
                'Critical'
            } elseif($freePct -lt [double]$Config.thresholds.systemDriveFreePercentWarning){
                'Warning'
            } else {'Healthy'}

            $out.Add((New-RBZFinding -Category 'Storage' -Name 'System drive free space' -Status $state `
                -Summary "$freePct% free on $($env:SystemDrive) ($freeGB GB of $sizeGB GB)" `
                -Value $freePct `
                -Recommendation $(if($state -ne 'Healthy'){'Free disk space before Windows updates or large application installs.'}else{''})))
        }
    } catch {}

    try {
        $disks=@(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)

        foreach($d in $disks){
            $sizeGB=if($d.Size){[math]::Round($d.Size/1GB,1)}else{$null}
            $diskId=if($null -ne $d.DeviceId){"Disk $($d.DeviceId)"}else{'Disk'}

            $serial=([string]$d.SerialNumber).Trim()
            $serialSuffix=if($serial.Length -ge 4){$serial.Substring($serial.Length-4)}else{$serial}

            $displayName="$diskId - $($d.FriendlyName)"
            if($serialSuffix){$displayName+=" [$serialSuffix]"}

            $health=[string]$d.HealthStatus
            $operational=@($d.OperationalStatus | ForEach-Object {[string]$_})

            $baseState=if($health -eq 'Healthy' -and ($operational -contains 'OK')){
                'Healthy'
            } elseif($health -match '(?i:unhealthy|failed)' -or ($operational -contains 'Lost Communication')){
                'Critical'
            } else {
                'Warning'
            }

            $reliability=$null
            $reliabilityState='Info'
            if([bool]$Config.storage.reliabilityCounters){
                $reliability=Get-RBZStorageReliability -PhysicalDisk $d
                $reliabilityState=Get-RBZStorageReliabilityStatus -Reliability $reliability -Config $Config
            }

            $rank=@{'Healthy'=0;'Info'=0;'Recommend'=1;'Warning'=2;'Critical'=3}
            $state=if($rank[$reliabilityState] -gt $rank[$baseState]){$reliabilityState}else{$baseState}

            $temperature=if($null -ne $reliability){ConvertTo-RBZStorageNumber $reliability.Temperature}else{$null}
            $wear=if($null -ne $reliability){ConvertTo-RBZStorageNumber $reliability.Wear}else{$null}

            $summaryParts=[System.Collections.Generic.List[string]]::new()
            $summaryParts.Add([string]$d.MediaType)
            if($null -ne $sizeGB){$summaryParts.Add("$sizeGB GB")}
            $summaryParts.Add("Health: $health")
            if($null -ne $temperature){$summaryParts.Add("Temp: $temperature C")}
            if($null -ne $wear){$summaryParts.Add("Wear: $wear%")}

            $details=[System.Collections.Generic.List[string]]::new()
            $details.Add("Disk ID: $($d.DeviceId)")
            $details.Add("Friendly name: $($d.FriendlyName)")
            $details.Add("Media type: $($d.MediaType)")
            $details.Add("Bus type: $($d.BusType)")
            $details.Add("Size: $sizeGB GB")
            $details.Add("Health: $health")
            $details.Add("Operational: $($operational -join ', ')")
            $details.Add("Firmware: $($d.FirmwareVersion)")
            $details.Add("Serial: $serial")
            $details.Add("")
            $details.Add("Reliability / SMART-style data:")
            $details.Add((Format-RBZStorageReliabilityDetails -Reliability $reliability))

            $recommendation=''
            if($state -in @('Warning','Critical')){
                $recommendation='Back up important data and investigate the flagged disk health/reliability values before making disruptive changes.'
            } elseif($null -eq $reliability -and [bool]$Config.storage.reliabilityCounters){
                $recommendation='Windows did not expose reliability counters for this drive. Consider the drive manufacturer diagnostic utility if deeper SMART data is required.'
            }

            $out.Add((New-RBZFinding -Category 'Storage' -Name $displayName -Status $state `
                -Summary ($summaryParts -join ' | ') `
                -Details ($details -join "`n") `
                -Value $d.MediaType `
                -Recommendation $recommendation))

        }
    } catch {
        $out.Add((New-RBZFinding -Category 'Storage' -Name 'Physical disk health' -Status 'Info' `
            -Summary 'Physical disk health data was unavailable.' `
            -Details $_.Exception.Message))
    }

    return $out
}

Export-ModuleMember -Function Get-RBZStorageFindings
