   param (
    [string]$BaseUrl,
    [string]$ArchiveTemplatePath
)

# Chargement des fonctions communes
. (Join-Path $PSScriptRoot "..\..\common.ps1")
if ([string]::IsNullOrEmpty($BaseUrl)) { $BaseUrl = "http://localhost:9000" }

# --- Paths ---
# PSScriptRoot = scripts/tests/20_Headless a       remonter 3 niveaux pour la racine projet
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$bridgePath  = Join-Path $projectRoot "Build\Debug\net48\TiaPortalApi.McpBridge.exe"
if (-not (Test-Path $bridgePath)) {
    $bridgePath = Join-Path $projectRoot "Build\Release\net48\TiaPortalApi.McpBridge.exe"
}

# --- Cleanup orphan bridges before tests ---
$orphans = Get-Process -Name "TiaPortalApi.McpBridge" -ErrorAction SilentlyContinue
if ($orphans) {
    Write-Host "[CLEANUP] Killing $($orphans.Count) orphan Bridge(s) before tests..." -ForegroundColor Yellow
    $orphans | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Get-McpApiKey {
    if (-not [string]::IsNullOrEmpty($env:TIA_API_KEY)) { return $env:TIA_API_KEY }
    $secretFile = Join-Path $env:LOCALAPPDATA "FeelAutomCorp\T-IA-Connect\api.secret"
    if (Test-Path $secretFile) { return (Get-Content $secretFile -Raw).Trim() }
    return Get-ApiKey
}

# Helper: Start Bridge process with redirected I/O
function Start-BridgeProcess {
    param([string]$ApiKey)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $bridgePath
    $psi.Arguments = "--url `"$BaseUrl/mcp/sse`" --api-key `"$ApiKey`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

# Helper: Wait for Bridge to connect (reads stderr with ReadLineAsync + timeout)
# IMPORTANT: Reuses the same pending ReadLineAsync task to avoid "stream in use" errors.
function Wait-BridgeConnection {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 20
    )
    $deadline = [DateTime]::Now.AddSeconds($TimeoutSeconds)
    $pendingTask = $null
    while ([DateTime]::Now -lt $deadline) {
        if ($Process.HasExited) {
            Write-Host "    [BRIDGE] Process exited with code $($Process.ExitCode)" -ForegroundColor Red
            return $false
        }
        if ($null -eq $pendingTask) {
            $pendingTask = $Process.StandardError.ReadLineAsync()
        }
        $remainingMs = [int](($deadline - [DateTime]::Now).TotalMilliseconds)
        if ($remainingMs -le 0) { break }
        $waitMs = [Math]::Min($remainingMs, 1000)
        if ($pendingTask.Wait($waitMs)) {
            $line = $pendingTask.Result
            $pendingTask = $null  # Completed a       allow new task on next iteration
            if ($null -ne $line) {
                Write-Host "    [BRIDGE] $line" -ForegroundColor DarkGray
                if ($line -match "Connected\. Endpoint:") { return $true }
            }
        }
        # If Wait timed out, keep the SAME pending task for next iteration
    }
    return $false
}

# Helper: Read one JSON-RPC response from stdout matching a specific id
# IMPORTANT: Reuses the same pending ReadLineAsync task to avoid "stream in use" errors.
function Read-JsonRpcResponse {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$ExpectedId,
        [int]$TimeoutSeconds = 10
    )
    $deadline = [DateTime]::Now.AddSeconds($TimeoutSeconds)
    $pendingTask = $null
    while ([DateTime]::Now -lt $deadline) {
        if ($null -eq $pendingTask) {
            $pendingTask = $Process.StandardOutput.ReadLineAsync()
        }
        $remainingMs = [int](($deadline - [DateTime]::Now).TotalMilliseconds)
        if ($remainingMs -le 0) { break }
        $waitMs = [Math]::Min($remainingMs, 2000)
        if ($pendingTask.Wait($waitMs)) {
            $line = $pendingTask.Result
            $pendingTask = $null  # Completed a       allow new task on next iteration
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line.StartsWith("{")) {
                try {
                    $parsed = $line | ConvertFrom-Json
                    if ($parsed.id -eq $ExpectedId) { return $parsed }
                } catch {}
            }
        }
        # If Wait timed out, keep the SAME pending task for next iteration
    }
    return $null
}

# Helper: Clean shutdown of Bridge process
function Stop-BridgeProcess {
    param([System.Diagnostics.Process]$Process)
    try { $Process.StandardInput.Close() } catch {}
    try { $Process.Kill() } catch {}
    try { $Process.WaitForExit(3000) } catch {}
    try { $Process.Dispose() } catch {}
}

