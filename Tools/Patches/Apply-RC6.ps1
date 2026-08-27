$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
$reportPath=Join-Path $repoRoot 'Modules\Report.psm1'
if(-not(Test-Path $mainPath)){throw "RBZHealth.ps1 not found: $mainPath"}
if(-not(Test-Path $reportPath)){throw "Report.psm1 not found: $reportPath"}

$main=Get-Content -Raw $mainPath
$report=Get-Content -Raw $reportPath
if($main -match 'RBZ080RC6_SERVICE_NOTES'){Write-Host 'RC6 already applied.' -ForegroundColor Yellow;exit 0}

$tabMarker='<TabItem Header="Repair Centre"><Grid Margin="10"><Grid.RowDefinitions>'
$serviceTab=@'
<!-- RBZ080RC6_SERVICE_NOTES -->
<TabItem Header="Service Record"><ScrollViewer VerticalScrollBarVisibility="Auto"><Grid Margin="12">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Border Grid.Row="0" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="14" Margin="0,0,0,12"><StackPanel>
<TextBlock Text="Technician Service Record" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Text="Record the customer's issue, work carried out and final service outcome. Notes stay with this session and are included in reports as appropriate." Margin="0,4,0,0" TextWrapping="Wrap" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel></Border>
<Grid Grid.Row="1" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,6,0"><TextBlock Text="CUSTOMER COMPLAINT / ISSUE DESCRIPTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="CustomerComplaintBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<StackPanel Grid.Column="1" Margin="6,0,0,0"><TextBlock Text="TECHNICIAN NOTES" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="TechnicianNotesBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
</Grid>
<Grid Grid.Row="2" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,6,0"><TextBlock Text="WORK PERFORMED" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="WorkPerformedBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<StackPanel Grid.Column="1" Margin="6,0,0,0"><TextBlock Text="SERVICE OUTCOME" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="ServiceOutcomeBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
</Grid>
<StackPanel Grid.Row="3" Margin="0,0,0,12"><TextBlock Text="FURTHER RECOMMENDATIONS / CUSTOMER ADVICE" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="FurtherRecommendationsBox" Height="90" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<Border Grid.Row="4" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12"><StackPanel>
<CheckBox Name="IncludeServiceSummaryCustomerCheck" Content="Include customer-safe service summary in Customer Report" IsChecked="True"/>
<TextBlock Text="Technician Notes are never included in the Customer Report." Margin="22,5,0,0" FontSize="11" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel></Border>
<StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,12,0,0"><Button Name="ClearServiceRecordButton" Content="Clear Service Record" Width="145" Height="32"/><TextBlock Name="ServiceRecordStatusText" Text="Service record is session-only until a report is generated." Margin="12,8,0,0" Foreground="{DynamicResource RBZ.Text}"/></StackPanel>
</Grid></ScrollViewer></TabItem>

'@
if(-not $main.Contains($tabMarker)){throw 'RC6: Repair Centre tab marker not found.'}
$main=$main.Replace($tabMarker,$serviceTab+$tabMarker)

$oldVars="'CustomerBox','JobBox','ScanButton'"
$newVars="'CustomerBox','JobBox','CustomerComplaintBox','TechnicianNotesBox','WorkPerformedBox','ServiceOutcomeBox','FurtherRecommendationsBox','IncludeServiceSummaryCustomerCheck','ClearServiceRecordButton','ServiceRecordStatusText','ScanButton'"
if(-not $main.Contains($oldVars)){throw 'RC6: control registration marker not found.'}
$main=$main.Replace($oldVars,$newVars)

$oldIndex="    # Attention=0, Technician Priorities=1, All Results=2,`n    # Before/After=3, Repair Centre=4.`n    `$MainTabs.SelectedIndex=4"
$newIndex="    # Attention=0, Technician Priorities=1, All Results=2,`n    # Before/After=3, Service Record=4, Repair Centre=5.`n    `$MainTabs.SelectedIndex=5"
if(-not $main.Contains($oldIndex)){throw 'RC6: Repair Centre tab-index marker not found.'}
$main=$main.Replace($oldIndex,$newIndex)

