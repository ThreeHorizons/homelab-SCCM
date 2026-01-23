#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 2 Testing and Validation Script (PowerShell version)

.DESCRIPTION
    This script provides testing commands that work from PowerShell Core on Linux/macOS.
    It demonstrates cross-platform network testing techniques.

.EXAMPLE
    pwsh /home/myodhes-nix/projects/homelab-SCCM/scripts/Test-Phase2.ps1
#>

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Wait-UserPrompt {
    param([string]$Message = "Press Enter to continue...")
    Write-Host $Message -ForegroundColor Yellow
    Read-Host | Out-Null
}

# ============================================================================
# Cross-Platform Network Testing Functions
# ============================================================================

function Test-TcpPort {
    <#
    .SYNOPSIS
        Tests if a TCP port is open (cross-platform alternative to Test-NetConnection)
    .DESCRIPTION
        Uses .NET TcpClient to test port connectivity. Works on Windows, Linux, and macOS.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$Timeout = 5000  # milliseconds
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne($Timeout)

        if ($wait) {
            try {
                $tcpClient.EndConnect($asyncResult)
                $tcpClient.Close()
                return @{
                    Success = $true
                    Port = $Port
                    ComputerName = $ComputerName
                    Message = "Port is open"
                }
            }
            catch {
                return @{
                    Success = $false
                    Port = $Port
                    ComputerName = $ComputerName
                    Message = $_.Exception.Message
                }
            }
        }
        else {
            $tcpClient.Close()
            return @{
                Success = $false
                Port = $Port
                ComputerName = $ComputerName
                Message = "Connection timeout after ${Timeout}ms"
            }
        }
    }
    catch {
        return @{
            Success = $false
            Port = $Port
            ComputerName = $ComputerName
            Message = $_.Exception.Message
        }
    }
}

function Test-Ping {
    <#
    .SYNOPSIS
        Tests ICMP ping connectivity (cross-platform)
    .DESCRIPTION
        Uses Test-Connection cmdlet which works on PowerShell Core
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [int]$Count = 4,

        [int]$Timeout = 2  # seconds
    )

    try {
        # Test-Connection works on PowerShell Core 6.0+
        $result = Test-Connection -ComputerName $ComputerName -Count $Count -TimeoutSeconds $Timeout -ErrorAction Stop
        return @{
            Success = $true
            ComputerName = $ComputerName
            PacketsSent = $Count
            PacketsReceived = ($result | Measure-Object).Count
            Message = "Ping successful"
        }
    }
    catch {
        return @{
            Success = $false
            ComputerName = $ComputerName
            PacketsSent = $Count
            PacketsReceived = 0
            Message = $_.Exception.Message
        }
    }
}

# ============================================================================
# TEST 1: Environment Check
# ============================================================================
Write-Section "TEST 1: PowerShell and Environment Check"

Write-Info "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Info "Operating System: $($PSVersionTable.OS)"
Write-Info "Platform: $($PSVersionTable.Platform)"
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning2 "PowerShell 7.0+ recommended for cross-platform features"
}
else {
    Write-Success "PowerShell version is compatible"
}

Wait-UserPrompt

# ============================================================================
# TEST 2: Network Connectivity to DC01
# ============================================================================
Write-Section "TEST 2: Testing Network Connectivity to DC01"

Write-Info "What we're testing: Can we reach DC01's IP address?"
Write-Info "DC01 IP: 192.168.56.10"
Write-Host ""

Write-Info "Running: Test-Ping -ComputerName 192.168.56.10 -Count 4"
$pingResult = Test-Ping -ComputerName "192.168.56.10" -Count 4

if ($pingResult.Success) {
    Write-Success "DC01 is reachable! ($($pingResult.PacketsReceived)/$($pingResult.PacketsSent) packets received)"
}
else {
    Write-ErrorMsg "Cannot ping DC01: $($pingResult.Message)"
    Write-Warning2 "Possible reasons:"
    Write-Warning2 "  1. VM is not running (check with: vagrant status)"
    Write-Warning2 "  2. VM is still booting"
    Write-Warning2 "  3. Network misconfiguration"
}

Wait-UserPrompt

# ============================================================================
# TEST 3: WinRM Port Connectivity
# ============================================================================
Write-Section "TEST 3: Testing WinRM Port Connectivity"

Write-Info "What we're testing: Is WinRM port accessible?"
Write-Info "WinRM Ports:"
Write-Info "  - 5985: HTTP (unencrypted, used in labs)"
Write-Info "  - 5986: HTTPS (encrypted, production)"
Write-Host ""

Write-Info "Running: Test-TcpPort -ComputerName 192.168.56.10 -Port 5985"
$winrmResult = Test-TcpPort -ComputerName "192.168.56.10" -Port 5985 -Timeout 5000

if ($winrmResult.Success) {
    Write-Success "WinRM port 5985 is open and accessible!"
}
else {
    Write-ErrorMsg "WinRM port is not accessible: $($winrmResult.Message)"
    Write-Warning2 "Troubleshooting steps:"
    Write-Warning2 "  1. Check if VM is running: vagrant status dc01"
    Write-Warning2 "  2. Check provisioning: vagrant provision dc01"
    Write-Warning2 "  3. Check logs in VM at: C:\tmp\vagrant-shell*.ps1.log"
}

