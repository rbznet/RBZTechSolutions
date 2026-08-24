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
            -Description 'Runs DISM /Online /Cleanup-Image /ScanHealth. Diagnostic only; no component repair is performed.'))
    }

    if($Config.remediation.allowSfcVerifyOnly){
        $actions.Add((New-RBZAction -Id 'SfcVerifyOnly' -Name 'System file verification' -Category 'Windows' -Risk 'Low' `
            -Description 'Runs SFC /verifyonly. Verifies protected system files without repairing them.'))
    }

    if($Config.remediation.allowCheckDiskScan){
        $actions.Add((New-RBZAction -Id 'CheckDiskScan' -Name 'System drive online disk scan' -Category 'Storage' -Risk 'Low' `
            -Description 'Runs CHKDSK on the Windows system drive using /scan. This is an online scan and does not schedule an offline repair.'))
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
            -Description 'Runs DISM /Online /Cleanup-Image /RestoreHealth. Windows may download replacement components. A restore point is attempted first when configured.'))
    }

    if($Config.remediation.allowSfcScannow){
        $actions.Add((New-RBZAction -Id 'SfcScannow' -Name 'Repair protected system files' -Category 'Windows' -Risk 'Medium' `
            -Description 'Runs SFC /scannow to repair protected Windows system files where possible. A restore point is attempted first when configured.'))
    }

    return $actions
}

function New-RBZRestorePoint {
    param($Config,[string]$Reason='Pre-repair protection')

    $description=[string]$Config.remediation.restorePointDescription
    if([string]::IsNullOrWhiteSpace($description)){$description='RBZ PC Health pre-repair'}

    try {
        if(-not(Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)){
            return [pscustomobject]@{Success=$false;Summary='System Restore checkpoint command is unavailable.';Details='Checkpoint-Computer was not found.'}
        }

        Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return [pscustomobject]@{
            Success=$true
            Summary="Restore point created: $description"
            Details="Reason: $Reason"
        }
    } catch {
        return [pscustomobject]@{
            Success=$false
            Summary='Restore point could not be created.'
            Details=$_.Exception.ToString()
        }
    }
}

function Invoke-RBZNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$FilePath
    $psi.Arguments=($Arguments -join ' ')
    $psi.UseShellExecute=$false
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true

    $p=New-Object System.Diagnostics.Process
    $p.StartInfo=$psi
    [void]$p.Start()
    $stdout=$p.StandardOutput.ReadToEnd()
    $stderr=$p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        ExitCode=$p.ExitCode
        Output=(($stdout,$stderr | Where-Object {$_}) -join "`n").Trim()
    }
}

function Invoke-RBZServiceAction {
    param(
        [Parameter(Mandatory)][string]$Id,
        $Config
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
    }

    try {
        if(-not $action){throw "Unknown service action: $Id"}

        if($action.Risk -eq 'Medium' -and $Config.remediation.attemptRestorePointBeforeMediumActions){
            $result.RestorePointAttempted=$true
            $rp=New-RBZRestorePoint -Config $Config -Reason $action.Name
            $result.RestorePointCreated=[bool]$rp.Success
            $result.RestorePointDetails="$($rp.Summary)`n$($rp.Details)"

            if(-not $rp.Success -and $Config.remediation.blockMediumActionIfRestorePointFails){
                throw "Pre-repair restore point failed and configuration blocks Medium-risk actions.`n$($rp.Details)"
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
                if(-not(Get-Command Update-MpSignature -ErrorAction SilentlyContinue)){
                    throw 'Microsoft Defender Update-MpSignature is unavailable. A third-party antivirus may be active.'
                }
                Update-MpSignature -ErrorAction Stop
                $mp=Get-MpComputerStatus -ErrorAction SilentlyContinue
                $result.Success=$true
                $result.Summary='Microsoft Defender security intelligence update completed.'
                $result.Details=$(if($mp){"Signature version: $($mp.AntivirusSignatureVersion)`nSignature age: $($mp.AntivirusSignatureAge) day(s)"}else{'Update-MpSignature completed without a PowerShell error.'})
            }

            'DefenderQuickScan' {
                if(-not(Get-Command Start-MpScan -ErrorAction SilentlyContinue)){
                    throw 'Microsoft Defender Start-MpScan is unavailable. A third-party antivirus may be active.'
                }
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                $result.Success=$true
                $result.Summary='Microsoft Defender quick scan completed.'
                $result.Details='Start-MpScan -ScanType QuickScan completed without a PowerShell error.'
            }

            'DismScanHealth' {
                $r=Invoke-RBZNativeCommand -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/ScanHealth')
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'DISM component health scan completed successfully.'}else{"DISM ScanHealth returned exit code $($r.ExitCode)."})
                $result.Details=$r.Output
            }

            'DismRestoreHealth' {
                $r=Invoke-RBZNativeCommand -FilePath 'dism.exe' -Arguments @('/Online','/Cleanup-Image','/RestoreHealth')
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'DISM component store repair completed successfully.'}else{"DISM RestoreHealth returned exit code $($r.ExitCode)."})
                $result.Details=$r.Output
            }

            'SfcVerifyOnly' {
                $r=Invoke-RBZNativeCommand -FilePath 'sfc.exe' -Arguments @('/verifyonly')
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'System File Checker verification completed.'}else{"SFC verify-only returned exit code $($r.ExitCode)."})
                $result.Details=$r.Output
            }

            'SfcScannow' {
                $r=Invoke-RBZNativeCommand -FilePath 'sfc.exe' -Arguments @('/scannow')
                # SFC can report useful repair outcomes even when exit-code semantics vary; preserve raw output.
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'System File Checker repair completed.'}else{"SFC /scannow returned exit code $($r.ExitCode); review output."})
                $result.Details=$r.Output
            }

            'CheckDiskScan' {
                $drive=$env:SystemDrive
                if([string]::IsNullOrWhiteSpace($drive)){$drive='C:'}
                $r=Invoke-RBZNativeCommand -FilePath 'chkdsk.exe' -Arguments @($drive,'/scan')
                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){"Online CHKDSK scan completed successfully on $drive."}else{"CHKDSK /scan returned exit code $($r.ExitCode) on $drive."})
                $result.Details=$r.Output
            }

            'WindowsTimeResync' {
                $svc=Get-Service W32Time -ErrorAction Stop
                if($svc.StartType -eq 'Disabled'){
                    throw 'Windows Time service is disabled. RBZ PC Health will not change a Disabled service automatically.'
                }

                if($svc.Status -ne 'Running'){
                    Start-Service W32Time -ErrorAction Stop
                    Start-Sleep -Seconds 1
                }

                $r=Invoke-RBZNativeCommand -FilePath 'w32tm.exe' -Arguments @('/resync','/rediscover')
                $source=(& w32tm.exe /query /source 2>&1 | Out-String).Trim()
                $status=(& w32tm.exe /query /status 2>&1 | Out-String).Trim()

                $result.Success=($r.ExitCode -eq 0)
                $result.Summary=$(if($result.Success){'Windows Time resynchronisation completed successfully.'}else{"Windows Time resynchronisation returned exit code $($r.ExitCode)."})
                $result.Details="Resync output:`n$($r.Output)`n`nSource:`n$source`n`nStatus:`n$status"
            }

            'TempCleanup' {
                $targets=@()
                if($env:TEMP){$targets+=$env:TEMP}
                $windowsTemp=Join-Path $env:WINDIR 'Temp'
                if(Test-Path $windowsTemp){$targets+=$windowsTemp}

                $bytesBefore=0L
                $bytesAfter=0L
                $deleted=0
                $skipped=0
                $seen=@{}

                foreach($target in $targets){
                    if([string]::IsNullOrWhiteSpace($target) -or -not(Test-Path $target)){continue}
                    $full=[IO.Path]::GetFullPath($target)
                    if($seen.ContainsKey($full)){continue}
                    $seen[$full]=$true

                    try {
                        $files=@(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue)
                        $sum=($files|Measure-Object Length -Sum).Sum
                        if($null -ne $sum){$bytesBefore+=[long]$sum}
                    } catch {}

                    foreach($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)){
                        try {
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                            $deleted++
                        } catch {$skipped++}
                    }

                    try {
                        $filesAfter=@(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue)
                        $sumAfter=($filesAfter|Measure-Object Length -Sum).Sum
                        if($null -ne $sumAfter){$bytesAfter+=[long]$sumAfter}
                    } catch {}
                }

                $recovered=[math]::Max(0,$bytesBefore-$bytesAfter)
                $result.BytesRecovered=$recovered
                $result.Success=$true
                $result.Summary=("Temporary-file cleanup completed. Recovered approximately {0:N2} GB." -f ($recovered/1GB))
                $result.Details="Items removed: $deleted`nItems skipped/in use: $skipped`nApproximate bytes recovered: $recovered"
            }

            default {throw "Unknown service action: $Id"}
        }
    } catch {
        $result.Success=$false
        $result.Summary="Action failed: $($result.Name)"
        $result.Details=$_.Exception.ToString()
    }

    $result.Finished=(Get-Date).ToString('o')
    [pscustomobject]$result
}

Export-ModuleMember -Function Get-RBZServiceActions,Invoke-RBZServiceAction,New-RBZRestorePoint
