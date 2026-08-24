#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath,[string]$Customer,[switch]$NoGui)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $ConfigPath){$ConfigPath=Join-Path $Root 'Config\settings.json'}
Import-Module (Join-Path $Root 'Modules\Common.psm1') -Force
$Config=Get-RBZConfig -Path $ConfigPath

if($Config.app.requireAdmin){
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=[Security.Principal.WindowsPrincipal]$id
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'RBZ PC Health must be run as Administrator.'}
}

$modulePath=Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.modules
Get-ChildItem $modulePath -Filter '*.psm1' | Where-Object Name -ne 'Common.psm1' | ForEach-Object {Import-Module $_.FullName -Force}
$reportsPath=Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.reports

function Invoke-RBZScan {
    $all=[System.Collections.Generic.List[object]]::new()
    foreach($fn in @('Get-RBZSystemFindings','Get-RBZStorageFindings','Get-RBZSecurityFindings','Get-RBZNetworkFindings','Get-RBZDeviceFindings','Get-RBZBatteryFindings','Get-RBZStartupFindings','Get-RBZUpdateFindings')){
        if(Get-Command $fn -ErrorAction SilentlyContinue){
            try{foreach($x in (& $fn -Config $Config)){$all.Add($x)}}
            catch{$all.Add((New-RBZFinding -Category 'System' -Name $fn -Status 'Warning' -Summary 'A scan module failed.' -Details $_.Exception.Message))}
        }
    }
    return $all
}

if($NoGui){
    $findings=Invoke-RBZScan
    $report=Export-RBZReport -Findings $findings -Config $Config -ReportsPath $reportsPath -Customer $Customer -Audience Technician
    $findings|Format-Table Category,Name,Status,Summary -AutoSize
    Write-Host "`nHealth score: $($report.Score)/100 ($($report.Label))"
    Write-Host "HTML report: $($report.Html)"
    exit
}

Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="RBZ PC Health" Height="820" Width="1260" MinHeight="700" MinWidth="1050" WindowStartupLocation="CenterScreen" Background="#F3F4F6">
<Window.Resources>
<Style TargetType="DataGridRow"><Style.Triggers>
<DataTrigger Binding="{Binding Status}" Value="Critical"><Setter Property="Background" Value="#FEE2E2"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Warning"><Setter Property="Background" Value="#FFEDD5"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Recommend"><Setter Property="Background" Value="#FEF3C7"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Healthy"><Setter Property="Background" Value="#ECFDF5"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Info"><Setter Property="Background" Value="#EFF6FF"/></DataTrigger>
</Style.Triggers></Style>
</Window.Resources>
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

<Border Grid.Row="0" Background="#111827" Padding="22,16"><Grid>
<StackPanel><TextBlock Text="RBZ PC Health" Foreground="White" FontSize="28" FontWeight="Bold"/><TextBlock Name="VersionText" Foreground="#CBD5E1" FontSize="13" Margin="0,4,0,0"/></StackPanel>
<TextBlock Name="DeviceText" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#E5E7EB" FontSize="14"/>
</Grid></Border>

<Border Grid.Row="1" Margin="18,16,18,10" Background="White" Padding="16" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="220"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="160"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<TextBlock Text="Customer:" VerticalAlignment="Center" FontWeight="SemiBold"/>
<TextBox Grid.Column="1" Name="CustomerBox" Margin="8,0,16,0" Height="32" Padding="8,5"/>
<TextBlock Grid.Column="2" Text="Job ref:" VerticalAlignment="Center" FontWeight="SemiBold"/>
<TextBox Grid.Column="3" Name="JobBox" Margin="8,0,16,0" Height="32" Padding="8,5"/>
<Button Grid.Column="4" Name="ScanButton" Content="Run Full Scan" Width="115" Height="34"/>
<Button Grid.Column="5" Name="CustomerReportButton" Content="Customer Report" Width="125" Height="34" Margin="8,0,0,0" IsEnabled="False"/>
<Button Grid.Column="6" Name="TechnicianReportButton" Content="Technician Report" Width="135" Height="34" Margin="8,0,0,0" IsEnabled="False"/>
<Button Grid.Column="7" Name="OpenReportsButton" Content="Open Reports" Width="105" Height="34" Margin="8,0,0,0"/>
<StackPanel Grid.Column="8" HorizontalAlignment="Right"><TextBlock Name="ScoreText" FontSize="24" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock Name="ScoreLabel" Foreground="#6B7280" HorizontalAlignment="Right"/></StackPanel>
</Grid></Border>

