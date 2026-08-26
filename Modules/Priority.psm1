function Get-RBZFindingPriority {
    param([Parameter(Mandatory)]$Finding)

    $status=[string]$Finding.Status
    $text=("{0} {1} {2} {3}" -f $Finding.Name,$Finding.Summary,$Finding.Details,$Finding.Recommendation).ToLowerInvariant()

    $rank=0
    $priority='Informational'
    $reason='Informational finding.'

    switch($status){
        'Critical'{$rank=400;$priority='Urgent';$reason='Critical diagnostic finding.'}
        'Warning'{$rank=300;$priority='High';$reason='Warning-level diagnostic finding.'}
        'Recommend'{$rank=200;$priority='Medium';$reason='Recommended maintenance or configuration action.'}
        'Info'{$rank=100;$priority='Informational';$reason='Informational finding.'}
        'Healthy'{$rank=0;$priority='Healthy';$reason='No action required.'}
    }

    # Specific diagnostic classes must be evaluated before broad category words.
    # For example, application crash evidence can contain words such as
    # "anti-cheat" or other security-related terms in its Details, which must
    # not cause it to inherit a security-priority explanation.
    if($text -match 'code 28|drivers? .*not installed|missing driver'){
        $rank+=45
        $reason='A device is missing a required driver.'
    }
    elseif($text -match 'disk|nvme|smart|uncorrected|filesystem|ntfs|controller'){
        $rank+=35
        $reason='Storage/controller findings can affect reliability or data integrity.'
    }
    elseif($text -match 'application crash|application hang|crash history|faulting application|crash/hang|unexpected shutdown|bugcheck|blue screen|minidump'){
        $rank+=20
        $reason='Repeated application crashes or hangs indicate a recurring software, driver or component stability issue that warrants investigation.'
    }
    elseif($text -match 'defender|firewall|bitlocker|secure boot|tpm|security'){
        $rank+=25
        $reason='Security protection or configuration requires review.'
    }
    elseif($text -match 'windows update|pending update|update'){
        $rank+=15
        $reason='Updates can resolve security, reliability and compatibility issues.'
    }
    elseif($text -match 'network|dns|gateway|tcp|tls'){
        $rank+=10
        $reason='Connectivity/configuration issue may affect normal operation.'
    }

    if($status -eq 'Info'){$rank=[math]::Min($rank,149)}
    if($status -eq 'Healthy'){$rank=0}

    [pscustomobject]@{
        Priority=$priority
        Rank=[int]$rank
        Reason=$reason
    }
}

