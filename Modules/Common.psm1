Set-StrictMode -Version Latest

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
        [Parameter(Mandatory)][ValidateSet('Healthy','Info','Recommend','Warning','Critical')][string]$Status,
        [Parameter(Mandatory)][string]$Summary,
        [object]$Value = $null,
        [string]$Details = '',
        [string]$Recommendation = '',
        [bool]$CanRemediate = $false,
        [string]$RemediationId = ''
    )
    [pscustomobject]@{
        Category = $Category
        Name = $Name
        Status = $Status
        Summary = $Summary
        Details = $Details
        Value = $Value
        Recommendation = $Recommendation
        CanRemediate = $CanRemediate
        RemediationId = $RemediationId
    }
}

Export-ModuleMember -Function Get-RBZConfig,Resolve-RBZPath,New-RBZFinding