<Border Grid.Row="2" Margin="18,0,18,10" Background="White" Padding="14" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
<StackPanel><TextBlock Text="HEALTHY" Foreground="#6B7280" FontSize="11"/><TextBlock Name="HealthyCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="1"><TextBlock Text="INFO" Foreground="#6B7280" FontSize="11"/><TextBlock Name="InfoCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="2"><TextBlock Text="RECOMMEND" Foreground="#6B7280" FontSize="11"/><TextBlock Name="RecommendCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="3"><TextBlock Text="WARNINGS" Foreground="#6B7280" FontSize="11"/><TextBlock Name="WarningCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="4"><TextBlock Text="CRITICAL" Foreground="#6B7280" FontSize="11"/><TextBlock Name="CriticalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="5"><TextBlock Text="TOTAL" Foreground="#6B7280" FontSize="11"/><TextBlock Name="TotalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
</Grid></Border>

<Border Grid.Row="3" Margin="18,0,18,0" Background="White" Padding="10" CornerRadius="8"><TabControl>
<TabItem Header="Attention"><Grid Margin="8"><Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<DataGrid Name="AttentionGrid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"><DataGrid.Columns>
<DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="105"/><DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="210"/><DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
</DataGrid.Columns></DataGrid>
<Border Grid.Column="1" Margin="12,0,0,0" Background="#F9FAFB" Padding="14" BorderBrush="#E5E7EB" BorderThickness="1"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
<TextBlock Name="DetailTitle" Text="Select a finding" FontSize="18" FontWeight="Bold" TextWrapping="Wrap"/><TextBlock Name="DetailStatus" Margin="0,5,0,12" Foreground="#6B7280"/>
<TextBlock Text="SUMMARY" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailSummary" Margin="0,4,0,14" TextWrapping="Wrap"/>
<TextBlock Text="DETAILS" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailBody" Margin="0,4,0,14" TextWrapping="Wrap"/>
<TextBlock Text="RECOMMENDATION" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailRecommendation" Margin="0,4,0,14" TextWrapping="Wrap"/>
<Button Name="CopyDetailsButton" Content="Copy Details" Width="110" Height="30" HorizontalAlignment="Left"/>
</StackPanel></ScrollViewer></Border></Grid></TabItem>

<TabItem Header="All Results"><DataGrid Name="ResultsGrid" Margin="8" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns>
<DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="110"/><DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="235"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="95"/><DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/><DataGridTextColumn Header="Recommendation" Binding="{Binding Recommendation}" Width="280"/>
</DataGrid.Columns></DataGrid></TabItem>

<TabItem Header="Before / After"><Grid Margin="10">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Border Background="#F9FAFB" BorderBrush="#E5E7EB" BorderThickness="1" Padding="14" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
<StackPanel><TextBlock Text="BASELINE" Foreground="#6B7280" FontSize="11"/><TextBlock Name="BaselineScoreText" Text="Not set" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="1"><TextBlock Text="CURRENT" Foreground="#6B7280" FontSize="11"/><TextBlock Name="CurrentScoreText" Text="Not set" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="2"><TextBlock Text="CHANGE" Foreground="#6B7280" FontSize="11"/><TextBlock Name="ScoreChangeText" Text="-" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="3"><TextBlock Text="SCAN COUNT" Foreground="#6B7280" FontSize="11"/><TextBlock Name="ScanCountText" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel>
</Grid></Border>
<TextBlock Grid.Row="1" Name="ComparisonSummaryText" Text="The first scan in this session becomes the baseline. Run another scan after service work to compare results." Foreground="#6B7280" Margin="0,12,0,10" TextWrapping="Wrap"/>
<DataGrid Grid.Row="2" Name="ComparisonGrid" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns>
<DataGridTextColumn Header="Change" Binding="{Binding Change}" Width="90"/><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100"/><DataGridTextColumn Header="Check" Binding="{Binding Check}" Width="210"/><DataGridTextColumn Header="Before" Binding="{Binding BeforeStatus}" Width="100"/><DataGridTextColumn Header="After" Binding="{Binding AfterStatus}" Width="100"/><DataGridTextColumn Header="Current finding" Binding="{Binding AfterSummary}" Width="*"/>
</DataGrid.Columns></DataGrid>
<StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0"><Button Name="SetBaselineButton" Content="Set Current as Baseline" Width="165" Height="32" IsEnabled="False"/><Button Name="ClearHistoryButton" Content="Clear Session History" Width="145" Height="32" Margin="8,0,0,0"/></StackPanel>
</Grid></TabItem>

