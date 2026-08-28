#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath,[string]$Customer,[switch]$NoGui)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# RBZ PC Health relies on Windows-native management modules that are safest
# under Windows PowerShell 5.1. If launched from PowerShell 7/Core, relaunch
# this same script under Windows PowerShell before importing any modules.
if($PSVersionTable.PSEdition -eq 'Core'){
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    if(-not(Test-Path $windowsPowerShell)){
        throw "Windows PowerShell 5.1 was not found at '$windowsPowerShell'."
    }

    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.Add('-NoLogo')
    $argList.Add('-NoProfile')
    $argList.Add('-ExecutionPolicy')
    $argList.Add('Bypass')
    $argList.Add('-File')
    $argList.Add($MyInvocation.MyCommand.Path)

    if(-not [string]::IsNullOrWhiteSpace($ConfigPath)){
        $argList.Add('-ConfigPath')
        $argList.Add($ConfigPath)
    }

    if(-not [string]::IsNullOrWhiteSpace($Customer)){
        $argList.Add('-Customer')
        $argList.Add($Customer)
    }

    if($NoGui){
        $argList.Add('-NoGui')
    }

    $proc = Start-Process -FilePath $windowsPowerShell -ArgumentList $argList -PassThru
    if($NoGui){
        $proc.WaitForExit()
        exit $proc.ExitCode
    }

    exit 0
}
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
    param([scriptblock]$ProgressCallback=$null)

    $all=[System.Collections.Generic.List[object]]::new()
    $modules=@(
        [pscustomobject]@{Name='System';Function='Get-RBZSystemFindings'}
        [pscustomobject]@{Name='Storage';Function='Get-RBZStorageFindings'}
        [pscustomobject]@{Name='Security';Function='Get-RBZSecurityFindings'}
        [pscustomobject]@{Name='Network';Function='Get-RBZNetworkFindings'}
        [pscustomobject]@{Name='Devices';Function='Get-RBZDeviceFindings'}
        [pscustomobject]@{Name='Battery';Function='Get-RBZBatteryFindings'}
        [pscustomobject]@{Name='Startup';Function='Get-RBZStartupFindings'}
        [pscustomobject]@{Name='Updates';Function='Get-RBZUpdateFindings'}
        [pscustomobject]@{Name='Event Logs';Function='Get-RBZEventLogFindings'}
    )

    $total=$modules.Count
    $completed=0

    foreach($module in $modules){
        if($ProgressCallback){
            & $ProgressCallback ([pscustomobject]@{
                Stage="Scanning $($module.Name)"
                Completed=$completed
                Total=$total
                Percent=[math]::Round(($completed/[double]$total)*100,0)
            })
        }

        if(Get-Command $module.Function -ErrorAction SilentlyContinue){
            try{
                foreach($x in (& $module.Function -Config $Config)){$all.Add($x)}
            }
            catch{
                $all.Add((New-RBZFinding -Category $module.Name -Name $module.Function -Status 'Warning' -Summary 'A scan module failed.' -Details $_.Exception.Message))
            }
        }

        $completed++
        if($ProgressCallback){
            & $ProgressCallback ([pscustomobject]@{
                Stage="Completed $($module.Name)"
                Completed=$completed
                Total=$total
                Percent=[math]::Round(($completed/[double]$total)*100,0)
            })
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
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="RBZ PC Health" Height="940" Width="1500" MinHeight="800" MinWidth="1180" WindowStartupLocation="CenterScreen" Background="#F3F4F6">
<Window.Resources>
<SolidColorBrush x:Key="RBZ.Panel" Color="#FFFFFF"/>
<SolidColorBrush x:Key="RBZ.PanelAlt" Color="#F9FAFB"/>
<SolidColorBrush x:Key="RBZ.Control" Color="#FFFFFF"/>
<SolidColorBrush x:Key="RBZ.Text" Color="#111827"/>
<SolidColorBrush x:Key="RBZ.Border" Color="#D1D5DB"/>
<SolidColorBrush x:Key="RBZ.Header" Color="#F3F4F6"/>
<SolidColorBrush x:Key="RBZ.HeaderText" Color="#111827"/>
<SolidColorBrush x:Key="RBZ.Selection" Color="#DBEAFE"/>
<SolidColorBrush x:Key="RBZ.SelectionText" Color="#111827"/>

<Style TargetType="Button">
<Setter Property="Background" Value="{DynamicResource RBZ.Control}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/>
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="BorderThickness" Value="1"/>
<Setter Property="Padding" Value="10,4"/>
<Setter Property="Template">
<Setter.Value>
<ControlTemplate TargetType="Button">
<Border Name="ButtonBorder"
        Background="{TemplateBinding Background}"
        BorderBrush="{TemplateBinding BorderBrush}"
        BorderThickness="{TemplateBinding BorderThickness}">
<ContentPresenter HorizontalAlignment="Center"
                  VerticalAlignment="Center"
                  Margin="{TemplateBinding Padding}"/>
</Border>
<ControlTemplate.Triggers>
<Trigger Property="IsMouseOver" Value="True">
<Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource RBZ.ControlHover}"/>
</Trigger>
<Trigger Property="IsPressed" Value="True">
<Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource RBZ.Selection}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.SelectionText}"/>
</Trigger>
<Trigger Property="IsEnabled" Value="False">
<Setter TargetName="ButtonBorder" Property="Background" Value="{DynamicResource RBZ.PanelAlt}"/>
<Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.TextMuted}"/>
<Setter Property="Opacity" Value="0.72"/>
</Trigger>
</ControlTemplate.Triggers>
</ControlTemplate>
</Setter.Value>
</Setter>
</Style>
<Style TargetType="TextBox">
<Setter Property="Background" Value="{DynamicResource RBZ.Control}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/>
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="CaretBrush" Value="{DynamicResource RBZ.Text}"/>
</Style>
<Style TargetType="CheckBox"><Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/></Style>
<Style TargetType="TabItem">
<Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/>
<Setter Property="Background" Value="{DynamicResource RBZ.Header}"/>
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="Padding" Value="8,4"/>
<Setter Property="Template">
<Setter.Value>
<ControlTemplate TargetType="TabItem">
<Border Name="TabBorder"
        Background="{TemplateBinding Background}"
        BorderBrush="{TemplateBinding BorderBrush}"
        BorderThickness="1,1,1,0"
        Padding="{TemplateBinding Padding}">
<ContentPresenter ContentSource="Header"
                  HorizontalAlignment="Center"
                  VerticalAlignment="Center"/>
