function New-RBZAction {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Category,
        [ValidateSet('Low','Medium')][string]$Risk,
        [string]$Description,
        [bool]$RequiresRestart=$false
    )

    [pscustomobject]@{
        Id=$Id
        Name=$Name
        Category=$Category
        Risk=$Risk
        Description=$Description
        RequiresRestart=$RequiresRestart
        Selected=$false
    }
}

function Get-RBZServiceActions {
    param($Config)

    $actions=[System.Collections.Generic.List[object]]::new()

    if($Config.remediation.allowRestorePoint){
        $actions.Add((New-RBZAction -Id 'RestorePoint' -Name 'Create system restore point' -Category 'Protection' -Risk 'Low' `
            -Description 'Attempts to create a Windows System Restore checkpoint before repair work. Requires System Protection to be available.'))
    }

    if($Config.remediation.allowDefenderSignatureUpdate){
        $actions.Add((New-RBZAction -Id 'DefenderSignatureUpdate' -Name 'Update Defender security intelligence' -Category 'Security' -Risk 'Low' `
            -Description 'Downloads the latest Microsoft Defender security intelligence using Update-MpSignature.'))
    }

    if($Config.remediation.allowDefenderQuickScan){
        $actions.Add((New-RBZAction -Id 'DefenderQuickScan' -Name 'Microsoft Defender quick scan' -Category 'Security' -Risk 'Low' `
            -Description 'Runs a Microsoft Defender Quick Scan. RBZ PC Health does not change Defender remediation policy.'))
    }

    if($Config.remediation.allowDismScanHealth){
        $actions.Add((New-RBZAction -Id 'DismScanHealth' -Name 'Windows component health scan' -Category 'Windows' -Risk 'Low' `
            -Description 'Runs DISM /Online /Cleanup-Image /ScanHealth. Live progress is shown where DISM exposes a percentage.'))
    }

    if($Config.remediation.allowSfcVerifyOnly){
        $actions.Add((New-RBZAction -Id 'SfcVerifyOnly' -Name 'System file verification' -Category 'Windows' -Risk 'Low' `
            -Description 'Runs SFC /verifyonly. Live progress is shown where SFC exposes a percentage.'))
    }

    if($Config.remediation.allowCheckDiskScan){
        $actions.Add((New-RBZAction -Id 'CheckDiskScan' -Name 'System drive online disk scan' -Category 'Storage' -Risk 'Low' `
            -Description 'Runs CHKDSK on the Windows system drive using /scan. This does not schedule an offline repair.'))
    }

    if($Config.remediation.allowWindowsTimeResync){
        $actions.Add((New-RBZAction -Id 'WindowsTimeResync' -Name 'Windows Time resynchronisation' -Category 'Windows' -Risk 'Low' `
            -Description 'Starts Windows Time if required and requests rediscovery/resynchronisation. It does not replace domain or NTP configuration.'))
    }

    # RBZ080RC8_SAFE_REPAIRS
    if($Config.remediation.allowFlushDnsCache){
        $actions.Add((New-RBZAction -Id 'FlushDnsCache' -Name 'Flush DNS resolver cache' -Category 'Network' -Risk 'Low' `
            -Description 'Clears the Windows DNS resolver cache. DNS servers and adapter configuration are not changed.'))
    }

    if($Config.remediation.allowRestartPrintSpooler){
        $actions.Add((New-RBZAction -Id 'RestartPrintSpooler' -Name 'Restart Print Spooler' -Category 'Windows' -Risk 'Low' `
            -Description 'Restarts the Windows Print Spooler and verifies that it returns to Running. Active print jobs may be interrupted.'))
    }

    if($Config.remediation.allowRestartWindowsUpdateServices){
        $actions.Add((New-RBZAction -Id 'RestartWindowsUpdateServices' -Name 'Restart Windows Update services' -Category 'Updates' -Risk 'Low' `
            -Description 'Restarts available Windows Update services without deleting update caches, history or policy.'))
    }

    # RBZ080RC9_REPAIR_EXPANSION
    if($Config.remediation.allowTriggerWindowsUpdateScan){
        $actions.Add((New-RBZAction -Id 'TriggerWindowsUpdateScan' -Name 'Trigger Windows Update scan' -Category 'Updates' -Risk 'Low' `
            -Description 'Requests a fresh Windows Update detection scan. The scan continues asynchronously; RBZ does not claim that updates were downloaded or installed.'))
    }

    if($Config.remediation.allowClearWindowsUpdateDownloadCache){
        $actions.Add((New-RBZAction -Id 'ClearWindowsUpdateDownloadCache' -Name 'Clear Windows Update download cache' -Category 'Updates' -Risk 'Medium' `
            -Description 'Stops update services, clears only SoftwareDistribution\Download, restarts services and verifies service recovery. Windows Update history and policy are not reset.'))
    }

    if($Config.remediation.allowRepairWindowsUpdateComponents){
        $actions.Add((New-RBZAction -Id 'RepairWindowsUpdateComponents' -Name 'Repair Windows Update components' -Category 'Updates' -Risk 'Medium' `
            -Description 'Resets SoftwareDistribution and Catroot2 by renaming them, then restarts Windows Update services. This is more invasive and should follow lower-risk update actions.'))
    }

    if($Config.remediation.allowResetNetworkStack){
        $actions.Add((New-RBZAction -Id 'ResetNetworkStack' -Name 'Reset Windows network stack' -Category 'Network' -Risk 'Medium' -RequiresRestart $true `
            -Description 'Runs Winsock and TCP/IP stack reset commands. A Windows restart is required and VPN/custom networking may need review afterwards.'))
    }

    if($Config.remediation.allowResetMicrosoftStoreCache){
        $actions.Add((New-RBZAction -Id 'ResetMicrosoftStoreCache' -Name 'Reset Microsoft Store cache' -Category 'Windows' -Risk 'Low' `
            -Description 'Runs the Windows Store cache reset tool. It does not uninstall Store applications.'))
    }

    if($Config.remediation.allowTempCleanup){
        $actions.Add((New-RBZAction -Id 'TempCleanup' -Name 'Temporary file cleanup' -Category 'Cleanup' -Risk 'Low' `
            -Description 'Deletes accessible files from the current-user TEMP folder and Windows TEMP folder. Locked/in-use items are skipped.'))
    }

    if($Config.remediation.allowDismRestoreHealth){
        $actions.Add((New-RBZAction -Id 'DismRestoreHealth' -Name 'Repair Windows component store' -Category 'Windows' -Risk 'Medium' `
            -Description 'Runs DISM /RestoreHealth with live activity/progress, then verifies component-store health. A restore point is attempted first when configured.'))
    }

    if($Config.remediation.allowSfcScannow){
        $actions.Add((New-RBZAction -Id 'SfcScannow' -Name 'Repair protected system files' -Category 'Windows' -Risk 'Medium' `
            -Description 'Runs SFC /scannow with live activity/progress and parses the final Windows Resource Protection result. A restore point is attempted first when configured.'))
    }

    return $actions
}