<TabItem Header="Repair Centre"><Grid Margin="10"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="160"/></Grid.RowDefinitions>
<TextBlock Text="Low-risk technician-approved actions only. Run a new scan after service actions to create an after-service comparison." Foreground="#6B7280" Margin="0,0,0,10"/>
<DataGrid Grid.Row="1" Name="ActionGrid" AutoGenerateColumns="False" CanUserAddRows="False"><DataGrid.Columns>
<DataGridCheckBoxColumn Header="Run" Binding="{Binding Selected}" Width="55"/>
<DataGridTextColumn Header="Category" Binding="{Binding Category}" IsReadOnly="True" Width="100"/>
<DataGridTextColumn Header="Action" Binding="{Binding Name}" IsReadOnly="True" Width="220"/>
<DataGridTextColumn Header="Risk" Binding="{Binding Risk}" IsReadOnly="True" Width="70"/>
<DataGridTextColumn Header="Description" Binding="{Binding Description}" IsReadOnly="True" Width="*"/>
</DataGrid.Columns></DataGrid>
<StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,8"><Button Name="RunActionsButton" Content="Run Selected Actions" Width="160" Height="34" IsEnabled="False"/><TextBlock Name="ActionStatusText" Margin="14,8,0,0" Foreground="#6B7280"/></StackPanel>
<Grid Grid.Row="3" Margin="0,0,0,8">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<ProgressBar Name="ActionProgressBar" Height="16" Minimum="0" Maximum="100" IsIndeterminate="False"/>
<Grid Grid.Row="1" Margin="0,5,0,0"><TextBlock Name="ActionProgressText" Text="Ready." Foreground="#6B7280"/><TextBlock Name="ActionElapsedText" Text="" HorizontalAlignment="Right" Foreground="#6B7280"/></Grid>
</Grid>
<TextBox Grid.Row="4" Name="ActionLogBox" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"/>
</Grid></TabItem>
</TabControl></Border>

<Border Grid.Row="4" Margin="18,10,18,14"><Grid><ProgressBar Name="Progress" Height="5" IsIndeterminate="True" Visibility="Collapsed" VerticalAlignment="Top"/><TextBlock Name="StatusText" Text="Ready." Margin="0,10,0,0" Foreground="#6B7280"/></Grid></Border>
</Grid></Window>
'@

$reader=New-Object System.Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)
foreach($name in @('CustomerBox','JobBox','ScanButton','CustomerReportButton','TechnicianReportButton','OpenReportsButton','ResultsGrid','AttentionGrid','ScoreText','ScoreLabel','StatusText','Progress','DeviceText','VersionText','HealthyCount','InfoCount','RecommendCount','WarningCount','CriticalCount','TotalCount','DetailTitle','DetailStatus','DetailSummary','DetailBody','DetailRecommendation','CopyDetailsButton','ActionGrid','RunActionsButton','ActionStatusText','ActionLogBox','ActionProgressBar','ActionProgressText','ActionElapsedText','BaselineScoreText','CurrentScoreText','ScoreChangeText','ScanCountText','ComparisonSummaryText','ComparisonGrid','SetBaselineButton','ClearHistoryButton')){Set-Variable -Name $name -Value $window.FindName($name)}

if($Customer){$CustomerBox.Text=$Customer}
$VersionText.Text="$($Config.app.productSubtitle) | v$($Config.app.version)"
$DeviceText.Text="$env:COMPUTERNAME | $env:USERNAME"
$script:Findings=$null
$script:ServiceLog=[System.Collections.Generic.List[object]]::new()
$script:ServiceVerificationRows=[System.Collections.Generic.List[object]]::new()
$script:Actions=@(Get-RBZServiceActions -Config $Config)
$ActionGrid.ItemsSource=$script:Actions
$script:ScanHistory=[System.Collections.Generic.List[object]]::new()
$script:BaselineSnapshot=$null
$script:CurrentSnapshot=$null