</Border>
<ControlTemplate.Triggers>
<Trigger Property="IsSelected" Value="True">
<Setter TargetName="TabBorder" Property="Background" Value="{DynamicResource RBZ.Panel}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/>
</Trigger>
<Trigger Property="IsMouseOver" Value="True">
<Setter TargetName="TabBorder" Property="Background" Value="{DynamicResource RBZ.ControlHover}"/>
</Trigger>
</ControlTemplate.Triggers>
</ControlTemplate>
</Setter.Value>
</Setter>
</Style>
<Style TargetType="DataGrid">
<Setter Property="Background" Value="{DynamicResource RBZ.Panel}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/>
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="VerticalGridLinesBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="RowBackground" Value="{DynamicResource RBZ.Panel}"/>
<Setter Property="AlternatingRowBackground" Value="{DynamicResource RBZ.PanelAlt}"/>
</Style>
<Style TargetType="DataGridColumnHeader">
<Setter Property="Background" Value="{DynamicResource RBZ.Header}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.HeaderText}"/>
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Setter Property="Padding" Value="6,4"/>
</Style>
<Style TargetType="DataGridCell">
<Setter Property="BorderBrush" Value="{DynamicResource RBZ.Border}"/>
<Style.Triggers>
<Trigger Property="IsSelected" Value="True">
<Setter Property="Background" Value="{DynamicResource RBZ.Selection}"/>
<Setter Property="Foreground" Value="{DynamicResource RBZ.SelectionText}"/>
</Trigger>
</Style.Triggers>
</Style>
<Style TargetType="DataGridRow"><Setter Property="Foreground" Value="{DynamicResource RBZ.Text}"/><Style.Triggers>
<DataTrigger Binding="{Binding Status}" Value="Critical"><Setter Property="Background" Value="#FEE2E2"/><Setter Property="Foreground" Value="#111827"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Warning"><Setter Property="Background" Value="#FFEDD5"/><Setter Property="Foreground" Value="#111827"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Recommend"><Setter Property="Background" Value="#FEF3C7"/><Setter Property="Foreground" Value="#111827"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Healthy"><Setter Property="Background" Value="#ECFDF5"/><Setter Property="Foreground" Value="#111827"/></DataTrigger>
<DataTrigger Binding="{Binding Status}" Value="Info"><Setter Property="Background" Value="#EFF6FF"/><Setter Property="Foreground" Value="#111827"/></DataTrigger>
</Style.Triggers></Style>
</Window.Resources>
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

<Border Grid.Row="0" Name="HeaderBorder" Background="#111827" Padding="22,16"><Grid>
<Grid.ColumnDefinitions>
<ColumnDefinition Width="Auto"/>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="Auto"/>
</Grid.ColumnDefinitions>

<Border Name="LogoPlaceholder" Grid.Column="0" Width="150" Height="58" CornerRadius="8"
        BorderThickness="1" BorderBrush="#64748B" Background="#0F172A" Margin="0,0,14,0">
<Grid>
<Image Name="BrandLogo" Stretch="Uniform" Margin="4" Visibility="Collapsed"/>
<TextBlock Name="LogoFallbackText" Text="RBZ" Foreground="White" FontWeight="Bold"
           FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
</Grid>
</Border>

<StackPanel Grid.Column="1" VerticalAlignment="Center">
<TextBlock Text="RBZ PC Health" Foreground="White" FontSize="28" FontWeight="Bold"/>
<TextBlock Name="VersionText" Foreground="#CBD5E1" FontSize="13" Margin="0,4,0,0"/>
</StackPanel>

<StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
<Button Name="ThemeButton" Content="Dark mode" Height="32" Padding="12,4" Margin="0,0,14,0"/>
<TextBlock Name="DeviceText" VerticalAlignment="Center" Foreground="#E5E7EB" FontSize="14"/>
</StackPanel>
</Grid></Border>

<Border Grid.Row="1" Name="JobPanelBorder" Margin="18,16,18,10" Background="White" Padding="16" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="220"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="160"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<TextBlock Name="CustomerLabel" Text="Customer:" VerticalAlignment="Center" FontWeight="SemiBold"/>
<TextBox Grid.Column="1" Name="CustomerBox" Margin="8,0,16,0" Height="32" Padding="8,5"/>
<TextBlock Grid.Column="2" Name="JobLabel" Text="Job ref:" VerticalAlignment="Center" FontWeight="SemiBold"/>
<TextBox Grid.Column="3" Name="JobBox" Margin="8,0,16,0" Height="32" Padding="8,5"/>
<Button Grid.Column="4" Name="ScanButton" Content="Run Full Scan" Width="115" Height="34"/>
<Button Grid.Column="5" Name="CustomerReportButton" Content="Customer Report" Width="125" Height="34" Margin="8,0,0,0" IsEnabled="False"/>
<Button Grid.Column="6" Name="TechnicianReportButton" Content="Technician Report" Width="135" Height="34" Margin="8,0,0,0" IsEnabled="False"/>
<Button Grid.Column="7" Name="OpenReportsButton" Content="Open Reports" Width="105" Height="34" Margin="8,0,0,0"/>
<StackPanel Grid.Column="8" HorizontalAlignment="Right"><TextBlock Name="ScoreText" FontSize="24" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock Name="ScoreLabel" Foreground="#6B7280" HorizontalAlignment="Right"/></StackPanel>
</Grid></Border>

<Border Grid.Row="2" Name="StatsBorder" Margin="18,0,18,10" Background="White" Padding="14" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
<StackPanel><TextBlock Text="HEALTHY" Foreground="#6B7280" FontSize="11"/><TextBlock Name="HealthyCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="1"><TextBlock Text="INFO" Foreground="#6B7280" FontSize="11"/><TextBlock Name="InfoCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="2"><TextBlock Text="RECOMMEND" Foreground="#6B7280" FontSize="11"/><TextBlock Name="RecommendCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="3"><TextBlock Text="WARNINGS" Foreground="#6B7280" FontSize="11"/><TextBlock Name="WarningCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="4"><TextBlock Text="CRITICAL" Foreground="#6B7280" FontSize="11"/><TextBlock Name="CriticalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="5"><TextBlock Text="TOTAL" Foreground="#6B7280" FontSize="11"/><TextBlock Name="TotalCount" Text="0" FontSize="22" FontWeight="Bold"/></StackPanel>
</Grid></Border>

