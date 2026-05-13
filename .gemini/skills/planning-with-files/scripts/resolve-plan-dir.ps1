# planning-with-files: resolve active plan directory (PowerShell mirror).
#
# Resolution order matches scripts/resolve-plan-dir.sh:
#   1. $env:PLAN_ID -> .\.planning\$PLAN_ID\ if it contains task_plan.md
#   2. .\.planning\.active_plan content if it contains task_plan.md
#   3. Newest .\.planning\<dir>\ with task_plan.md by LastWriteTime
#   4. Empty (legacy fallback to .\task_plan.md handled by caller)

param(
    [string]$PlanRoot = (Join-Path (Get-Location) ".planning")
)

$activeFile = Join-Path $PlanRoot ".active_plan"

function Test-ValidPlanId {
    param([string]$PlanId)
    if ([string]::IsNullOrWhiteSpace($PlanId)) { return $false }
    if ($PlanId.StartsWith(".")) { return $false }
    if ($PlanId.Contains("/") -or $PlanId.Contains("\")) { return $false }
    if ($PlanId.Contains("..")) { return $false }
    return $true
}

function Test-PlanDir {
    param([string]$Path)
    return (Test-Path $Path -PathType Container) -and (Test-Path (Join-Path $Path "task_plan.md") -PathType Leaf)
}

if ($env:PLAN_ID) {
    $candidate = Join-Path $PlanRoot $env:PLAN_ID
    if ((Test-ValidPlanId $env:PLAN_ID) -and (Test-PlanDir $candidate)) {
        Write-Output $candidate
        exit 0
    }
}

if (Test-Path $activeFile) {
    $planId = (Get-Content $activeFile -Raw).Trim()
    if (Test-ValidPlanId $planId) {
        $candidate = Join-Path $PlanRoot $planId
        if (Test-PlanDir $candidate) {
            Write-Output $candidate
            exit 0
        }
    }
}

if (Test-Path $PlanRoot -PathType Container) {
    $latest = Get-ChildItem -Path $PlanRoot -Directory |
        Where-Object { -not $_.Name.StartsWith('.') } |
        Where-Object { Test-Path (Join-Path $_.FullName "task_plan.md") -PathType Leaf } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) {
        Write-Output $latest.FullName
    }
}

exit 0