function Show-RBZDetail($Finding){
    if($null -eq $Finding){return}
    $DetailTitle.Text=$Finding.Name;$DetailStatus.Text="$($Finding.Category) | $($Finding.Status)";$DetailSummary.Text=$Finding.Summary
    $DetailBody.Text=if([string]::IsNullOrWhiteSpace([string]$Finding.Details)){'No additional technical detail was returned.'}else{$Finding.Details}
    $DetailRecommendation.Text=if([string]::IsNullOrWhiteSpace([string]$Finding.Recommendation)){'No action required.'}else{$Finding.Recommendation}
}
$AttentionGrid.Add_SelectionChanged({if($AttentionGrid.SelectedItem){Show-RBZDetail $AttentionGrid.SelectedItem}})
$CopyDetailsButton.Add_Click({if($AttentionGrid.SelectedItem){$f=$AttentionGrid.SelectedItem;[Windows.Clipboard]::SetText("Status: $($f.Status)`r`nCategory: $($f.Category)`r`nCheck: $($f.Name)`r`nSummary: $($f.Summary)`r`n`r`nDetails:`r`n$($f.Details)`r`n`r`nRecommendation:`r`n$($f.Recommendation)");$StatusText.Text='Finding details copied to clipboard.'}})

function Update-RBZComparisonView {
    $ScanCountText.Text=$script:ScanHistory.Count
    if($script:BaselineSnapshot){$BaselineScoreText.Text="$($script:BaselineSnapshot.Score)/100"}else{$BaselineScoreText.Text='Not set'}
    if($script:CurrentSnapshot){$CurrentScoreText.Text="$($script:CurrentSnapshot.Score)/100";$SetBaselineButton.IsEnabled=$true}else{$CurrentScoreText.Text='Not set';$SetBaselineButton.IsEnabled=$false}
    if($script:BaselineSnapshot -and $script:CurrentSnapshot){
        $cmp=Get-RBZComparisonSummary -Baseline $script:BaselineSnapshot -Current $script:CurrentSnapshot
        $delta=[int]$cmp.ScoreChange
        $ScoreChangeText.Text=$(if($delta -gt 0){"+$delta"}else{"$delta"})
        $displayChanges=[System.Collections.Generic.List[object]]::new()
        foreach($c in @($cmp.Changes)){$displayChanges.Add($c)}
        foreach($v in @($script:ServiceVerificationRows)){$displayChanges.Add($v)}
        $ComparisonGrid.ItemsSource=@($displayChanges)
        $ComparisonSummaryText.Text="Improved: $($cmp.Improved) | Worsened: $($cmp.Worsened) | New: $($cmp.New) | Removed: $($cmp.Removed) | Updated: $($cmp.Updated) | Repair verified: $($script:ServiceVerificationRows.Count)"
    }else{
        $ScoreChangeText.Text='-';$ComparisonGrid.ItemsSource=$null
        $ComparisonSummaryText.Text='The first scan in this session becomes the baseline. Run another scan after service work to compare results.'
    }
}

$SetBaselineButton.Add_Click({if($script:CurrentSnapshot){$script:BaselineSnapshot=$script:CurrentSnapshot;Update-RBZComparisonView;$StatusText.Text='Current scan set as the new baseline.'}})
$ClearHistoryButton.Add_Click({$script:ScanHistory.Clear();$script:BaselineSnapshot=$null;$script:CurrentSnapshot=$null;Update-RBZComparisonView;$StatusText.Text='Session scan history cleared.'})