function Write-RBZProgressState {
    param(
        [string]$ProgressPath,
        [string]$Stage,
        [Nullable[double]]$Percent=$null,
        [string]$Message='',
        [datetime]$Started=(Get-Date),
        [bool]$Indeterminate=$false
    )

    if([string]::IsNullOrWhiteSpace($ProgressPath)){return}

    try {
        $payload=[ordered]@{
            Stage=$Stage
            Percent=$(if($null -eq $Percent){$null}else{[math]::Round([double]$Percent,1)})
            Message=$Message
            Indeterminate=$Indeterminate
            ElapsedSeconds=[math]::Round(((Get-Date)-$Started).TotalSeconds,0)
            Updated=(Get-Date).ToString('o')
        }
        $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $ProgressPath -Encoding UTF8 -Force
    } catch {}
}

function Get-RBZSystemProtectionState {
    param([string]$Drive=$env:SystemDrive)
    if([string]::IsNullOrWhiteSpace($Drive)){$Drive='C:'}
    try {
        $output=& vssadmin.exe list shadowstorage 2>&1 | Out-String
        $enabled=[bool]($output -match ('(?is)For volume:\s*\(' + [regex]::Escape($Drive) + '\)'))
        [pscustomobject]@{Drive=$Drive;Enabled=$enabled;Available=$true;Details=$output.Trim()}
    } catch {
        [pscustomobject]@{Drive=$Drive;Enabled=$false;Available=$false;Details=$_.Exception.ToString()}
    }
}

function Enable-RBZSystemProtection {
    param($Config,[string]$Drive=$env:SystemDrive)
    if([string]::IsNullOrWhiteSpace($Drive)){$Drive='C:'}
    $driveRoot="$Drive\\"
    $percent=[int]$Config.remediation.systemProtectionAllocationPercent
    if($percent -lt 1){$percent=5}; if($percent -gt 20){$percent=20}
    try {
        if(-not(Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue)){throw 'Enable-ComputerRestore is unavailable on this Windows installation.'}
        Enable-ComputerRestore -Drive $driveRoot -ErrorAction Stop
        $resize=& vssadmin.exe Resize ShadowStorage "/For=$Drive" "/On=$Drive" "/MaxSize=$percent%" 2>&1 | Out-String
        if($LASTEXITCODE -ne 0){throw "System Protection was enabled, but shadow storage configuration failed.`n$resize"}
        Start-Sleep -Seconds 1
        $check=Get-RBZSystemProtectionState -Drive $Drive
        [pscustomobject]@{Success=[bool]$check.Enabled;Summary=$(if($check.Enabled){"System Protection enabled on $Drive with shadow storage capped at $percent%."}else{'System Protection enablement could not be verified.'});Details="$resize`n`nVerification:`n$($check.Details)"}
    } catch {
        [pscustomobject]@{Success=$false;Summary='System Protection could not be enabled.';Details=$_.Exception.ToString()}
    }
}

