$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$main=Join-Path $root 'RBZHealth.ps1'
$configPath=Join-Path $root 'Config\settings.json'
$rc2=Join-Path $root 'Apply-RC2.ps1'

if(-not(Test-Path $main)){throw "RBZHealth.ps1 not found: $main"}
if(-not(Test-Path $configPath)){throw "settings.json not found: $configPath"}

# Make this package cumulative. If RC2 UI isn't present, apply RC2 first.
$initial=Get-Content -Raw $main
if($initial -notmatch 'RBZ080RC2_PRIORITY_UI'){
    if(-not(Test-Path $rc2)){throw 'RC2 prerequisite is missing from the cumulative package.'}
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $rc2
    if($LASTEXITCODE -ne 0){throw "RC2 prerequisite patch failed with exit code $LASTEXITCODE."}
}

$c=Get-Content -Raw $configPath | ConvertFrom-Json
$c.app.version='0.8.0'
if(-not($c.PSObject.Properties.Name -contains 'priority')){
    $c | Add-Member -NotePropertyName priority -NotePropertyValue ([pscustomobject]@{
        enabled=$true
        topTechnicianActions=3
        includeInfoInPriorityList=$false
    })
}
$c | ConvertTo-Json -Depth 20 | Set-Content $configPath -Encoding UTF8

$text=Get-Content -Raw $main
if($text -match 'RBZ080RC3_ACTION_MAPPING'){
    Write-Host 'RBZ PC Health v0.8.0 RC3 patch already present.' -ForegroundColor Yellow
    exit 0
}

Copy-Item $main "$main.v080rc3.bak" -Force

# Add action type to priority grid.
$gridOld='<DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>'
$gridNew=@'
<DataGridTextColumn Header="Action" Binding="{Binding ActionType}" Width="105"/>
<DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
'@
if(-not $text.Contains($gridOld)){throw 'RC3 patch failed: priority Summary column marker not found.'}
$text=$text.Replace($gridOld,$gridNew)

# Replace the RC2 recommendation block with richer action detail + buttons.
$oldDetail=@'
<TextBlock Text="RECOMMENDED ACTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailAction" Margin="0,4,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<Button Name="OpenPriorityFindingButton" Content="Open Finding" Width="110" Height="30" HorizontalAlignment="Left" IsEnabled="False"/>
'@

$newDetail=@'
<!-- RBZ080RC3_ACTION_MAPPING -->
<TextBlock Text="RECOMMENDED ACTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailAction" Margin="0,4,0,8" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<TextBlock Name="PriorityDetailGuidance" Margin="0,0,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<StackPanel Orientation="Horizontal">
<Button Name="OpenPriorityFindingButton" Content="Open Finding" Width="110" Height="30" HorizontalAlignment="Left" IsEnabled="False"/>
<Button Name="OpenPriorityRepairButton" Content="Open Repair Centre" Width="140" Height="30" Margin="8,0,0,0" HorizontalAlignment="Left" IsEnabled="False"/>
</StackPanel>
'@
if(-not $text.Contains($oldDetail)){throw 'RC3 patch failed: RC2 priority detail block not found.'}
$text=$text.Replace($oldDetail,$newDetail)

# Register new controls.
$regOld="'PriorityDetailAction','OpenPriorityFindingButton','ScoreText'"
$regNew="'PriorityDetailAction','PriorityDetailGuidance','OpenPriorityFindingButton','OpenPriorityRepairButton','ScoreText'"
if(-not $text.Contains($regOld)){throw 'RC3 patch failed: priority control registration marker not found.'}
$text=$text.Replace($regOld,$regNew)

