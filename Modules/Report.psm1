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
    # RBZ080RC4B_CUSTOMER_SPACING
    $encoded=[System.Web.HttpUtility]::HtmlEncode($text)
    # RBZ080RC4C2_NORMALISE_CUSTOMER_DETAILS
    if($Audience -eq 'Customer'){
        $lines=@(
            $text -split "(`r`n|`n|`r)" |
            ForEach-Object {
                if($null -ne $_){ $_.TrimEnd() }
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
        )

        if($Config.report.hideHardwareSerialsInHtml){
            $lines=@($lines | Where-Object {
                $_ -notmatch '^\s*(Serial|Thumbprint)(\s+number)?:\s*'
            })
        }

        if($lines.Count -eq 0){ return '' }

        return (
            @($lines | ForEach-Object {
                [System.Web.HttpUtility]::HtmlEncode([string]$_)
            }) -join '<br>'
        )
    }
    $encoded -replace "(`r`n|`n)",'<br>'
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
        [object[]]$ServiceLog=@(),
        $BaselineSnapshot=$null,
        $CurrentSnapshot=$null
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
        TechnicianPriorities=$(if($Audience -eq 'Technician' -and (Get-Command Get-RBZPrioritizedFindings -ErrorAction SilentlyContinue)){
            $top=3
            try{$top=[int]$Config.priority.topTechnicianActions}catch{}
            @(Get-RBZPrioritizedFindings -Findings $Findings -Top $top)
        }else{@()})
        Findings=$Findings
        ServiceLog=$ServiceLog
        BaselineSnapshot=$BaselineSnapshot
        CurrentSnapshot=$CurrentSnapshot
        Comparison=$(if($BaselineSnapshot -and $CurrentSnapshot){Get-RBZComparisonSummary -Baseline $BaselineSnapshot -Current $CurrentSnapshot}else{$null})
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

    $verificationSection=''
    if($Config.remediation.includeRepairVerificationInReports -and $ServiceLog.Count){
        $verified=@($ServiceLog | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.VerificationStatus)})
        if($verified.Count){
            $verificationRows=foreach($v in $verified){
                $statusClass=([string]$v.VerificationStatus).ToLowerInvariant()
                $check=[System.Web.HttpUtility]::HtmlEncode([string]$v.VerificationCheck)
                $summary=[System.Web.HttpUtility]::HtmlEncode([string]$v.VerificationSummary)
                "<tr><td>$($v.VerificationCategory)</td><td>$check</td><td><span class='badge $statusClass'>$($v.VerificationStatus)</span></td><td>$summary</td><td>$($v.Name)</td></tr>"
            }
            $verificationSection="<h2>Repair Verification</h2><table><thead><tr><th>Category</th><th>Verification</th><th>Status</th><th>Result</th><th>Action</th></tr></thead><tbody>$($verificationRows -join "`n")</tbody></table>"
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

    $comparisonSection=''
    if($BaselineSnapshot -and $CurrentSnapshot -and $Config.session.includeComparisonInReports){
        $comparison=Get-RBZComparisonSummary -Baseline $BaselineSnapshot -Current $CurrentSnapshot
        $delta=[int]$comparison.ScoreChange
        $deltaText=if($delta -gt 0){"+$delta"}else{"$delta"}
        $deltaClass=if($delta -gt 0){'deltaGood'}elseif($delta -lt 0){'deltaBad'}else{'deltaNeutral'}
        $changeRows=foreach($c in @($comparison.Changes)){
            if($Audience -eq 'Customer' -and $c.Change -eq 'Updated'){continue}
            $before=[System.Web.HttpUtility]::HtmlEncode([string]$c.BeforeStatus)
            $after=[System.Web.HttpUtility]::HtmlEncode([string]$c.AfterStatus)
            $check=[System.Web.HttpUtility]::HtmlEncode([string]$c.Check)
            "<tr><td>$($c.Category)</td><td>$check</td><td>$before</td><td>$after</td><td>$($c.Change)</td></tr>"
        }
        $rowsText=if(@($changeRows).Count){$changeRows -join "`n"}else{"<tr><td colspan='5'>No material finding changes were detected between scans.</td></tr>"}
        $comparisonSection=@"
<h2>Before / After</h2>
<div class='compareCards'>
<div class='compareCard'><div class='compareLabel'>Before</div><div class='compareScore'>$($comparison.BaselineScore)/100</div></div>
<div class='compareArrow'>-&gt;</div>
<div class='compareCard'><div class='compareLabel'>After</div><div class='compareScore'>$($comparison.CurrentScore)/100</div></div>
<div class='compareCard'><div class='compareLabel'>Change</div><div class='compareScore $deltaClass'>$deltaText</div></div>
</div>
<div class='details'>Improved: $($comparison.Improved) | Worsened: $($comparison.Worsened) | New: $($comparison.New) | Removed: $($comparison.Removed)</div>
<table><thead><tr><th>Category</th><th>Check</th><th>Before</th><th>After</th><th>Change</th></tr></thead><tbody>$rowsText</tbody></table>
"@
    }

    $scoreSection=''
    if($Audience -eq 'Technician'){
        $breakdownRows=foreach($b in $breakdown){
            "<tr><td>$($b.Category)</td><td>$($b.Worst)</td><td>$($b.Awarded) / $($b.Weight)</td><td>-$($b.Deduction)</td></tr>"
        }
        $scoreSection="<div class='scoreExplain'><h2 style='margin-top:0'>Score Explanation</h2><table><thead><tr><th>Category</th><th>Worst status</th><th>Points</th><th>Deduction</th></tr></thead><tbody>$($breakdownRows -join "`n")</tbody></table></div>"
    }

    # RBZ080RC4_TECHNICIAN_WORKFLOW
    $technicianWorkflowSection=''

    if($Audience -eq 'Technician' -and (Get-Command Get-RBZPrioritizedFindings -ErrorAction SilentlyContinue)){
        $priorityTop=3
        try{$priorityTop=[int]$Config.priority.topTechnicianActions}catch{}
        if($priorityTop -lt 1){$priorityTop=3}

        $priorityItems=@(Get-RBZPrioritizedFindings -Findings $Findings -Top $priorityTop)

        $priorityRows=if($priorityItems.Count){
            foreach($p in $priorityItems){
                $priority=[System.Web.HttpUtility]::HtmlEncode([string]$p.Priority)
                $category=[System.Web.HttpUtility]::HtmlEncode([string]$p.Category)
                $name=[System.Web.HttpUtility]::HtmlEncode([string]$p.Name)
                $summary=[System.Web.HttpUtility]::HtmlEncode([string]$p.Summary)
                $reason=[System.Web.HttpUtility]::HtmlEncode([string]$p.Reason)
                $actionName=[System.Web.HttpUtility]::HtmlEncode([string]$p.ActionName)
                $actionText=[System.Web.HttpUtility]::HtmlEncode([string]$p.ActionText)
                $repairName=if([string]$p.ActionType -eq 'Repair Centre'){
                    "<div class='repairLink'>Repair Centre: $actionName</div>"
                }else{
                    "<div class='manualLink'>Manual: $actionName</div>"
                }

                "<tr><td><span class='priorityBadge priority$($p.Priority)'>$priority</span></td><td>$category</td><td><strong>$name</strong><div class='details'>$summary</div></td><td>$reason</td><td>$repairName<div class='details'>$actionText</div></td></tr>"
            }
        }else{
            "<tr><td colspan='5'>No priority technician actions were identified.</td></tr>"
        }

        $manualCandidates=[System.Collections.Generic.List[object]]::new()
        $repairCandidates=[System.Collections.Generic.List[object]]::new()

        foreach($f in @($Findings | Where-Object Status -in @('Recommend','Warning','Critical'))){
            $a=Get-RBZRecommendedAction -Finding $f
            $row=[pscustomobject]@{Finding=$f;Action=$a}

            if([string]$a.ActionType -eq 'Repair Centre'){
                $repairCandidates.Add($row)
            }else{
                $manualCandidates.Add($row)
            }
        }

        $repairRows=if($repairCandidates.Count){
            foreach($r in @($repairCandidates)){
                $f=$r.Finding
                $a=$r.Action
                $name=[System.Web.HttpUtility]::HtmlEncode([string]$f.Name)
                $category=[System.Web.HttpUtility]::HtmlEncode([string]$f.Category)
                $status=[System.Web.HttpUtility]::HtmlEncode([string]$f.Status)
                $actionName=[System.Web.HttpUtility]::HtmlEncode([string]$a.ActionName)
                $actionText=[System.Web.HttpUtility]::HtmlEncode([string]$a.ActionText)
                "<tr><td>$category</td><td>$name</td><td>$status</td><td><strong>$actionName</strong><div class='details'>$actionText</div></td></tr>"
            }
        }else{
            "<tr><td colspan='4'>No current findings map to an existing Repair Centre action.</td></tr>"
        }

        $manualRows=if($manualCandidates.Count){
            foreach($m in @($manualCandidates)){
                $f=$m.Finding
                $a=$m.Action
                $name=[System.Web.HttpUtility]::HtmlEncode([string]$f.Name)
                $category=[System.Web.HttpUtility]::HtmlEncode([string]$f.Category)
                $status=[System.Web.HttpUtility]::HtmlEncode([string]$f.Status)
                $actionName=[System.Web.HttpUtility]::HtmlEncode([string]$a.ActionName)
                $actionText=[System.Web.HttpUtility]::HtmlEncode([string]$a.ActionText)
                "<tr><td>$category</td><td>$name</td><td>$status</td><td><strong>$actionName</strong><div class='details'>$actionText</div></td></tr>"
            }
        }else{
            "<tr><td colspan='4'>No manual investigation items were identified.</td></tr>"
        }

        $infoItems=@($Findings | Where-Object Status -eq 'Info')
        $infoRows=if($infoItems.Count){
            foreach($f in $infoItems){
                $category=[System.Web.HttpUtility]::HtmlEncode([string]$f.Category)
                $name=[System.Web.HttpUtility]::HtmlEncode([string]$f.Name)
                $summary=[System.Web.HttpUtility]::HtmlEncode([string]$f.Summary)
                "<tr><td>$category</td><td>$name</td><td>$summary</td></tr>"
            }
        }else{
            "<tr><td colspan='3'>No informational findings were returned.</td></tr>"
        }

        $technicianWorkflowSection=@"
<section class='techWorkflow'>
<h2>Technician Workflow</h2>
<div class='workflowIntro'>Priorities are ranked from the diagnostic evidence. They do not alter the original finding status or the health score.</div>

<h3>Priority Actions</h3>
<table class='priorityTable'>
<thead><tr><th>Priority</th><th>Category</th><th>Finding</th><th>Why this priority</th><th>Recommended action</th></tr></thead>
<tbody>$($priorityRows -join "`n")</tbody>
</table>

<h3>Repair Centre Opportunities</h3>
<div class='workflowNote'>These findings map to an existing technician-approved Repair Centre action. RBZ PC Health still requires the technician to select and confirm the action in the application.</div>
<table>
<thead><tr><th>Category</th><th>Finding</th><th>Status</th><th>Repair Centre action</th></tr></thead>
<tbody>$($repairRows -join "`n")</tbody>
</table>

<h3>Manual Investigation</h3>
<div class='workflowNote'>These items intentionally remain manual because there is no sufficiently safe generic automated repair.</div>
<table>
<thead><tr><th>Category</th><th>Finding</th><th>Status</th><th>Technician action</th></tr></thead>
<tbody>$($manualRows -join "`n")</tbody>
</table>

<details class='infoSection'>
<summary>Informational Findings ($($infoItems.Count))</summary>
<table>
<thead><tr><th>Category</th><th>Check</th><th>Summary</th></tr></thead>
<tbody>$($infoRows -join "`n")</tbody>
</table>
</details>
</section>
"@
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
.compareCards{display:flex;gap:14px;align-items:center;margin:14px 0}.compareCard{padding:14px 18px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:9px;min-width:120px}.compareLabel{font-size:11px;color:#6b7280;text-transform:uppercase}.compareScore{font-size:27px;font-weight:800;margin-top:3px}.compareArrow{font-size:24px;color:#6b7280}.deltaGood{color:#15803d}.deltaBad{color:#b91c1c}.deltaNeutral{color:#374151}
.techWorkflow{margin:26px 0;padding:18px;border:1px solid #dbeafe;background:#f8fbff;border-radius:10px}
.techWorkflow h2{margin-top:0}.techWorkflow h3{margin:24px 0 8px}
.workflowIntro,.workflowNote{color:#4b5563;font-size:13px;margin:5px 0 12px}
.priorityBadge{display:inline-block;padding:4px 9px;border-radius:999px;font-size:11px;font-weight:700}
.priorityUrgent{background:#fee2e2;color:#991b1b}.priorityHigh{background:#ffedd5;color:#9a3412}.priorityMedium{background:#fef3c7;color:#854d0e}.priorityInformational{background:#e0f2fe;color:#075985}
.repairLink{font-weight:700;color:#1d4ed8}.manualLink{font-weight:700;color:#374151}
.infoSection{margin-top:22px;border:1px solid #e5e7eb;border-radius:8px;padding:10px 14px;background:#fff}
.infoSection summary{cursor:pointer;font-weight:700}
/* RBZ080RC4B_CUSTOMER_SPACING */
.customerReport .wrap{padding:26px 32px}
.customerReport .job{margin-bottom:18px}
.customerReport .scorecard{margin:18px 0 24px;padding:20px}
.customerReport h2{margin-top:26px;margin-bottom:12px}
.customerReport table{margin-bottom:16px}
.customerReport th,.customerReport td{padding:9px 10px;line-height:1.35}
.customerReport .attentionBox{padding:14px}
.customerReport .details{display:block;white-space:normal;line-height:1.35;margin-top:5px;margin-bottom:0}
.customerReport .details:empty{display:none}
.customerReport .badge{line-height:1.2}
.customerReport .compareCards{margin:12px 0}
.customerReport .scoreExplain{margin-top:18px}
.customerReport footer{margin-top:28px}
footer{margin-top:34px;padding-top:16px;border-top:1px solid #e5e7eb;color:#6b7280;font-size:12px}
@media print{body{background:#fff}.wrap{box-shadow:none;margin:0;max-width:none}.top{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style></head><body class='$(if($Audience -eq "Customer"){"customerReport"}else{"technicianReport"})'>
<div class='top'><h1>$($Config.app.company)</h1><div class='sub'>$($Config.app.name) | $Audience Report | v$($Config.app.version)</div></div>
<div class='wrap'>
<div class='job'>
<div class='jobbox'><div class='joblabel'>Customer</div><div class='jobvalue'>$customerDisplay</div></div>
<div class='jobbox'><div class='joblabel'>Device</div><div class='jobvalue'>$env:COMPUTERNAME</div></div>
<div class='jobbox'><div class='joblabel'>Job Reference</div><div class='jobvalue'>$jobDisplay</div></div>
<div class='jobbox'><div class='joblabel'>Scan ID</div><div class='jobvalue'>$scanId</div></div>
</div>
<div class='scorecard'><div class='score'>$score/100</div><div><div class='label'>$label</div><div class='counts'>Healthy $($counts.Healthy) | Recommend $($counts.Recommend) | Warning $($counts.Warning) | Critical $($counts.Critical)</div></div></div>
$technicianWorkflowSection
<h2>Needs Attention</h2><div class='attentionBox'><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$attentionRows</tbody></table></div>
$comparisonSection
$verificationSection
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



