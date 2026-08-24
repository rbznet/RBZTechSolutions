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
        if($items.Count -eq 0){$total += $weight;continue}
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

function Get-RBZCategoryBreakdown {
    param([object[]]$Findings,$Config)

    $weights = $Config.scoring.categoryWeights
    $factors = $Config.scoring.statusFactors
    $statusRank = @{ 'Healthy'=0; 'Info'=0; 'Recommend'=1; 'Warning'=2; 'Critical'=3 }

    foreach($prop in $weights.PSObject.Properties){
        $category=$prop.Name
        $weight=[double]$prop.Value
        $items=@($Findings | Where-Object Category -eq $category)
        if($items.Count -eq 0){
            [pscustomobject]@{Category=$category;Weight=$weight;Worst='Not assessed';Awarded=$weight;Deduction=0}
            continue
        }
        $worst=$items | Sort-Object @{Expression={$statusRank[$_.Status]};Descending=$true} | Select-Object -First 1
        $factorProp=$factors.PSObject.Properties[$worst.Status]
        $factor=if($null -ne $factorProp){[double]$factorProp.Value}else{1.0}
        $awarded=[math]::Round($weight*$factor,1)
        [pscustomobject]@{Category=$category;Weight=$weight;Worst=$worst.Status;Awarded=$awarded;Deduction=[math]::Round($weight-$awarded,1)}
    }
}

function ConvertTo-RBZCustomerDetails {
    param([string]$Details,$Config,[string]$Audience='Customer')
    if([string]::IsNullOrWhiteSpace($Details)){return ''}
    $text=$Details
    if($Audience -eq 'Customer' -and $Config.report.hideHardwareSerialsInHtml){
        $lines=$text -split "(`r`n|`n)"
        $lines=@($lines | Where-Object {$_ -notmatch '^\s*(Serial|Thumbprint)(\s+number)?:\s*'})
        $text=$lines -join "`n"
    }
    [System.Web.HttpUtility]::HtmlEncode($text) -replace "(`r`n|`n)",'<br>'
}

function ConvertTo-RBZHtmlRow {
    param($Finding,$Config,[string]$Audience='Customer')
    $rec=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Recommendation)
    $summary=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Summary)
    $details=ConvertTo-RBZCustomerDetails -Details ([string]$Finding.Details) -Config $Config -Audience $Audience
    $statusClass=([string]$Finding.Status).ToLowerInvariant()
    "<tr><td>$($Finding.Category)</td><td>$($Finding.Name)</td><td><span class='badge $statusClass'>$($Finding.Status)</span></td><td>$summary<div class='details'>$details</div></td><td>$rec</td></tr>"
}

