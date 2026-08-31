$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
if(-not(Test-Path -LiteralPath $mainPath)){throw "Required file not found: $mainPath"}

$main=Get-Content -LiteralPath $mainPath -Raw

if($main -match 'RBZ080RC10_PERSISTENT_REPAIR_STATE'){
    Write-Host 'RBZ PC Health v0.8.0 RC10c is already applied.' -ForegroundColor Yellow
    exit 0
}

# Broad RC9e capability validation only.
$required=@(
    '$script:RestartRequired=$false',
    'RestartRequiredBanner',
    'if([bool]$r.RequiresRestart)',
    '$script:RepairVerificationPending=$false',
    "ScanButton.Content='Verify Repairs'"
)
foreach($fragment in $required){
    if(-not $main.Contains($fragment)){
        throw "RC10c baseline validation failed. Missing expected RC9e capability: $fragment"
    }
}

# --------------------------------------------------------------------------
# 1. Persistent state helpers
# Insert immediately after the ThemeStatePath assignment.
# --------------------------------------------------------------------------
$stateHelpers=@'

# RBZ080RC10_PERSISTENT_REPAIR_STATE
$script:RepairStateRoot=Join-Path $env:ProgramData 'RBZ Tech Solutions\RBZ PC Health'
$script:RepairStatePath=Join-Path $script:RepairStateRoot 'pending-repair.json'
$script:PendingRepairState=$null

function Save-RBZPendingRepairState {
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)]$Result
    )

    try{
        if(-not(Test-Path -LiteralPath $script:RepairStateRoot)){
            New-Item -ItemType Directory -Path $script:RepairStateRoot -Force | Out-Null
        }

        $payload=[ordered]@{
            SchemaVersion=1
            Pending=$true
            ComputerName=[string]$env:COMPUTERNAME
            ActionId=[string]$Action.Id
            ActionName=[string]$Action.Name
            Category=[string]$Action.Category
            PerformedAt=(Get-Date).ToString('o')
            RequiresRestart=[bool]$Result.RequiresRestart
            Summary=[string]$Result.Summary
            VerificationCategory=[string]$Result.VerificationCategory
            VerificationCheck=[string]$Result.VerificationCheck
            VerificationStatus=[string]$Result.VerificationStatus
            VerificationSummary=[string]$Result.VerificationSummary
        }

        $payload |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $script:RepairStatePath -Encoding UTF8 -Force

        $script:PendingRepairState=[pscustomobject]$payload
        return $true
    }
    catch{
        return $false
    }
}

function Get-RBZPendingRepairState {
    try{
        if(-not(Test-Path -LiteralPath $script:RepairStatePath)){return $null}

        $state=Get-Content -LiteralPath $script:RepairStatePath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if(-not [bool]$state.Pending){return $null}
        if([string]$state.ComputerName -ne [string]$env:COMPUTERNAME){return $null}
        return $state
    }
    catch{
        return $null
    }
}

function Clear-RBZPendingRepairState {
    try{
        Remove-Item -LiteralPath $script:RepairStatePath -Force -ErrorAction SilentlyContinue
    }catch{}
    $script:PendingRepairState=$null
}
'@

$themePattern='(?m)^(\$script:ThemeStatePath=.*)$'
if(-not [regex]::IsMatch($main,$themePattern)){
    throw 'RC10c could not locate ThemeStatePath insertion point.'
}
$main=[regex]::Replace(
    $main,
    $themePattern,
    { param($m) $m.Groups[1].Value + $stateHelpers },
    1
)

# --------------------------------------------------------------------------
# 2. Save state whenever a repair requires restart.
# Find the existing restart banner block and append persistence logic.
# --------------------------------------------------------------------------
$restartPattern='(?ms)(\s*if\(\[bool\]\$r\.RequiresRestart\)\{\s*\$script:RestartRequired=\$true\s*\$RestartRequiredText\.Text="Restart required to complete: \$\(\$a\.Name\)\. Restart Windows, then run Verify Repairs\."\s*\$RestartRequiredBanner\.Visibility=''Visible''\s*)(\})'

