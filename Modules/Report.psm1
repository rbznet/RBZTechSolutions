function Get-RBZHealthScore {
    param([object[]]$Findings,$Config)

    $weights = $Config.scoring.categoryWeights
    $factors = $Config.scoring.statusFactors
    $statusRank = @{ 'Healthy'=0; 'Info'=0; 'Recommend'=1; 'Warning'=2; 'Critical'=3 }
    $total = 0.0

    foreach($prop in $weights.PSObject.Properties){
        $category = $prop.Name
        $weight = [double]$prop.Value
        $items = @($Findings | Where-Object Category -eq $category)

        if($items.Count -eq 0){
            $total += $weight
            continue
        }

        $worst = $items | Sort-Object @{Expression={ $statusRank[$_.Status] };Descending=$true} | Select-Object -First 1
        $factorProp = $factors.PSObject.Properties[$worst.Status]
        $factor = if($null -ne $factorProp){[double]$factorProp.Value}else{1.0}
        $total += ($weight * $factor)
    }

    [math]::Round([math]::Max(0,[math]::Min(100,$total)),0)
}

function Get-RBZScoreLabel {
    param([int]$Score)
    if($Score -ge 90){'Excellent'}
    elseif($Score -ge 80){'Good'}
    elseif($Score -ge 65){'Attention recommended'}
    elseif($Score -ge 50){'Poor'}
    else{'Critical attention'}
}

function Export-RBZReport {
    param([object[]]$Findings,$Config,[string]$ReportsPath,[string]$Customer='')

    Add-Type -AssemblyName System.Web
    if(-not(Test-Path $ReportsPath)){New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null}

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeCustomer = if($Customer){($Customer -replace '[^a-zA-Z0-9_-]','-')}else{'Customer'}
    $base = "$($Config.app.reportPrefix)-$safeCustomer-$env:COMPUTERNAME-$stamp"
    $jsonPath = Join-Path $ReportsPath "$base.json"
    $htmlPath = Join-Path $ReportsPath "$base.html"
    $score = Get-RBZHealthScore -Findings $Findings -Config $Config
    $label = Get-RBZScoreLabel -Score $score

    $counts = @{
        Healthy = @($Findings | Where-Object Status -eq 'Healthy').Count
        Info = @($Findings | Where-Object Status -eq 'Info').Count
        Recommend = @($Findings | Where-Object Status -eq 'Recommend').Count
        Warning = @($Findings | Where-Object Status -eq 'Warning').Count
        Critical = @($Findings | Where-Object Status -eq 'Critical').Count
    }

    $payload = [pscustomobject]@{
        Generated=(Get-Date).ToString('o')
        Company=$Config.app.company
        AppVersion=$Config.app.version
        Customer=$Customer
        Computer=$env:COMPUTERNAME
        User=$env:USERNAME
        Score=$score
        ScoreLabel=$label
        Counts=$counts
        Findings=$Findings
    }
    $payload | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $jsonPath

    $rows = foreach($f in $Findings){
        $rec = [System.Web.HttpUtility]::HtmlEncode([string]$f.Recommendation)
        $summary = [System.Web.HttpUtility]::HtmlEncode([string]$f.Summary)
        $details = [System.Web.HttpUtility]::HtmlEncode([string]$f.Details) -replace "(`r`n|`n)",'<br>'
        $statusClass = ([string]$f.Status).ToLowerInvariant()
        "<tr><td>$($f.Category)</td><td>$($f.Name)</td><td><span class='badge $statusClass'>$($f.Status)</span></td><td>$summary<div class='details'>$details</div></td><td>$rec</td></tr>"
    }

    $html = @"
<!doctype html>
<html>
<head>
<meta charset='utf-8'>
<title>$($Config.app.name) Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f3f4f6;color:#111827}
.wrap{max-width:1180px;margin:32px auto;background:#fff;padding:34px;border-radius:12px;box-shadow:0 2px 16px rgba(0,0,0,.08)}
h1{margin:0}.meta{color:#6b7280;margin-top:6px}.scorecard{display:flex;align-items:center;gap:30px;margin:28px 0;padding:22px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:10px}
.score{font-size:52px;font-weight:800}.label{font-size:20px;font-weight:600}.counts{color:#4b5563;margin-top:5px}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid #e5e7eb;padding:10px;vertical-align:top}th{background:#f9fafb;text-align:left}
.badge{padding:3px 8px;border-radius:999px;font-weight:600;font-size:12px}.healthy{background:#dcfce7}.info{background:#e0f2fe}.recommend{background:#fef3c7}.warning{background:#fed7aa}.critical{background:#fee2e2}
.details{color:#6b7280;font-size:12px;margin-top:5px}footer{margin-top:30px;color:#6b7280;font-size:12px}
</style>
</head>
<body><div class='wrap'>
<h1>$($Config.app.company)</h1>
<div class='meta'>$($Config.app.name) v$($Config.app.version) | $env:COMPUTERNAME | $(Get-Date -Format 'dd MMMM yyyy HH:mm')</div>
<div class='scorecard'><div class='score'>$score/100</div><div><div class='label'>$label</div><div class='counts'>Healthy $($counts.Healthy) | Recommend $($counts.Recommend) | Warning $($counts.Warning) | Critical $($counts.Critical)</div></div></div>
<table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$($rows -join "`n")</tbody></table>
<footer>Scan-only diagnostic report. No automatic remediation was performed.</footer>
</div></body></html>
"@
    $html | Set-Content -Encoding UTF8 $htmlPath
    [pscustomobject]@{Json=$jsonPath;Html=$htmlPath;Score=$score;Label=$label}
}

Export-ModuleMember -Function Get-RBZHealthScore,Get-RBZScoreLabel,Export-RBZReport