Wait-UserPrompt

# ============================================================================
# TEST 4: Test All Lab IPs
# ============================================================================
Write-Section "TEST 4: Testing All Lab VM IP Addresses"

$labHosts = @(
    @{ Name = "DC01"; IP = "192.168.56.10"; Ports = @(5985, 3389) }
    @{ Name = "SCCM01"; IP = "192.168.56.11"; Ports = @(5985, 3389, 1433) }
)

foreach ($host in $labHosts) {
    Write-Host ""
    Write-Info "Testing $($host.Name) ($($host.IP))..."

    # Test ping
    $pingResult = Test-Ping -ComputerName $host.IP -Count 2 -Timeout 2
    if ($pingResult.Success) {
        Write-Success "  Ping: OK ($($pingResult.PacketsReceived)/2)"
    }
    else {
        Write-ErrorMsg "  Ping: Failed"
        continue  # Skip port tests if host is unreachable
    }

    # Test ports
    foreach ($port in $host.Ports) {
        $portResult = Test-TcpPort -ComputerName $host.IP -Port $port -Timeout 3000
        $portName = switch ($port) {
            5985 { "WinRM HTTP" }
            5986 { "WinRM HTTPS" }
            3389 { "RDP" }
            1433 { "SQL Server" }
            default { "Port $port" }
        }

        if ($portResult.Success) {
            Write-Success "  ${portName}: Open"
        }
        else {
            Write-Warning2 "  ${portName}: Closed/Filtered"
        }
    }
}

Wait-UserPrompt

# ============================================================================
# TEST 5: Vagrant Integration Tests
# ============================================================================
Write-Section "TEST 5: Vagrant Command Tests"

Write-Info "These tests use Vagrant's built-in commands"
Write-Info "Note: These require running VMs"
Write-Host ""

# Change to vagrant directory
$vagrantDir = "/home/myodhes-nix/projects/homelab-SCCM/vagrant"
if (Test-Path $vagrantDir) {
    Set-Location $vagrantDir
    Write-Success "Changed directory to: $(Get-Location)"
}
else {
    Write-ErrorMsg "Vagrant directory not found: $vagrantDir"
}

Write-Host ""
Write-Info "Suggested Vagrant commands to run manually:"
Write-Host ""
Write-Host "# Check VM status" -ForegroundColor Cyan
Write-Host "vagrant status" -ForegroundColor Yellow
Write-Host ""
Write-Host "# Get hostname from DC01" -ForegroundColor Cyan
Write-Host "vagrant winrm dc01 -c 'hostname'" -ForegroundColor Yellow
Write-Host ""
Write-Host "# Get IP configuration" -ForegroundColor Cyan
Write-Host "vagrant winrm dc01 -c 'ipconfig'" -ForegroundColor Yellow
Write-Host ""
Write-Host "# Test connectivity from DC01 to SCCM01" -ForegroundColor Cyan
Write-Host "vagrant winrm dc01 -c 'Test-Connection -ComputerName 192.168.56.11 -Count 2'" -ForegroundColor Yellow
Write-Host ""

Wait-UserPrompt

# ============================================================================
# SUMMARY AND NEXT STEPS
# ============================================================================
Write-Section "TEST SUMMARY AND NEXT STEPS"

Write-Info "Testing Complete! Here's what we covered:"
Write-Host ""
Write-Host "  ✓ PowerShell environment verification"
Write-Host "  ✓ Network connectivity testing (ping)"
Write-Host "  ✓ WinRM port accessibility testing"
Write-Host "  ✓ Multi-VM connectivity testing"
Write-Host "  ✓ Vagrant integration commands"
Write-Host ""

Write-Info "Key PowerShell Concepts You Learned:"
Write-Host ""
Write-Host "1. Test-Connection cmdlet:"
Write-Host "   - Cross-platform alternative to Test-NetConnection"
Write-Host "   - Works on Linux/macOS/Windows with PowerShell Core"
Write-Host ""
Write-Host "2. .NET TcpClient for port testing:"
Write-Host "   - Uses System.Net.Sockets.TcpClient"
Write-Host "   - Works on any platform with .NET Core"
Write-Host ""
Write-Host "3. PowerShell remoting with Vagrant:"
Write-Host "   - 'vagrant winrm' command executes PowerShell on VMs"
Write-Host "   - Uses WinRM protocol on port 5985/5986"
Write-Host ""

Write-Info "Next Steps for Phase 2 Completion:"
Write-Host ""
Write-Host "1. Create VM snapshots (for rollback capability):" -ForegroundColor Cyan
Write-Host "   vagrant snapshot save dc01 'base-install'" -ForegroundColor Yellow
Write-Host "   vagrant snapshot save sccm01 'base-install'" -ForegroundColor Yellow
Write-Host "   vagrant snapshot save client01 'base-install'" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Test snapshot restore:" -ForegroundColor Cyan
Write-Host "   vagrant snapshot list dc01" -ForegroundColor Yellow
Write-Host "   vagrant snapshot restore dc01 'base-install'" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Update Phase 2 checklist:" -ForegroundColor Cyan
Write-Host "   Mark completed tests in: .claude/phase2-checklist.md" -ForegroundColor Yellow
Write-Host ""

Write-Section "Script Complete!"