<Border Grid.Row="3" Name="ContentBorder" Margin="18,0,18,0" Background="White" Padding="10" CornerRadius="8"><TabControl Name="MainTabs">
<TabItem Header="Attention"><Grid Margin="8"><Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<DataGrid Name="AttentionGrid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True"><DataGrid.Columns>
<DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="105"/><DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="210"/><DataGridTextColumn Header="Action" Binding="{Binding ActionType}" Width="105"/>
<DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/>
</DataGrid.Columns></DataGrid>
<Border Grid.Column="1" Name="DetailBorder" Margin="12,0,0,0" Background="#F9FAFB" Padding="14" BorderBrush="#E5E7EB" BorderThickness="1"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
<TextBlock Name="DetailTitle" Text="Select a finding" FontSize="18" FontWeight="Bold" TextWrapping="Wrap"/><TextBlock Name="DetailStatus" Margin="0,5,0,12" Foreground="#6B7280"/>
<TextBlock Text="SUMMARY" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailSummary" Margin="0,4,0,14" TextWrapping="Wrap"/>
<TextBlock Text="DETAILS" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailBody" Margin="0,4,0,14" TextWrapping="Wrap"/>
<TextBlock Text="RECOMMENDATION" FontSize="11" Foreground="#6B7280" FontWeight="Bold"/><TextBlock Name="DetailRecommendation" Margin="0,4,0,14" TextWrapping="Wrap"/>
<Button Name="CopyDetailsButton" Content="Copy Details" Width="110" Height="30" HorizontalAlignment="Left"/>
</StackPanel></ScrollViewer></Border></Grid></TabItem>

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
<DataGridTextColumn Header="Action" Binding="{Binding ActionType}" Width="105"/>
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
<!-- RBZ080RC3_ACTION_MAPPING -->
<TextBlock Text="RECOMMENDED ACTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Name="PriorityDetailAction" Margin="0,4,0,8" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<TextBlock Name="PriorityDetailGuidance" Margin="0,0,0,14" Foreground="{DynamicResource RBZ.Text}" TextWrapping="Wrap"/>
<StackPanel Orientation="Horizontal">
<Button Name="OpenPriorityFindingButton" Content="Open Finding" Width="110" Height="30" HorizontalAlignment="Left" IsEnabled="False"/>
<Button Name="OpenPriorityRepairButton" Content="Open Repair Centre" Width="140" Height="30" Margin="8,0,0,0" HorizontalAlignment="Left" IsEnabled="False"/>
</StackPanel>
</StackPanel></ScrollViewer>
</Border>
</Grid></TabItem>
<TabItem Header="All Results"><DataGrid Name="ResultsGrid" Margin="8" AutoGenerateColumns="False" IsReadOnly="True" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True"><DataGrid.Columns>
<DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="110"/><DataGridTextColumn Header="Check" Binding="{Binding Name}" Width="235"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="95"/><DataGridTextColumn Header="Action" Binding="{Binding ActionType}" Width="105"/>
<DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/><DataGridTextColumn Header="Recommendation" Binding="{Binding Recommendation}" Width="280"/>
</DataGrid.Columns></DataGrid></TabItem>

<TabItem Header="Before / After"><Grid Margin="10">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Border Name="ComparisonHeaderBorder" Background="#F9FAFB" BorderBrush="#E5E7EB" BorderThickness="1" Padding="14" CornerRadius="8"><Grid>
<Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
<StackPanel><TextBlock Text="BASELINE" Foreground="#6B7280" FontSize="11"/><TextBlock Name="BaselineScoreText" Text="Not set" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="1"><TextBlock Text="CURRENT" Foreground="#6B7280" FontSize="11"/><TextBlock Name="CurrentScoreText" Text="Not set" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="2"><TextBlock Text="CHANGE" Foreground="#6B7280" FontSize="11"/><TextBlock Name="ScoreChangeText" Text="-" FontSize="24" FontWeight="Bold"/></StackPanel>
<StackPanel Grid.Column="3"><TextBlock Text="SCAN COUNT" Foreground="#6B7280" FontSize="11"/><TextBlock Name="ScanCountText" Text="0" FontSize="24" FontWeight="Bold"/></StackPanel>
</Grid></Border>
<TextBlock Grid.Row="1" Name="ComparisonSummaryText" Text="The first scan in this session becomes the baseline. Run another scan after service work to compare results." Foreground="#6B7280" Margin="0,12,0,10" TextWrapping="Wrap"/>
<DataGrid Grid.Row="2" Name="ComparisonGrid" AutoGenerateColumns="False" IsReadOnly="True" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True"><DataGrid.Columns>
<DataGridTextColumn Header="Change" Binding="{Binding Change}" Width="90"/><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100"/><DataGridTextColumn Header="Check" Binding="{Binding Check}" Width="210"/><DataGridTextColumn Header="Before" Binding="{Binding BeforeStatus}" Width="100"/><DataGridTextColumn Header="After" Binding="{Binding AfterStatus}" Width="100"/><DataGridTextColumn Header="Current finding" Binding="{Binding AfterSummary}" Width="*"/>
</DataGrid.Columns></DataGrid>
<StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0"><Button Name="SetBaselineButton" Content="Set Current as Baseline" Width="165" Height="32" IsEnabled="False"/><Button Name="ClearHistoryButton" Content="Clear Session History" Width="145" Height="32" Margin="8,0,0,0"/></StackPanel>
</Grid></TabItem>

