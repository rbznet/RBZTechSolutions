$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'

if(-not(Test-Path -LiteralPath $mainPath)){
    throw "Required file not found: $mainPath"
}

$main=Get-Content -LiteralPath $mainPath -Raw

if($main -match 'RBZ080RC12_BOOT_AWARE_REPAIR_STATE'){
    Write-Host 'RBZ PC Health v0.8.0 RC12 is already applied.' -ForegroundColor Yellow
    exit 0
}

$required=@(
    'RBZ080RC10_PERSISTENT_REPAIR_STATE',
    'function Save-RBZPendingRepairState',
    'function Get-RBZPendingRepairState',
    '$script:PendingRepairState=Get-RBZPendingRepairState',
    '$ScanButton.Content=''Verify Repairs''',
    'if([bool]$r.RequiresRestart)'
)

foreach($fragment in $required){
    if(-not $main.Contains($fragment)){
        throw "RC12 baseline validation failed. Missing expected RC11/RC10c capability: $fragment"
    }
}

$bootHelpers=@'
# RBZ080RC12_BOOT_AWARE_REPAIR_STATE
function Get-RBZCurrentBootTime {
    try{
        $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if($os.LastBootUpTime){
            return ([datetime]$os.LastBootUpTime)
        }
    }catch{}

    try{
        $os=Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        if($os.LastBootUpTime){
            return ([Management.ManagementDateTimeConverter]::ToDateTime([string]$os.LastBootUpTime))
        }
    }catch{}

    return $null
}

function Test-RBZRestartOccurred {
    param([Parameter(Mandatory)]$State)

    if(-not($State.PSObject.Properties.Name -contains 'BootTimeAtRepair')){
        return $null
    }

    if([string]::IsNullOrWhiteSpace([string]$State.BootTimeAtRepair)){
        return $null
    }

    try{
        $bootAtRepair=[datetime]$State.BootTimeAtRepair
        $currentBoot=Get-RBZCurrentBootTime
        if(-not $currentBoot){return $null}

        return ($currentBoot -gt $bootAtRepair.AddSeconds(2))
    }catch{
        return $null
    }
}

'@

$saveAnchor='(?m)^function Save-RBZPendingRepairState \{'
if(-not [regex]::IsMatch($main,$saveAnchor)){
    throw 'RC12 could not locate Save-RBZPendingRepairState.'
}
$main=[regex]::Replace($main,$saveAnchor,($bootHelpers + 'function Save-RBZPendingRepairState {'),1)

$schemaPattern='(?m)^(\s*)SchemaVersion=1\s*$'
if(-not [regex]::IsMatch($main,$schemaPattern)){
    throw 'RC12 could not locate SchemaVersion=1 in the pending repair payload.'
}
$main=[regex]::Replace($main,$schemaPattern,'$1SchemaVersion=2',1)

