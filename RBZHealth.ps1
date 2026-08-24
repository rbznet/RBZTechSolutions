#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$Customer,
    [switch]$NoGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $ConfigPath){$ConfigPath = Join-Path $Root 'Config\settings.json'}

Import-Module (Join-Path $Root 'Modules\Common.psm1') -Force
$Config = Get-RBZConfig -Path $ConfigPath

if($Config.app.requireAdmin){
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=[Security.Principal.WindowsPrincipal]$id
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'RBZ PC Health must be run as Administrator.'}
}

$modulePath = Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.modules
Get-ChildItem $modulePath -Filter '*.psm1' | Where-Object Name -ne 'Common.psm1' | ForEach-Object {Import-Module $_.FullName -Force}
$reportsPath = Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.reports

function Invoke-RBZScan {
    $all=[System.Collections.Generic.List[object]]::new()
    $functions = @(
        'Get-RBZSystemFindings',
        'Get-RBZStorageFindings',
        'Get-RBZSecurityFindings',
        'Get-RBZNetworkFindings',
        'Get-RBZDeviceFindings',
        'Get-RBZBatteryFindings',
        'Get-RBZStartupFindings',
        'Get-RBZUpdateFindings'
    )
    foreach($fn in $functions){
        if(Get-Command $fn -ErrorAction SilentlyContinue){
            try {
                foreach($x in (& $fn -Config $Config)){$all.Add($x)}
            } catch {
                $all.Add((New-RBZFinding -Category 'System' -Name $fn -Status 'Warning' -Summary 'A scan module failed.' -Details $_.Exception.Message))
            }
        }
    }
    return $all
}

if($NoGui){
    $findings=Invoke-RBZScan
    $report=Export-RBZReport -Findings $findings -Config $Config -ReportsPath $reportsPath -Customer $Customer
    $findings | Format-Table Category,Name,Status,Summary -AutoSize
    Write-Host "`nHealth score: $($report.Score)/100 ($($report.Label))"
    Write-Host "HTML report: $($report.Html)"
    Write-Host "JSON report: $($report.Json)"
    exit
}

Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="RBZ PC Health" Height="760" Width="1220" MinHeight="650" MinWidth="1000"
        WindowStartupLocation="CenterScreen" Background="#F3F4F6">
<Grid>
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>

  <Border Grid.Row="0" Background="#111827" Padding="22,16">
    <Grid>
      <StackPanel>
        <TextBlock Text="RBZ PC Health" Foreground="White" FontSize="28" FontWeight="Bold"/>
        <TextBlock Text="Technician Diagnostic Suite | v0.2.1" Foreground="#CBD5E1" FontSize="13" Margin="0,4,0,0"/>
      </StackPanel>
      <TextBlock Name="DeviceText" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#E5E7EB" FontSize="14"/>
    </Grid>
  </Border>

  <Border Grid.Row="1" Margin="18,16,18,10" Background="White" Padding="16" CornerRadius="8">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="300"/>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <TextBlock Text="Customer:" VerticalAlignment="Center" FontWeight="SemiBold"/>
      <TextBox Grid.Column="1" Name="CustomerBox" Margin="8,0,18,0" Height="32" Padding="8,5"/>
      <Button Grid.Column="2" Name="ScanButton" Content="Run Full Scan" Width="125" Height="34"/>
      <Button Grid.Column="3" Name="ReportButton" Content="Generate Report" Width="135" Height="34" Margin="8,0,0,0" IsEnabled="False"/>
      <StackPanel Grid.Column="4" HorizontalAlignment="Right">
        <TextBlock Name="ScoreText" FontSize="24" FontWeight="Bold" HorizontalAlignment="Right"/>
        <TextBlock Name="ScoreLabel" Foreground="#6B7280" HorizontalAlignment="Right"/>
      </StackPanel>
    </Grid>
  </Border>

  <Border Grid.Row="2" Margin="18,0,18,10" Background="White" Padding="14" CornerRadius="8">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
      <StackPanel><TextBlock Text="HEALTHY" Foreground="#6B7280" FontSize="11"/><TextBlock Name="HealthyCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
      <StackPanel Grid.Column="1"><TextBlock Text="RECOMMEND" Foreground="#6B7280" FontSize="11"/><TextBlock Name="RecommendCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
      <StackPanel Grid.Column="2"><TextBlock Text="WARNINGS" Foreground="#6B7280" FontSize="11"/><TextBlock Name="WarningCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
      <StackPanel Grid.Column="3"><TextBlock Text="CRITICAL" Foreground="#6B7280" FontSize="11"/><TextBlock Name="CriticalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
      <StackPanel Grid.Column="4"><TextBlock Text="TOTAL CHECKS" Foreground="#6B7280" FontSize="11"/><TextBlock Name="TotalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
    </Grid>
  </Border>

  <Border Grid.Row="3" Margin="18,0,18,0" Background="White" Padding="10" CornerRadius="8">
    <TabControl Name="Tabs">
      <TabItem Header="Attention">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <DataGrid Name="AttentionGrid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" HeadersVisibility="Column">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
              <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="110"/>
              <DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="200"/>
              <DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Column="1" Margin="12,0,0,0" Background="#F9FAFB" Padding="14" BorderBrush="#E5E7EB" BorderThickness="1">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <TextBlock Name="DetailTitle" Text="Select a finding" FontSize="18" FontWeight="Bold" TextWrapping="Wrap"/>
                <TextBlock Name="DetailStatus" Margin="0,5,0,12" Foreground="#6B7280"/>
                <TextBlock Text="SUMMARY" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/>
                <TextBlock Name="DetailSummary" Margin="0,4,0,14" TextWrapping="Wrap"/>
                <TextBlock Text="DETAILS" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/>
                <TextBlock Name="DetailBody" Margin="0,4,0,14" TextWrapping="Wrap"/>
                <TextBlock Text="RECOMMENDATION" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/>
                <TextBlock Name="DetailRecommendation" Margin="0,4,0,0" TextWrapping="Wrap"/>
              </StackPanel>
            </ScrollViewer>
          </Border>
        </Grid>
      </TabItem>
      <TabItem Header="All Results">
        <DataGrid Name="ResultsGrid" Margin="8" AutoGenerateColumns="False" IsReadOnly="True">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="110"/>
            <DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="210"/>
            <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="95"/>
            <DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
            <DataGridTextColumn Header="Recommendation" Binding="{Binding Recommendation}" Width="280"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
    </TabControl>
  </Border>

  <Border Grid.Row="4" Margin="18,10,18,14" Background="Transparent">
    <Grid>
      <ProgressBar Name="Progress" Height="5" IsIndeterminate="True" Visibility="Collapsed" VerticalAlignment="Top"/>
      <TextBlock Name="StatusText" Text="Ready." Margin="0,10,0,0" Foreground="#6B7280"/>
    </Grid>
  </Border>
