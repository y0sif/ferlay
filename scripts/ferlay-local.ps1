# Ferlay Local Mode — PowerShell script for Windows
$ErrorActionPreference = "Stop"

# --- Detect repo root ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# --- Check prerequisites ---
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Error: cargo is not installed. Install Rust via https://rustup.rs" -ForegroundColor Red
    exit 1
}

# --- Locate binaries ---
$RelayBin = Join-Path $RepoRoot "target\release\furlay-relay.exe"
$DaemonBin = Join-Path $RepoRoot "target\release\furlay-daemon.exe"

if (-not (Test-Path $RelayBin) -or -not (Test-Path $DaemonBin)) {
    Write-Host "Binaries not found. Building from source..."
    $CargoToml = Join-Path $RepoRoot "Cargo.toml"
    cargo build --release --manifest-path $CargoToml -p furlay-relay -p furlay-daemon
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# --- Detect LAN IP ---
$LanIP = "127.0.0.1"
try {
    $adapter = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1
    if ($adapter) {
        $LanIP = $adapter.IPAddress
    }
} catch {
    # Fallback already set
}

$RelayUrl = "ws://${LanIP}:8080/ws"
$PidFile = Join-Path $RepoRoot ".ferlay-local.pids"

Write-Host ""
Write-Host "=== Ferlay Local Mode ===" -ForegroundColor Cyan
Write-Host "Relay URL: $RelayUrl"
Write-Host "LAN IP:    $LanIP"
Write-Host ""
Write-Host "Point your Ferlay app at: $RelayUrl"
Write-Host ""

# --- Start relay in background ---
Write-Host "Starting relay on port 8080..."
$env:PORT = "8080"
$env:RUST_LOG = "furlay_relay=info"
$RelayProc = Start-Process -FilePath $RelayBin -PassThru -NoNewWindow

Start-Sleep -Seconds 1

if ($RelayProc.HasExited) {
    Write-Host "Error: Relay failed to start. Is port 8080 already in use?" -ForegroundColor Red
    exit 1
}

# Save PIDs
"relay=$($RelayProc.Id)" | Out-File -FilePath $PidFile -Encoding ASCII

# --- Start daemon ---
Write-Host "Starting daemon..."
Write-Host ""
$env:RUST_LOG = "furlay_daemon=info"
$DaemonProc = Start-Process -FilePath $DaemonBin -ArgumentList "daemon","--local" -PassThru -NoNewWindow

"daemon=$($DaemonProc.Id)" | Out-File -FilePath $PidFile -Append -Encoding ASCII

Write-Host ""
Write-Host "Ferlay is running. Press Ctrl+C to stop." -ForegroundColor Green
Write-Host ""

# --- Cleanup on exit ---
$CleanupBlock = {
    Write-Host ""
    Write-Host "Shutting down Ferlay..."
    try { Stop-Process -Id $DaemonProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    try { Stop-Process -Id $RelayProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path $PidFile) { Remove-Item $PidFile }
    Write-Host "Ferlay stopped."
}

try {
    # Register Ctrl+C handler
    [Console]::TreatControlCAsInput = $false
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $CleanupBlock

    # Wait for either process to exit
    while (-not $RelayProc.HasExited -and -not $DaemonProc.HasExited) {
        Start-Sleep -Milliseconds 500
    }
} finally {
    & $CleanupBlock
}