$payloadAnchor='(?m)^(\s*)\$payload=\[ordered\]@\{'
if(-not [regex]::IsMatch($main,$payloadAnchor)){
    throw 'RC12 could not locate pending repair payload creation.'
}
$payloadPrep=@'
        $bootTimeAtRepair=Get-RBZCurrentBootTime

        $payload=[ordered]@{
'@
$main=[regex]::Replace($main,$payloadAnchor,$payloadPrep.TrimEnd(),1)

$performedPattern='(?m)^(\s*)PerformedAt=\(Get-Date\)\.ToString\(''o''\)\s*$'
if(-not [regex]::IsMatch($main,$performedPattern)){
    throw 'RC12 could not locate PerformedAt in the pending repair payload.'
}
$performedReplacement=@'
$1PerformedAt=(Get-Date).ToString('o')
$1BootTimeAtRepair=if($bootTimeAtRepair){$bootTimeAtRepair.ToString('o')}else{$null}
'@
$main=[regex]::Replace($main,$performedPattern,$performedReplacement.TrimEnd(),1)

$postActionPattern='(?s)\s*\$ActionGrid\.Items\.Refresh\(\)\s*\r?\n\s*\$script:RepairVerificationPending=\$true\s*\r?\n\s*\$ScanButton\.Content=''Verify Repairs''\s*\r?\n\s*\$ActionStatusText\.Text=''Selected actions completed\. Verification required: run a Full Scan to confirm whether the original diagnostic finding changed\.''\s*\r?\n\s*\$StatusText\.Text=''Service actions completed\. Verification is pending; use Verify Repairs\.'''
if(-not [regex]::IsMatch($main,$postActionPattern)){
    throw 'RC12 could not locate the post-action verification UI block.'
}

$postActionReplacement=@'

        $ActionGrid.Items.Refresh()

        if($script:RestartRequired){
            $script:RepairVerificationPending=$false
            $ScanButton.Content='Restart Required'
            $ScanButton.IsEnabled=$false
            $ActionStatusText.Text='Selected actions completed. Restart Windows before verification can run.'
            $StatusText.Text='Service actions completed. Restart Windows to complete the repair; verification will be available after reboot.'
        }else{
            $script:RepairVerificationPending=$true
            $ScanButton.Content='Verify Repairs'
            $ActionStatusText.Text='Selected actions completed. Verification required: run a Full Scan to confirm whether the original diagnostic finding changed.'
            $StatusText.Text='Service actions completed. Verification is pending; use Verify Repairs.'
        }
'@
$main=[regex]::Replace($main,$postActionPattern,$postActionReplacement,1)

$finallyPattern='(?s)(\$RunActionsButton\.IsEnabled=\$true\s*\r?\n)\s*\$ScanButton\.IsEnabled=\$true(\s*\r?\n\s*\}\s*\r?\n\}\))'
if(-not [regex]::IsMatch($main,$finallyPattern)){
    throw 'RC12 could not locate the Repair Centre finally block.'
}
$finallyReplacement=@'
$1        if($script:RestartRequired){
            $ScanButton.IsEnabled=$false
        }else{
            $ScanButton.IsEnabled=$true
        }$2
'@
$main=[regex]::Replace($main,$finallyPattern,$finallyReplacement.TrimEnd(),1)

$startupPattern='(?s)\$script:PendingRepairState=Get-RBZPendingRepairState\s*\r?\nif\(\$script:PendingRepairState\)\{.*?\r?\n\}\s*\r?\n\$window\.ShowDialog\(\)\|Out-Null'
if(-not [regex]::IsMatch($main,$startupPattern)){
    throw 'RC12 could not locate the launch-time pending repair recovery block.'
}

$startupReplacement=@'
$script:PendingRepairState=Get-RBZPendingRepairState
if($script:PendingRepairState){
    $performed=[string]$script:PendingRepairState.PerformedAt
    try{
        $performed=([datetime]$script:PendingRepairState.PerformedAt).ToString('dd MMM yyyy HH:mm')
    }catch{}

    $restartOccurred=Test-RBZRestartOccurred -State $script:PendingRepairState

    if($restartOccurred -eq $false){
        $script:RepairVerificationPending=$false
        $script:RestartRequired=$true
        $ScanButton.Content='Restart Required'
        $ScanButton.IsEnabled=$false

        $RestartRequiredText.Text="Restart still required: $($script:PendingRepairState.ActionName) was performed $performed. Restart Windows before running verification."
        $RestartRequiredBanner.Visibility='Visible'
        $ActionStatusText.Text="Restart required to complete: $($script:PendingRepairState.ActionName)."
        $StatusText.Text='Pending repair detected on the same Windows boot. Restart Windows before verification.'
    }else{
        $script:RepairVerificationPending=$true
        $script:RestartRequired=$false
        $ScanButton.Content='Verify Repairs'
        $ScanButton.IsEnabled=$true

        if($restartOccurred -eq $true){
            $RestartRequiredText.Text="Restart completed: $($script:PendingRepairState.ActionName) was performed $performed. Run Verify Repairs."
            $ActionStatusText.Text="Post-restart verification ready: $($script:PendingRepairState.ActionName)."
            $StatusText.Text='Windows restart detected. Pending repair is ready for verification.'
        }else{
            $RestartRequiredText.Text="Pending repair verification: $($script:PendingRepairState.ActionName) was performed $performed. Boot-time metadata is unavailable; run Verify Repairs."
            $ActionStatusText.Text="Previous restart-required repair detected: $($script:PendingRepairState.ActionName). Run Verify Repairs."
            $StatusText.Text='Legacy pending repair state detected. Verification is available.'
        }

        $RestartRequiredBanner.Visibility='Visible'
    }
}
$window.ShowDialog()|Out-Null
'@

$main=[regex]::Replace($main,$startupPattern,$startupReplacement,1)

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $mainPath,[ref]$tokens,[ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $message=($errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"
    throw "RBZHealth.ps1 parser check failed after RC12:`n$message"
}

Write-Host 'RBZ PC Health v0.8.0 RC12 applied.' -ForegroundColor Green
Write-Host 'Restart-required repairs now record the Windows boot time.' -ForegroundColor Cyan
Write-Host 'Verify Repairs is blocked until a later Windows boot is detected.' -ForegroundColor Cyan
Write-Host 'RBZHealth.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
