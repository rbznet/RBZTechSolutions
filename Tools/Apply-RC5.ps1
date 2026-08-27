$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$appPath=Join-Path $repoRoot 'RBZHealth.ps1'

if(-not(Test-Path $appPath)){throw "RBZHealth.ps1 not found: $appPath"}

$text=Get-Content -Raw $appPath
if($text -match 'RBZ080RC5_REPAIR_WORKFLOW'){
    Write-Host 'RBZ PC Health v0.8.0 RC5 already applied.' -ForegroundColor Yellow
    exit 0
}

# Work against a candidate file and only replace RBZHealth.ps1 after parsing.
$original=$text

# 1) Add repair-verification session state beside the existing service state.
$stateMarker='$script:ServiceVerificationRows=[System.Collections.Generic.List[object]]::new()'
$stateReplacement=@'
$script:ServiceVerificationRows=[System.Collections.Generic.List[object]]::new()
# RBZ080RC5_REPAIR_WORKFLOW
$script:RepairVerificationPending=$false
$script:RepairContextFinding=$null
$script:RepairContextAction=$null
'@
if(-not $text.Contains($stateMarker)){throw 'RC5: service state marker not found.'}
$text=$text.Replace($stateMarker,$stateReplacement)

# 2) Improve priority -> Repair Centre hand-off.
$oldOpenStatus='$ActionStatusText.Text="Recommended action highlighted: $($match[0].Name). Review it before selecting Run."'
$newOpenStatus=@'
    $script:RepairContextFinding=$item
    $script:RepairContextAction=$match[0]
    $ActionStatusText.Text="Recommended for: $($item.Category) - $($item.Name) | Highlighted: $($match[0].Name) | Risk: $($match[0].Risk). Nothing has been selected or run. Review the description, tick Run only if appropriate, then confirm."
'@
if(-not $text.Contains($oldOpenStatus)){throw 'RC5: priority Repair Centre status marker not found.'}
$text=$text.Replace($oldOpenStatus,$newOpenStatus)

# 3) Make the confirmation dialog carry the originating diagnostic context.
$confirmMarker='$names=($selected.Name -join "`n- ")'
$confirmReplacement=@'
    $names=($selected.Name -join "`n- ")
    $contextText=''
    if($script:RepairContextFinding){
        $contextText="`n`nDiagnostic context:`n$($script:RepairContextFinding.Category) - $($script:RepairContextFinding.Name)`n$($script:RepairContextFinding.Summary)"
    }
'@
if(-not $text.Contains($confirmMarker)){throw 'RC5: action confirmation marker not found.'}
$text=$text.Replace($confirmMarker,$confirmReplacement)

$oldConfirm='$confirm=[System.Windows.MessageBox]::Show("Run these selected actions?`n`n- $names`n`nOnly explicitly selected actions will run.",''RBZ PC Health - Confirm'',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)'
$newConfirm='$confirm=[System.Windows.MessageBox]::Show("Run these selected actions?`n`n- $names$contextText`n`nOnly explicitly selected actions will run. A verification scan will still be required afterwards.",''RBZ PC Health - Confirm'',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)'
if(-not $text.Contains($oldConfirm)){throw 'RC5: confirmation dialog marker not found.'}
$text=$text.Replace($oldConfirm,$newConfirm)

# 4) After service actions complete, turn the main scan button into an obvious
# verification step. This does NOT run a scan automatically.
$oldComplete=@'
        $ActionGrid.Items.Refresh()
        $ActionStatusText.Text='Selected actions completed. Run a new scan to verify diagnostic findings.'
        $StatusText.Text='Service actions completed. Repair verification is shown in Before / After; full re-scan still recommended.'
'@
$newComplete=@'
        $ActionGrid.Items.Refresh()
        $script:RepairVerificationPending=$true
        $ScanButton.Content='Verify Repairs - Run Full Scan'
        $ActionStatusText.Text='Selected actions completed. Verification required: run a Full Scan to confirm whether the original diagnostic finding changed.'
        $StatusText.Text='Service actions completed. Verification is pending; use Verify Repairs - Run Full Scan.'
'@
if(-not $text.Contains($oldComplete)){throw 'RC5: service completion marker not found.'}
$text=$text.Replace($oldComplete,$newComplete)

# 5) Capture whether the next scan is a verification scan.
$scanStart=@'
$ScanButton.Add_Click({
    try{
        $scanStarted=Get-Date
'@
$scanStartNew=@'
$ScanButton.Add_Click({
    try{
        $scanStarted=Get-Date
        $isRepairVerification=[bool]$script:RepairVerificationPending
'@
if(-not $text.Contains($scanStart)){throw 'RC5: scan-start marker not found.'}
$text=$text.Replace($scanStart,$scanStartNew)

# 6) On successful verification scan, clear the pending state and return the
# button to its normal label.
$scanComplete='$StatusText.Text="Scan complete: $($script:Findings.Count) checks."'
$scanCompleteNew=@'
        if($isRepairVerification){
            $script:RepairVerificationPending=$false
            $ScanButton.Content='Run Full Scan'
            $ActionStatusText.Text='Verification scan completed. Review Technician Priorities and Before / After to confirm the repair outcome.'
            $StatusText.Text="Verification scan complete: $($script:Findings.Count) checks. Review Before / After and Technician Priorities."
            $script:RepairContextFinding=$null
            $script:RepairContextAction=$null
        }else{
            $StatusText.Text="Scan complete: $($script:Findings.Count) checks."
        }
'@
if(-not $text.Contains($scanComplete)){throw 'RC5: scan-complete marker not found.'}
$text=$text.Replace($scanComplete,$scanCompleteNew)

$temp="$appPath.rc5.tmp"
Set-Content -LiteralPath $temp -Value $text -Encoding UTF8

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count -gt 0){
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    $message=($errors|ForEach-Object{"Line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
    throw "RC5 aborted. RBZHealth.ps1 was NOT changed because the candidate failed parsing:`n$message"
}

$backup="$appPath.v080rc5.bak"
Copy-Item $appPath $backup -Force
Move-Item $temp $appPath -Force

Write-Host 'RBZ PC Health v0.8.0 RC5 Repair Centre workflow integration applied.' -ForegroundColor Green
Write-Host 'Candidate syntax check passed before RBZHealth.ps1 was replaced.' -ForegroundColor Green
Write-Host 'Test priority -> Repair Centre -> selected action -> verification scan.' -ForegroundColor Green
