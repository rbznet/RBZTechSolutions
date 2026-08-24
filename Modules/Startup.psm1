function Get-RBZStartupFindings {
    param($Config)
    $out=[System.Collections.Generic.List[object]]::new()
    try {
        $items=@(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Sort-Object Name,User); $limit=[int]$Config.thresholds.startupCountRecommend
        $status=if($items.Count -gt $limit){'Recommend'}else{'Info'}
        $detailLines=foreach($item in $items){$name=if($item.Name){$item.Name}else{'Unnamed startup item'}; $location=if($item.Location){$item.Location}else{'Unknown location'}; $user=if($item.User){$item.User}else{'Unknown user'}; "$name | User: $user | Location: $location`nCommand: $($item.Command)"}
        $out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status $status -Summary "$($items.Count) startup command(s) detected." -Details ($detailLines -join "`n`n") -Value $items.Count -Recommendation $(if($status -eq 'Recommend'){'Review unnecessary startup applications with the customer before disabling anything.'}else{'Review the detailed list if startup performance is a concern.'})))
    } catch {$out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status 'Info' -Summary 'Startup application inventory unavailable.' -Details $_.Exception.Message))}
    return $out
}
Export-ModuleMember -Function Get-RBZStartupFindings
