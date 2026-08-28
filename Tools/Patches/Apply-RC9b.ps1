$ErrorActionPreference='Stop'

$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainPath=Join-Path $repoRoot 'RBZHealth.ps1'
if(-not(Test-Path $mainPath)){throw "Missing $mainPath"}

$main=Get-Content -Raw $mainPath

if($main -match 'RBZ080RC9B_REPAIR_SPLITTER'){
    Write-Host 'RC9b already applied.' -ForegroundColor Yellow
    exit 0
}

$old=@'
<TabItem Header="Repair Centre"><Grid Margin="10"><Grid.RowDefinitions>
<RowDefinition Height="Auto"/>
<RowDefinition Height="3*"/>
<RowDefinition Height="Auto"/>
<RowDefinition Height="Auto"/>
<RowDefinition Height="2*"/>
</Grid.RowDefinitions>
<TextBlock Text="Low-risk technician-approved actions only. Run a new scan after service actions to create an after-service comparison." Foreground="#6B7280" Margin="0,0,0,10"/>
<DataGrid Grid.Row="1"
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
<StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,8,0,8"><Button Name="RunActionsButton" Content="Run Selected Actions" Width="160" Height="34" IsEnabled="False"/><TextBlock Name="ActionStatusText" Margin="14,8,0,0" Foreground="#6B7280"/></StackPanel>
<Grid Grid.Row="3" Margin="0,0,0,8">
<Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<ProgressBar Name="ActionProgressBar" Height="16" Minimum="0" Maximum="100" IsIndeterminate="False"/>
<Grid Grid.Row="1" Margin="0,5,0,0"><TextBlock Name="ActionProgressText" Text="Ready." Foreground="#6B7280"/><TextBlock Name="ActionElapsedText" Text="" HorizontalAlignment="Right" Foreground="#6B7280"/></Grid>
</Grid>
<TextBox Grid.Row="4"
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
'@

$new=@'
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
'@

if(-not $main.Contains($old)){
    throw 'RC9b Repair Centre XAML block was not found. Make sure RC9/RC9a are applied to the expected baseline.'
}

$main=$main.Replace($old,$new)
Set-Content -LiteralPath $mainPath -Value $main -Encoding UTF8

Write-Host 'RBZ PC Health v0.8.0 RC9b applied.' -ForegroundColor Green
Write-Host 'Repair Centre now has a draggable horizontal splitter above the output log.' -ForegroundColor Cyan
Write-Host 'Drag up for a larger log; drag down for a larger action list.' -ForegroundColor Cyan
Write-Host 'No repair logic was changed.' -ForegroundColor DarkGray