# Enrich detail renderer.
# Use regex rather than exact text so CRLF/LF and whitespace differences do not break the patch.
$showPattern='(?ms)^\s*\$PriorityDetailAction\.Text\s*=\s*if\(\[string\]::IsNullOrWhiteSpace\(\[string\]\$Item\.Recommendation\)\)\{''Review the underlying diagnostic finding\.''\}else\{\$Item\.Recommendation\}\s*\r?\n\s*\$OpenPriorityFindingButton\.IsEnabled\s*=\s*\$true'
$showReplacement=@'
    $PriorityDetailAction.Text="$($Item.ActionName)`n$($Item.ActionText)"
    $PriorityDetailGuidance.Text=$Item.Guidance
    $OpenPriorityFindingButton.IsEnabled=$true
    $OpenPriorityRepairButton.IsEnabled=[bool]$Item.CanOpenRepairCentre
'@

if($text -notmatch $showPattern){
    # Fallback: patch the body inside Show-RBZPriorityDetail directly.
    $functionPattern='(?ms)(function\s+Show-RBZPriorityDetail\s*\(\$Item\)\s*\{.*?\$PriorityDetailSummary\.Text=\$Item\.Summary\s*\r?\n\s*\$PriorityDetailReason\.Text=\$Item\.Reason\s*\r?\n)(.*?)(\r?\n\})'
    if($text -notmatch $functionPattern){
        throw 'RC3 patch failed: Show-RBZPriorityDetail function could not be located.'
    }

    $replacementBody=@'
    $PriorityDetailAction.Text="$($Item.ActionName)`n$($Item.ActionText)"
    $PriorityDetailGuidance.Text=$Item.Guidance
    $OpenPriorityFindingButton.IsEnabled=$true
    $OpenPriorityRepairButton.IsEnabled=[bool]$Item.CanOpenRepairCentre
'@

    $text=[regex]::Replace(
        $text,
        $functionPattern,
        ('$1' + $replacementBody + '$3'),
        1
    )
}
else{
    $text=[regex]::Replace($text,$showPattern,$showReplacement,1)
}

# Add safe Repair Centre navigation. It highlights the matching action but does
# NOT tick Selected and does NOT run anything.
$buttonMarker='$OpenPriorityFindingButton.Add_Click({Open-RBZPriorityFinding})'
$buttonAddition=@'
$OpenPriorityFindingButton.Add_Click({Open-RBZPriorityFinding})

function Open-RBZPriorityRepairAction {
    $item=$PriorityGrid.SelectedItem
    if($null -eq $item -or -not [bool]$item.CanOpenRepairCentre -or [string]::IsNullOrWhiteSpace([string]$item.ActionId)){return}

    $match=@($script:Actions | Where-Object Id -eq $item.ActionId | Select-Object -First 1)
    if($match.Count -eq 0){
        [System.Windows.MessageBox]::Show(
            "The recommended Repair Centre action '$($item.ActionName)' is not available in this configuration.",
            'RBZ PC Health'
        )|Out-Null
        return
    }

    # Attention=0, Technician Priorities=1, All Results=2,
    # Before/After=3, Repair Centre=4.
    $MainTabs.SelectedIndex=4
    $ActionGrid.SelectedItem=$match[0]
    $ActionGrid.ScrollIntoView($match[0])
    $ActionStatusText.Text="Recommended action highlighted: $($match[0].Name). Review it before selecting Run."
}
$OpenPriorityRepairButton.Add_Click({Open-RBZPriorityRepairAction})
'@
if(-not $text.Contains($buttonMarker)){throw 'RC3 patch failed: Open Finding button marker not found.'}
$text=$text.Replace($buttonMarker,$buttonAddition)

# Ensure no-priority state disables/clears RC3 controls.
$emptyMarker="$PriorityDetailAction.Text='No priority action required.'"
$emptyNew=@'
$PriorityDetailAction.Text='No priority action required.'
            $PriorityDetailGuidance.Text=''
            $OpenPriorityRepairButton.IsEnabled=$false
'@
if($text.Contains($emptyMarker)){$text=$text.Replace($emptyMarker,$emptyNew)}

Set-Content -LiteralPath $main -Value $text -Encoding UTF8
Write-Host 'RBZ PC Health v0.8.0 RC3 smarter recommended actions applied.' -ForegroundColor Green
Write-Host 'Repair Centre links only navigate/highlight; they never select or run an action automatically.' -ForegroundColor Green