function New-RBZRestorePoint {
    param($Config,[string]$Reason='Pre-repair protection')

    $description=[string]$Config.remediation.restorePointDescription
    if([string]::IsNullOrWhiteSpace($description)){$description='RBZ PC Health pre-repair'}

    try {
        if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
            return [pscustomobject]@{
                Success=$false
                Verified=$false
                FailureType='WrongPowerShellRuntime'
                Summary='Restore-point creation requires Windows PowerShell 5.1.'
                Details="Current runtime: PSEdition=$($PSVersionTable.PSEdition); Version=$($PSVersionTable.PSVersion)"
            }
        }

        $before=@()
        try {
            $before=@(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        } catch {
            $before=@()
        }

        $beforeSequences=@($before | ForEach-Object {[int]$_.SequenceNumber})

        Checkpoint-Computer `
            -Description $description `
            -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop

        Start-Sleep -Seconds 2

        $after=@(
            Get-ComputerRestorePoint -ErrorAction Stop |
            Sort-Object SequenceNumber -Descending
        )

        $newPoint=$after |
            Where-Object {
                ([int]$_.SequenceNumber -notin $beforeSequences) -and
                ([string]$_.Description -eq $description)
            } |
            Select-Object -First 1

        if(-not $newPoint){
            return [pscustomobject]@{
                Success=$false
                Verified=$false
                FailureType='VerificationFailed'
                Summary='A restore point command completed, but the new restore point could not be verified.'
                Details="Description requested: $description`nReason: $Reason"
            }
        }

        [pscustomobject]@{
            Success=$true
            Verified=$true
            FailureType=''
            SequenceNumber=[int]$newPoint.SequenceNumber
            Description=[string]$newPoint.Description
            CreationTime=[string]$newPoint.CreationTime
            Summary="Restore point created and verified: $description"
            Details="Sequence: $($newPoint.SequenceNumber)`nDescription: $($newPoint.Description)`nCreation time: $($newPoint.CreationTime)`nReason: $Reason"
        }
    } catch {
        [pscustomobject]@{
            Success=$false
            Verified=$false
            FailureType='CreateFailed'
            Summary='Windows could not create or verify the pre-repair restore point.'
            Details=$_.Exception.ToString()
        }
    }
}

function Get-RBZLatestPercent {
    param([string]$Text)

    if([string]::IsNullOrWhiteSpace($Text)){return $null}
    $matches=[regex]::Matches($Text,'(?<!\d)(\d{1,3}(?:[.,]\d+)?)\s*%')
    if($matches.Count -eq 0){return $null}

    $raw=$matches[$matches.Count-1].Groups[1].Value.Replace(',','.')
    $value=0.0
    if([double]::TryParse($raw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value)){
        return [math]::Max(0,[math]::Min(100,$value))
    }
    return $null
}