<!-- RBZ080RC6_SERVICE_NOTES -->
<TabItem Header="Service Record"><ScrollViewer VerticalScrollBarVisibility="Auto"><Grid Margin="12">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Border Grid.Row="0" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="14" Margin="0,0,0,12"><StackPanel>
<TextBlock Text="Technician Service Record" FontSize="18" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/>
<TextBlock Text="Record the customer's issue, work carried out and final service outcome. Notes stay with this session and are included in reports as appropriate." Margin="0,4,0,0" TextWrapping="Wrap" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel></Border>
<Border Grid.Row="1" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12" Margin="0,0,0,12">
<Grid>
<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,8,0"><TextBlock Text="TECHNICIAN" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="ServiceTechnicianBox" Height="30" Margin="0,5,0,0" Padding="7,4"/></StackPanel>
<StackPanel Grid.Column="1" Margin="8,0"><TextBlock Text="FINAL SERVICE STATUS" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><ComboBox Name="ServiceStatusBox" Height="30" Margin="0,5,0,0" SelectedIndex="0"><ComboBoxItem Content="Further Work Required"/><ComboBoxItem Content="Resolved"/><ComboBoxItem Content="Improved"/><ComboBoxItem Content="No Fault Found"/></ComboBox></StackPanel>
<StackPanel Grid.Column="2" Margin="8,0"><TextBlock Text="COMPLETION DATE / TIME" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="ServiceCompletedBox" Height="30" Margin="0,5,0,0" Padding="7,4" IsReadOnly="True"/></StackPanel>
<Button Grid.Column="3" Name="CompleteServiceButton" Content="Complete Service" Width="125" Height="32" Margin="12,21,0,0" VerticalAlignment="Top"/>
</Grid>
</Border>
<Grid Grid.Row="2" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,6,0"><TextBlock Text="CUSTOMER COMPLAINT / ISSUE DESCRIPTION" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="CustomerComplaintBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<StackPanel Grid.Column="1" Margin="6,0,0,0"><TextBlock Text="TECHNICIAN NOTES" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="TechnicianNotesBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
</Grid>
<Grid Grid.Row="3" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<StackPanel Margin="0,0,6,0"><TextBlock Text="WORK PERFORMED" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="WorkPerformedBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<StackPanel Grid.Column="1" Margin="6,0,0,0"><TextBlock Text="SERVICE OUTCOME" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="ServiceOutcomeBox" Height="105" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
</Grid>
<StackPanel Grid.Row="4" Margin="0,0,0,12"><TextBlock Text="FURTHER RECOMMENDATIONS / CUSTOMER ADVICE" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource RBZ.Text}"/><TextBox Name="FurtherRecommendationsBox" Height="90" Margin="0,5,0,0" Padding="8" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></StackPanel>
<!-- RBZ080RC7A_SIGNOFF_LAYOUT -->
<Border Grid.Row="5" Background="{DynamicResource RBZ.PanelAlt}" BorderBrush="{DynamicResource RBZ.Border}" BorderThickness="1" Padding="12">
<StackPanel>
<CheckBox Name="IncludeServiceSummaryCustomerCheck" Content="Include customer-safe service summary in Customer Report" IsChecked="True"/>
<TextBlock Text="Technician Notes and technician identity are never included in the Customer Report." Margin="22,5,0,0" FontSize="11" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel>
</Border>
<StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,12,0,0">
<Button Name="ClearServiceRecordButton" Content="Clear Service Record" Width="145" Height="32"/>
<TextBlock Name="ServiceRecordStatusText" Text="Service record is session-only until a report is generated." Margin="12,8,0,0" Foreground="{DynamicResource RBZ.Text}"/>
</StackPanel>
</Grid></ScrollViewer></TabItem>
<!-- RBZ080RC9B_REPAIR_SPLITTER -->
<TabItem Header="Repair Centre"><Grid Margin="10"><Grid.RowDefinitions>
<RowDefinition Height="Auto"/>
<RowDefinition Height="3*" MinHeight="220"/>
<RowDefinition Height="8"/>
<RowDefinition Height="2*" MinHeight="120"/>
</Grid.RowDefinitions>

<TextBlock Grid.Row="0"
Text="Low-risk technician-approved actions only. Run a new scan after service actions to create an after-service comparison."
Foreground="#6B7280"
Margin="0,0,0,10"/>

<!-- Upper Repair Centre area: action list + controls + progress stay together. -->
<Grid Grid.Row="1">
<Grid.RowDefinitions>
<RowDefinition Height="*"/>
<RowDefinition Height="Auto"/>
<RowDefinition Height="Auto"/>
</Grid.RowDefinitions>

<DataGrid Grid.Row="0"
Name="ActionGrid"
AutoGenerateColumns="False"
CanUserAddRows="False"
VerticalAlignment="Stretch"
HorizontalAlignment="Stretch"
ScrollViewer.VerticalScrollBarVisibility="Auto"
ScrollViewer.HorizontalScrollBarVisibility="Auto"
ScrollViewer.CanContentScroll="True"
ScrollViewer.IsDeferredScrollingEnabled="False"><DataGrid.Columns>
<DataGridCheckBoxColumn Header="Run" Binding="{Binding Selected}" Width="55"/>
<DataGridTextColumn Header="Category" Binding="{Binding Category}" IsReadOnly="True" Width="100"/>
<DataGridTextColumn Header="Action" Binding="{Binding Name}" IsReadOnly="True" Width="220"/>
<DataGridTextColumn Header="Risk" Binding="{Binding Risk}" IsReadOnly="True" Width="70"/>
<DataGridTextColumn Header="Description" Binding="{Binding Description}" IsReadOnly="True" Width="*"/>
</DataGrid.Columns></DataGrid>

<StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,8">
<Button Name="RunActionsButton" Content="Run Selected Actions" Width="160" Height="34" IsEnabled="False"/>
<TextBlock Name="ActionStatusText" Margin="14,8,0,0" Foreground="#6B7280"/>
</StackPanel>

<Grid Grid.Row="2" Margin="0,0,0,4">
<Grid.RowDefinitions>
<RowDefinition Height="Auto"/>
<RowDefinition Height="Auto"/>
</Grid.RowDefinitions>
<ProgressBar Name="ActionProgressBar" Height="16" Minimum="0" Maximum="100" IsIndeterminate="False"/>
<Grid Grid.Row="1" Margin="0,5,0,0">
<TextBlock Name="ActionProgressText" Text="Ready." Foreground="#6B7280"/>
<TextBlock Name="ActionElapsedText" Text="" HorizontalAlignment="Right" Foreground="#6B7280"/>
</Grid>
</Grid>
</Grid>

<!-- Drag this bar vertically to resize the action area and output log. -->
<GridSplitter Grid.Row="2"
Height="8"
HorizontalAlignment="Stretch"
VerticalAlignment="Stretch"
ResizeDirection="Rows"
ResizeBehavior="PreviousAndNext"
ShowsPreview="True"
Background="{DynamicResource RBZ.Border}"
Cursor="SizeNS"
Margin="0,1,0,1"/>

<TextBox Grid.Row="3"
Name="ActionLogBox"
IsReadOnly="True"
VerticalAlignment="Stretch"
HorizontalAlignment="Stretch"
TextWrapping="Wrap"
AcceptsReturn="True"
VerticalScrollBarVisibility="Auto"
HorizontalScrollBarVisibility="Auto"
FontFamily="Consolas"
FontSize="12"/>

</Grid></TabItem>
</TabControl></Border>

<Border Grid.Row="4" Margin="18,10,18,14">
<Grid>
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

