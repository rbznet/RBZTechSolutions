function Get-RBZSecurityFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()

    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        $disabled = @($profiles | Where-Object Enabled -eq $false)
        $state = if($disabled.Count){'Warning'}else{'Healthy'}
        $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status $state `
            -Summary $(if($disabled.Count){"Disabled profiles: $($disabled.Name -join ', ')"}else{'All Windows Firewall profiles are enabled.'}) `
            -Details (($profiles | ForEach-Object {"$($_.Name): Enabled=$($_.Enabled)"}) -join "`n") `
            -Recommendation $(if($disabled.Count){'Review why one or more Windows Firewall profiles are disabled.'}else{''})))
    } catch {
        $out.Add((New-RBZFinding -Category 'Security' -Name 'Windows Firewall' -Status 'Info' -Summary 'Firewall status unavailable.' -Details $_.Exception.Message))
    }

    if ($Config.scan.defender) {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $sigAge = [int]$mp.AntivirusSignatureAge
            $state = if(-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled){'Critical'}elseif($sigAge -gt [int]$Config.thresholds.defenderSignatureAgeWarningDays){'Warning'}else{'Healthy'}
            $details = "Antivirus enabled: $($mp.AntivirusEnabled)`nReal-time protection: $($mp.RealTimeProtectionEnabled)`nBehavior monitoring: $($mp.BehaviorMonitorEnabled)`nSignature age: $sigAge day(s)`nLast quick scan: $($mp.QuickScanEndTime)`nLast full scan: $($mp.FullScanEndTime)"
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status $state `
                -Summary "Antivirus=$($mp.AntivirusEnabled); Real-time=$($mp.RealTimeProtectionEnabled); Signature age=$sigAge day(s)" `
                -Details $details -Recommendation $(if($state -ne 'Healthy'){'Review antivirus protection and signature/update state.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Microsoft Defender' -Status 'Info' `
                -Summary 'Defender status unavailable or a third-party antivirus may be active.' -Details $_.Exception.Message))
        }
    }

    if($Config.scan.secureBoot){
        try {
            $enabled = Confirm-SecureBootUEFI -ErrorAction Stop
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Secure Boot' -Status $(if($enabled){'Healthy'}else{'Warning'}) `
                -Summary $(if($enabled){'Secure Boot is enabled.'}else{'Secure Boot is disabled.'}) `
                -Recommendation $(if(-not $enabled){'Review firmware settings and device requirements before enabling Secure Boot.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'Security' -Name 'Secure Boot' -Status 'Info' -Summary 'Secure Boot status unavailable or unsupported.' -Details $_.Exception.Message))
        }
    }

    if($Config.scan.tpm){
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            $state = if($tpm.TpmPresent -and $tpm.TpmReady){'Healthy'}elseif($tpm.TpmPresent){'Warning'}else{'Warning'}
            $out.Add((New-RBZFinding -Category 'Security' -Name 'TPM' -Status $state `
                -Summary "Present=$($tpm.TpmPresent); Ready=$($tpm.TpmReady); Enabled=$($tpm.TpmEnabled)" `
                -Details "Owned: $($tpm.TpmOwned)`nAuto provisioning: $($tpm.AutoProvisioning)"))
        } catch {
            $out.Add((New-RBZFinding -Category 'Security' -Name 'TPM' -Status 'Info' -Summary 'TPM status unavailable.' -Details $_.Exception.Message))
        }
    }

    if($Config.scan.bitLocker){
        try {
            $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            $protected = $bl.ProtectionStatus -eq 'On'
            $state = if($protected){'Healthy'}else{'Recommend'}
            $out.Add((New-RBZFinding -Category 'Security' -Name 'BitLocker' -Status $state `
                -Summary "Protection: $($bl.ProtectionStatus); Encryption: $($bl.VolumeStatus)" `
                -Details "Encryption method: $($bl.EncryptionMethod)`nPercent encrypted: $($bl.EncryptionPercentage)" `
                -Recommendation $(if(-not $protected){'Consider BitLocker/device encryption where appropriate and ensure recovery information is retained.'}else{''})))
        } catch {
            $out.Add((New-RBZFinding -Category 'Security' -Name 'BitLocker' -Status 'Info' -Summary 'BitLocker status unavailable.' -Details $_.Exception.Message))
        }
    }
    return $out
}
Export-ModuleMember -Function Get-RBZSecurityFindings
