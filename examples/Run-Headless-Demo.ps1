<#
.SYNOPSIS
    T-IA Copilot — Headless Demo Blueprint
    GenAI Zürich Hackathon 2026

.DESCRIPTION
    This script demonstrates the full headless workflow:
    1. Launches T-IA Connect in headless mode (no GUI)
    2. Waits for the API to be ready
    3. Opens a TIA Portal project silently
    4. Generates a PLC block from a natural language description
    5. Compiles the block
    6. Cleans up

.NOTES
    Prerequisites:
    - T-IA Connect installed (TiaPortalApi.App.exe)
    - Siemens TIA Portal V17-V20 installed
    - A valid TIA Portal project file (.ap17/.ap18/.ap19/.ap20)
#>

param(
    [string]$TiaConnectPath = "C:\Program Files\FeelAutomCorp\TiaConnect\TiaPortalApi.App.exe",
    [string]$ProjectPath    = "C:\Projects\WaterPlant.ap20",
    [string]$ApiKey         = "your-api-key",
    [string]$BaseUrl        = "http://localhost:9000"
)

$Headers = @{
    "X-API-Key"    = $ApiKey
    "Content-Type" = "application/json"
}

# ── Step 1: Launch T-IA Connect in headless mode ────────────────────────
Write-Host "Starting T-IA Connect in headless mode..." -ForegroundColor Cyan
$process = Start-Process -FilePath $TiaConnectPath -ArgumentList "--headless" -PassThru -WindowStyle Hidden

# ── Step 2: Wait for API readiness ──────────────────────────────────────
Write-Host "Waiting for API to be ready..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $health = Invoke-RestMethod -Method GET -Uri "$BaseUrl/api/health" -Headers $Headers -ErrorAction Stop
        if ($health.Success) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 2 }
}
if (-not $ready) { Write-Error "API did not start in time."; exit 1 }
Write-Host "API is ready at $BaseUrl" -ForegroundColor Green

# ── Step 3: Open TIA Portal project (headless, no GUI) ──────────────────
Write-Host "Opening TIA Portal project: $ProjectPath" -ForegroundColor Cyan
$openResult = Invoke-RestMethod -Method POST -Uri "$BaseUrl/api/projects/open" `
    -Headers $Headers `
    -Body (@{ projectPath = $ProjectPath } | ConvertTo-Json)
Write-Host "Project opened: $($openResult.Data.Name)" -ForegroundColor Green

# ── Step 4: Generate a PLC block from natural language ──────────────────
Write-Host "Generating FB_WaterPump from natural language..." -ForegroundColor Cyan
$generateBody = @{
    deviceName  = "PLC_1"
    blockType   = "FB"
    blockName   = "FB_WaterPump"
    description = "Water pump control with Start/Stop logic, thermal fault alarm (TON timer 5s), and Manual/Auto mode selection"
    language    = "SCL"
} | ConvertTo-Json

$genResult = Invoke-RestMethod -Method POST -Uri "$BaseUrl/api/blocks/generate" `
    -Headers $Headers -Body $generateBody
Write-Host "Block generated and imported: $($genResult.Data.BlockName)" -ForegroundColor Green

# ── Step 5: Compile the block ───────────────────────────────────────────
Write-Host "Compiling FB_WaterPump..." -ForegroundColor Cyan
$compileBody = @{
    deviceName = "PLC_1"
    blockName  = "FB_WaterPump"
} | ConvertTo-Json

$compileResult = Invoke-RestMethod -Method POST -Uri "$BaseUrl/api/blocks/compile" `
    -Headers $Headers -Body $compileBody
Write-Host "Compilation result: $($compileResult.Message)" -ForegroundColor Green

# ── Step 6: Cleanup ─────────────────────────────────────────────────────
Write-Host "Demo complete. Stopping T-IA Connect..." -ForegroundColor Cyan
$process | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Done!" -ForegroundColor Green
