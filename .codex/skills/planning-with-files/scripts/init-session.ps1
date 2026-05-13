# Initialize planning files for a new Codex session
# Usage: .\init-session.ps1 [-Template TYPE] [project-name]
# Templates: default, analytics

param(
    [string]$ProjectName = "project",
    [string]$Template = "default"
)

$DATE = Get-Date -Format "yyyy-MM-dd"

# Resolve template directory (skill root is one level up from scripts/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillRoot = Split-Path -Parent $ScriptDir
$TemplateDir = Join-Path $SkillRoot "templates"

Write-Host "Initializing planning files for: $ProjectName (template: $Template)"

# Validate template
if ($Template -ne "default" -and $Template -ne "analytics") {
    Write-Host "Unknown template: $Template (available: default, analytics). Using default."
    $Template = "default"
}

$StateDir = ".state"
$TaskPlanFile = Join-Path $StateDir "task_plan.md"
$FindingsFile = Join-Path $StateDir "findings.md"
$ProgressFile = Join-Path $StateDir "progress.md"

if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir | Out-Null
}

# Create .state/task_plan.md if it doesn't exist
if (-not (Test-Path $TaskPlanFile)) {
    $AnalyticsPlan = Join-Path $TemplateDir "analytics_task_plan.md"
    if ($Template -eq "analytics" -and (Test-Path $AnalyticsPlan)) {
        Copy-Item $AnalyticsPlan $TaskPlanFile
    } else {
        @"
# Task Plan: [Brief Description]

## Goal
[One sentence describing the end state]

## Current Phase
Phase 1

## Phases

### Phase 1: Requirements & Discovery
- [ ] Understand user intent
- [ ] Identify constraints
- [ ] Document in findings.md
- **Status:** in_progress

### Phase 2: Planning & Structure
- [ ] Define approach
- [ ] Create project structure
- **Status:** pending

### Phase 3: Implementation
- [ ] Execute the plan
- [ ] Write to files before executing
- **Status:** pending

### Phase 4: Testing & Verification
- [ ] Verify requirements met
- [ ] Document test results
- **Status:** pending

### Phase 5: Delivery
- [ ] Review outputs
- [ ] Deliver to user
- **Status:** pending

## Decisions Made
| Decision | Rationale |
|----------|-----------|

## Errors Encountered
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $TaskPlanFile -Encoding UTF8
    }
    Write-Host "Created $TaskPlanFile"
} else {
    Write-Host "$TaskPlanFile already exists, skipping"
}

# Create .state/findings.md if it doesn't exist
if (-not (Test-Path $FindingsFile)) {
    $AnalyticsFindings = Join-Path $TemplateDir "analytics_findings.md"
    if ($Template -eq "analytics" -and (Test-Path $AnalyticsFindings)) {
        Copy-Item $AnalyticsFindings $FindingsFile
    } else {
        @"
# Findings & Decisions

## Requirements
-

## Research Findings
-

## Technical Decisions
| Decision | Rationale |
|----------|-----------|

## Issues Encountered
| Issue | Resolution |
|-------|------------|

## Resources
-
"@ | Out-File -FilePath $FindingsFile -Encoding UTF8
    }
    Write-Host "Created $FindingsFile"
} else {
    Write-Host "$FindingsFile already exists, skipping"
}

# Create .state/progress.md if it doesn't exist
if (-not (Test-Path $ProgressFile)) {
    if ($Template -eq "analytics") {
        @"
# Progress Log

## Session: $DATE

### Current Status
- **Phase:** 1 - Data Discovery
- **Started:** $DATE

### Actions Taken
-

### Query Log
| Query | Result Summary | Interpretation |
|-------|---------------|----------------|

### Errors
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $ProgressFile -Encoding UTF8
    } else {
        @"
# Progress Log

## Session: $DATE

### Current Status
- **Phase:** 1 - Requirements & Discovery
- **Started:** $DATE

### Actions Taken
-

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|

### Errors
| Error | Resolution |
|-------|------------|
"@ | Out-File -FilePath $ProgressFile -Encoding UTF8
    }
    Write-Host "Created $ProgressFile"
} else {
    Write-Host "$ProgressFile already exists, skipping"
}

Write-Host ""
Write-Host "Planning files initialized!"
Write-Host "Files: $TaskPlanFile, $FindingsFile, $ProgressFile"
