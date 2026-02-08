# Enable-SSH.ps1
# Run this script on Windows Server to enable OpenSSH Server
# Usage: Run this in PowerShell as Administrator on the Windows VM

Write-Host "Installing OpenSSH Server..." -ForegroundColor Cyan

# Install OpenSSH Server capability
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start the SSH service
Write-Host "Starting SSH service..." -ForegroundColor Cyan
Start-Service sshd

# Set SSH to start automatically
Write-Host "Setting SSH to start automatically..." -ForegroundColor Cyan
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the firewall rule is configured
Write-Host "`nChecking firewall rules..." -ForegroundColor Cyan
$firewallRule = Get-NetFirewallRule -Name *ssh* -ErrorAction SilentlyContinue
if ($firewallRule) {
    Write-Host "✓ SSH firewall rules are configured" -ForegroundColor Green
    $firewallRule | Format-Table Name, Enabled, Direction, Action
} else {
    Write-Host "⚠ No SSH firewall rules found, creating..." -ForegroundColor Yellow
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}

# Set PowerShell as the default shell (optional but recommended)
Write-Host "`nSetting PowerShell as default SSH shell..." -ForegroundColor Cyan
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
    -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -PropertyType String -Force | Out-Null

Write-Host "`n✓ SSH is now enabled!" -ForegroundColor Green
Write-Host "`nYou can now connect from Linux:" -ForegroundColor Cyan
Write-Host "  ssh Administrator@192.168.56.10" -ForegroundColor White
Write-Host "`nYour default shell is PowerShell - you'll be in a PowerShell prompt when you connect." -ForegroundColor Gray
