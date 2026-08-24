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

        $before=@()
        try {
            $before=@(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        } catch {}

        $beforeSequences=@($before | ForEach-Object {[int]$_.SequenceNumber})

        Checkpoint-Computer `
            -Description $description `
            -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop

        Start-Sleep -Seconds 2

        $after=@(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending)

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
                Summary='Checkpoint-Computer returned without error, but a new restore point could not be verified.'
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
            Summary='Restore point could not be created.'
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
        $out=''
        if(Test-Path $stdout){$out += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
        if(Test-Path $stderr){$out += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}

        Write-RBZProgressState -ProgressPath $ProgressPath -Stage $Stage -Percent 100 -Message 'Finished.' -Started $started -Indeterminate:$false

        [pscustomobject]@{
            ExitCode=$p.ExitCode
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

            'WindowsTimeResync' {
                Write-RBZProgressState -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation' -Message 'Checking Windows Time service...' -Started $started -Indeterminate:$true
                $svc=Get-Service W32Time -ErrorAction Stop
                if($svc.StartType -eq 'Disabled'){throw 'Windows Time service is disabled. RBZ PC Health will not change a Disabled service automatically.'}
                if($svc.Status -ne 'Running'){Start-Service W32Time -ErrorAction Stop;Start-Sleep -Seconds 1}

                $r=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync','/rediscover') -ProgressPath $ProgressPath -Stage 'Windows Time resynchronisation'
                $source=(& w32tm.exe /query /source 2>&1 | Out-String).Trim()
                $status=(& w32tm.exe /query /status 2>&1 | Out-String).Trim()

                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'Windows Time resynchronisation completed successfully.'}else{"Windows Time resynchronisation returned exit code $($r.ExitCode)."})
                $result.Details="Resync output:`n$($r.Output)`n`nSource:`n$source`n`nStatus:`n$status"
                $result.VerificationCategory='System'
                $result.VerificationCheck='Windows Time synchronisation'
                $result.VerificationStatus=$(if($r.ExitCode -eq 0){'Healthy'}else{'Warning'})
                $result.VerificationSummary=$(if($r.ExitCode -eq 0){"Windows Time resynchronised. Source: $source"}else{'Windows Time resynchronisation did not complete successfully.'})
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