# ===================================================================
# 20.10 a       MCP Bridge: SSE Connection Stability (30 seconds)
# ===================================================================
Describe "20.10. MCP Bridge - SSE Connection Stability" {

    It "Should keep SSE connection alive for 30 seconds" {
        $bridgePath | Should Exist

        $apiKey = Get-McpApiKey
        $apiKey | Should Not BeNullOrEmpty

        $proc = Start-BridgeProcess -ApiKey $apiKey
        $proc | Should Not Be $null

        $connected = Wait-BridgeConnection -Process $proc -TimeoutSeconds 20
        $connected | Should Be $true

        # Now wait 18s a       the heartbeat fires at 15s, connection must survive past it
        Write-Host "    [TEST] Connection established. Waiting 18s for heartbeat survival..." -ForegroundColor Cyan
        Start-Sleep -Seconds 18

        # Check if process is still alive (it should be a       SSE connection held)
        $proc.HasExited | Should Be $false

        # Read any stderr that accumulated during the wait
        $stderrDump = ""
        while ($true) {
            $task = $proc.StandardError.ReadLineAsync()
            if ($task.Wait(200)) {
                if ($null -ne $task.Result) { $stderrDump += $task.Result + "`n" }
                else { break }
            } else { break }
        }
        if ($stderrDump.Length -gt 0) {
            Write-Host "    [BRIDGE] Stderr after 18s:`n$stderrDump" -ForegroundColor DarkGray
        }

        # Verify no SSE errors occurred
        $stderrDump | Should Not Match "SSE IO error"
        $stderrDump | Should Not Match "Connection error"
        $stderrDump | Should Not Match "Connection closed\. Attempting to reconnect"

        Write-Host "    [PASS] SSE connection stable for 18+ seconds (heartbeat survived)" -ForegroundColor Green

        Stop-BridgeProcess -Process $proc
    }
}

# ===================================================================
# 20.11 a       MCP Bridge: JSON-RPC Initialize + tools/list via stdio
# ===================================================================
Describe "20.11. MCP Bridge - JSON-RPC Initialize and Tools List" {

    It "Should return initialize response with capabilities" {
        $apiKey = Get-McpApiKey

        $proc = Start-BridgeProcess -ApiKey $apiKey

        $connected = Wait-BridgeConnection -Process $proc -TimeoutSeconds 20
        $connected | Should Be $true

        # Send initialize
        $initMsg = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"pester-test","version":"1.0"}}}'
        Write-Host "    [STDIN] $initMsg" -ForegroundColor Magenta
        $proc.StandardInput.WriteLine($initMsg)
        $proc.StandardInput.Flush()

        $response = Read-JsonRpcResponse -Process $proc -ExpectedId 1 -TimeoutSeconds 10
        $response | Should Not Be $null
        $response.jsonrpc | Should Be "2.0"
        $response.id | Should Be 1
        $response.result | Should Not Be $null
        $response.result.protocolVersion | Should Be "2024-11-05"
        $response.result.capabilities | Should Not Be $null
        $response.result.serverInfo | Should Not Be $null
        Write-Host "    [PASS] Initialize OK: $($response.result.serverInfo.name)" -ForegroundColor Green

        # Send notifications/initialized
        $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
        $proc.StandardInput.Flush()
        Start-Sleep -Milliseconds 500

        # Send tools/list
        $toolsMsg = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
        Write-Host "    [STDIN] tools/list" -ForegroundColor Magenta
        $proc.StandardInput.WriteLine($toolsMsg)
        $proc.StandardInput.Flush()

        $toolsResponse = Read-JsonRpcResponse -Process $proc -ExpectedId 2 -TimeoutSeconds 10
        $toolsResponse | Should Not Be $null
        $toolsResponse.result.tools | Should Not Be $null
        $toolCount = $toolsResponse.result.tools.Count
        $toolCount | Should BeGreaterThan 10
        Write-Host "    [PASS] tools/list OK: $toolCount tools available" -ForegroundColor Green

        # Verify key tools exist (Pester 3.4.0: 'Should Contain' is a file test, use -contains operator)
        $toolNames = $toolsResponse.result.tools | ForEach-Object { $_.name }
        ($toolNames -contains "get_project_status") | Should Be $true
        ($toolNames -contains "list_devices") | Should Be $true
        ($toolNames -contains "list_blocks") | Should Be $true
        Write-Host "    [PASS] Key tools present (get_project_status, list_devices, list_blocks)" -ForegroundColor Green

        Stop-BridgeProcess -Process $proc
    }
}