function Invoke-RBZNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$ProgressPath='',
        [string]$Stage='Running command',
        [switch]$ParsePercent
    )

    $started=Get-Date
    $work=Join-Path $env:TEMP ("RBZ-PC-Health-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $stdout=Join-Path $work 'stdout.txt'
    $stderr=Join-Path $work 'stderr.txt'

    try {
        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Message 'Starting...' -Started $started -Indeterminate:$true

        $p=Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        while(-not $p.HasExited){
            $text=''
            try {
                if(Test-Path $stdout){$text += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
                if(Test-Path $stderr){$text += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}
            } catch {}

            $percent=$null
            if($ParsePercent){$percent=Get-RBZLatestPercent -Text $text}

            if($null -ne $percent){
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Percent $percent `
                    -Message ("{0:N1}% complete" -f $percent) -Started $started -Indeterminate:$false
            } else {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage `
                    -Message 'Working...' -Started $started -Indeterminate:$true
            }

            Start-Sleep -Milliseconds 350
            $p.Refresh()
        }

        $p.WaitForExit()
        $p.Refresh()

        # RBZ080RC5A_NATIVE_EXITCODE
        $nativeExitCode=1
        try{
            if($null -ne $p.ExitCode){
                $nativeExitCode=[int]$p.ExitCode
            }
        }catch{
            $nativeExitCode=1
        }

        $out=''
        if(Test-Path $stdout){$out += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
        if(Test-Path $stderr){$out += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}

        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Percent 100 -Message 'Command finished.' -Started $started -Indeterminate:$false

        [pscustomobject]@{
            ExitCode=$nativeExitCode
            Output=$out.Trim()
            Elapsed=((Get-Date)-$started)
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-RBZDismVerification {
    param([string]$Text,[int]$ExitCode)

    $status='Info'
    $summary='DISM completed; review the detailed output.'
    if($ExitCode -ne 0){
        $status='Warning'
        $summary="DISM returned exit code $ExitCode."
    }
    elseif($Text -match '(?i)No component store corruption detected'){
        $status='Healthy';$summary='Windows component store verification reports no corruption.'
    }
    elseif($Text -match '(?i)component store corruption.*repairable|repairable'){
        $status='Recommend';$summary='Windows component store corruption is repairable.'
    }
    elseif($Text -match '(?i)restore operation completed successfully|component store corruption was repaired|operation completed successfully'){
        $status='Healthy';$summary='Windows component store repair completed successfully.'
    }
    elseif($Text -match '(?i)component store corruption.*not repairable'){
        $status='Warning';$summary='Windows component store corruption was reported as not repairable.'
    }

    [pscustomobject]@{Status=$status;Summary=$summary}
}

function Get-RBZSfcVerification {
    param([string]$Text,[int]$ExitCode)

    if($Text -match '(?i)did not find any integrity violations'){
        return [pscustomobject]@{Status='Healthy';Summary='Windows Resource Protection found no integrity violations.'}
    }
    if($Text -match '(?i)found corrupt files and successfully repaired them'){
        return [pscustomobject]@{Status='Healthy';Summary='Windows Resource Protection found corrupt files and repaired them successfully.'}
    }
    if($Text -match '(?i)found corrupt files but was unable to fix some'){
        return [pscustomobject]@{Status='Warning';Summary='Windows Resource Protection found corruption that it could not fully repair.'}
    }
    if($Text -match '(?i)could not perform the requested operation'){
        return [pscustomobject]@{Status='Warning';Summary='System File Checker could not perform the requested operation.'}
    }
    if($ExitCode -ne 0){
        return [pscustomobject]@{Status='Warning';Summary="System File Checker returned exit code $ExitCode; review detailed output."}
    }
    [pscustomobject]@{Status='Info';Summary='System File Checker completed; no recognised final result string was parsed.'}
}

function Invoke-RBZServiceAction {
    param(
        [Parameter(Mandatory)][string]$Id,
        $Config,
        [string]$ProgressPath='',
        [switch]$SkipRestorePoint,
        [switch]$RestorePointAlreadyCreated
    )

    $started=Get-Date
    $actions=@(Get-RBZServiceActions -Config $Config)
    $action=$actions | Where-Object Id -eq $Id | Select-Object -First 1

    $result=[ordered]@{
        Id=$Id
        Name=if($action){$action.Name}else{$Id}
        Risk=if($action){$action.Risk}else{'Unknown'}
        Started=$started.ToString('o')
        Finished=$null
        Success=$false
        Summary=''
        Details=''
        RestorePointAttempted=$false
        RestorePointCreated=$false
        RestorePointDetails=''
        BytesRecovered=0
        RequiresRestart=if($action){[bool]$action.RequiresRestart}else{$false}
        VerificationCategory=''
        VerificationCheck=''
        VerificationStatus=''
        VerificationSummary=''
        VerificationDetails=''
    }

    try {
        if(-not $action){throw "Unknown service action: $Id"}

        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $action.Name -Message 'Preparing action...' -Started $started -Indeterminate:$true

        if($action.Risk -eq 'Medium' -and $Config.remediation.attemptRestorePointBeforeMediumActions){
            if($RestorePointAlreadyCreated){
                $result.RestorePointAttempted=$true;$result.RestorePointCreated=$true;$result.RestorePointDetails='Restore point was created and verified during technician preflight.'
            } elseif($SkipRestorePoint){
                $result.RestorePointAttempted=$false;$result.RestorePointCreated=$false;$result.RestorePointDetails='Pre-repair restore point skipped explicitly by technician.'
            } else {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Creating restore point' -Message 'Attempting pre-repair restore point...' -Started $started -Indeterminate:$true
                $result.RestorePointAttempted=$true
                $rp=New-RBZRestorePoint -Config $Config -Reason $action.Name
                $result.RestorePointCreated=[bool]$rp.Success
                $result.RestorePointDetails="$($rp.Summary)`n$($rp.Details)"
                if(-not $rp.Success -and $Config.remediation.blockMediumActionIfRestorePointFails){throw "Pre-repair restore point failed and configuration blocks Medium-risk actions.`n$($rp.Details)"}
            }
        }

        switch($Id){
            'RestorePoint' {
                $rp=New-RBZRestorePoint -Config $Config -Reason 'Technician requested restore point'
                $result.RestorePointAttempted=$true
                $result.RestorePointCreated=[bool]$rp.Success
                $result.RestorePointDetails="$($rp.Summary)`n$($rp.Details)"
                $result.Success=[bool]$rp.Success
                $result.Summary=$rp.Summary
                $result.Details=$rp.Details
            }

            'DefenderSignatureUpdate' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Updating Defender intelligence' -Message 'Downloading current security intelligence...' -Started $started -Indeterminate:$true
                if(-not(Get-Command Update-MpSignature -ErrorAction SilentlyContinue)){throw 'Microsoft Defender Update-MpSignature is unavailable. A third-party antivirus may be active.'}
                Update-MpSignature -ErrorAction Stop
                $mp=Get-MpComputerStatus -ErrorAction SilentlyContinue
                $result.Success=$true
                $result.Summary='Microsoft Defender security intelligence update completed.'
                $result.Details=$(if($mp){"Signature version: $($mp.AntivirusSignatureVersion)`nSignature age: $($mp.AntivirusSignatureAge) day(s)"}else{'Update-MpSignature completed without a PowerShell error.'})
                $result.VerificationCategory='Security'
                $result.VerificationCheck='Defender security intelligence'
                $result.VerificationStatus='Healthy'
                $result.VerificationSummary=$(if($mp){"Security intelligence current; signature age $($mp.AntivirusSignatureAge) day(s)."}else{'Defender intelligence update completed successfully.'})
            }

            'DefenderQuickScan' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Microsoft Defender quick scan' -Message 'Scanning...' -Started $started -Indeterminate:$true
                if(-not(Get-Command Start-MpScan -ErrorAction SilentlyContinue)){throw 'Microsoft Defender Start-MpScan is unavailable. A third-party antivirus may be active.'}
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                $result.Success=$true
                $result.Summary='Microsoft Defender quick scan completed.'
                $result.Details='Start-MpScan -ScanType QuickScan completed without a PowerShell error.'
                $result.VerificationCategory='Security'
                $result.VerificationCheck='Microsoft Defender quick scan'
                $result.VerificationStatus='Healthy'
                $result.VerificationSummary='Microsoft Defender quick scan completed without a PowerShell error.'
            }

            'DismScanHealth' {
                $r=Invoke-RBZNativeCommand -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/ScanHealth') -ProgressPath $ProgressPath -Stage 'DISM ScanHealth' -ParsePercent
                $v=Get-RBZDismVerification -Text $r.Output -ExitCode $r.ExitCode
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'DISM component health scan completed.'}else{"DISM ScanHealth returned exit code $($r.ExitCode)."})
                $result.Details=$r.Output
                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Windows Component Store'
                $result.VerificationStatus=$v.Status
                $result.VerificationSummary=$v.Summary
                $result.VerificationDetails=$r.Output
            }

            'DismRestoreHealth' {
                $r=Invoke-RBZNativeCommand -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') -ProgressPath $ProgressPath -Stage 'DISM RestoreHealth' -ParsePercent
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'DISM component store repair completed.'}else{"DISM RestoreHealth returned exit code $($r.ExitCode)."})
                $result.Details=$r.Output

                $verifyText=$r.Output
                $verifyExit=$r.ExitCode
                if($result.Success -and $Config.remediation.verifyDismAfterRestoreHealth){
                    $check=Invoke-RBZNativeCommand -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/CheckHealth') -ProgressPath $ProgressPath -Stage 'Verifying component store'
                    $verifyText="$($r.Output)`n`n--- Post-repair CheckHealth ---`n$($check.Output)"
                    $verifyExit=$check.ExitCode
                }

                $v=Get-RBZDismVerification -Text $verifyText -ExitCode $verifyExit
                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Windows Component Store'
                $result.VerificationStatus=$v.Status
                $result.VerificationSummary=$v.Summary
                $result.VerificationDetails=$verifyText
            }

            'SfcVerifyOnly' {
                $r=Invoke-RBZNativeCommand -FilePath 'sfc.exe' -Arguments @('/verifyonly') -ProgressPath $ProgressPath -Stage 'SFC VerifyOnly' -ParsePercent
                $v=Get-RBZSfcVerification -Text $r.Output -ExitCode $r.ExitCode
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary='System File Checker verification completed.'
                $result.Details=$r.Output
                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Protected System Files'
                $result.VerificationStatus=$v.Status
                $result.VerificationSummary=$v.Summary
                $result.VerificationDetails=$r.Output
            }

            'SfcScannow' {
                $r=Invoke-RBZNativeCommand -FilePath 'sfc.exe' -Arguments @('/scannow') -ProgressPath $ProgressPath -Stage 'SFC Scannow' -ParsePercent
                $v=Get-RBZSfcVerification -Text $r.Output -ExitCode $r.ExitCode
                $result.Success=($r.ExitCode -eq 0 -or $v.Status -eq 'Healthy')
                $result.Summary=$(if($result.Success){'System File Checker repair completed.'}else{"SFC /scannow returned exit code $($r.ExitCode); review output."})
                $result.Details=$r.Output
                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Protected System Files'
                $result.VerificationStatus=$v.Status
                $result.VerificationSummary=$v.Summary
                $result.VerificationDetails=$r.Output
            }

            'CheckDiskScan' {
                $drive=$env:SystemDrive
                if([string]::IsNullOrWhiteSpace($drive)){$drive='C:'}
                $r=Invoke-RBZNativeCommand -FilePath 'chkdsk.exe' -Arguments @($drive,'/scan') -ProgressPath $ProgressPath -Stage "CHKDSK $drive /scan" -ParsePercent
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){"Online CHKDSK scan completed successfully on $drive."}else{"CHKDSK /scan returned exit code $($r.ExitCode) on $drive."})
                $result.Details=$r.Output
                $result.VerificationCategory='Storage'
                $result.VerificationCheck="CHKDSK $drive"
                $result.VerificationStatus=$(if($r.ExitCode -eq 0){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($r.ExitCode -eq 0){'Online CHKDSK scan completed without a reported error.'}else{"CHKDSK returned exit code $($r.ExitCode)."})
                $result.VerificationDetails=$r.Output
            }

            # RBZ080RC8A_TIME_VERIFY
            'WindowsTimeResync' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation' -Message 'Capturing current state...' -Started $started -Indeterminate:$true
                $timeService=Get-Service W32Time -ErrorAction Stop
                if($timeService.StartType -eq 'Disabled'){throw 'Windows Time is Disabled. RBZ will not change a Disabled service automatically.'}
                if($timeService.Status -ne 'Running'){Start-Service W32Time -ErrorAction Stop;Start-Sleep -Seconds 1}

                $beforeSource=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/source') -Stage 'Windows Time source'
                $beforeStatus=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/status') -Stage 'Windows Time status'
                $beforePeers=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/query','/peers') -Stage 'Windows Time peers'

                $first=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync') -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation'
                Start-Sleep -Seconds 2

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

                if(-not $verified){
                    Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time recovery' -Message 'Restarting Windows Time and rediscovering configured source...' -Started $started -Indeterminate:$true
                    Restart-Service W32Time -Force -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $fallback=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync','/rediscover') -ProgressPath $ProgressPath -Stage 'Windows Time rediscovery'
                    $fallbackOutput=$fallback.Output
                    Start-Sleep -Seconds 2
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
                }

                $result.Success=$verified
                $result.Summary=$(if($verified){'Windows Time was resynchronised and verified.'}else{'Windows Time repair completed, but synchronisation could not be verified.'})
                $result.VerificationCategory='System'
                $result.VerificationCheck='Windows Time synchronisation'
                $result.VerificationStatus=$(if($verified){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($verified){"Windows Time is synchronised. Source: $source"}else{"Windows Time remains unsynchronised or unverified. Source: $source"})
                $result.Details=@"
Before source:
$($beforeSource.Output)

Before status:
$($beforeStatus.Output)

Peer state:
$($beforePeers.Output)

Initial resync:
$($first.Output)

Fallback:
$fallbackOutput

After source:
$source

After status:
$status

Verification attempts:
$($verificationAttempts -join "`n")

RBZ did not change the NTP server, registry settings or policy.
"@
                $result.VerificationDetails=$result.Details
            }
            'FlushDnsCache' {
                $r=Invoke-RBZNativeCommand -FilePath 'ipconfig.exe' -Arguments @('/flushdns') -ProgressPath $ProgressPath -Stage 'Flush DNS resolver cache'
                $ok=($r.ExitCode -eq 0 -and $r.Output -match '(?i)successfully flushed|dns resolver cache')
                $result.Success=$ok
                $result.Summary=$(if($ok){'Windows DNS resolver cache was flushed successfully.'}else{'DNS cache flush could not be verified.'})
                $result.Details="Exit code: $($r.ExitCode)`n$($r.Output)"
                $result.VerificationCategory='Network';$result.VerificationCheck='DNS resolver cache'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }

            'RestartPrintSpooler' {
                $svc=Get-Service Spooler -ErrorAction Stop;$before=[string]$svc.Status
                Restart-Service Spooler -Force -ErrorAction Stop
                $svc.WaitForStatus('Running',[TimeSpan]::FromSeconds(15));$svc.Refresh()
                $ok=($svc.Status -eq 'Running')
                $result.Success=$ok;$result.Summary=$(if($ok){'Print Spooler restarted and returned to Running.'}else{'Print Spooler restart could not be verified.'})
                $result.Details="Before: $before`nAfter: $($svc.Status)"
                $result.VerificationCategory='Windows';$result.VerificationCheck='Print Spooler'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }

            'RestartWindowsUpdateServices' {
                $names=@('wuauserv','UsoSvc');$lines=[System.Collections.Generic.List[string]]::new();$ok=$true;$seen=0
                foreach($n in $names){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$lines.Add("$n : not installed");continue}
                    $before=[string]$svc.Status
                    try{
                        if($svc.Status -eq 'Running'){Restart-Service $n -Force -ErrorAction Stop}else{Start-Service $n -ErrorAction Stop}
                        Start-Sleep -Milliseconds 500;$svc=Get-Service $n -ErrorAction Stop;$after=[string]$svc.Status;$seen++
                        if($after -ne 'Running'){$ok=$false};$lines.Add("$n : $before -> $after")
                    }catch{$ok=$false;$lines.Add("$n : $before -> ERROR: $($_.Exception.Message)")}
                }
                if($seen -eq 0){$ok=$false}
                $result.Success=$ok;$result.Summary=$(if($ok){'Windows Update services were restarted and verified.'}else{'One or more Windows Update services could not be restarted or verified.'})
                $result.Details=($lines -join "`n")
                $result.VerificationCategory='Updates';$result.VerificationCheck='Windows Update services'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'});$result.VerificationSummary=$result.Summary;$result.VerificationDetails=$result.Details
            }
            'TriggerWindowsUpdateScan' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Trigger Windows Update scan' -Message 'Requesting fresh update detection...' -Started $started -Indeterminate:$true

                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                if($wu -and $wu.StartType -ne 'Disabled' -and $wu.Status -ne 'Running'){
                    Start-Service wuauserv -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }

                $methods=[System.Collections.Generic.List[string]]::new()
                $requested=$false
                $errors=[System.Collections.Generic.List[string]]::new()

                try{
                    $autoUpdate=New-Object -ComObject Microsoft.Update.AutoUpdate
                    $autoUpdate.DetectNow()
                    $methods.Add('Microsoft.Update.AutoUpdate.DetectNow')
                    $requested=$true
                }catch{
                    $errors.Add("COM DetectNow: $($_.Exception.Message)")
                }

                $uso=Join-Path $env:SystemRoot 'System32\UsoClient.exe'
                if(Test-Path $uso){
                    try{
                        $r=Invoke-RBZNativeCommand -FilePath $uso -Arguments @('StartScan') -ProgressPath $ProgressPath -Stage 'Windows Update StartScan'
                        $methods.Add("UsoClient StartScan (exit $($r.ExitCode))")
                        # UsoClient is asynchronous and often returns no useful output.
                        $requested=$true
                    }catch{
                        $errors.Add("UsoClient StartScan: $($_.Exception.Message)")
                    }
                }

                Start-Sleep -Seconds 2
                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceState=if($wu){[string]$wu.Status}else{'Unavailable'}

                $result.Success=$requested
                $result.Summary=$(if($requested){'Windows Update scan request was submitted.'}else{'Windows Update scan request could not be submitted.'})
                $result.Details=@"
