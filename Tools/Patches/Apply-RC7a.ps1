$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
if(-not(Test-Path $mainPath)){throw "RBZHealth.ps1 not found: $mainPath"}

$main=Get-Content -Raw $mainPath
if($main -match 'RBZ080RC7A_SIGNOFF_LAYOUT'){Write-Host 'RC7a already applied.' -ForegroundColor Yellow;exit 0}
if($main -notmatch 'RBZ080RC7_SERVICE_COMPLETION'){throw 'RC7a requires RC7 to be applied first.'}

$rowsOld='<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
$rowsNew='<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>'
if(-not $main.Contains($rowsOld)){throw 'RC7a: row definitions not found.'}
$main=$main.Replace($rowsOld,$rowsNew)

$oldBottom=@'
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

$newBottom=@'
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
'@
if(-not $main.Contains($oldBottom)){throw 'RC7a: RC7 sign-off block not found.'}
$main=$main.Replace($oldBottom,$newBottom)

$headerOld=@'
</StackPanel></Border>
<Grid Grid.Row="1" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
'@
$headerNew=@'
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
'@
if(-not $main.Contains($headerOld)){throw 'RC7a: header marker not found.'}
$main=$main.Replace($headerOld,$headerNew)

$workOld='<Grid Grid.Row="2" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
$workNew='<Grid Grid.Row="3" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>'
$first=$main.IndexOf($workOld)
$second=$main.IndexOf($workOld,$first+1)
if($second -lt 0){throw 'RC7a: work-performed row marker not found.'}
$main=$main.Remove($second,$workOld.Length).Insert($second,$workNew)

$furtherOld='<StackPanel Grid.Row="3" Margin="0,0,0,12"><TextBlock Text="FURTHER RECOMMENDATIONS / CUSTOMER ADVICE"'
$furtherNew='<StackPanel Grid.Row="4" Margin="0,0,0,12"><TextBlock Text="FURTHER RECOMMENDATIONS / CUSTOMER ADVICE"'
if(-not $main.Contains($furtherOld)){throw 'RC7a: further-recommendations marker not found.'}
$main=$main.Replace($furtherOld,$furtherNew)

Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8
Write-Host 'RBZ PC Health v0.8.0 RC7a applied.' -ForegroundColor Green
Write-Host 'Service completion controls are now at the top of Service Record.' -ForegroundColor Cyan
