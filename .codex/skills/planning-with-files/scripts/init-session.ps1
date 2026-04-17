# Initialize planning files for a new session
# Usage: .\init-session.ps1 [project-name]

param(
    [string]$ProjectName = "project"
)

$DATE = Get-Date -Format "yyyy-MM-dd"

Write-Host "Initializing planning files for: $ProjectName"

$stateDir = ".state"
$taskPlanFile = Join-Path $stateDir "task_plan.md"
$findingsFile = Join-Path $stateDir "findings.md"
$progressFile = Join-Path $stateDir "progress.md"

if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
}

# Create .state/task_plan.md if it doesn't exist
if (-not (Test-Path $taskPlanFile)) {
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
- [ ] Document in .state/findings.md
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
"@ | Out-File -FilePath $taskPlanFile -Encoding UTF8
    Write-Host "Created $taskPlanFile"
} else {
    Write-Host "$taskPlanFile already exists, skipping"
}

# Create .state/findings.md if it doesn't exist
if (-not (Test-Path $findingsFile)) {
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
"@ | Out-File -FilePath $findingsFile -Encoding UTF8
    Write-Host "Created $findingsFile"
} else {
    Write-Host "$findingsFile already exists, skipping"
}

# Create .state/progress.md if it doesn't exist
if (-not (Test-Path $progressFile)) {
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
"@ | Out-File -FilePath $progressFile -Encoding UTF8
    Write-Host "Created $progressFile"
} else {
    Write-Host "$progressFile already exists, skipping"
}

Write-Host ""
Write-Host "Planning files initialized!"
Write-Host "Files: $taskPlanFile, $findingsFile, $progressFile"