function Export-RBZReport {
    param(
        [object[]]$Findings,
        $Config,
        [string]$ReportsPath,
        [string]$Customer='',
        [string]$JobReference='',
        [ValidateSet('Customer','Technician')][string]$Audience='Customer',
        [object[]]$ServiceLog=@()
    )

    Add-Type -AssemblyName System.Web
    if(-not(Test-Path $ReportsPath)){New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null}

    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $scanId="RBZ-$(Get-Date -Format 'yyyyMMdd')-$(([guid]::NewGuid().ToString('N').Substring(0,6)).ToUpperInvariant())"
    $safeCustomer=if($Customer){($Customer -replace '[^a-zA-Z0-9_-]','-')}else{'Customer'}
    $suffix=if($Audience -eq 'Technician'){'TECH'}else{'CUSTOMER'}
    $base="$($Config.app.reportPrefix)-$safeCustomer-$env:COMPUTERNAME-$stamp-$suffix"
    $jsonPath=Join-Path $ReportsPath "$base.json"
    $htmlPath=Join-Path $ReportsPath "$base.html"

    $score=Get-RBZHealthScore -Findings $Findings -Config $Config
    $label=Get-RBZScoreLabel -Score $score
    $breakdown=@(Get-RBZCategoryBreakdown -Findings $Findings -Config $Config)
    $counts=@{
        Healthy=@($Findings|Where-Object Status -eq 'Healthy').Count
        Info=@($Findings|Where-Object Status -eq 'Info').Count
        Recommend=@($Findings|Where-Object Status -eq 'Recommend').Count
        Warning=@($Findings|Where-Object Status -eq 'Warning').Count
        Critical=@($Findings|Where-Object Status -eq 'Critical').Count
    }

    $payload=[pscustomobject]@{
        Generated=(Get-Date).ToString('o')
        ScanId=$scanId
        JobReference=$JobReference
        Audience=$Audience
        Company=$Config.app.company
        AppVersion=$Config.app.version
        Customer=$Customer
        Computer=$env:COMPUTERNAME
        User=$env:USERNAME
        Score=$score
        ScoreLabel=$label
        Counts=$counts
        CategoryBreakdown=$breakdown
        Findings=$Findings
        ServiceLog=$ServiceLog
    }
    $payload | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $jsonPath

    $attention=@($Findings | Where-Object Status -in @('Recommend','Warning','Critical'))
    $attentionRows=if($attention.Count){
        ($attention | ForEach-Object {ConvertTo-RBZHtmlRow $_ $Config $Audience}) -join "`n"
    }else{"<tr><td colspan='5'>No findings require attention.</td></tr>"}

    $groupSections=foreach($category in @('System','Storage','Security','Network','Devices','Battery','Startup','Updates')){
        $items=@($Findings | Where-Object Category -eq $category)
        if($Audience -eq 'Customer'){
            $items=@($items | Where-Object Status -ne 'Info')
        } elseif(-not $Config.report.showInfoFindings){
            $items=@($items | Where-Object Status -ne 'Info')
        }
        if($items.Count){
            $rows=($items|ForEach-Object{ConvertTo-RBZHtmlRow $_ $Config $Audience}) -join "`n"
            "<h2>$category</h2><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$rows</tbody></table>"
        }
    }

    $serviceSection=''
    if($ServiceLog.Count){
        $serviceRows=foreach($a in $ServiceLog){
            $status=if($a.Success){'Completed'}else{'Failed'}
            $details=[System.Web.HttpUtility]::HtmlEncode([string]$a.Summary)
            "<tr><td>$($a.Id)</td><td>$status</td><td>$details</td><td>$($a.Started)</td></tr>"
        }
        $serviceSection="<h2>Service Actions Performed</h2><table><thead><tr><th>Action</th><th>Result</th><th>Summary</th><th>Started</th></tr></thead><tbody>$($serviceRows -join "`n")</tbody></table>"
    }

    $scoreSection=''
    if($Audience -eq 'Technician'){
        $breakdownRows=foreach($b in $breakdown){
            "<tr><td>$($b.Category)</td><td>$($b.Worst)</td><td>$($b.Awarded) / $($b.Weight)</td><td>-$($b.Deduction)</td></tr>"
        }
        $scoreSection="<div class='scoreExplain'><h2 style='margin-top:0'>Score Explanation</h2><table><thead><tr><th>Category</th><th>Worst status</th><th>Points</th><th>Deduction</th></tr></thead><tbody>$($breakdownRows -join "`n")</tbody></table></div>"
    }

    $customerDisplay=if([string]::IsNullOrWhiteSpace($Customer)){'Not supplied'}else{[System.Web.HttpUtility]::HtmlEncode($Customer)}
    $jobDisplay=if([string]::IsNullOrWhiteSpace($JobReference)){'Not supplied'}else{[System.Web.HttpUtility]::HtmlEncode($JobReference)}
    $brandAccent=[string]$Config.branding.accent
    $site=[System.Web.HttpUtility]::HtmlEncode([string]$Config.branding.website)
    $email=[System.Web.HttpUtility]::HtmlEncode([string]$Config.branding.supportEmail)

    $html=@"
<!doctype html><html><head><meta charset='utf-8'><title>$($Config.app.name) Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f3f4f6;color:#111827}
.top{background:$brandAccent;color:#fff;padding:28px 34px}.top h1{margin:0;font-size:28px}.top .sub{opacity:.8;margin-top:4px}
.wrap{max-width:1180px;margin:0 auto 32px;background:#fff;padding:30px 34px;box-shadow:0 2px 16px rgba(0,0,0,.08)}
.job{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:0 0 22px}.jobbox{padding:12px 14px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px}.joblabel{color:#6b7280;font-size:10px;text-transform:uppercase}.jobvalue{font-weight:600;margin-top:3px}
.scorecard{display:flex;align-items:center;gap:30px;margin:20px 0;padding:22px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:10px}.score{font-size:52px;font-weight:800}.label{font-size:20px;font-weight:600}.counts{color:#4b5563;margin-top:5px}
h2{margin-top:32px}table{border-collapse:collapse;width:100%;font-size:13px;margin-bottom:18px}th,td{border-bottom:1px solid #e5e7eb;padding:10px;vertical-align:top}th{background:#f9fafb;text-align:left}
.badge{padding:3px 8px;border-radius:999px;font-weight:600;font-size:12px}.healthy{background:#dcfce7}.info{background:#e0f2fe}.recommend{background:#fef3c7}.warning{background:#fed7aa}.critical{background:#fee2e2}
.details{color:#6b7280;font-size:12px;margin-top:5px}.attentionBox{border:1px solid #fed7aa;background:#fffaf5;border-radius:10px;padding:16px}.scoreExplain{border:1px solid #e5e7eb;border-radius:10px;padding:16px;margin-top:20px}
footer{margin-top:34px;padding-top:16px;border-top:1px solid #e5e7eb;color:#6b7280;font-size:12px}
@media print{body{background:#fff}.wrap{box-shadow:none;margin:0;max-width:none}.top{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style></head><body>
<div class='top'><h1>$($Config.app.company)</h1><div class='sub'>$($Config.app.name) | $Audience Report | v$($Config.app.version)</div></div>
<div class='wrap'>
<div class='job'>
<div class='jobbox'><div class='joblabel'>Customer</div><div class='jobvalue'>$customerDisplay</div></div>
<div class='jobbox'><div class='joblabel'>Device</div><div class='jobvalue'>$env:COMPUTERNAME</div></div>
<div class='jobbox'><div class='joblabel'>Job Reference</div><div class='jobvalue'>$jobDisplay</div></div>
<div class='jobbox'><div class='joblabel'>Scan ID</div><div class='jobvalue'>$scanId</div></div>
</div>
<div class='scorecard'><div class='score'>$score/100</div><div><div class='label'>$label</div><div class='counts'>Healthy $($counts.Healthy) | Recommend $($counts.Recommend) | Warning $($counts.Warning) | Critical $($counts.Critical)</div></div></div>
<h2>Needs Attention</h2><div class='attentionBox'><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$attentionRows</tbody></table></div>
$serviceSection
$scoreSection
<h2>Diagnostic Results</h2>
$($groupSections -join "`n")
<footer>$($Config.app.company) | $site | $email<br>Report generated $(Get-Date -Format 'dd MMMM yyyy HH:mm'). RBZ PC Health only records actions explicitly selected by the technician.</footer>
</div></body></html>
"@

    $html|Set-Content -Encoding UTF8 $htmlPath
    [pscustomobject]@{Json=$jsonPath;Html=$htmlPath;Score=$score;Label=$label;ScanId=$scanId}
}

Export-ModuleMember -Function Get-RBZHealthScore,Get-RBZScoreLabel,Get-RBZCategoryBreakdown,Export-RBZReport
