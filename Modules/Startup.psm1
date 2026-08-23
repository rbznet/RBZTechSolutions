function Get-RBZStartupFindings {
    param($Config)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        $items = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
        $status = if($items.Count -gt 20){'Warning'}else{'Info'}
        $out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status $status -Summary "$($items.Count) startup command(s) detected." -Value $items.Count -Recommendation $(if($status -eq 'Warning'){'Review unnecessary startup applications with the customer before disabling anything.'}else{''})))
    } catch {$out.Add((New-RBZFinding -Category 'Startup' -Name 'Startup applications' -Status 'Info' -Summary 'Startup application inventory unavailable.'))}
    return $out
}
Export-ModuleMember -Function Get-RBZStartupFindings
