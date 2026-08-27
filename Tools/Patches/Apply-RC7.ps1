$ErrorActionPreference='Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath = Join-Path $repoRoot 'RBZHealth.ps1'
$reportPath = Join-Path $repoRoot 'Modules\Report.psm1'

if(-not(Test-Path $mainPath)){ throw "RBZHealth.ps1 not found: $mainPath" }
if(-not(Test-Path $reportPath)){ throw "Report.psm1 not found: $reportPath" }

$main = Get-Content -Raw $mainPath
$report = Get-Content -Raw $reportPath

if($main -match 'RBZ080RC7_SERVICE_COMPLETION'){
    Write-Host 'RBZ PC Health v0.8.0 RC7 is already applied.' -ForegroundColor Yellow
    exit 0
}
if($main -notmatch 'RBZ080RC6_SERVICE_NOTES'){
    throw 'RC7 requires the committed RC6 Service Record baseline.'
}

# -------------------------------------------------------------------------
# Add service-completion/sign-off controls to the RC6 Service Record.
# -------------------------------------------------------------------------
$old = @'
<Border Grid.Row="4" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12"><StackPanel>
<CheckBox Name="IncludeServiceSummaryCustomerCheck" Content="Include customer-safe service summary in Customer Report" IsChecked="True"/>
<TextBlock Text="Technician Notes are never included in the Customer Report." Margin="22,5,0,0" FontSize="11" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel></Border>
<StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,12,0,0"><Button Name="ClearServiceRecordButton" Content="Clear Service Record" Width="145" Height="32"/><TextBlock Name="ServiceRecordStatusText" Text="Service record is session-only until a report is generated." Margin="12,8,0,0" Foreground="{DynamicResource RBZ.Text}"/></StackPanel>
'@

$new = @'
<!-- RBZ080RC7_SERVICE_COMPLETION -->
<Border Grid.Row="4" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12">
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Grid Grid.Row="0">
<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,8,0">
<TextBlock Text="TECHNICIAN" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBox Name="ServiceTechnicianBox" Height="30" Margin="0,5,0,0" Padding="7,4"/>
</StackPanel>
<StackPanel Grid.Column="1" Margin="8,0">
<TextBlock Text="FINAL SERVICE STATUS" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<ComboBox Name="ServiceStatusBox" Height="30" Margin="0,5,0,0" SelectedIndex="0">
<ComboBoxItem Content="Further Work Required"/>
<ComboBoxItem Content="Resolved"/>
<ComboBoxItem Content="Improved"/>
<ComboBoxItem Content="No Fault Found"/>
</ComboBox>
</StackPanel>
<StackPanel Grid.Column="2" Margin="8,0,0,0">
<TextBlock Text="COMPLETION DATE / TIME" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBox Name="ServiceCompletedBox" Height="30" Margin="0,5,0,0" Padding="7,4" IsReadOnly="True"/>
</StackPanel>
</Grid>
<StackPanel Grid.Row="1" Margin="0,12,0,0">
<CheckBox Name="IncludeServiceSummaryCustomerCheck" Content="Include customer-safe service summary in Customer Report" IsChecked="True"/>
<TextBlock Text="Technician Notes and technician identity are never included in the Customer Report." Margin="22,5,0,0" FontSize="11" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel>
</Grid>
</Border>
<StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,12,0,0">
<Button Name="CompleteServiceButton" Content="Complete Service" Width="125" Height="32" Margin="0,0,8,0"/>
<Button Name="ClearServiceRecordButton" Content="Clear Service Record" Width="145" Height="32"/>
<TextBlock Name="ServiceRecordStatusText" Text="Service record is session-only until a report is generated." Margin="12,8,0,0" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel>
'@

if(-not $main.Contains($old)){ throw 'RC7: expected RC6 service-record controls were not found.' }
$main = $main.Replace($old,$new)

# Register new UI controls.
$old = "'CustomerComplaintBox','TechnicianNotesBox','WorkPerformedBox','ServiceOutcomeBox','FurtherRecommendationsBox','IncludeServiceSummaryCustomerCheck','ClearServiceRecordButton','ServiceRecordStatusText'"
$new = "'CustomerComplaintBox','TechnicianNotesBox','WorkPerformedBox','ServiceOutcomeBox','FurtherRecommendationsBox','ServiceTechnicianBox','ServiceStatusBox','ServiceCompletedBox','IncludeServiceSummaryCustomerCheck','CompleteServiceButton','ClearServiceRecordButton','ServiceRecordStatusText'"
if(-not $main.Contains($old)){ throw 'RC7: RC6 control registration marker not found.' }
$main = $main.Replace($old,$new)

# Add default technician and Complete Service behaviour.
$marker = '$ClearServiceRecordButton.Add_Click({'
$logic = @'
$ServiceTechnicianBox.Text=[Environment]::UserName
$ServiceCompletedBox.Text=''

