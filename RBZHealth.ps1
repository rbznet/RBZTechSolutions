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
    $id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=[Security.Principal.WindowsPrincipal]$id
    if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'RBZ PC Health must be run as Administrator.'}
}
$modulePath = Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.modules
Get-ChildItem $modulePath -Filter '*.psm1' | Where-Object Name -ne 'Common.psm1' | ForEach-Object {Import-Module $_.FullName -Force}
$reportsPath = Resolve-RBZPath -BasePath $Root -ConfiguredPath $Config.paths.reports

function Invoke-RBZScan {
    $all=[System.Collections.Generic.List[object]]::new()
    foreach($fn in @('Get-RBZSystemFindings','Get-RBZStorageFindings','Get-RBZSecurityFindings','Get-RBZNetworkFindings','Get-RBZDeviceFindings','Get-RBZBatteryFindings','Get-RBZStartupFindings','Get-RBZUpdateFindings')){
        if(Get-Command $fn -ErrorAction SilentlyContinue){foreach($x in (& $fn -Config $Config)){$all.Add($x)}}
    }
    return $all
}

if($NoGui){
    $findings=Invoke-RBZScan
    $report=Export-RBZReport -Findings $findings -Config $Config -ReportsPath $reportsPath -Customer $Customer
    $findings | Format-Table Category,Name,Status,Summary -AutoSize
    Write-Host "`nHealth score: $($report.Score)/100"
    Write-Host "HTML report: $($report.Html)"
    Write-Host "JSON report: $($report.Json)"
    exit
}

Add-Type -AssemblyName PresentationFramework
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="RBZ PC Health" Height="650" Width="1050" WindowStartupLocation="CenterScreen">
<Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<StackPanel><TextBlock Text="RBZ PC Health" FontSize="28" FontWeight="Bold"/><TextBlock Text="Scan-only technician diagnostic" Foreground="Gray" Margin="0,4,0,14"/></StackPanel>
<StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12"><TextBlock Text="Customer:" VerticalAlignment="Center"/><TextBox Name="CustomerBox" Width="260" Margin="8,0,16,0"/><Button Name="ScanButton" Content="Run Scan" Width="110" Height="32"/><Button Name="ReportButton" Content="Generate Report" Width="130" Height="32" Margin="8,0,0,0" IsEnabled="False"/><TextBlock Name="ScoreText" Margin="18,6,0,0" FontSize="18" FontWeight="Bold"/></StackPanel>
<DataGrid Grid.Row="2" Name="ResultsGrid" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="110"/><DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="190"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/><DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/><DataGridTextColumn Header="Recommendation" Binding="{Binding Recommendation}" Width="260"/></DataGrid.Columns></DataGrid>
<TextBlock Grid.Row="3" Name="StatusText" Text="Ready." Margin="0,12,0,0" Foreground="Gray"/></Grid></Window>
'@
$reader=New-Object System.Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)
$customerBox=$window.FindName('CustomerBox'); if($Customer){$customerBox.Text=$Customer}
$scanButton=$window.FindName('ScanButton');$reportButton=$window.FindName('ReportButton');$grid=$window.FindName('ResultsGrid');$scoreText=$window.FindName('ScoreText');$statusText=$window.FindName('StatusText')
$script:Findings=$null
$scanButton.Add_Click({
    try{$statusText.Text='Scanning...';$scanButton.IsEnabled=$false;$window.Cursor='Wait';$script:Findings=Invoke-RBZScan;$grid.ItemsSource=$script:Findings;$score=Get-RBZHealthScore $script:Findings;$scoreText.Text="Health score: $score/100";$reportButton.IsEnabled=$true;$statusText.Text="Scan complete: $($script:Findings.Count) checks."}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null;$statusText.Text='Scan failed.'}finally{$window.Cursor=$null;$scanButton.IsEnabled=$true}
})
$reportButton.Add_Click({
    try{$r=Export-RBZReport -Findings $script:Findings -Config $Config -ReportsPath $reportsPath -Customer $customerBox.Text;$statusText.Text="Report saved: $($r.Html)";Start-Process $r.Html}catch{[System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null}
})
$window.ShowDialog()|Out-Null