<Border Name="RestartRequiredBanner"
        Grid.Row="0"
        Background="#FEF3C7"
        BorderBrush="#F59E0B"
        BorderThickness="1"
        CornerRadius="4"
        Padding="10,7"
        Margin="0,0,0,8"
        Visibility="Collapsed">
<TextBlock Name="RestartRequiredText"
           Text="Restart required to complete one or more repairs."
           Foreground="#92400E"
           FontWeight="SemiBold"/>
</Border>

<ProgressBar Grid.Row="1" Name="Progress" Height="10" Minimum="0" Maximum="100" IsIndeterminate="False" Visibility="Collapsed"/>
<Grid Grid.Row="2" Margin="0,8,0,0">
<Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
<StackPanel>
<TextBlock Name="StatusText" Text="Ready." Foreground="#6B7280"/>
<TextBlock Name="ScanProgressText" Text="" Foreground="#9CA3AF" FontSize="11" Margin="0,2,0,0"/>
</StackPanel>
<TextBlock Grid.Column="1" Name="ScanElapsedText" Text="" Foreground="#6B7280" VerticalAlignment="Center"/>
</Grid>
</Grid>
</Border>
</Grid></Window>
'@

$reader=New-Object System.Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)
foreach($name in @('CustomerBox','JobBox','CustomerComplaintBox','TechnicianNotesBox','WorkPerformedBox','ServiceOutcomeBox','FurtherRecommendationsBox','ServiceTechnicianBox','ServiceStatusBox','ServiceCompletedBox','IncludeServiceSummaryCustomerCheck','CompleteServiceButton','ClearServiceRecordButton','ServiceRecordStatusText','ScanButton','CustomerReportButton','TechnicianReportButton','OpenReportsButton','ResultsGrid','AttentionGrid','PriorityGrid','PriorityDetailTitle','PriorityDetailStatus','PriorityDetailSummary','PriorityDetailReason','PriorityDetailAction','PriorityDetailGuidance','OpenPriorityFindingButton','OpenPriorityRepairButton','ScoreText','ScoreLabel','StatusText','Progress','ScanProgressText','ScanElapsedText','DeviceText','VersionText','HealthyCount','InfoCount','RecommendCount','WarningCount','CriticalCount','TotalCount','DetailTitle','DetailStatus','DetailSummary','DetailBody','DetailRecommendation','CopyDetailsButton','ActionGrid','RunActionsButton','ActionStatusText','ActionLogBox','ActionProgressBar','ActionProgressText','ActionElapsedText','RestartRequiredBanner','RestartRequiredText','BaselineScoreText','CurrentScoreText','ScoreChangeText','ScanCountText','ComparisonSummaryText','ComparisonGrid','SetBaselineButton','ClearHistoryButton','HeaderBorder','JobPanelBorder','StatsBorder','ContentBorder','MainTabs','DetailBorder','ComparisonHeaderBorder','LogoPlaceholder','BrandLogo','LogoFallbackText','ThemeButton','CustomerLabel','JobLabel')){Set-Variable -Name $name -Value $window.FindName($name)}

if($Customer){$CustomerBox.Text=$Customer}
$VersionText.Text="$($Config.app.productSubtitle) | v$($Config.app.version)"

$script:Theme='Light'
$script:RestartRequired=$false
$script:ThemeStatePath=[Environment]::ExpandEnvironmentVariables([string]$Config.ui.themeStateFile)

function Get-RBZSavedTheme {
    $fallback=[string]$Config.ui.defaultTheme
    if($fallback -notin @('Light','Dark')){$fallback='Light'
=False}

    if(-not [bool]$Config.ui.rememberTheme){return $fallback}

    try {
        if(Test-Path $script:ThemeStatePath){
            $saved=Get-Content -LiteralPath $script:ThemeStatePath -Raw -ErrorAction Stop | ConvertFrom-Json
            if([string]$saved.theme -in @('Light','Dark')){
                return [string]$saved.theme
            }
        }
    } catch {}

    return $fallback
}