$CompleteServiceButton.Add_Click({
    if([string]::IsNullOrWhiteSpace([string]$ServiceTechnicianBox.Text)){
        [System.Windows.MessageBox]::Show(
            'Enter the technician name before completing the service.',
            'RBZ PC Health - Service Record',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )|Out-Null
        return
    }

    $ServiceCompletedBox.Text=(Get-Date).ToString('dd MMM yyyy HH:mm')
    $selected=$ServiceStatusBox.SelectedItem
    $finalStatus=if($selected -and $selected.Content){[string]$selected.Content}else{'Further Work Required'}

    $ServiceRecordStatusText.Text="Service completed: $finalStatus | $($ServiceCompletedBox.Text)"
    $StatusText.Text="Service record completed: $finalStatus"
})

'@
if(-not $main.Contains($marker)){ throw 'RC7: RC6 clear-service handler marker not found.' }
$main = $main.Replace($marker,$logic+$marker)

# Clear/reset the sign-off fields too.
$old = '$CustomerComplaintBox.Clear();$TechnicianNotesBox.Clear();$WorkPerformedBox.Clear();$ServiceOutcomeBox.Clear();$FurtherRecommendationsBox.Clear()'
$new = '$CustomerComplaintBox.Clear();$TechnicianNotesBox.Clear();$WorkPerformedBox.Clear();$ServiceOutcomeBox.Clear();$FurtherRecommendationsBox.Clear();$ServiceTechnicianBox.Text=[Environment]::UserName;$ServiceStatusBox.SelectedIndex=0;$ServiceCompletedBox.Clear()'
if(-not $main.Contains($old)){ throw 'RC7: RC6 clear-fields marker not found.' }
$main = $main.Replace($old,$new)

# Persist completion metadata in ServiceNotes.
$old = @'
        FurtherRecommendations=[string]$FurtherRecommendationsBox.Text
        IncludeInCustomerReport=[bool]$IncludeServiceSummaryCustomerCheck.IsChecked
'@
$new = @'
        FurtherRecommendations=[string]$FurtherRecommendationsBox.Text
        Technician=[string]$ServiceTechnicianBox.Text
        FinalStatus=if($ServiceStatusBox.SelectedItem){[string]$ServiceStatusBox.SelectedItem.Content}else{'Further Work Required'}
        Completed=[string]$ServiceCompletedBox.Text
        IncludeInCustomerReport=[bool]$IncludeServiceSummaryCustomerCheck.IsChecked
'@
if(-not $main.Contains($old)){ throw 'RC7: ServiceNotes object marker not found.' }
$main = $main.Replace($old,$new)

# -------------------------------------------------------------------------
# Report output.
# Technician report: identity + status + completion.
# Customer report: status + completion only.
# -------------------------------------------------------------------------
$old = @'
        $further=& $enc ([string]$ServiceNotes.FurtherRecommendations)
        $blocks=[System.Collections.Generic.List[string]]::new()
        if($Audience -eq 'Technician'){
'@
$new = @'
        $further=& $enc ([string]$ServiceNotes.FurtherRecommendations)
        $technician=& $enc ([string]$ServiceNotes.Technician)
        $finalStatus=& $enc ([string]$ServiceNotes.FinalStatus)
        $completed=& $enc ([string]$ServiceNotes.Completed)
        $blocks=[System.Collections.Generic.List[string]]::new()
        if($Audience -eq 'Technician'){
            if($technician){$blocks.Add("<div class='serviceNote'><h3>Technician</h3><div>$technician</div></div>")}
            if($finalStatus){$blocks.Add("<div class='serviceNote'><h3>Final Service Status</h3><div>$finalStatus</div></div>")}
            if($completed){$blocks.Add("<div class='serviceNote'><h3>Completed</h3><div>$completed</div></div>")}
'@
if(-not $report.Contains($old)){ throw 'RC7: RC6 Technician Service Record report marker not found.' }
$report = $report.Replace($old,$new)

$old = @'
        }elseif([bool]$ServiceNotes.IncludeInCustomerReport){
            if($complaint){$blocks.Add("<div class='serviceNote'><h3>Reason for Service</h3><div>$complaint</div></div>")}
'@
$new = @'
        }elseif([bool]$ServiceNotes.IncludeInCustomerReport){
            if($finalStatus){$blocks.Add("<div class='serviceNote'><h3>Service Status</h3><div>$finalStatus</div></div>")}
            if($completed){$blocks.Add("<div class='serviceNote'><h3>Completed</h3><div>$completed</div></div>")}
            if($complaint){$blocks.Add("<div class='serviceNote'><h3>Reason for Service</h3><div>$complaint</div></div>")}
'@
if(-not $report.Contains($old)){ throw 'RC7: RC6 Customer Service Summary report marker not found.' }
$report = $report.Replace($old,$new)

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8
Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC7 service-completion patch applied.' -ForegroundColor Green
Write-Host 'Test Service Record plus both reports before committing.' -ForegroundColor Cyan
