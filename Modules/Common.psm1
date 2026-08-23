Set-StrictMode -Version Latest

function ConvertTo-RBZStatus {
    param([ValidateSet('Healthy','Warning','Critical','Info')][string]$State)
    [pscustomobject]@{ State = $State }
}

function Get-RBZConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Configuration file not found: $Path" }
    Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Resolve-RBZPath {
    param([Parameter(Mandatory)][string]$BasePath,[Parameter(Mandatory)][string]$ConfiguredPath)
    $expanded = [Environment]::ExpandEnvironmentVariables($ConfiguredPath)
    if ([IO.Path]::IsPathRooted($expanded)) { return [IO.Path]::GetFullPath($expanded) }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $expanded))
}

function New-RBZFinding {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Healthy','Warning','Critical','Info')][string]$Status,
        [Parameter(Mandatory)][string]$Summary,
        [object]$Value = $null,
        [string]$Recommendation = ''
    )
    [pscustomobject]@{
        Category = $Category
        Name = $Name
        Status = $Status
        Summary = $Summary
        Value = $Value
        Recommendation = $Recommendation
    }
}

Export-ModuleMember -Function Get-RBZConfig,Resolve-RBZPath,New-RBZFinding
