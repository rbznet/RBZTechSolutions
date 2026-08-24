function New-RBZScanSnapshot {
    param(
        [Parameter(Mandatory)][object[]]$Findings,
        [Parameter(Mandatory)]$Config,
        [int]$Sequence = 1
    )

    $score = Get-RBZHealthScore -Findings $Findings -Config $Config
    $label = Get-RBZScoreLabel -Score $score

    [pscustomobject]@{
        Sequence = $Sequence
        Timestamp = Get-Date
        Score = $score
        Label = $label
        Healthy = @($Findings | Where-Object Status -eq 'Healthy').Count
        Info = @($Findings | Where-Object Status -eq 'Info').Count
        Recommend = @($Findings | Where-Object Status -eq 'Recommend').Count
        Warning = @($Findings | Where-Object Status -eq 'Warning').Count
        Critical = @($Findings | Where-Object Status -eq 'Critical').Count
        Findings = @($Findings)
    }
}

function Compare-RBZFindingSets {
    param(
        [Parameter(Mandatory)][object[]]$Before,
        [Parameter(Mandatory)][object[]]$After
    )

    $rank = @{'Healthy'=0;'Info'=0;'Recommend'=1;'Warning'=2;'Critical'=3}
    $beforeMap=@{}
    foreach($f in $Before){$beforeMap["$($f.Category)|$($f.Name)"]=$f}
    $afterMap=@{}
    foreach($f in $After){$afterMap["$($f.Category)|$($f.Name)"]=$f}
    $keys=@($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    $changes=[System.Collections.Generic.List[object]]::new()

    foreach($key in $keys){
        $b=$beforeMap[$key]; $a=$afterMap[$key]
        if($null -eq $b -and $null -ne $a){
            $changes.Add([pscustomobject]@{Category=$a.Category;Check=$a.Name;BeforeStatus='Not present';AfterStatus=$a.Status;Change='New';BeforeSummary='';AfterSummary=$a.Summary}); continue
        }
        if($null -ne $b -and $null -eq $a){
            $changes.Add([pscustomobject]@{Category=$b.Category;Check=$b.Name;BeforeStatus=$b.Status;AfterStatus='Not present';Change='Removed';BeforeSummary=$b.Summary;AfterSummary=''}); continue
        }
        $br=if($rank.ContainsKey([string]$b.Status)){$rank[[string]$b.Status]}else{0}
        $ar=if($rank.ContainsKey([string]$a.Status)){$rank[[string]$a.Status]}else{0}
        if($br -gt $ar){$change='Improved'}
        elseif($br -lt $ar){$change='Worsened'}
        elseif([string]$b.Status -ne [string]$a.Status){$change='Changed'}
        elseif([string]$b.Summary -ne [string]$a.Summary){$change='Updated'}
        else{continue}
        $changes.Add([pscustomobject]@{Category=$a.Category;Check=$a.Name;BeforeStatus=$b.Status;AfterStatus=$a.Status;Change=$change;BeforeSummary=$b.Summary;AfterSummary=$a.Summary})
    }
    return @($changes)
}

function Get-RBZComparisonSummary {
    param([Parameter(Mandatory)]$Baseline,[Parameter(Mandatory)]$Current)
    $changes=@(Compare-RBZFindingSets -Before $Baseline.Findings -After $Current.Findings)
    [pscustomobject]@{
        BaselineScore=[int]$Baseline.Score
        CurrentScore=[int]$Current.Score
        ScoreChange=[int]$Current.Score-[int]$Baseline.Score
        BaselineTime=$Baseline.Timestamp
        CurrentTime=$Current.Timestamp
        Improved=@($changes|Where-Object Change -eq 'Improved').Count
        Worsened=@($changes|Where-Object Change -eq 'Worsened').Count
        New=@($changes|Where-Object Change -eq 'New').Count
        Removed=@($changes|Where-Object Change -eq 'Removed').Count
        Updated=@($changes|Where-Object Change -in @('Updated','Changed')).Count
        Changes=$changes
    }
}

Export-ModuleMember -Function New-RBZScanSnapshot,Compare-RBZFindingSets,Get-RBZComparisonSummary
