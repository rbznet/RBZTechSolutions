$ErrorActionPreference='Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$reportPath = Join-Path $repoRoot 'Modules\Report.psm1'
$configPath = Join-Path $repoRoot 'Config\settings.json'

if(-not(Test-Path $reportPath)){ throw "Report.psm1 not found: $reportPath" }
if(-not(Test-Path $configPath)){ throw "settings.json not found: $configPath" }

$text = Get-Content -Raw $reportPath

if($text -match 'RBZ080RC5B_CUSTOMER_SIMPLIFICATION'){
    Write-Host 'RBZ PC Health v0.8.0 RC5b customer-report patch already present.' -ForegroundColor Yellow
    exit 0
}
if($text -notmatch 'RBZ080RC5_REPORT_BRANDING'){
    throw 'RC5b expects the RC5 report-branding patch to be installed first.'
}

Copy-Item $reportPath "$reportPath.v080rc5b.bak" -Force

$marker='function ConvertTo-RBZHtmlRow {'
$helpers=@'
# RBZ080RC5B_CUSTOMER_SIMPLIFICATION
function Get-RBZCustomerFindingText {
    param($Finding)

    $name=[string]$Finding.Name
    $category=[string]$Finding.Category
    $status=[string]$Finding.Status
    $text=("{0} {1} {2} {3}" -f $Finding.Name,$Finding.Summary,$Finding.Details,$Finding.Recommendation).ToLowerInvariant()

    $summary=[string]$Finding.Summary
    $recommendation=[string]$Finding.Recommendation

    if($text -match 'code 28|drivers? .*not installed|missing driver'){
        $summary='A hardware device is missing its required driver.'
        $recommendation='Install the appropriate manufacturer driver.'
    }
    elseif($text -match 'application crash|application hang|crash history|faulting application|crash/hang'){
        $summary='Several applications have stopped unexpectedly recently, including repeated failures from the same application.'
        $recommendation='Further investigation is recommended if the crashes continue.'
    }
    elseif($name -match 'Secure Boot'){
        $summary='Secure Boot is currently disabled.'
        $recommendation='Consider enabling Secure Boot if supported by this PC.'
    }
    elseif($name -match 'BitLocker'){
        $summary='Device encryption is not currently protecting the Windows system drive.'
        $recommendation='Consider enabling device encryption and securely retaining the recovery information.'
    }
    elseif($category -eq 'Updates' -and $text -match 'fail'){
        $summary='Windows Update has recorded recent update-check failures.'
        $recommendation='Review Windows Update and retry the failed update check.'
    }
    elseif($category -eq 'Updates' -and $text -match 'pending'){
        $summary='Windows updates are waiting to be installed.'
        $recommendation='Install the available Windows updates and restart if requested.'
    }
    elseif($category -eq 'Storage' -and $status -in @('Warning','Critical')){
        $summary='A storage-related issue needs further review.'
        $recommendation='Review drive health and back up important data if the issue persists.'
    }
    elseif($category -eq 'Network' -and $status -in @('Warning','Critical')){
        $summary='A network connectivity or configuration issue was detected.'
        $recommendation='Check the network connection and configuration.'
    }
    elseif([string]::IsNullOrWhiteSpace($recommendation)){
        if($status -eq 'Recommend'){
            $recommendation='Review this recommendation with the technician.'
        } elseif($status -in @('Warning','Critical')){
            $recommendation='Further technician investigation is recommended.'
        }
    }

    [pscustomobject]@{Summary=$summary;Recommendation=$recommendation}
}

