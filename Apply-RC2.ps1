$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$main=Join-Path $root 'RBZHealth.ps1'
$configPath=Join-Path $root 'Config\settings.json'

if(-not(Test-Path $main)){throw "RBZHealth.ps1 not found: $main"}
if(-not(Test-Path $configPath)){throw "settings.json not found: $configPath"}

# RC2 is cumulative: make sure version and priority config are present.
$c=Get-Content -Raw $configPath | ConvertFrom-Json
$c.app.version='0.8.0'
if(-not($c.PSObject.Properties.Name -contains 'priority')){
    $c | Add-Member -NotePropertyName priority -NotePropertyValue ([pscustomobject]@{
        enabled=$true
        topTechnicianActions=3
        includeInfoInPriorityList=$false
    })
}
$c.priority.enabled=$true
$c.priority.topTechnicianActions=3
$c.priority.includeInfoInPriorityList=$false
$c | ConvertTo-Json -Depth 20 | Set-Content $configPath -Encoding UTF8

$text=Get-Content -Raw $main

if($text -notmatch 'RBZ080RC2_PRIORITY_UI'){
    Copy-Item $main "$main.v080rc2.bak" -Force

    $priorityTab=@'
<!-- RBZ080RC2_PRIORITY_UI -->
<TabItem Header="Technician Priorities"><Grid Margin="8">
<Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

<Border Grid.ColumnSpan="2" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12" Margin="0,0,0,10">
<StackPanel>
<TextBlock Text="Top Technician Actions" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Text="Ranked from existing diagnostics. Priority does not change the underlying finding status or health score." Margin="0,4,0,0" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
</StackPanel>
</Border>

<DataGrid Grid.Row="1" Name="PriorityGrid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
          ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Auto">
<DataGrid.Columns>
<DataGridTextColumn Header="Priority" Binding="{Binding Priority}" Width="90"/>
<DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
<DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100"/>
<DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="210"/>
<DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
</DataGrid.Columns>
</DataGrid>

<Border Grid.Row="1" Grid.Column="1" Margin="12,0,0,0" Background="{DynamicResource RBZ.PanelAlt}"
        BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="14">
<ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
<TextBlock Name="PriorityDetailTitle" Text="Run a scan to generate priorities" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<TextBlock Name="PriorityDetailStatus" Margin="0,5,0,12" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Text="SUMMARY" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailSummary" Margin="0,4,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<TextBlock Text="WHY THIS PRIORITY" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailReason" Margin="0,4,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<TextBlock Text="RECOMMENDED ACTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailAction" Margin="0,4,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<Button Name="OpenPriorityFindingButton" Content="Open Finding" Width="110" Height="30" HorizontalAlignment="Left" IsEnabled="False"/>
</StackPanel></ScrollViewer>
</Border>
</Grid></TabItem>

'@

    $marker='<TabItem Header="All Results">'
    if(-not $text.Contains($marker)){throw 'RC2 patch failed: All Results tab marker not found.'}
    $text=$text.Replace($marker,$priorityTab+$marker)

    $old="'ResultsGrid','AttentionGrid','ScoreText'"
    $new="'ResultsGrid','AttentionGrid','PriorityGrid','PriorityDetailTitle','PriorityDetailStatus','PriorityDetailSummary','PriorityDetailReason','PriorityDetailAction','OpenPriorityFindingButton','ScoreText'"
    if(-not $text.Contains($old)){throw 'RC2 patch failed: UI control registration marker not found.'}
    $text=$text.Replace($old,$new)

    $detailMarker='$AttentionGrid.Add_SelectionChanged({if($AttentionGrid.SelectedItem){Show-RBZDetail $AttentionGrid.SelectedItem}})'
    $detailAddition=@'
$AttentionGrid.Add_SelectionChanged({if($AttentionGrid.SelectedItem){Show-RBZDetail $AttentionGrid.SelectedItem}})

function Show-RBZPriorityDetail($Item){
    if($null -eq $Item){return}
    $PriorityDetailTitle.Text=$Item.Name
    $PriorityDetailStatus.Text="$($Item.Priority) priority | $($Item.Category) | $($Item.Status)"
    $PriorityDetailSummary.Text=$Item.Summary
    $PriorityDetailReason.Text=$Item.Reason
    $PriorityDetailAction.Text=if([string]::IsNullOrWhiteSpace([string]$Item.Recommendation)){'Review the underlying diagnostic finding.'}else{$Item.Recommendation}
    $OpenPriorityFindingButton.IsEnabled=$true
}

function Open-RBZPriorityFinding {
    $item=$PriorityGrid.SelectedItem
    if($null -eq $item -or $null -eq $item.Finding){return}

    $target=$item.Finding
    $attentionItems=@($AttentionGrid.ItemsSource)

    $match=$attentionItems | Where-Object {
        $_.Category -eq $target.Category -and $_.Name -eq $target.Name -and $_.Status -eq $target.Status
    } | Select-Object -First 1

    if($match){
        $AttentionGrid.SelectedItem=$match
        $AttentionGrid.ScrollIntoView($match)
        $MainTabs.SelectedIndex=0
        Show-RBZDetail $match
    } else {
        $resultsItems=@($ResultsGrid.ItemsSource)
        $result=$resultsItems | Where-Object {
            $_.Category -eq $target.Category -and $_.Name -eq $target.Name -and $_.Status -eq $target.Status
        } | Select-Object -First 1

        if($result){
            $ResultsGrid.SelectedItem=$result
            $ResultsGrid.ScrollIntoView($result)
            $MainTabs.SelectedIndex=2
        }
    }
}

$PriorityGrid.Add_SelectionChanged({
    if($PriorityGrid.SelectedItem){Show-RBZPriorityDetail $PriorityGrid.SelectedItem}
})
$PriorityGrid.Add_MouseDoubleClick({Open-RBZPriorityFinding})
$OpenPriorityFindingButton.Add_Click({Open-RBZPriorityFinding})
'@
    if(-not $text.Contains($detailMarker)){throw 'RC2 patch failed: Attention selection marker not found.'}
    $text=$text.Replace($detailMarker,$detailAddition)

    $scanMarker='$AttentionGrid.ItemsSource=$attention'
    $scanAddition=@'
$AttentionGrid.ItemsSource=$attention

        $priorityTop=3
        try{$priorityTop=[int]$Config.priority.topTechnicianActions}catch{}
        if($priorityTop -lt 1){$priorityTop=3}

        $includeInfo=$false
        try{$includeInfo=[bool]$Config.priority.includeInfoInPriorityList}catch{}

        if($includeInfo){
            $priorities=@(Get-RBZPrioritizedFindings -Findings $script:Findings -Top $priorityTop -IncludeInfo)
        } else {
            $priorities=@(Get-RBZPrioritizedFindings -Findings $script:Findings -Top $priorityTop)
        }

        $PriorityGrid.ItemsSource=$priorities
        $OpenPriorityFindingButton.IsEnabled=$false

        if($priorities.Count -gt 0){
            $PriorityGrid.SelectedIndex=0
            Show-RBZPriorityDetail $PriorityGrid.SelectedItem
        } else {
            $PriorityDetailTitle.Text='No priority actions identified'
            $PriorityDetailStatus.Text='Healthy'
            $PriorityDetailSummary.Text='No Critical, Warning or Recommend findings were returned.'
            $PriorityDetailReason.Text='There are no non-informational findings requiring technician prioritisation.'
            $PriorityDetailAction.Text='No priority action required.'
        }
'@
    if(-not $text.Contains($scanMarker)){throw 'RC2 patch failed: scan priority marker not found.'}
    $text=$text.Replace($scanMarker,$scanAddition)

    Set-Content -LiteralPath $main -Value $text -Encoding UTF8
    Write-Host 'RBZ PC Health v0.8.0 RC2 UI patch applied.' -ForegroundColor Green
} else {
    Write-Host 'RBZ PC Health v0.8.0 RC2 UI patch already present.' -ForegroundColor Yellow
}

Write-Host 'Config/version verified for v0.8.0 RC2.' -ForegroundColor Green