function Get-RBZRecommendedAction {
    param([Parameter(Mandatory)]$Finding)

    $name=[string]$Finding.Name
    $category=[string]$Finding.Category
    $status=[string]$Finding.Status
    $text=("{0} {1} {2} {3}" -f $Finding.Name,$Finding.Summary,$Finding.Details,$Finding.Recommendation).ToLowerInvariant()

    $manual=if([string]::IsNullOrWhiteSpace([string]$Finding.Recommendation)){
        'Review the underlying diagnostic evidence before making changes.'
    }else{
        [string]$Finding.Recommendation
    }

    $result=[ordered]@{
        ActionType='Manual'
        ActionId=''
        ActionName='Manual technician action'
        ActionText=$manual
        CanOpenRepairCentre=$false
        Guidance='This finding does not have a safe automatic repair mapping.'
    }

    if($text -match 'code 28|drivers? .*not installed|missing driver'){
        $result.ActionName='Identify and install manufacturer driver'
        $result.ActionText='Confirm the hardware ID, then install the appropriate signed driver from the PC, motherboard or device manufacturer.'
        $result.Guidance='Driver installation remains manual because selecting the wrong storage/chipset/device driver can make the system unstable.'
        return [pscustomobject]$result
    }

    if($text -match 'defender' -and $text -match 'signature|security intelligence|out.of.date|age'){
        $result.ActionType='Repair Centre'
        $result.ActionId='DefenderSignatureUpdate'
        $result.ActionName='Update Defender security intelligence'
        $result.ActionText='Open Repair Centre and review the Defender security intelligence update action.'
        $result.CanOpenRepairCentre=$true
        $result.Guidance='RBZ can navigate to the matching low-risk Repair Centre action. It will not run or select it automatically.'
        return [pscustomobject]$result
    }

    if($text -match 'defender|antivirus|malware' -and $text -match 'scan|threat|protection'){
        $result.ActionType='Repair Centre'
        $result.ActionId='DefenderQuickScan'
        $result.ActionName='Microsoft Defender quick scan'
        $result.ActionText='Open Repair Centre and review the Defender quick scan action.'
        $result.CanOpenRepairCentre=$true
        $result.Guidance='A quick scan is available as a low-risk technician-approved action.'
        return [pscustomobject]$result
    }

    if($category -eq 'Storage' -and $text -match 'filesystem|ntfs|disk|volume|chkdsk|file system'){
        $result.ActionType='Repair Centre'
        $result.ActionId='CheckDiskScan'
        $result.ActionName='System drive online disk scan'
        $result.ActionText='Open Repair Centre and review the non-disruptive CHKDSK /scan action.'
        $result.CanOpenRepairCentre=$true
        $result.Guidance='RBZ only maps to the online scan. It does not schedule an offline repair automatically.'
        return [pscustomobject]$result
    }

    if($text -match 'component store|dism|component corruption'){
        $result.ActionType='Repair Centre'
        if($status -in @('Warning','Critical')){
            $result.ActionId='DismRestoreHealth'
            $result.ActionName='Repair Windows component store'
            $result.ActionText='Open Repair Centre and review DISM /RestoreHealth.'
        }else{
            $result.ActionId='DismScanHealth'
            $result.ActionName='Windows component health scan'
            $result.ActionText='Open Repair Centre and review DISM /ScanHealth.'
        }
        $result.CanOpenRepairCentre=$true
        $result.Guidance='The Repair Centre keeps technician confirmation and restore-point safeguards for repair actions.'
        return [pscustomobject]$result
    }

    if($text -match 'system file|windows resource protection|sfc'){
        $result.ActionType='Repair Centre'
        if($status -in @('Warning','Critical')){
            $result.ActionId='SfcScannow'
            $result.ActionName='Repair protected system files'
            $result.ActionText='Open Repair Centre and review SFC /scannow.'
        }else{
            $result.ActionId='SfcVerifyOnly'
            $result.ActionName='System file verification'
            $result.ActionText='Open Repair Centre and review SFC /verifyonly.'
        }
        $result.CanOpenRepairCentre=$true
        $result.Guidance='RBZ navigates to the matching action but does not select or execute it automatically.'
        return [pscustomobject]$result
    }

    if($text -match 'windows time|time service|time synchron|clock skew'){
        $result.ActionType='Repair Centre'
        $result.ActionId='WindowsTimeResync'
        $result.ActionName='Windows Time resynchronisation'
        $result.ActionText='Open Repair Centre and review the Windows Time resynchronisation action.'
        $result.CanOpenRepairCentre=$true
        $result.Guidance='This action requests rediscovery/resynchronisation without replacing domain or NTP policy.'
        return [pscustomobject]$result
    }

    if($text -match 'free space|temporary files|temp folder|disk space'){
        $result.ActionType='Repair Centre'
        $result.ActionId='TempCleanup'
        $result.ActionName='Temporary file cleanup'
        $result.ActionText='Open Repair Centre and review temporary file cleanup.'
        $result.CanOpenRepairCentre=$true
        $result.Guidance='Cleanup is limited to accessible TEMP locations and skips locked items.'
        return [pscustomobject]$result
    }

    if($text -match 'application crash|application hang|crash history|faulting application|crash/hang'){
        $result.ActionName='Investigate recurring application failures'
        $result.ActionText='Prioritise repeated executables/modules, update the affected application and related drivers, then retest. Do not run generic Windows repairs solely because an application crashed.'
        $result.Guidance='Application failures can be app-, driver-, overlay-, anti-cheat- or hardware-specific, so RC3 deliberately avoids a generic automatic repair.'
        return [pscustomobject]$result
    }

    if($category -eq 'Updates' -or $text -match 'windows update|pending update'){
        $result.ActionName='Review and install Windows Updates'
        $result.ActionText='Open Windows Update, review pending/failed updates, install appropriate updates, restart if required, then run another RBZ scan.'
        $result.Guidance='The current Repair Centre does not have a dedicated Windows Update install/repair action, so this remains manual.'
        return [pscustomobject]$result
    }

    if($category -eq 'Network'){
        $result.ActionName='Investigate network configuration'
        $result.ActionText='Use the adapter, gateway, DNS, TCP and TLS evidence to isolate local configuration, Wi-Fi/Ethernet, router, VPN, proxy or upstream problems before changing settings.'
        $result.Guidance='RC3 does not perform blanket Winsock/IP/DNS resets because those can disrupt managed or VPN configurations.'
        return [pscustomobject]$result
    }

    return [pscustomobject]$result
}

function Get-RBZPrioritizedFindings {
    param(
        [Parameter(Mandatory)][object[]]$Findings,
        [int]$Top=5,
        [switch]$IncludeInfo
    )

    $items=foreach($finding in @($Findings)){
        if($finding.Status -eq 'Healthy'){continue}
        if(-not $IncludeInfo -and $finding.Status -eq 'Info'){continue}

        $p=Get-RBZFindingPriority -Finding $finding
        $a=Get-RBZRecommendedAction -Finding $finding

        [pscustomobject]@{
            Priority=$p.Priority
            Rank=$p.Rank
            Category=$finding.Category
            Name=$finding.Name
            Status=$finding.Status
            Summary=$finding.Summary
            Recommendation=$finding.Recommendation
            Reason=$p.Reason
            ActionType=$a.ActionType
            ActionId=$a.ActionId
            ActionName=$a.ActionName
            ActionText=$a.ActionText
            CanOpenRepairCentre=$a.CanOpenRepairCentre
            Guidance=$a.Guidance
            Finding=$finding
        }
    }

    @($items |
        Sort-Object @{Expression='Rank';Descending=$true},
                    @{Expression='Category';Descending=$false},
                    @{Expression='Name';Descending=$false} |
        Select-Object -First $Top)
}

function Get-RBZPrioritySummary {
    param(
        [Parameter(Mandatory)][object[]]$Findings,
        [int]$Top=3
    )

    $topItems=@(Get-RBZPrioritizedFindings -Findings $Findings -Top $Top)
    if($topItems.Count -eq 0){
        return 'No priority actions identified.'
    }

    $lines=[System.Collections.Generic.List[string]]::new()
    $i=1

    foreach($item in $topItems){
        $lines.Add("$i. [$($item.Priority)] $($item.Category) - $($item.Name)")
        $lines.Add("   $($item.Summary)")
        $lines.Add("   Action: $($item.ActionText)")
        $i++
    }

    $lines -join "`n"
}

Export-ModuleMember -Function Get-RBZFindingPriority,Get-RBZRecommendedAction,Get-RBZPrioritizedFindings,Get-RBZPrioritySummary