function Save-RBZTheme {
    if(-not [bool]$Config.ui.rememberTheme){return}

    try {
        $folder=Split-Path $script:ThemeStatePath -Parent
        if(-not(Test-Path $folder)){
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        [pscustomobject]@{theme=$script:Theme} |
            ConvertTo-Json |
            Set-Content -LiteralPath $script:ThemeStatePath -Encoding UTF8
    } catch {}
}

function Set-RBZTheme {
    param([ValidateSet('Light','Dark')][string]$Theme)
    $script:Theme=$Theme
    $bc=[System.Windows.Media.BrushConverter]::new()
    if($Theme -eq 'Dark'){
        $window.Background='#111827'; $JobPanelBorder.Background='#1F2937'; $StatsBorder.Background='#1F2937'; $ContentBorder.Background='#1F2937'; $DetailBorder.Background='#111827'; $DetailBorder.BorderBrush='#374151'; $ComparisonHeaderBorder.Background='#111827'; $ComparisonHeaderBorder.BorderBrush='#374151'; $MainTabs.Background='#1F2937'; $MainTabs.Foreground='#F3F4F6'
        $window.Resources['RBZ.Panel']=$bc.ConvertFromString('#111827')
        $window.Resources['RBZ.PanelAlt']=$bc.ConvertFromString('#1F2937')
        $window.Resources['RBZ.Control']=$bc.ConvertFromString('#172033')
        $window.Resources['RBZ.Text']=$bc.ConvertFromString('#F3F4F6')
        $window.Resources['RBZ.Border']=$bc.ConvertFromString('#475569')
        $window.Resources['RBZ.Header']=$bc.ConvertFromString('#263449')
        $window.Resources['RBZ.HeaderText']=$bc.ConvertFromString('#F8FAFC')
        $window.Resources['RBZ.Selection']=$bc.ConvertFromString('#334155')
        $window.Resources['RBZ.SelectionText']=$bc.ConvertFromString('#FFFFFF')
        foreach($text in @($ScoreText,$HealthyCount,$InfoCount,$RecommendCount,$WarningCount,$CriticalCount,$TotalCount,$DetailTitle,$DetailSummary,$DetailBody,$DetailRecommendation,$BaselineScoreText,$CurrentScoreText,$ScoreChangeText,$ScanCountText)){$text.Foreground='#F3F4F6'}
        $ScoreLabel.Foreground='#CBD5E1';$DetailStatus.Foreground='#94A3B8';$ComparisonSummaryText.Foreground='#CBD5E1';$ActionStatusText.Foreground='#CBD5E1';$ActionProgressText.Foreground='#CBD5E1';$ActionElapsedText.Foreground='#CBD5E1';$StatusText.Foreground='#CBD5E1';$ScanProgressText.Foreground='#94A3B8';$ScanElapsedText.Foreground='#CBD5E1';$CustomerLabel.Foreground='#F3F4F6'
        $JobLabel.Foreground='#F3F4F6'
        $ThemeButton.Content='Light mode'
    } else {
        $window.Background='#F3F4F6'; $JobPanelBorder.Background='White'; $StatsBorder.Background='White'; $ContentBorder.Background='White'; $DetailBorder.Background='#F9FAFB'; $DetailBorder.BorderBrush='#E5E7EB'; $ComparisonHeaderBorder.Background='#F9FAFB'; $ComparisonHeaderBorder.BorderBrush='#E5E7EB'; $MainTabs.Background='White'; $MainTabs.Foreground='#111827'
        $window.Resources['RBZ.Panel']=$bc.ConvertFromString('#FFFFFF')
        $window.Resources['RBZ.PanelAlt']=$bc.ConvertFromString('#F9FAFB')
        $window.Resources['RBZ.Control']=$bc.ConvertFromString('#FFFFFF')
        $window.Resources['RBZ.Text']=$bc.ConvertFromString('#111827')
        $window.Resources['RBZ.Border']=$bc.ConvertFromString('#D1D5DB')
        $window.Resources['RBZ.Header']=$bc.ConvertFromString('#F3F4F6')
        $window.Resources['RBZ.HeaderText']=$bc.ConvertFromString('#111827')
        $window.Resources['RBZ.Selection']=$bc.ConvertFromString('#DBEAFE')
        $window.Resources['RBZ.SelectionText']=$bc.ConvertFromString('#111827')
        foreach($text in @($ScoreText,$HealthyCount,$InfoCount,$RecommendCount,$WarningCount,$CriticalCount,$TotalCount,$DetailTitle,$DetailSummary,$DetailBody,$DetailRecommendation,$BaselineScoreText,$CurrentScoreText,$ScoreChangeText,$ScanCountText)){$text.Foreground='#111827'}
        $ScoreLabel.Foreground='#6B7280';$DetailStatus.Foreground='#6B7280';$ComparisonSummaryText.Foreground='#6B7280';$ActionStatusText.Foreground='#6B7280';$ActionProgressText.Foreground='#6B7280';$ActionElapsedText.Foreground='#6B7280';$StatusText.Foreground='#6B7280';$ScanProgressText.Foreground='#9CA3AF';$ScanElapsedText.Foreground='#6B7280';$CustomerLabel.Foreground='#111827'
        $JobLabel.Foreground='#111827'
        $ThemeButton.Content='Dark mode'
    }
}

$ThemeButton.Add_Click({
    $next=if($script:Theme -eq 'Dark'){'Light'}else{'Dark'}
    Set-RBZTheme -Theme $next
    Save-RBZTheme
})

# Header logo: use Assets\rbz-logo.png when present; otherwise retain RBZ placeholder.
try {
    $logoPath=Resolve-RBZPath -BasePath $Root -ConfiguredPath ([string]$Config.ui.logoPath)
    if(Test-Path $logoPath){
        $bitmap=New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption=[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource=New-Object System.Uri($logoPath)
        $bitmap.EndInit()
        $BrandLogo.Source=$bitmap
        $BrandLogo.Visibility='Visible'
        $LogoFallbackText.Visibility='Collapsed'
    }
} catch {}

Set-RBZTheme -Theme (Get-RBZSavedTheme)

$DeviceText.Text="$env:COMPUTERNAME | $env:USERNAME"
$script:Findings=$null
$script:ServiceLog=[System.Collections.Generic.List[object]]::new()
$script:ServiceVerificationRows=[System.Collections.Generic.List[object]]::new()
# RBZ080RC5_REPAIR_WORKFLOW
$script:RepairVerificationPending=$false
$script:RepairContextFinding=$null
$script:RepairContextAction=$null
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

function Show-RBZPriorityDetail($Item){
    if($null -eq $Item){return}
    $PriorityDetailTitle.Text=$Item.Name
    $PriorityDetailStatus.Text="$($Item.Priority) priority | $($Item.Category) | $($Item.Status)"
    $PriorityDetailSummary.Text=$Item.Summary
    $PriorityDetailReason.Text=$Item.Reason
    $PriorityDetailAction.Text="$($Item.ActionName)`n$($Item.ActionText)"
    $PriorityDetailGuidance.Text=$Item.Guidance
    $OpenPriorityFindingButton.IsEnabled=$true
    $OpenPriorityRepairButton.IsEnabled=[bool]$Item.CanOpenRepairCentre
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
    # Before/After=3, Service Record=4, Repair Centre=5.
    $MainTabs.SelectedIndex=5
    $ActionGrid.SelectedItem=$match[0]
    $ActionGrid.ScrollIntoView($match[0])
        $script:RepairContextFinding=$item
    $script:RepairContextAction=$match[0]
    $ActionStatusText.Text="Recommended for: $($item.Category) - $($item.Name) | Highlighted: $($match[0].Name) | Risk: $($match[0].Risk). Nothing has been selected or run. Review the description, tick Run only if appropriate, then confirm."
}
$OpenPriorityRepairButton.Add_Click({Open-RBZPriorityRepairAction})
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
        $scanStarted=Get-Date
        $isRepairVerification=[bool]$script:RepairVerificationPending

        $StatusText.Text='Scanning system...'
        $ScanProgressText.Text='Preparing scan...'
        $ScanElapsedText.Text='00:00:00'
        $Progress.Visibility='Visible'
        $Progress.IsIndeterminate=$false
        $Progress.Value=0

        $ScanButton.IsEnabled=$false
        $CustomerReportButton.IsEnabled=$false
        $TechnicianReportButton.IsEnabled=$false
        $RunActionsButton.IsEnabled=$false
        $window.Cursor='Wait'

        $progressCallback={
            param($state)

            $Progress.Value=[double]$state.Percent
            $StatusText.Text=$state.Stage
            $ScanProgressText.Text="Module $($state.Completed) of $($state.Total) | $($state.Percent)%"
            $ScanElapsedText.Text=((Get-Date)-$scanStarted).ToString('hh\:mm\:ss')

            $window.Dispatcher.Invoke(
                [action]{},
                [System.Windows.Threading.DispatcherPriority]::Background
            )
        }

        $script:Findings=Invoke-RBZScan -ProgressCallback $progressCallback
        $ResultsGrid.ItemsSource=$script:Findings

        $snapshot=New-RBZScanSnapshot -Findings $script:Findings -Config $Config -Sequence ($script:ScanHistory.Count+1)
        $script:ScanHistory.Add($snapshot)

        while($script:ScanHistory.Count -gt [int]$Config.session.maxInMemoryScans){
            $script:ScanHistory.RemoveAt(0)
        }

        if(-not $script:BaselineSnapshot -and $Config.session.autoSetFirstScanAsBaseline){
            $script:BaselineSnapshot=$snapshot
        }

        $script:CurrentSnapshot=$snapshot
        Update-RBZComparisonView

        $rank=@{'Critical'=0;'Warning'=1;'Recommend'=2}
        $attention=@(
            $script:Findings |
            Where-Object Status -in @('Recommend','Warning','Critical') |
            Sort-Object @{Expression={$rank[$_.Status]}},Category,Name
        )
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
            $PriorityDetailGuidance.Text=''
            $OpenPriorityRepairButton.IsEnabled=$false
        }

        $score=Get-RBZHealthScore -Findings $script:Findings -Config $Config
        $ScoreText.Text="$score/100"
        $ScoreLabel.Text=Get-RBZScoreLabel -Score $score

        $HealthyCount.Text=@($script:Findings|Where-Object Status -eq 'Healthy').Count
        $InfoCount.Text=@($script:Findings|Where-Object Status -eq 'Info').Count
        $RecommendCount.Text=@($script:Findings|Where-Object Status -eq 'Recommend').Count
        $WarningCount.Text=@($script:Findings|Where-Object Status -eq 'Warning').Count
        $CriticalCount.Text=@($script:Findings|Where-Object Status -eq 'Critical').Count
        $TotalCount.Text=$script:Findings.Count

        if($attention.Count){$AttentionGrid.SelectedIndex=0}

        $Progress.Value=100
        $ScanProgressText.Text='Module 9 of 9 | 100%'
        $ScanElapsedText.Text=((Get-Date)-$scanStarted).ToString('hh\:mm\:ss')

        $CustomerReportButton.IsEnabled=$true
        $TechnicianReportButton.IsEnabled=$true
        $RunActionsButton.IsEnabled=[bool]$Config.remediation.enabled

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
    }
    catch{
        [System.Windows.MessageBox]::Show($_.Exception.Message,'RBZ PC Health')|Out-Null
        $StatusText.Text='Scan failed.'
        $ScanProgressText.Text=''
    }
    finally{
        $window.Cursor=$null
        $ScanButton.IsEnabled=$true
        $Progress.Visibility='Collapsed'
    }
})