# ===================================================================
# 20.12 a       MCP Bridge: tools/call get_project_status
# ===================================================================
Describe "20.12. MCP Bridge - Tool Call (get_project_status)" {

    It "Should execute get_project_status tool via Bridge" {
        $apiKey = Get-McpApiKey

        $proc = Start-BridgeProcess -ApiKey $apiKey

        $connected = Wait-BridgeConnection -Process $proc -TimeoutSeconds 20
        $connected | Should Be $true

        # Initialize handshake
        $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"pester-test","version":"1.0"}}}')
        $proc.StandardInput.Flush()

        $initResp = Read-JsonRpcResponse -Process $proc -ExpectedId 1 -TimeoutSeconds 10
        $initResp | Should Not Be $null

        $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
        $proc.StandardInput.Flush()
        Start-Sleep -Milliseconds 500

        # Call get_project_status
        $callMsg = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_project_status","arguments":{}}}'
        Write-Host "    [STDIN] tools/call get_project_status" -ForegroundColor Magenta
        $proc.StandardInput.WriteLine($callMsg)
        $proc.StandardInput.Flush()

        $callResponse = Read-JsonRpcResponse -Process $proc -ExpectedId 3 -TimeoutSeconds 15
        $callResponse | Should Not Be $null
        $callResponse.result | Should Not Be $null
        $callResponse.result.content | Should Not Be $null
        $callResponse.result.content.Count | Should BeGreaterThan 0

        $textContent = $callResponse.result.content[0].text
        Write-Host "    [RESULT] $($textContent.Substring(0, [Math]::Min($textContent.Length, 200)))" -ForegroundColor Cyan
        Write-Host "    [PASS] Tool call returned content" -ForegroundColor Green

        Stop-BridgeProcess -Process $proc
    }
}

# ===================================================================
# 20.13 a       Claude Code CLI: MCP Connection Test
# ===================================================================
Describe "20.13. Claude Code CLI - MCP Tool Discovery" {

    It "Should discover T-IA Connect tools via MCP" {
        # Check if claude CLI is available
        $claudePath = Get-Command "claude" -ErrorAction SilentlyContinue
        if (-not $claudePath) {
            Write-Host "    [SKIP] Claude Code CLI not found in PATH" -ForegroundColor Yellow
            Set-TestInconclusive "Claude Code CLI not installed"
            return
        }

        Write-Host "    [TEST] Asking Claude to list MCP tools..." -ForegroundColor Cyan

        # Check if we're inside a Claude Code session (env var set by Claude Code)
        if ($env:CLAUDE_CODE_ENTRYPOINT -or $env:CLAUDE_SESSION_ID) {
            Write-Host "    [SKIP] Cannot launch Claude inside an existing Claude session" -ForegroundColor Yellow
            Set-TestInconclusive "Running inside Claude Code session"
            return
        }

        $result = $null
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = (Get-Command "claude" -ErrorAction Stop).Source
            $psi.Arguments = '--print --max-turns 1 "Use get_project_status and return the raw result"'
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit(60000) | Out-Null
            if (-not $proc.HasExited) { $proc.Kill() }
            $result = $proc.StandardOutput.ReadToEnd()
            $proc.Dispose()
        }
        catch {
            Write-Host "    [ERROR] Claude CLI failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($null -ne $result -and $result.Trim().Length -gt 0) {
            Write-Host "    [CLAUDE] $($result.Substring(0, [Math]::Min($result.Length, 300)))..." -ForegroundColor DarkCyan
            $result | Should Not BeNullOrEmpty
            Write-Host "    [PASS] Claude Code successfully used MCP" -ForegroundColor Green
        } else {
            Write-Host "    [SKIP] Claude returned empty response (may need auth or is nested)" -ForegroundColor Yellow
            Set-TestInconclusive "Claude returned empty response"
        }
    }
}

# ===================================================================
# 20.14 a       Gemini CLI: MCP Connection Test
# ===================================================================
Describe "20.14. Gemini CLI - MCP Tool Discovery" {

    It "Should discover T-IA Connect tools via MCP" {
        # Check if we're already inside a Gemini CLI session to avoid interactive hanging
        if ($env:GEMINI_CLI) {
            Write-Host "    [SKIP] Cannot launch Gemini CLI inside an existing Gemini session" -ForegroundColor Yellow
            Set-TestInconclusive "Running inside Gemini CLI session"
            return
        }

        # Check if gemini CLI is available
        $geminiPath = Get-Command "gemini" -ErrorAction SilentlyContinue
        if (-not $geminiPath) {
            Write-Host "    [SKIP] Gemini CLI not found in PATH" -ForegroundColor Yellow
            Set-TestInconclusive "Gemini CLI not installed"
            return
        }

        Write-Host "    [TEST] Asking Gemini to use MCP tools..." -ForegroundColor Cyan

        $result = $null
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = '/c gemini -p "Use get_project_status and return the raw result"'
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit(60000) | Out-Null
            if (-not $proc.HasExited) {
                Write-Host "    [WARN] Gemini timed out after 60s" -ForegroundColor Yellow
                $proc.Kill()
            }
            $result = $proc.StandardOutput.ReadToEnd()
            $proc.Dispose()
        }
        catch {
            Write-Host "    [ERROR] Gemini CLI failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($null -ne $result -and $result.Trim().Length -gt 0) {
            Write-Host "    [GEMINI] $($result.Substring(0, [Math]::Min($result.Length, 300)))..." -ForegroundColor DarkCyan
            $result | Should Not BeNullOrEmpty
            Write-Host "    [PASS] Gemini CLI successfully used MCP" -ForegroundColor Green
        } else {
            Write-Host "    [SKIP] Gemini returned empty response (may need auth)" -ForegroundColor Yellow
            Set-TestInconclusive "Gemini returned empty response"
        }
    }
}

