function Get-RBZSecurityFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
        $disabled = @($profiles | Where-Object Enabled -eq $false)
        $state = if($disabled.Count){'Warning'}else{'Healthy'}
        $details = ($profiles | ForEach-Object {
            "$($_.Name): Enabled=$($_.Enabled); Inbound=$($_.DefaultInboundAction); Outbound=$($_.DefaultOutboundAction)"
        }) -join "`n"
        $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status $state -Summary $(if($disabled.Count){"Disabled profiles: $($disabled.Name -join ', ')"}else{'All Windows Firewall profiles are enabled.'}) -Details $details -Recommendation $(if($disabled.Count){'Review why one or more Windows Firewall profiles are disabled.'}else{''})))
    } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status 'Info' -Summary 'Firewall status unavailable.' -Details $_.Exception.Message)) }

    if ($Config.scan.defender) {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $sigAge = [int]$mp.AntivirusSignatureAge
            $state = if(-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled){'Critical'}elseif($sigAge -gt [int]$Config.thresholds.defenderSignatureAgeWarningDays){'Warning'}else{'Healthy'}
            $details = @(
                "Antivirus enabled: $($mp.AntivirusEnabled)"
                "Antispyware enabled: $($mp.AntispywareEnabled)"
                "Real-time protection: $($mp.RealTimeProtectionEnabled)"
                "Behavior monitoring: $($mp.BehaviorMonitorEnabled)"
                "IOAV protection: $($mp.IoavProtectionEnabled)"
                "Network inspection: $($mp.NISEnabled)"
                "Tamper protected: $($mp.IsTamperProtected)"
                "Defender service: $($mp.AMServiceEnabled)"
                "Engine version: $($mp.AMEngineVersion)"
                "Platform version: $($mp.AMProductVersion)"
                "Signature version: $($mp.AntivirusSignatureVersion)"
                "Signature age: $sigAge day(s)"
                "Signature updated: $($mp.AntivirusSignatureLastUpdated)"
                "Last quick scan: $($mp.QuickScanEndTime)"
                "Last full scan: $($mp.FullScanEndTime)"
            ) -join "`n"
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status $state -Summary "Antivirus=$($mp.AntivirusEnabled); Real-time=$($mp.RealTimeProtectionEnabled); Signature age=$sigAge day(s)" -Details $details -Recommendation $(if($state -ne 'Healthy'){'Review antivirus protection and signature/update state.'}else{''})))

            try {
                $pref = Get-MpPreference -ErrorAction Stop

                # RBZ080RC4A_NORMALISE_DEFENDER_EXCLUSIONS
                # Some Defender/PowerShell combinations can return several exclusion
                # paths inside one string. Normalise them so the count and report
                # presentation reflect the actual individual entries.
                function Expand-RBZDefenderExclusionValue {
                    param(
                        [AllowNull()]$Value,
                        [ValidateSet('Path','Process','Extension','IP')][string]$Type
                    )

                    foreach($raw in @($Value)){
                        if($null -eq $raw){continue}

                        $s=[string]$raw
                        if([string]::IsNullOrWhiteSpace($s)){continue}

                        $parts=@()

                        if($Type -eq 'Path'){
                            # First handle conventional separators.
                            $parts=@($s -split '[;\r\n]+' | Where-Object {-not [string]::IsNullOrWhiteSpace($_)})

                            # Defender can occasionally expose multiple absolute paths
                            # concatenated without separators. Split before each new
                            # drive-root or UNC path while retaining the root itself.
                            $expanded=[System.Collections.Generic.List[string]]::new()

                            foreach($part in $parts){
                                $p=$part.Trim()

                                $matches=[regex]::Matches(
                                    $p,
                                    '(?i)(?:[A-Z]:\\|\\\\)[\s\S]*?(?=(?:[A-Z]:\\|\\\\)|$)'
                                )

                                if($matches.Count -gt 1){
                                    foreach($m in $matches){
                                        $v=$m.Value.Trim()
                                        if($v){$expanded.Add($v)}
                                    }
                                }else{
                                    $expanded.Add($p)
                                }
                            }

                            $parts=@($expanded)
                        }
                        else{
                            $parts=@($s -split '[;\r\n]+' | Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
                        }

                        foreach($part in $parts){
                            $clean=$part.Trim()
                            if($clean){$clean}
                        }
                    }
                }

                $exclusions=[System.Collections.Generic.List[string]]::new()

                foreach($v in @(Expand-RBZDefenderExclusionValue -Value $pref.ExclusionPath -Type Path)){
                    $exclusions.Add("Path: $v")
                }
                foreach($v in @(Expand-RBZDefenderExclusionValue -Value $pref.ExclusionProcess -Type Process)){
                    $exclusions.Add("Process: $v")
                }
                foreach($v in @(Expand-RBZDefenderExclusionValue -Value $pref.ExclusionExtension -Type Extension)){
                    $exclusions.Add("Extension: $v")
                }
                foreach($v in @(Expand-RBZDefenderExclusionValue -Value $pref.ExclusionIpAddress -Type IP)){
                    $exclusions.Add("IP: $v")
                }

                $count=$exclusions.Count
                $out.Add((New-RBZFinding -Category 'Security' -Name 'Defender exclusions' -Status $(if($count){'Info'}else{'Healthy'}) -Summary $(if($count){"$count configured Microsoft Defender exclusion(s)."}else{'No Microsoft Defender exclusions detected.'}) -Details $(if($count){$exclusions -join "`n"}else{'No path, process, extension or IP exclusions returned.'}) -Recommendation $(if($count){'Review exclusions and confirm each is required and trusted.'}else{''})))
            } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Defender exclusions' -Status 'Info' -Summary 'Defender exclusion configuration unavailable.' -Details $_.Exception.Message)) }
        } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status 'Info' -Summary 'Defender status unavailable or a third-party antivirus may be active.' -Details $_.Exception.Message)) }
    }

    try {
        $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $uac = Get-ItemProperty -Path $uacPath -ErrorAction Stop
        $enabled = ([int]$uac.EnableLUA -eq 1)
        $details = "EnableLUA: $($uac.EnableLUA)`nConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin)`nPromptOnSecureDesktop: $($uac.PromptOnSecureDesktop)`nFilterAdministratorToken: $($uac.FilterAdministratorToken)"
        $out.Add((New-RBZFinding -Category 'Security' -Name 'User Account Control' -Status $(if($enabled){'Healthy'}else{'Warning'}) -Summary $(if($enabled){'User Account Control (UAC) is enabled.'}else{'User Account Control (UAC) is disabled.'}) -Details $details -Recommendation $(if(-not $enabled){'Enable UAC unless there is a documented compatibility requirement to disable it.'}else{''})))
    } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'User Account Control' -Status 'Info' -Summary 'UAC configuration unavailable.' -Details $_.Exception.Message)) }

    try {
        $ssPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
        $ss = Get-ItemProperty -Path $ssPath -Name SmartScreenEnabled -ErrorAction Stop
        $value = [string]$ss.SmartScreenEnabled
        $ssState = if($value -match '^(Off|0)$'){'Recommend'}else{'Healthy'}
        $out.Add((New-RBZFinding -Category 'Security' -Name 'SmartScreen' -Status $ssState -Summary "Windows SmartScreen setting: $value" -Details "SmartScreenEnabled: $value" -Recommendation $(if($ssState -ne 'Healthy'){'Consider enabling Microsoft Defender SmartScreen unless another security control intentionally manages it.'}else{''})))
    } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'SmartScreen' -Status 'Info' -Summary 'SmartScreen setting is not explicitly configured or could not be read.' -Details $_.Exception.Message)) }

    if($Config.scan.secureBoot){
        try {
            $enabled = Confirm-SecureBootUEFI -ErrorAction Stop
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Secure Boot' -Status $(if($enabled){'Healthy'}else{'Recommend'}) -Summary $(if($enabled){'Secure Boot is enabled.'}else{'Secure Boot is disabled.'}) -Recommendation $(if(-not $enabled){'Consider enabling Secure Boot where supported and appropriate after confirming firmware/OS requirements.'}else{''})))
        } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'Secure Boot' -Status 'Info' -Summary 'Secure Boot status unavailable or unsupported.' -Details $_.Exception.Message)) }
    }

    if($Config.scan.tpm){
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            $state = if($tpm.TpmPresent -and $tpm.TpmReady){'Healthy'}else{'Warning'}
            $out.Add((New-RBZFinding -Category 'Security' -Name 'TPM' -Status $state -Summary "Present=$($tpm.TpmPresent); Ready=$($tpm.TpmReady); Enabled=$($tpm.TpmEnabled)" -Details "Owned: $($tpm.TpmOwned)`nAuto provisioning: $($tpm.AutoProvisioning)"))
        } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'TPM' -Status 'Info' -Summary 'TPM status unavailable.' -Details $_.Exception.Message)) }
    }

    if($Config.scan.bitLocker){
        try {
            $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            $protected = $bl.ProtectionStatus -eq 'On'
            $protectors = @($bl.KeyProtector | ForEach-Object { [string]$_.KeyProtectorType }) | Where-Object { $_ }
            $details = @(
                "Mount point: $($bl.MountPoint)"
                "Volume type: $($bl.VolumeType)"
                "Volume status: $($bl.VolumeStatus)"
                "Protection status: $($bl.ProtectionStatus)"
                "Encryption method: $($bl.EncryptionMethod)"
                "Percent encrypted: $($bl.EncryptionPercentage)"
                "Key protector types: $(if($protectors){$protectors -join ', '}else{'None returned'})"
            ) -join "`n"
            $out.Add((New-RBZFinding -Category 'Security' -Name 'BitLocker' -Status $(if($protected){'Healthy'}else{'Recommend'}) -Summary "Protection: $($bl.ProtectionStatus); Encryption: $($bl.VolumeStatus)" -Details $details -Recommendation $(if(-not $protected){'Consider BitLocker/device encryption where appropriate and ensure recovery information is retained.'}else{''})))
        } catch { $out.Add((New-RBZFinding -Category 'Security' -Name 'BitLocker' -Status 'Info' -Summary 'BitLocker status unavailable.' -Details $_.Exception.Message)) }
    }

    return $out
}
Export-ModuleMember -Function Get-RBZSecurityFindings