$fnMarker='function New-RBZSelectedReport {'
$logic=@'
$ClearServiceRecordButton.Add_Click({
    $answer=[System.Windows.MessageBox]::Show('Clear all Service Record fields for this session?','RBZ PC Health - Clear Service Record',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    if($answer -ne [System.Windows.MessageBoxResult]::Yes){return}
    $CustomerComplaintBox.Clear();$TechnicianNotesBox.Clear();$WorkPerformedBox.Clear();$ServiceOutcomeBox.Clear();$FurtherRecommendationsBox.Clear()
    $IncludeServiceSummaryCustomerCheck.IsChecked=$true
    $ServiceRecordStatusText.Text='Service record cleared.';$StatusText.Text='Service record cleared.'
})
function Get-RBZCurrentServiceNotes {
    [pscustomobject]@{
        CustomerComplaint=[string]$CustomerComplaintBox.Text
        TechnicianNotes=[string]$TechnicianNotesBox.Text
        WorkPerformed=[string]$WorkPerformedBox.Text
        ServiceOutcome=[string]$ServiceOutcomeBox.Text
        FurtherRecommendations=[string]$FurtherRecommendationsBox.Text
        IncludeInCustomerReport=[bool]$IncludeServiceSummaryCustomerCheck.IsChecked
    }
}

'@
if(-not $main.Contains($fnMarker)){throw 'RC6: report function marker not found.'}
$main=$main.Replace($fnMarker,$logic+$fnMarker)

$oldCall="            -ServiceLog @(`$script:ServiceLog) ```n            -BaselineSnapshot `$script:BaselineSnapshot ```n"
$newCall="            -ServiceLog @(`$script:ServiceLog) ```n            -ServiceNotes (Get-RBZCurrentServiceNotes) ```n            -BaselineSnapshot `$script:BaselineSnapshot ```n"
if(-not $main.Contains($oldCall)){throw 'RC6: report call marker not found.'}
$main=$main.Replace($oldCall,$newCall)

$oldParams="        [object[]]`$ServiceLog=@(),`n        `$BaselineSnapshot=`$null,"
$newParams="        [object[]]`$ServiceLog=@(),`n        `$ServiceNotes=`$null,`n        `$BaselineSnapshot=`$null,"
if(-not $report.Contains($oldParams)){throw 'RC6: report parameter marker not found.'}
$report=$report.Replace($oldParams,$newParams)

$oldPayload="        ServiceLog=`$ServiceLog`n        BaselineSnapshot=`$BaselineSnapshot"
$newPayload="        ServiceLog=`$ServiceLog`n        ServiceNotes=`$ServiceNotes`n        BaselineSnapshot=`$BaselineSnapshot"
if(-not $report.Contains($oldPayload)){throw 'RC6: report payload marker not found.'}
$report=$report.Replace($oldPayload,$newPayload)

$serviceMarker="    `$serviceSection=''"
$builder=@'
    # RBZ080RC6_SERVICE_RECORD_REPORT
    $serviceNotesSection=''
    if($ServiceNotes){
        $enc={param([string]$v) if([string]::IsNullOrWhiteSpace($v)){return ''};([System.Web.HttpUtility]::HtmlEncode($v.Trim()) -replace "(`r`n|`n|`r)",'<br>')}
        $complaint=& $enc ([string]$ServiceNotes.CustomerComplaint)
        $techNotes=& $enc ([string]$ServiceNotes.TechnicianNotes)
        $work=& $enc ([string]$ServiceNotes.WorkPerformed)
        $outcome=& $enc ([string]$ServiceNotes.ServiceOutcome)
        $further=& $enc ([string]$ServiceNotes.FurtherRecommendations)
        $blocks=[System.Collections.Generic.List[string]]::new()
        if($Audience -eq 'Technician'){
            if($complaint){$blocks.Add("<div class='serviceNote'><h3>Customer Complaint / Issue</h3><div>$complaint</div></div>")}
            if($techNotes){$blocks.Add("<div class='serviceNote'><h3>Technician Notes</h3><div>$techNotes</div></div>")}
            if($work){$blocks.Add("<div class='serviceNote'><h3>Work Performed</h3><div>$work</div></div>")}
            if($outcome){$blocks.Add("<div class='serviceNote'><h3>Service Outcome</h3><div>$outcome</div></div>")}
            if($further){$blocks.Add("<div class='serviceNote'><h3>Further Recommendations</h3><div>$further</div></div>")}
            if($blocks.Count){$serviceNotesSection="<h2>Service Record</h2><div class='serviceRecord'>$($blocks -join '')</div>"}
        }elseif([bool]$ServiceNotes.IncludeInCustomerReport){
            if($complaint){$blocks.Add("<div class='serviceNote'><h3>Reason for Service</h3><div>$complaint</div></div>")}
            if($work){$blocks.Add("<div class='serviceNote'><h3>Work Performed</h3><div>$work</div></div>")}
            if($outcome){$blocks.Add("<div class='serviceNote'><h3>Service Outcome</h3><div>$outcome</div></div>")}
            if($further){$blocks.Add("<div class='serviceNote'><h3>Further Advice</h3><div>$further</div></div>")}
            if($blocks.Count){$serviceNotesSection="<h2>Service Summary</h2><div class='serviceRecord customerServiceRecord'>$($blocks -join '')</div>"}
        }
    }

'@
if(-not $report.Contains($serviceMarker)){throw 'RC6: service section marker not found.'}
$report=$report.Replace($serviceMarker,$builder+$serviceMarker)

$cssMarker='.sectionLead{color:#64748b;font-size:12px;margin:-5px 0 12px}'
$cssNew=".serviceRecord{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:0 0 20px}.serviceNote{border:1px solid #e5e7eb;background:#f8fafc;border-radius:8px;padding:12px 14px;line-height:1.45}.serviceNote h3{font-size:12px;text-transform:uppercase;letter-spacing:.35px;color:#475569;margin:0 0 6px}.sectionLead{color:#64748b;font-size:12px;margin:-5px 0 12px}"
if(-not $report.Contains($cssMarker)){throw 'RC6: CSS marker not found.'}
$report=$report.Replace($cssMarker,$cssNew)

$bodyMarker="`$technicianWorkflowSection`n`$customerCategorySummary`n<h2>`$(if(`$Audience -eq 'Customer'){'Issues & Recommendations'}else{'Needs Attention'})</h2>"
$bodyNew="`$technicianWorkflowSection`n`$customerCategorySummary`n`$serviceNotesSection`n<h2>`$(if(`$Audience -eq 'Customer'){'Issues & Recommendations'}else{'Needs Attention'})</h2>"
if(-not $report.Contains($bodyMarker)){throw 'RC6: report body marker not found.'}
$report=$report.Replace($bodyMarker,$bodyNew)

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8
Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8
Write-Host 'RBZ PC Health v0.8.0 RC6 applied.' -ForegroundColor Green
Write-Host 'Test Customer + Technician reports and Open Repair Centre navigation before committing.' -ForegroundColor Cyan
