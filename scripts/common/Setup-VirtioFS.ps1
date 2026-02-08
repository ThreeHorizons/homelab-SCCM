#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures virtiofs shared directories on a Windows guest VM.

.DESCRIPTION
    Sets up WinFsp.Launcher to mount multiple virtiofs shares that are defined
    in the libvirt domain XML. The default VirtioFsSvc only supports a single
    share, so this script disables it and uses WinFsp.Launcher instead.

    PREREQUISITES:
    - virtio-win drivers installed (provides virtiofs.exe and VirtioFsDrv)
    - WinFsp installed (provides WinFsp.Launcher service and launchctl-x64.exe)

    WHAT THIS SCRIPT DOES:
    1. Verifies prerequisites (virtiofs.exe, WinFsp launchctl)
    2. Stops and disables the single-instance VirtioFsSvc
    3. Creates the WinFsp.Launcher registry entry for virtiofs
    4. Mounts each configured share via launchctl
    5. Creates scheduled tasks so shares mount on boot

.PARAMETER Shares
    Array of hashtables defining shares to mount. Each entry needs:
      Tag   - The virtiofs mount tag from the domain XML target dir
      Drive - The drive letter to mount as (e.g. "Z:")
      Name  - A friendly name for the scheduled task and launchctl instance

.EXAMPLE
    # Uses the default lab shares defined in this script
    .\Setup-VirtioFS.ps1

.EXAMPLE
    # Custom shares
    .\Setup-VirtioFS.ps1 -Shares @(
        @{ Tag = "my_share"; Drive = "X:"; Name = "MyShare" }
    )

.NOTES
    Intended to run once during initial VM provisioning (post-OS install).
    Safe to re-run; checks for existing configuration before applying.
#>

param(
    [hashtable[]]$Shares = @(
        @{ Tag = "windows_installers";    Drive = "Z:"; Name = "Windows" }
        @{ Tag = "configuration_scripts"; Drive = "Y:"; Name = "Scripts" }
    )
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$virtiofsExe = "C:\Program Files\Virtio-Win\VioFS\virtiofs.exe"
$launchctl   = "C:\Program Files (x86)\WinFsp\bin\launchctl-x64.exe"
$regPath     = "HKLM\SOFTWARE\WOW6432Node\WinFsp\Services\virtiofs"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

if (-not (Test-Path $virtiofsExe)) {
    Write-Error "virtiofs.exe not found at $virtiofsExe. Install virtio-win drivers first."
    exit 1
}

if (-not (Test-Path $launchctl)) {
    Write-Error "launchctl-x64.exe not found at $launchctl. Install WinFsp first."
    exit 1
}

Write-Host "  virtiofs.exe : $virtiofsExe" -ForegroundColor Green
Write-Host "  launchctl    : $launchctl" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Disable default single-instance VirtioFsSvc
# ---------------------------------------------------------------------------
$svc = Get-Service -Name VirtioFsSvc -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Disabling default VirtioFsSvc (single-share only)..." -ForegroundColor Cyan
    if ($svc.Status -eq "Running") {
        Stop-Service -Name VirtioFsSvc -Force
    }
    Set-Service -Name VirtioFsSvc -StartupType Disabled
    Write-Host "  VirtioFsSvc stopped and disabled." -ForegroundColor Green
} else {
    Write-Host "  VirtioFsSvc not found (already removed or not installed)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Create WinFsp.Launcher registry entry for virtiofs
# ---------------------------------------------------------------------------
if (-not (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue)) {
    Write-Host "Creating WinFsp.Launcher registry entry for virtiofs..." -ForegroundColor Cyan
    # Use New-ItemProperty for a cleaner PS approach, or keep your 'reg add' lines
    reg add $regPath /v Executable  /d $virtiofsExe /t REG_SZ   /f | Out-Null
    reg add $regPath /v CommandLine /d "-t %1 -m %2" /t REG_SZ   /f | Out-Null
    reg add $regPath /v JobControl  /d 1             /t REG_DWORD /f | Out-Null
    Write-Host "  Registry entry created." -ForegroundColor Green
} else {
    Write-Host "  WinFsp.Launcher registry entry already exists." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Mount shares and create scheduled tasks
# ---------------------------------------------------------------------------
foreach ($share in $Shares) {
    $tag       = $share.Tag
    $drive     = $share.Drive
    $instance  = "viofs$($share.Name)"
    $taskName  = "VirtioFS-$($share.Name)"

    Write-Host "Configuring share: $tag -> $drive ($instance)" -ForegroundColor Cyan

    # Mount now
    Write-Host "  Mounting..." -NoNewline
    & $launchctl start virtiofs $instance $tag $drive
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "  Continuing with scheduled task creation anyway..."
    }

    # Create scheduled task for boot persistence
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Scheduled task '$taskName' already exists, updating..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $action  = New-ScheduledTaskAction -Execute $launchctl -Argument "start virtiofs $instance $tag $drive"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -RunLevel Highest `
        -User "SYSTEM" `
        -Description "Mount virtiofs share '$tag' as $drive" | Out-Null

    Write-Host "  Scheduled task '$taskName' created." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "VirtioFS setup complete." -ForegroundColor Cyan
Write-Host "Mounted shares:" -ForegroundColor Cyan
foreach ($share in $Shares) {
    Write-Host "  $($share.Drive) -> $($share.Tag)" -ForegroundColor Green
}
Write-Host ""
Write-Host "Shares will auto-mount off boot via scheduled tasks." -ForegroundColor Cyan
