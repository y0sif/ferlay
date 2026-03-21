# Ferlay Daemon Installer for Windows
# Usage: irm https://get.ferlay.dev/windows | iex
#   or:  powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$Repo = "OWNER/ferlay"
$BinaryName = "ferlay.exe"

Write-Host ""
Write-Host "  Ferlay Daemon Installer (Windows)" -ForegroundColor Cyan
Write-Host "  ===================================" -ForegroundColor Cyan
Write-Host ""

# --- Detect architecture ---
$Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
switch ($Arch) {
    "X64"   { $ArchName = "x86_64" }
    "Arm64" { $ArchName = "aarch64" }
    default {
        Write-Host "Error: Unsupported architecture: $Arch" -ForegroundColor Red
        exit 1
    }
}

$AssetName = "ferlay-daemon-windows-${ArchName}"
Write-Host "  Detected: windows / $ArchName"

# --- Get latest release ---
Write-Host "  Fetching latest release..."
$ReleaseUrl = "https://api.github.com/repos/$Repo/releases/latest"
$Release = Invoke-RestMethod -Uri $ReleaseUrl -Headers @{ "User-Agent" = "ferlay-installer" }
$Tag = $Release.tag_name

if (-not $Tag) {
    Write-Host "Error: Could not determine latest release." -ForegroundColor Red
    exit 1
}

Write-Host "  Latest release: $Tag"

# --- Download ---
$DownloadUrl = "https://github.com/$Repo/releases/download/$Tag/${AssetName}.zip"
$TempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "ferlay-install-$(Get-Random)")

Write-Host "  Downloading ${AssetName}.zip ..."
$ZipPath = Join-Path $TempDir.FullName "ferlay.zip"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

# --- Extract ---
Expand-Archive -Path $ZipPath -DestinationPath $TempDir.FullName -Force

# --- Install ---
$InstallDir = Join-Path $env:LOCALAPPDATA "Ferlay"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$ExePath = Join-Path $TempDir.FullName "$AssetName.exe"
if (-not (Test-Path $ExePath)) {
    # Try without .exe extension in archive
    $ExePath = Join-Path $TempDir.FullName $AssetName
}
Copy-Item -Path $ExePath -Destination (Join-Path $InstallDir $BinaryName) -Force

Write-Host "  Installed to: $InstallDir\$BinaryName"

# --- Add to PATH ---
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$UserPath", "User")
    Write-Host "  Added $InstallDir to user PATH."
    Write-Host "  Restart your terminal for PATH changes to take effect."
}

# --- Cleanup ---
Remove-Item -Recurse -Force $TempDir.FullName -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Ferlay installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Open a new terminal"
Write-Host "    2. Run:  ferlay daemon"
Write-Host "    3. Scan the QR code with the Ferlay app"
Write-Host "    4. Start sessions from your phone!"
Write-Host ""
Write-Host "  Get the app:"
Write-Host "    Android APK: https://github.com/$Repo/releases/latest"
Write-Host ""