function Get-RBZCustomerCategorySummary {
    param([object[]]$Findings)

    $rank=@{'Healthy'=0;'Info'=0;'Recommend'=1;'Warning'=2;'Critical'=3}

    foreach($category in @('System','Storage','Security','Network','Devices','Battery','Startup','Updates')){
        $items=@($Findings | Where-Object Category -eq $category)
        if(-not $items.Count){ continue }

        $worst=$items |
            Sort-Object @{Expression={ if($rank.ContainsKey([string]$_.Status)){$rank[[string]$_.Status]}else{0} };Descending=$true} |
            Select-Object -First 1

        $customerStatus=switch([string]$worst.Status){
            'Critical'  {'Attention required'}
            'Warning'   {'Attention required'}
            'Recommend' {'Recommendation available'}
            default     {'Good'}
        }

        $message=switch($customerStatus){
            'Attention required'       {'One or more checks in this area need technician attention.'}
            'Recommendation available' {'This area is generally working, with one or more recommendations to consider.'}
            default                    {'No customer-actionable issues were detected in this area.'}
        }

        [pscustomobject]@{Category=$category;Status=$customerStatus;Message=$message}
    }
}

'@
if(-not $text.Contains($marker)){ throw 'RC5b patch failed: ConvertTo-RBZHtmlRow marker not found.' }
$text=$text.Replace($marker,$helpers+$marker)

$oldRow=@'
function ConvertTo-RBZHtmlRow {
    param($Finding,$Config,[string]$Audience='Customer')
    $rec=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Recommendation)
    $summary=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Summary)
    $details=ConvertTo-RBZCustomerDetails -Details ([string]$Finding.Details) -Config $Config -Audience $Audience
    $statusClass=([string]$Finding.Status).ToLowerInvariant()
    "<tr><td>$($Finding.Category)</td><td>$($Finding.Name)</td><td><span class='badge $statusClass'>$($Finding.Status)</span></td><td>$summary<div class='details'>$details</div></td><td>$rec</td></tr>"
}
'@
$newRow=@'
function ConvertTo-RBZHtmlRow {
    param($Finding,$Config,[string]$Audience='Customer')
    $statusClass=([string]$Finding.Status).ToLowerInvariant()

    if($Audience -eq 'Customer'){
        $plain=Get-RBZCustomerFindingText -Finding $Finding
        $rec=[System.Web.HttpUtility]::HtmlEncode([string]$plain.Recommendation)
        $summary=[System.Web.HttpUtility]::HtmlEncode([string]$plain.Summary)
        return "<tr><td>$($Finding.Category)</td><td>$($Finding.Name)</td><td><span class='badge $statusClass'>$($Finding.Status)</span></td><td>$summary</td><td>$rec</td></tr>"
    }

    $rec=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Recommendation)
    $summary=[System.Web.HttpUtility]::HtmlEncode([string]$Finding.Summary)
    $details=ConvertTo-RBZCustomerDetails -Details ([string]$Finding.Details) -Config $Config -Audience $Audience
    "<tr><td>$($Finding.Category)</td><td>$($Finding.Name)</td><td><span class='badge $statusClass'>$($Finding.Status)</span></td><td>$summary<div class='details'>$details</div></td><td>$rec</td></tr>"
}
'@
if(-not $text.Contains($oldRow)){ throw 'RC5b patch failed: HTML row function did not match expected RC5 content.' }
$text=$text.Replace($oldRow,$newRow)

$oldAttention=@'
    $attention=@($Findings | Where-Object Status -in @('Recommend','Warning','Critical'))
    $attentionRows=if($attention.Count){
        ($attention | ForEach-Object {ConvertTo-RBZHtmlRow $_ $Config $Audience}) -join "`n"
    }else{"<tr><td colspan='5'>No findings require attention.</td></tr>"}
