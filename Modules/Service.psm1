function Get-RBZServiceActions {
    param($Config)

    $actions = [System.Collections.Generic.List[object]]::new()

    if($Config.remediation.allowDefenderQuickScan){
        $actions.Add([pscustomobject]@{
            Id='DefenderQuickScan'
            Name='Microsoft Defender quick scan'
            Category='Security'
            Risk='Low'
            Description='Runs a Microsoft Defender Quick Scan. No threats are automatically removed by RBZ PC Health.'
            RequiresRestart=$false
            Selected=$false
        })
    }

    if($Config.remediation.allowDismScanHealth){
        $actions.Add([pscustomobject]@{
            Id='DismScanHealth'
            Name='Windows component health scan'
            Category='Windows'
            Risk='Low'
            Description='Runs DISM /Online /Cleanup-Image /ScanHealth. This scans the component store and does not repair it.'
            RequiresRestart=$false
            Selected=$false
        })
    }

    if($Config.remediation.allowSfcVerifyOnly){
        $actions.Add([pscustomobject]@{
            Id='SfcVerifyOnly'
            Name='System file verification'
            Category='Windows'
            Risk='Low'
            Description='Runs SFC /verifyonly. This verifies protected system files without repairing them.'
            RequiresRestart=$false
            Selected=$false
        })
    }

    if($Config.remediation.allowTempCleanup){
        $actions.Add([pscustomobject]@{
            Id='TempCleanup'
            Name='Temporary file cleanup'
            Category='Cleanup'
            Risk='Low'
            Description='Deletes accessible files from the current user TEMP folder and Windows TEMP folder. Locked/in-use items are skipped.'
            RequiresRestart=$false
            Selected=$false
        })
    }

    return $actions
}

function Invoke-RBZServiceAction {
    param(
        [Parameter(Mandatory)][string]$Id,
        $Config
    )

    $started = Get-Date
    $result = [ordered]@{
        Id=$Id
        Started=$started.ToString('o')
        Finished=$null
        Success=$false
        Summary=''
        Details=''
        BytesRecovered=0
    }

    try {
        switch($Id){
            'DefenderQuickScan' {
                if(-not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)){
                    throw 'Microsoft Defender Start-MpScan is not available on this device.'
                }
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                $result.Success=$true
                $result.Summary='Microsoft Defender quick scan started/completed successfully.'
                $result.Details='Start-MpScan -ScanType QuickScan completed without a PowerShell error.'
            }

            'DismScanHealth' {
                $output = & dism.exe /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                $result.Success=($exitCode -eq 0)
                $result.Summary=$(if($result.Success){'DISM component health scan completed successfully.'}else{"DISM component health scan returned exit code $exitCode."})
                $result.Details=$output.Trim()
            }

            'SfcVerifyOnly' {
                $output = & sfc.exe /verifyonly 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                $result.Success=($exitCode -eq 0)
                $result.Summary=$(if($result.Success){'System File Checker verification completed.'}else{"SFC verification returned exit code $exitCode."})
                $result.Details=$output.Trim()
            }

            'TempCleanup' {
                $targets = @()
                if($env:TEMP){$targets += $env:TEMP}
                $windowsTemp = Join-Path $env:WINDIR 'Temp'
                if(Test-Path $windowsTemp){$targets += $windowsTemp}

                $bytesBefore = 0L
                $bytesAfter = 0L
                $deleted = 0
                $skipped = 0
                $seen = @{}

                foreach($target in $targets){
                    if([string]::IsNullOrWhiteSpace($target) -or -not(Test-Path $target)){continue}
                    $full = [IO.Path]::GetFullPath($target)
                    if($seen.ContainsKey($full)){continue}
                    $seen[$full]=$true

                    try {
                        $files = @(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue)
                        $bytesBefore += [long](($files | Measure-Object Length -Sum).Sum)
                    } catch {}

                    foreach($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)){
                        try {
                            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                            $deleted++
                        } catch {
                            $skipped++
                        }
                    }

                    try {
                        $filesAfter = @(Get-ChildItem -LiteralPath $full -File -Recurse -Force -ErrorAction SilentlyContinue)
                        $bytesAfter += [long](($filesAfter | Measure-Object Length -Sum).Sum)
                    } catch {}
                }

                $recovered=[math]::Max(0,$bytesBefore-$bytesAfter)
                $result.BytesRecovered=$recovered
                $result.Success=$true
                $result.Summary=("Temporary-file cleanup completed. Recovered approximately {0:N2} GB." -f ($recovered/1GB))
                $result.Details="Items removed: $deleted`nItems skipped/in use: $skipped`nApproximate bytes recovered: $recovered"
            }

            default { throw "Unknown service action: $Id" }
        }
    } catch {
        $result.Success=$false
        $result.Summary="Action failed: $Id"
        $result.Details=$_.Exception.ToString()
    }

    $result.Finished=(Get-Date).ToString('o')
    [pscustomobject]$result
}

Export-ModuleMember -Function Get-RBZServiceActions,Invoke-RBZServiceAction
