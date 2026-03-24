# Ferlay Daemon Installer for Windows
# Usage: irm https://ferlay.dev/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo = "y0sif/ferlay"
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
    $env:PATH = "$InstallDir;$env:PATH"
    Write-Host "  Added $InstallDir to user PATH."
}

# --- Cleanup ---
Remove-Item -Recurse -Force $TempDir.FullName -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Ferlay installed successfully!" -ForegroundColor Green
Write-Host ""

# --- Run interactive setup ---
Write-Host "  Running setup..." -ForegroundColor Yellow
Write-Host ""
& "$InstallDir\$BinaryName" setup