$RunActionsButton.Add_Click({
    $selected=@($script:Actions|Where-Object Selected -eq $true)
    if(-not $selected.Count){[System.Windows.MessageBox]::Show('Select at least one service action first.','RBZ PC Health')|Out-Null;return}

        $names=($selected.Name -join "`n- ")
    $contextText=''
    if($script:RepairContextFinding){
        $contextText="`n`nDiagnostic context:`n$($script:RepairContextFinding.Category) - $($script:RepairContextFinding.Name)`n$($script:RepairContextFinding.Summary)"
    }
    $confirm=[System.Windows.MessageBox]::Show("Run these selected actions?`n`n- $names$contextText`n`nOnly explicitly selected actions will run. A verification scan will still be required afterwards.",'RBZ PC Health - Confirm',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    if($confirm -ne [System.Windows.MessageBoxResult]::Yes){return}

    try{
        $RunActionsButton.IsEnabled=$false
        $ScanButton.IsEnabled=$false
        $window.Cursor='Wait'
        $serviceModule=Join-Path $modulePath 'Service.psm1'
        $configJson=$Config | ConvertTo-Json -Depth 20 -Compress

        foreach($a in $selected){
            $skipRestorePoint=$false
            $restorePointAlreadyCreated=$false
            if($a.Risk -eq 'Medium' -and $Config.remediation.attemptRestorePointBeforeMediumActions){
                $ActionStatusText.Text='Creating pre-repair restore point...'
                $window.Dispatcher.Invoke([action]{},[System.Windows.Threading.DispatcherPriority]::Background)

                $rp=New-RBZRestorePoint -Config $Config -Reason $a.Name

                if($rp.Success){
                    $restorePointAlreadyCreated=$true
                    $ActionLogBox.AppendText(
                        "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                        "Pre-repair protection: restore point CREATED AND VERIFIED.`r`n" +
                        "$($rp.Details)`r`n`r`n"
                    )
                    $ActionLogBox.ScrollToEnd()
                }
                else {
                    $failureMessage=$rp.Summary
                    $failureTechnicalDetails=$rp.Details

                    $choice=Show-RBZSystemProtectionPrompt -FailureMessage $failureMessage

                    if($choice -eq 'Cancel'){
                        $ActionLogBox.AppendText(
                            "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                            "Repair cancelled because the pre-repair restore point was not created/verified.`r`n" +
                            "$failureMessage`r`n$failureTechnicalDetails`r`n`r`n"
                        )
                        $a.Selected=$false
                        continue
                    }

                    if($choice -eq 'Enable'){
                        $ActionStatusText.Text='Enabling System Protection and retrying restore point...'
                        $window.Dispatcher.Invoke([action]{},[System.Windows.Threading.DispatcherPriority]::Background)

                        $enabled=Enable-RBZSystemProtection -Config $Config

                        if(-not $enabled.Success){
                            [System.Windows.MessageBox]::Show(
                                "$($enabled.Summary)`n`n$($enabled.Details)",
                                'RBZ PC Health - System Protection',
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Warning
                            )|Out-Null
                            $a.Selected=$false
                            continue
                        }

                        $retry=New-RBZRestorePoint -Config $Config -Reason $a.Name

                        if($retry.Success){
                            $restorePointAlreadyCreated=$true
                            $ActionLogBox.AppendText(
                                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                                "Pre-repair protection: System Protection enabled; restore point CREATED AND VERIFIED.`r`n" +
                                "$($retry.Details)`r`n`r`n"
                            )
                            $ActionLogBox.ScrollToEnd()
                        }
                        else {
                            $fallback=[System.Windows.MessageBox]::Show(
                                "System Protection was enabled, but the restore point still could not be created and verified.`n`n$($retry.Summary)`n`nContinue WITHOUT a restore point?",
                                'RBZ PC Health - Restore Point Verification',
                                [System.Windows.MessageBoxButton]::YesNo,
                                [System.Windows.MessageBoxImage]::Warning
                            )

                            if($fallback -ne [System.Windows.MessageBoxResult]::Yes){
                                $a.Selected=$false
                                continue
                            }

                            $skipRestorePoint=$true
                            $ActionLogBox.AppendText(
                                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                                "Pre-repair protection: SKIPPED BY TECHNICIAN after retry failed.`r`n" +
                                "$($retry.Summary)`r`n$($retry.Details)`r`n`r`n"
                            )
                        }
                    }
                    elseif($choice -eq 'Skip'){
                        $confirmSkip=[System.Windows.MessageBox]::Show(
                            "Continue with '$($a.Name)' without a verified restore point?",
                            'RBZ PC Health - Confirm No Restore Point',
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Warning
                        )

                        if($confirmSkip -ne [System.Windows.MessageBoxResult]::Yes){
                            $a.Selected=$false
                            continue
                        }

                        $skipRestorePoint=$true
                        $ActionLogBox.AppendText(
                            "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                            "Pre-repair protection: SKIPPED BY TECHNICIAN.`r`n" +
                            "$failureMessage`r`n$failureTechnicalDetails`r`n`r`n"
                        )
                    }
                }
            }

            $actionStarted=Get-Date
            $progressPath=Join-Path $env:TEMP ("RBZ-PC-Health-progress-" + [guid]::NewGuid().ToString('N') + '.json')
            Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue

            $ActionStatusText.Text="Running: $($a.Name)"
            $ActionProgressBar.Value=0
            $ActionProgressBar.Foreground='#2563EB'
            $ActionProgressBar.IsIndeterminate=$true
            $ActionProgressText.Text='Starting...'
            $ActionElapsedText.Text='00:00:00'

            $job=Start-Job -ScriptBlock {
                param($ModulePath,$ConfigJson,$ActionId,$ProgressPath,$SkipRestorePoint,$RestorePointAlreadyCreated)
                Import-Module $ModulePath -Force
                $cfg=$ConfigJson | ConvertFrom-Json
                Invoke-RBZServiceAction -Id $ActionId -Config $cfg -ProgressPath $ProgressPath -SkipRestorePoint:$SkipRestorePoint -RestorePointAlreadyCreated:$RestorePointAlreadyCreated
            } -ArgumentList $serviceModule,$configJson,$a.Id,$progressPath,$skipRestorePoint,$restorePointAlreadyCreated

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

            $verificationWarning=([string]$r.VerificationStatus -in @('Warning','Critical'))

            if([bool]$r.Success -and -not $verificationWarning){
                $ActionProgressBar.Foreground='#16A34A'
                $ActionProgressText.Text="Completed successfully - $($r.Summary)"
                $ActionStatusText.Text="Completed successfully: $($a.Name)"
            }
            elseif([bool]$r.Success -and $verificationWarning){
                $ActionProgressBar.Foreground='#D97706'
                $ActionProgressText.Text="Completed with warning - $($r.Summary)"
                $ActionStatusText.Text="Completed with warning: $($a.Name)"
            }
            else{
                $ActionProgressBar.Foreground='#DC2626'
                $ActionProgressText.Text="Failed - $($r.Summary)"
                $ActionStatusText.Text="Failed: $($a.Name)"
            }

            $ActionElapsedText.Text=((Get-Date)-$actionStarted).ToString('hh\:mm\:ss')

            # RBZ080RC9A_UPDATE_OUTPUT
            $verifyText=$(if(-not [string]::IsNullOrWhiteSpace([string]$r.VerificationSummary)){"`r`nVerification: $($r.VerificationStatus) - $($r.VerificationSummary)"}else{''})

            # RBZ080RC9C_FAILURE_DETAILS
            # Windows Update actions always show technical details. Any failed
            # action also shows its technical details automatically so the
            # technician can see the real exception/result without leaving RBZ.
            $detailText=''
            if(-not [string]::IsNullOrWhiteSpace([string]$r.Details)){
                if([string]$a.Category -eq 'Updates'){
                    $detailText="`r`n`r`nWindows Update details:`r`n$($r.Details)"
                }
                elseif(-not [bool]$r.Success -or [string]$r.VerificationStatus -eq 'Warning'){
                    $detailText="`r`n`r`nTechnical details:`r`n$($r.Details)"
                }
            }

            $ActionLogBox.AppendText(
                "[$((Get-Date).ToString('HH:mm:ss'))] $($a.Name)`r`n" +
                "$($r.Summary)$verifyText$detailText`r`n`r`n"
            )

            if([bool]$r.RequiresRestart){
                $script:RestartRequired=$true
                $RestartRequiredText.Text="Restart required to complete: $($a.Name). Restart Windows, then run Verify Repairs."
                $RestartRequiredBanner.Visibility='Visible'
            }
            $ActionLogBox.ScrollToEnd()
            $a.Selected=$false
            Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue
            Update-RBZComparisonView
        }

        $ActionGrid.Items.Refresh()
        $script:RepairVerificationPending=$true
        $ScanButton.Content='Verify Repairs'
        $ActionStatusText.Text='Selected actions completed. Verification required: run a Full Scan to confirm whether the original diagnostic finding changed.'
        $StatusText.Text='Service actions completed. Verification is pending; use Verify Repairs.'
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
$ClearServiceRecordButton.Add_Click({
    $answer=[System.Windows.MessageBox]::Show('Clear all Service Record fields for this session?','RBZ PC Health - Clear Service Record',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    if($answer -ne [System.Windows.MessageBoxResult]::Yes){return}
    $CustomerComplaintBox.Clear();$TechnicianNotesBox.Clear();$WorkPerformedBox.Clear();$ServiceOutcomeBox.Clear();$FurtherRecommendationsBox.Clear();$ServiceTechnicianBox.Text=[Environment]::UserName;$ServiceStatusBox.SelectedIndex=0;$ServiceCompletedBox.Clear()
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
        Technician=[string]$ServiceTechnicianBox.Text
        FinalStatus=if($ServiceStatusBox.SelectedItem){[string]$ServiceStatusBox.SelectedItem.Content}else{'Further Work Required'}
        Completed=[string]$ServiceCompletedBox.Text
        IncludeInCustomerReport=[bool]$IncludeServiceSummaryCustomerCheck.IsChecked
    }
}
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
            -ServiceNotes (Get-RBZCurrentServiceNotes) `
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













