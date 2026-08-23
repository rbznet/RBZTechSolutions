function Get-RBZHealthScore {
    param([object[]]$Findings)
    $score = 100
    foreach($f in $Findings){
        switch($f.Status){'Critical'{$score-=15};'Warning'{$score-=6};default{}}
    }
    [math]::Max(0,[math]::Min(100,$score))
}

function Export-RBZReport {
    param([object[]]$Findings,$Config,[string]$ReportsPath,[string]$Customer='')
    if(-not(Test-Path $ReportsPath)){New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null}
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeCustomer = if($Customer){($Customer -replace '[^a-zA-Z0-9_-]','-')}else{'Customer'}
    $base = "$($Config.app.reportPrefix)-$safeCustomer-$env:COMPUTERNAME-$stamp"
    $jsonPath = Join-Path $ReportsPath "$base.json"
    $htmlPath = Join-Path $ReportsPath "$base.html"
    $score = Get-RBZHealthScore $Findings
    $payload = [pscustomobject]@{Generated=(Get-Date).ToString('o');Company=$Config.app.company;AppVersion=$Config.app.version;Customer=$Customer;Computer=$env:COMPUTERNAME;User=$env:USERNAME;Score=$score;Findings=$Findings}
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $jsonPath

    $rows = foreach($f in $Findings){
        $rec = [System.Web.HttpUtility]::HtmlEncode([string]$f.Recommendation)
        $summary = [System.Web.HttpUtility]::HtmlEncode([string]$f.Summary)
        "<tr><td>$($f.Category)</td><td>$($f.Name)</td><td><strong>$($f.Status)</strong></td><td>$summary</td><td>$rec</td></tr>"
    }
    $html = @"
<!doctype html><html><head><meta charset='utf-8'><title>$($Config.app.name) Report</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:36px;color:#1f2937}h1{margin-bottom:0}.meta{color:#6b7280;margin-top:6px}.score{font-size:42px;font-weight:700;margin:24px 0}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border:1px solid #d1d5db;padding:8px;vertical-align:top}th{background:#f3f4f6;text-align:left}footer{margin-top:30px;color:#6b7280;font-size:12px}</style></head><body><h1>$($Config.app.company)</h1><div class='meta'>$($Config.app.name) v$($Config.app.version) • $env:COMPUTERNAME • $(Get-Date)</div><div class='score'>Health score: $score/100</div><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Summary</th><th>Recommendation</th></tr></thead><tbody>$($rows -join "`n")</tbody></table><footer>Scan-only diagnostic report. No automatic remediation was performed.</footer></body></html>
"@
    $html | Set-Content -Encoding UTF8 $htmlPath
    [pscustomobject]@{Json=$jsonPath;Html=$htmlPath;Score=$score}
}
Export-ModuleMember -Function Get-RBZHealthScore,Export-RBZReport