Methods attempted:
$($methods -join "`n")

Errors:
$($errors -join "`n")

Windows Update service state: $serviceState

Windows Update detection continues asynchronously. This action does not mean that updates were downloaded or installed.
"@
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update scan request'
                $result.VerificationStatus=$(if($requested){'Info'}else{'Warning'})
                $result.VerificationSummary=$(if($requested){'A fresh Windows Update detection request was submitted.'}else{'A fresh Windows Update detection request could not be submitted.'})
                $result.VerificationDetails=$result.Details
            }

            'ClearWindowsUpdateDownloadCache' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Clear Windows Update download cache' -Message 'Stopping update services...' -Started $started -Indeterminate:$true

                $downloadPath=Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
                $services=@('bits','wuauserv')
                $log=[System.Collections.Generic.List[string]]::new()
                $stopped=[System.Collections.Generic.List[string]]::new()

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$log.Add("$n : not installed");continue}
                    if($svc.Status -eq 'Running'){
                        try{Stop-Service $n -Force -ErrorAction Stop;$stopped.Add($n);$log.Add("$n : stopped")}
                        catch{throw "Could not stop $n. $($_.Exception.Message)"}
                    }else{$log.Add("$n : already $($svc.Status)")}
                }

                $before=0L;$after=0L;$deleted=0;$skipped=0
                if(Test-Path $downloadPath){
                    try{
                        $sum=(Get-ChildItem $downloadPath -File -Recurse -Force -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
                        if($null -ne $sum){$before=[long]$sum}
                    }catch{}

                    foreach($item in @(Get-ChildItem $downloadPath -Force -ErrorAction SilentlyContinue)){
                        try{Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop;$deleted++}
                        catch{$skipped++}
                    }

                    try{
                        $sum=(Get-ChildItem $downloadPath -File -Recurse -Force -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
                        if($null -ne $sum){$after=[long]$sum}
                    }catch{}
                }

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if($svc -and $svc.StartType -ne 'Disabled'){
                        try{
                            if($svc.Status -ne 'Running'){Start-Service $n -ErrorAction Stop;Start-Sleep -Milliseconds 500}
                            $svc=Get-Service $n -ErrorAction Stop
                            $log.Add("$n : final $($svc.Status)")
                        }catch{$log.Add("$n : restart error - $($_.Exception.Message)")}
                    }
                }

                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceOk=($null -eq $wu -or $wu.StartType -eq 'Disabled' -or $wu.Status -eq 'Running')
                $recovered=[math]::Max(0,$before-$after)

                $result.BytesRecovered=$recovered
                $result.Success=($serviceOk -and $skipped -eq 0)
                $result.Summary=$(if($result.Success){"Windows Update download cache cleared. Approximately {0:N2} MB removed." -f ($recovered/1MB)}else{'Windows Update download cache cleanup completed with items requiring review.'})
                $result.Details="Path: $downloadPath`nItems removed: $deleted`nItems skipped: $skipped`nBytes before: $before`nBytes after: $after`n`n$($log -join "`n")"
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update download cache'
                $result.VerificationStatus=$(if($result.Success){'Healthy'}else{'Recommend'})
                $result.VerificationSummary=$result.Summary
                $result.VerificationDetails=$result.Details
            }

            'RepairWindowsUpdateComponents' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Repair Windows Update components' -Message 'Stopping Windows Update services...' -Started $started -Indeterminate:$true

                $services=@('bits','wuauserv','cryptsvc')
                $log=[System.Collections.Generic.List[string]]::new()
                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if(-not $svc){$log.Add("$n : not installed");continue}
                    if($svc.Status -eq 'Running'){
                        try{Stop-Service $n -Force -ErrorAction Stop;$log.Add("$n : stopped")}
                        catch{throw "Could not stop $n. $($_.Exception.Message)"}
                    }else{$log.Add("$n : already $($svc.Status)")}
                }

                $stamp=(Get-Date).ToString('yyyyMMdd-HHmmss')
                $targets=@(
                    [pscustomobject]@{Path=(Join-Path $env:SystemRoot 'SoftwareDistribution');Name="SoftwareDistribution.rbz-$stamp"},
                    [pscustomobject]@{Path=(Join-Path $env:SystemRoot 'System32\catroot2');Name="catroot2.rbz-$stamp"}
                )

                foreach($t in $targets){
                    if(Test-Path $t.Path){
                        $parent=Split-Path -Parent $t.Path
                        try{
                            Rename-Item -LiteralPath $t.Path -NewName $t.Name -ErrorAction Stop
                            $log.Add("$($t.Path) -> $(Join-Path $parent $t.Name)")
                        }catch{
                            throw "Could not reset $($t.Path). $($_.Exception.Message)"
                        }
                    }else{
                        $log.Add("$($t.Path) : not present")
                    }
                }

                foreach($n in $services){
                    $svc=Get-Service $n -ErrorAction SilentlyContinue
                    if($svc -and $svc.StartType -ne 'Disabled'){
                        try{
                            Start-Service $n -ErrorAction Stop
                            Start-Sleep -Milliseconds 750
                            $svc=Get-Service $n -ErrorAction Stop
                            $log.Add("$n : final $($svc.Status)")
                        }catch{$log.Add("$n : restart error - $($_.Exception.Message)")}
                    }
                }

                Start-Sleep -Seconds 2
                $sdExists=Test-Path (Join-Path $env:SystemRoot 'SoftwareDistribution')
                $wu=Get-Service wuauserv -ErrorAction SilentlyContinue
                $serviceOk=($null -eq $wu -or $wu.StartType -eq 'Disabled' -or $wu.Status -eq 'Running')
                $verified=($sdExists -and $serviceOk)

                $result.Success=$verified
                $result.Summary=$(if($verified){'Windows Update components were reset and service recovery was verified.'}else{'Windows Update component reset completed, but recovery could not be fully verified.'})
                $result.Details=($log -join "`n")
                $result.VerificationCategory='Updates'
                $result.VerificationCheck='Windows Update components'
                $result.VerificationStatus=$(if($verified){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$result.Summary
                $result.VerificationDetails=$result.Details
            }

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

            # RBZ080RC9C_STORE_RESET
            'ResetMicrosoftStoreCache' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Reset Microsoft Store cache' -Message 'Running WSReset...' -Started $started -Indeterminate:$true

                $wsreset=Join-Path $env:SystemRoot 'System32\wsreset.exe'
                if(-not(Test-Path $wsreset)){throw 'wsreset.exe is not available on this Windows installation.'}

                $beforePkg=Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
                $beforeStatus=if($beforePkg){[string]$beforePkg.Status}else{'Not installed'}

                $proc=$null
                $timedOut=$false
                $exitCode=$null

                try{
                    $proc=Start-Process -FilePath $wsreset -PassThru -ErrorAction Stop

                    # WSReset may briefly open a Store window. Give it a reasonable
                    # period to finish, but do not hang RBZ indefinitely.
                    if(-not $proc.WaitForExit(30000)){
                        $timedOut=$true
                    }else{
                        $exitCode=$proc.ExitCode
                    }
                }catch{
                    throw "Could not launch wsreset.exe. $($_.Exception.Message)"
                }

                Start-Sleep -Seconds 2

                $afterPkg=Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
                $afterStatus=if($afterPkg){[string]$afterPkg.Status}else{'Not installed'}
                $packageHealthy=($afterPkg -and $afterStatus -eq 'Ok')

                # A timeout is not automatically a failure because WSReset can hand
                # off to the Store UI and continue outside the original process.
                # The post-action package health is the stronger verification signal.
                $ok=$packageHealthy -and (-not $timedOut -or $afterPkg)

                $result.Success=$ok
                $result.Summary=$(if($ok){'Microsoft Store cache reset completed and Store package health was verified.'}else{'Microsoft Store cache reset could not be verified.'})

                $result.Details=@"
WSReset path: $wsreset
Process started: $([bool]$proc)
Process timed out after 30 seconds: $timedOut
Process exit code: $(if($null -eq $exitCode){'Not available'}else{$exitCode})

Store package before:
Present: $([bool]$beforePkg)
Status: $beforeStatus

Store package after:
Present: $([bool]$afterPkg)
Status: $afterStatus
Package: $(if($afterPkg){$afterPkg.PackageFullName}else{'Not found'})
Install location: $(if($afterPkg){$afterPkg.InstallLocation}else{'Not found'})

RBZ verifies package health after WSReset because wsreset.exe can behave as a GUI hand-off and does not always provide useful console output.
"@

                $result.VerificationCategory='Windows'
                $result.VerificationCheck='Microsoft Store cache'
                $result.VerificationStatus=$(if($ok){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($ok){'Microsoft Store package reports Status=Ok after cache reset.'}else{"Microsoft Store package health could not be verified. Status: $afterStatus"})
                $result.VerificationDetails=$result.Details
            }
            'TempCleanup' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Temporary file cleanup' -Message 'Removing accessible temporary files...' -Started $started -Indeterminate:$true
                $targets=@()
                if($env:TEMP){$targets+=$env:TEMP}
                $windowsTemp=Join-Path $env:WINDIR 'Temp'
                if(Test-Path $windowsTemp){$targets+=$windowsTemp}

                $bytesBefore=0L;$bytesAfter=0L;$deleted=0;$skipped=0;$seen=@{}
                foreach($target in $targets){
                    if([string]::IsNullOrWhiteSpace($target) -or -not(Test-Path $target)){continue}
                    $full=[IO.Path]::GetFullPath($target)
                    if($seen.ContainsKey($full)){continue};$seen[$full]=$true
                    try{$files=@(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue);$sum=($files|Measure-Object Length -Sum).Sum;if($null -ne $sum){$bytesBefore+=[long]$sum}}catch{}
                    foreach($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)){try{Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop;$deleted++}catch{$skipped++}}
                    try{$filesAfter=@(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue);$sumAfter=($filesAfter|Measure-Object Length -Sum).Sum;if($null -ne $sumAfter){$bytesAfter+=[long]$sumAfter}}catch{}
                }
                $recovered=[math]::Max(0,$bytesBefore-$bytesAfter)
                $result.BytesRecovered=$recovered;$result.Success=$true
                $result.Summary=("Temporary-file cleanup completed. Recovered approximately {0:N2} GB." -f ($recovered/1GB))
                $result.Details="Items removed: $deleted`nItems skipped/in use: $skipped`nApproximate bytes recovered: $recovered"
                $result.VerificationCategory='Cleanup'
                $result.VerificationCheck='Temporary files'
                $result.VerificationStatus='Healthy'
                $result.VerificationSummary=("Approximately {0:N2} GB recovered." -f ($recovered/1GB))
            }

            default {throw "Unknown service action: $Id"}
        }
    } catch {
        $result.Success=$false
        $result.Summary="Action failed: $($result.Name)"
        $result.Details=$_.Exception.ToString()
        if([string]::IsNullOrWhiteSpace($result.VerificationStatus)){
            $result.VerificationCategory=if($action){$action.Category}else{'Repair'}
            $result.VerificationCheck=if($action){$action.Name}else{$Id}
            $result.VerificationStatus='Warning'
            $result.VerificationSummary=$result.Summary
            $result.VerificationDetails=$result.Details
        }
    }

    Write-RBZProgressState -ProgressPath $ProgressPath -Stage $result.Name -Percent 100 -Message $result.Summary -Started $started -Indeterminate:$false
    $result.Finished=(Get-Date).ToString('o')
    [pscustomobject]$result
}

Export-ModuleMember -Function Get-RBZServiceActions,Invoke-RBZServiceAction,New-RBZRestorePoint,Get-RBZSystemProtectionState,Enable-RBZSystemProtection