$ScanButton.Add_Click({
    try{
        $StatusText.Text='Scanning system...';$Progress.Visibility='Visible';$ScanButton.IsEnabled=$false;$window.Cursor='Wait'
        $script:Findings=Invoke-RBZScan;$ResultsGrid.ItemsSource=$script:Findings
        $snapshot=New-RBZScanSnapshot -Findings $script:Findings -Config $Config -Sequence ($script:ScanHistory.Count+1)
        $script:ScanHistory.Add($snapshot)
        while($script:ScanHistory.Count -gt [int]$Config.session.maxInMemoryScans){$script:ScanHistory.RemoveAt(0)}
        if(-not $script:BaselineSnapshot -and $Config.session.autoSetFirstScanAsBaseline){$script:BaselineSnapshot=$snapshot}
        $script:CurrentSnapshot=$snapshot
        Update-RBZComparisonView
        $rank=@{'Critical'=0;'Warning'=1;'Recommend'=2}
        $attention=@($script:Findings|Where-Object Status -in @('Recommend','Warning','Critical')|Sort-Object @{Expression={$rank[$_.Status]}},Category,Name)
        $AttentionGrid.ItemsSource=$attention
        $score=Get-RBZHealthScore -Findings $script:Findings -Config $Config;$ScoreText.Text="$score/100";$ScoreLabel.Text=Get-RBZScoreLabel -Score $score
        $HealthyCount.Text=@($script:Findings|Where-Object Status -eq 'Healthy').Count;$InfoCount.Text=@($script:Findings|Where-Object Status -eq 'Info').Count
        $RecommendCount.Text=@($script:Findings|Where-Object Status -eq 'Recommend').Count;$WarningCount.Text=@($script:Findings|Where-Object Status -eq 'Warning').Count
        $CriticalCount.Text=@($script:Findings|Where-Object Status -eq 'Critical').Count;$TotalCount.Text=$script:Findings.Count
        if($attention.Count){$AttentionGrid.SelectedIndex=0}
        $CustomerReportButton.IsEnabled=$true;$TechnicianReportButton.IsEnabled=$true;$RunActionsButton.IsEnabled=[bool]$Config.remediation.enabled
        $StatusText.Text="Scan complete: $($script:Findings.Count) checks."
    }catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null;$StatusText.Text='Scan failed.'}
    finally{$Progress.Visibility='Collapsed';$window.Cursor=$null;$ScanButton.IsEnabled=$true}
})