'@
$newAttention=@'
    $attention=@($Findings | Where-Object Status -in @('Recommend','Warning','Critical'))
    $attentionRows=if($attention.Count){
        ($attention | ForEach-Object {ConvertTo-RBZHtmlRow $_ $Config $Audience}) -join "`n"
    }else{"<tr><td colspan='5'>No findings require attention.</td></tr>"}

    $customerCategorySummary=''
    if($Audience -eq 'Customer'){
        $categoryRows=foreach($s in @(Get-RBZCustomerCategorySummary -Findings $Findings)){
            $statusClass=if($s.Status -eq 'Attention required'){'warning'}elseif($s.Status -eq 'Recommendation available'){'recommend'}else{'healthy'}
            "<tr><td><strong>$($s.Category)</strong></td><td><span class='badge $statusClass'>$($s.Status)</span></td><td>$($s.Message)</td></tr>"
        }
        $customerCategorySummary=@"
<h2>Health Summary</h2>
<div class='sectionLead'>A simple overview of the main areas checked on this PC.</div>
<table class='customerSummaryTable'>
<thead><tr><th>Area</th><th>Result</th><th>Summary</th></tr></thead>
<tbody>$($categoryRows -join "`n")</tbody>
</table>
"@
    }
'@
if(-not $text.Contains($oldAttention)){ throw 'RC5b patch failed: attention-data marker not found.' }
$text=$text.Replace($oldAttention,$newAttention)

$oldGroup=@'
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
'@
$newGroup=@'
    $groupSections=@()
    if($Audience -eq 'Technician'){
        $groupSections=foreach($category in @('System','Storage','Security','Network','Devices','Battery','Startup','Updates')){
            $items=@($Findings | Where-Object Category -eq $category)
            if(-not $Config.report.showInfoFindings){
                $items=@($items | Where-Object Status -ne 'Info')
            }
            if($items.Count){
                $rows=($items|ForEach-Object{ConvertTo-RBZHtmlRow $_ $Config $Audience}) -join "`n"
                "<h2>$category</h2><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$rows</tbody></table>"
            }
        }
    }
'@
if(-not $text.Contains($oldGroup)){ throw 'RC5b patch failed: Diagnostic Results grouping marker not found.' }
$text=$text.Replace($oldGroup,$newGroup)

$oldBody=@'
$technicianWorkflowSection
<h2>Needs Attention</h2>
<div class='sectionLead'>Items below are the non-healthy findings that may require maintenance, investigation or repair.</div>
<div class='attentionBox'><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$attentionRows</tbody></table></div>
$comparisonSection
$verificationSection
$serviceSection
$scoreSection
<h2>Diagnostic Results</h2>
$($groupSections -join "`n")
'@
$newBody=@'
$technicianWorkflowSection
$customerCategorySummary
<h2>$(if($Audience -eq 'Customer'){'Issues & Recommendations'}else{'Needs Attention'})</h2>
<div class='sectionLead'>$(if($Audience -eq 'Customer'){'Only items that may need attention or a recommendation are shown below. Technical evidence is retained in the Technician Report.'}else{'Items below are the non-healthy findings that may require maintenance, investigation or repair.'})</div>
<div class='attentionBox'><table><thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Finding</th><th>Recommendation</th></tr></thead><tbody>$attentionRows</tbody></table></div>
$comparisonSection
$verificationSection
$serviceSection
$scoreSection
$(if($Audience -eq 'Technician'){"<h2>Diagnostic Results</h2>"}else{''})
$($groupSections -join "`n")
'@
if(-not $text.Contains($oldBody)){ throw 'RC5b patch failed: report-body marker not found.' }
$text=$text.Replace($oldBody,$newBody)

Set-Content -LiteralPath $reportPath -Value $text -Encoding UTF8

$oldRootPatch=Join-Path $repoRoot 'Apply-RC5.ps1'
if(Test-Path $oldRootPatch){
    Remove-Item -LiteralPath $oldRootPatch -Force
    Write-Host 'Removed old root-level Apply-RC5.ps1.' -ForegroundColor DarkGray
}

Write-Host 'RBZ PC Health v0.8.0 RC5b customer-report simplification applied.' -ForegroundColor Green
Write-Host 'Customer report simplified; Technician report keeps full technical detail.' -ForegroundColor Cyan