if(-not [regex]::IsMatch($main,$restartPattern)){
    throw 'RC10c could not locate the restart-required action block.'
}

$main=[regex]::Replace(
    $main,
    $restartPattern,
    {
        param($m)
        $m.Groups[1].Value + @'
                if(Save-RBZPendingRepairState -Action $a -Result $r){
                    $ActionLogBox.AppendText(
                        "Pending repair verification saved for next launch.`r`n" +
                        "State file: $script:RepairStatePath`r`n`r`n"
                    )
                }else{
                    $ActionLogBox.AppendText(
                        "WARNING: Pending repair state could not be saved for post-restart verification.`r`n`r`n"
                    )
                }
'@ + $m.Groups[2].Value
    },
    1
)

# --------------------------------------------------------------------------
# 3. Clear persistent state after a verification scan completes.
# Insert after RepairContextAction is cleared.
# --------------------------------------------------------------------------
$verifyPattern='(?m)^(\s*\$script:RepairContextAction=\$null\s*)$'
$verifyMatches=[regex]::Matches($main,$verifyPattern)
if($verifyMatches.Count -lt 1){
    throw 'RC10c could not locate the verification completion insertion point.'
}

# Use the last occurrence: it is inside the Verify Repairs completion branch.
$last=$verifyMatches[$verifyMatches.Count-1]
$verifyInsert=@'

            if($script:PendingRepairState){
                Clear-RBZPendingRepairState
                $script:RestartRequired=$false
                $RestartRequiredBanner.Visibility='Collapsed'
                $ActionStatusText.Text='Post-restart repair verification completed. Pending repair state cleared.'
            }
'@
$main=$main.Substring(0,$last.Index+$last.Length) + $verifyInsert + $main.Substring($last.Index+$last.Length)

# --------------------------------------------------------------------------
# 4. Load pending state before the WPF window is shown.
# --------------------------------------------------------------------------
$startup=@'
$script:PendingRepairState=Get-RBZPendingRepairState
if($script:PendingRepairState){
    $script:RepairVerificationPending=$true
    $script:RestartRequired=$true
    $ScanButton.Content='Verify Repairs'

    $performed=[string]$script:PendingRepairState.PerformedAt
    try{
        $performed=([datetime]$script:PendingRepairState.PerformedAt).ToString('dd MMM yyyy HH:mm')
    }catch{}

    $RestartRequiredText.Text="Pending repair verification: $($script:PendingRepairState.ActionName) was performed $performed. Run Verify Repairs."
    $RestartRequiredBanner.Visibility='Visible'
    $ActionStatusText.Text="Previous restart-required repair detected: $($script:PendingRepairState.ActionName). Run Verify Repairs."
    $StatusText.Text='Pending post-restart repair verification detected.'
}

'@

$showPattern='(?m)^\$window\.ShowDialog\(\)\|Out-Null\s*$'
if(-not [regex]::IsMatch($main,$showPattern)){
    throw 'RC10c could not locate ShowDialog startup insertion point.'
}
$main=[regex]::Replace(
    $main,
    $showPattern,
    { param($m) $startup + $m.Value },
    1
)

# --------------------------------------------------------------------------
# Write and parser-check.
# --------------------------------------------------------------------------
Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    $mainPath,[ref]$tokens,[ref]$errors
) | Out-Null

if($errors.Count -gt 0){
    $msg=($errors | ForEach-Object {"Line $($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"
    throw "RBZHealth.ps1 parser check failed after RC10c:`n$msg"
}

Write-Host 'RBZ PC Health v0.8.0 RC10c applied.' -ForegroundColor Green
Write-Host 'Persistent post-restart repair verification has been added.' -ForegroundColor Cyan
Write-Host "State file: $env:ProgramData\RBZ Tech Solutions\RBZ PC Health\pending-repair.json" -ForegroundColor DarkGray
Write-Host 'RBZHealth.ps1 passed the PowerShell parser check.' -ForegroundColor Cyan