$RunActionsButton.Add_Click({
    $selected=@($script:Actions|Where-Object Selected -eq $true)
    if(-not $selected.Count){[System.Windows.MessageBox]::Show('Select at least one service action first.','RBZ PC Health')|Out-Null;return}

    $names=($selected.Name -join "`n- ")
    $confirm=[System.Windows.MessageBox]::Show("Run these selected actions?`n`n- $names`n`nOnly explicitly selected actions will run.",'RBZ PC Health - Confirm',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    if($confirm -ne [System.Windows.MessageBoxResult]::Yes){return}

    try{
        $RunActionsButton.IsEnabled=$false
        $ScanButton.IsEnabled=$false
        $window.Cursor='Wait'
        $serviceModule=Join-Path $modulePath 'Service.psm1'
        $configJson=$Config | ConvertTo-Json -Depth 20 -Compress

        foreach($a in $selected){
            $actionStarted=Get-Date
            $progressPath=Join-Path $env:TEMP ("RBZ-PC-Health-progress-" + [guid]::NewGuid().ToString('N') + '.json')
            Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue

            $ActionStatusText.Text="Running: $($a.Name)"
            $ActionProgressBar.Value=0
            $ActionProgressBar.IsIndeterminate=$true
            $ActionProgressText.Text='Starting...'
            $ActionElapsedText.Text='00:00:00'

            $job=Start-Job -ScriptBlock {
                param($ModulePath,$ConfigJson,$ActionId,$ProgressPath)
                Import-Module $ModulePath -Force
                $cfg=$ConfigJson | ConvertFrom-Json
                Invoke-RBZServiceAction -Id $ActionId -Config $cfg -ProgressPath $ProgressPath
            } -ArgumentList $serviceModule,$configJson,$a.Id,$progressPath

            while($job.State -in @('NotStarted','Running')){
                try {
                    if(Test-Path $progressPath){
                        $state=Get-Content -LiteralPath $progressPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                        if($state){
                            $ActionProgressBar.IsIndeterminate=[bool]$state.Indeterminate
                            if(-not $state.Indeterminate -and $null -ne $state.Percent){$ActionProgressBar.Value=[double]$state.Percent}
                            $ActionProgressText.Text=$(if([string]::IsNullOrWhiteSpace([string]$state.Message)){$state.Stage}else{"$($state.Stage) - $($state.Message)"})
                        }
                    }
                } catch {}

                $elapsed=(Get-Date)-$actionStarted
                $ActionElapsedText.Text=$elapsed.ToString('hh\:mm\:ss')
                $StatusText.Text="Service action running: $($a.Name) | Elapsed $($elapsed.ToString('hh\:mm\:ss'))"

                $window.Dispatcher.Invoke([action]{},[System.Windows.Threading.DispatcherPriority]::Background)
                Start-Sleep -Milliseconds ([int]$Config.remediation.progressPollMilliseconds)
            }

            $jobOutput=@(Receive-Job -Job $job -Wait -AutoRemoveJob)
            $r=$jobOutput | Where-Object {$_ -and $_.PSObject.Properties['Id']} | Select-Object -Last 1
            if(-not $r){
                $r=[pscustomobject]@{
                    Id=$a.Id;Name=$a.Name;Risk=$a.Risk;Started=$actionStarted.ToString('o');Finished=(Get-Date).ToString('o')
                    Success=$false;Summary='Service action did not return a result object.';Details=($jobOutput|Out-String)
                    VerificationCategory=$a.Category;VerificationCheck=$a.Name;VerificationStatus='Warning'
                    VerificationSummary='Service action result could not be verified.';VerificationDetails=($jobOutput|Out-String)
                }
            }

            $script:ServiceLog.Add($r)

            if(-not [string]::IsNullOrWhiteSpace([string]$r.VerificationStatus)){
                $script:ServiceVerificationRows.Remove(
                    ($script:ServiceVerificationRows | Where-Object Check -eq $r.VerificationCheck | Select-Object -First 1)
                ) | Out-Null

                $script:ServiceVerificationRows.Add([pscustomobject]@{
                    Change='Verified'
                    Category=$r.VerificationCategory
                    Check=$r.VerificationCheck
                    BeforeStatus='Service action'
                    AfterStatus=$r.VerificationStatus
                    BeforeSummary=$a.Name
                    AfterSummary=$r.VerificationSummary
                })
            }

            $ActionProgressBar.IsIndeterminate=$false
            $ActionProgressBar.Value=100
            $ActionProgressText.Text=$r.Summary
            $ActionElapsedText.Text=((Get-Date)-$actionStarted).ToString('hh\:mm\:ss')

            $verifyText=$(if(-not [string]::IsNullOrWhiteSpace([string]$r.VerificationSummary)){"`r`nVerification: $($r.VerificationStatus) - $($r.VerificationSummary)"}else{''})
            $ActionLogBox.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n$($r.Summary)$verifyText`r`n`r`n")
            $ActionLogBox.ScrollToEnd()
            $a.Selected=$false
            Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue
            Update-RBZComparisonView
        }

        $ActionGrid.Items.Refresh()
        $ActionStatusText.Text='Selected actions completed. Run a new scan to verify diagnostic findings.'
        $StatusText.Text='Service actions completed. Repair verification is shown in Before / After; full re-scan still recommended.'
    }
    catch{
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health - Repair Centre')|Out-Null
        $StatusText.Text='A service action failed.'
    }
    finally{
        $window.Cursor=$null
        $RunActionsButton.IsEnabled=$true
        $ScanButton.IsEnabled=$true
    }
})

function New-RBZSelectedReport {
    param([ValidateSet('Customer','Technician')][string]$Audience)

    if(-not $script:Findings){
        [System.Windows.MessageBox]::Show('Run a scan before generating a report.','RBZ PC Health')|Out-Null
        return
    }

    try {
        $r = Export-RBZReport `
            -Findings $script:Findings `
            -Config $Config `
            -ReportsPath $reportsPath `
            -Customer $CustomerBox.Text `
            -JobReference $JobBox.Text `
            -Audience $Audience `
            -ServiceLog @($script:ServiceLog) `
            -BaselineSnapshot $script:BaselineSnapshot `
            -CurrentSnapshot $script:CurrentSnapshot

        $StatusText.Text="$Audience report saved: $($r.Html)"
        Start-Process $r.Html
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null
    }
}

$CustomerReportButton.Add_Click({
    New-RBZSelectedReport -Audience 'Customer'
})

$TechnicianReportButton.Add_Click({
    New-RBZSelectedReport -Audience 'Technician'
})

$OpenReportsButton.Add_Click({
    try {
        if(-not(Test-Path $reportsPath)){
            New-Item -ItemType Directory -Path $reportsPath -Force | Out-Null
        }
        Start-Process explorer.exe -ArgumentList "`"$reportsPath`""
        $StatusText.Text="Opened reports folder: $reportsPath"
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null
    }
})

$window.ShowDialog()|Out-Null