</Grid>
</Window>
'@

$reader=New-Object System.Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)

$customerBox=$window.FindName('CustomerBox')
if($Customer){$customerBox.Text=$Customer}

$scanButton=$window.FindName('ScanButton')
$reportButton=$window.FindName('ReportButton')
$grid=$window.FindName('ResultsGrid')
$attentionGrid=$window.FindName('AttentionGrid')
$scoreText=$window.FindName('ScoreText')
$scoreLabel=$window.FindName('ScoreLabel')
$statusText=$window.FindName('StatusText')
$progress=$window.FindName('Progress')
$deviceText=$window.FindName('DeviceText')
$healthyCount=$window.FindName('HealthyCount')
$recommendCount=$window.FindName('RecommendCount')
$warningCount=$window.FindName('WarningCount')
$criticalCount=$window.FindName('CriticalCount')
$totalCount=$window.FindName('TotalCount')
$detailTitle=$window.FindName('DetailTitle')
$detailStatus=$window.FindName('DetailStatus')
$detailSummary=$window.FindName('DetailSummary')
$detailBody=$window.FindName('DetailBody')
$detailRecommendation=$window.FindName('DetailRecommendation')

$deviceText.Text="$env:COMPUTERNAME | $env:USERNAME"
$script:Findings=$null

function Show-RBZDetail {
    param($Finding)
    if($null -eq $Finding){return}
    $detailTitle.Text=$Finding.Name
    $detailStatus.Text="$($Finding.Category) | $($Finding.Status)"
    $detailSummary.Text=$Finding.Summary
    $detailBody.Text=$(if([string]::IsNullOrWhiteSpace([string]$Finding.Details)){'No additional technical detail was returned.'}else{$Finding.Details})
    $detailRecommendation.Text=$(if([string]::IsNullOrWhiteSpace([string]$Finding.Recommendation)){'No action required.'}else{$Finding.Recommendation})
}

$attentionGrid.Add_SelectionChanged({
    if($attentionGrid.SelectedItem){Show-RBZDetail -Finding $attentionGrid.SelectedItem}
})

$scanButton.Add_Click({
    try {
        $statusText.Text='Scanning system...'
        $progress.Visibility='Visible'
        $scanButton.IsEnabled=$false
        $window.Cursor='Wait'

        $script:Findings=Invoke-RBZScan
        $grid.ItemsSource=$script:Findings

        $attention=@($script:Findings | Where-Object Status -in @('Recommend','Warning','Critical'))
        $attentionGrid.ItemsSource=$attention

        $score=Get-RBZHealthScore -Findings $script:Findings -Config $Config
        $label=Get-RBZScoreLabel -Score $score
        $scoreText.Text="$score/100"
        $scoreLabel.Text=$label

        $healthyCount.Text=@($script:Findings | Where-Object Status -eq 'Healthy').Count
        $recommendCount.Text=@($script:Findings | Where-Object Status -eq 'Recommend').Count
        $warningCount.Text=@($script:Findings | Where-Object Status -eq 'Warning').Count
        $criticalCount.Text=@($script:Findings | Where-Object Status -eq 'Critical').Count
        $totalCount.Text=$script:Findings.Count

        if($attention.Count -gt 0){
            $attentionGrid.SelectedIndex=0
        } else {
            $detailTitle.Text='No findings require attention'
            $detailStatus.Text=''
            $detailSummary.Text='The scan did not identify any warning, critical, or recommendation findings.'
            $detailBody.Text=''
            $detailRecommendation.Text=''
        }

        $reportButton.IsEnabled=$true
        $statusText.Text="Scan complete: $($script:Findings.Count) checks."
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null
        $statusText.Text='Scan failed.'
    } finally {
        $progress.Visibility='Collapsed'
        $window.Cursor=$null
        $scanButton.IsEnabled=$true
    }
})

$reportButton.Add_Click({
    try {
        $r=Export-RBZReport -Findings $script:Findings -Config $Config -ReportsPath $reportsPath -Customer $customerBox.Text
        $statusText.Text="Report saved: $($r.Html)"
        Start-Process $r.Html
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null
    }
})

$window.ShowDialog()|Out-Null

