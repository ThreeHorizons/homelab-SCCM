# Phase 2 Testing Guide

This guide explains how to test and validate your Vagrant VMs using both Bash and PowerShell on Linux/macOS hosts.

## Quick Start

```bash
# Run the comprehensive bash testing script
cd /home/myodhes-nix/projects/homelab-SCCM
./scripts/test-phase2.sh

# Or run the PowerShell version
pwsh ./scripts/Test-Phase2.ps1
```

---

## Understanding Cross-Platform Network Testing

### The Problem with Test-NetConnection

When you tried to run:
```powershell
pwsh -c "Test-NetConnection -ComputerName 192.168.56.10 -Port 5985"
```

You got this error:
```
Test-NetConnection: The term 'Test-NetConnection' is not recognized...
```

**Why?** `Test-NetConnection` is a **Windows-only** cmdlet that doesn't exist in **PowerShell Core** (the cross-platform version).

### The Solution: Cross-Platform Alternatives

We have several options for network testing on Linux/macOS:

#### Option 1: Native Linux Tools (Bash)

```bash
# Test ping (ICMP)
ping -c 4 192.168.56.10

# Test TCP port with netcat
nc -zv 192.168.56.10 5985

# Test TCP port with timeout
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/192.168.56.10/5985' && echo "Port is open"

# Alternative: Use curl for HTTP ports
curl -v telnet://192.168.56.10:5985
```

#### Option 2: PowerShell Core with Test-Connection

```powershell
# Test-Connection works on PowerShell Core 6.0+
Test-Connection -ComputerName 192.168.56.10 -Count 4

# With timeout
Test-Connection -ComputerName 192.168.56.10 -Count 4 -TimeoutSeconds 2
```

#### Option 3: PowerShell with .NET TcpClient

```powershell
# Custom function using .NET (see Test-Phase2.ps1)
function Test-TcpPort {
    param($ComputerName, $Port, $Timeout = 5000)
    
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
    $wait = $asyncResult.AsyncWaitHandle.WaitOne($Timeout)
    
    if ($wait) {
        try {
            $tcpClient.EndConnect($asyncResult)
            $tcpClient.Close()
            return $true
        }
        catch {
            return $false
        }
    }
    else {
        $tcpClient.Close()
        return $false
    }
}

# Usage
Test-TcpPort -ComputerName "192.168.56.10" -Port 5985
```

#### Option 4: Use Vagrant's Built-in Commands

```bash
# Best option: Let Vagrant handle WinRM for you
vagrant winrm dc01 -c "hostname"
vagrant winrm dc01 -c "Test-Connection -ComputerName 192.168.56.11 -Count 2"
```

---

## Complete Testing Workflow

### Step 1: Verify Environment

```bash
# Check Vagrant is installed
vagrant --version
# Expected: Vagrant 2.4.x

# Check VirtualBox is working
VBoxManage --version
# Expected: 7.x.x

# Check PowerShell Core
pwsh --version
# Expected: PowerShell 7.x
```

### Step 2: Check VM Status

```bash
cd /home/myodhes-nix/projects/homelab-SCCM/vagrant

# See what VMs are defined
vagrant status

# See what VMs are running (VirtualBox level)
VBoxManage list runningvms

# Expected output if DC01 is running:
# "sccm-lab-dc01" {some-uuid}
```

### Step 3: Network Connectivity Tests

#### Test 3a: Ping Test (ICMP)

```bash
# Ping DC01
ping -c 4 192.168.56.10

# What to look for:
# - "4 packets transmitted, 4 received" = Success
# - "0% packet loss" = Good connection
# - "100% packet loss" = VM not reachable
```

**What this tells you:**
- ✅ Success: VM is running and network is configured
- ❌ Failure: VM is off, network misconfigured, or firewall blocking

#### Test 3b: WinRM Port Test (TCP 5985)

```bash
# Using netcat
nc -zv 192.168.56.10 5985

# Expected success: "Connection to 192.168.56.10 5985 port [tcp/wsman] succeeded!"
# Expected failure: "Connection refused" or timeout
```

**What this tells you:**
- ✅ Success: WinRM service is running and accessible
- ❌ Failure: 
  - WinRM not configured
  - Windows still booting
  - Firewall blocking port
  - enable-winrm.ps1 script failed

### Step 4: WinRM Functionality Tests

#### Test 4a: Basic Command Execution

```bash
# Execute simple command
vagrant winrm dc01 -c "hostname"

# Expected: DC01 or SCCM-LAB-DC01
```

**What this tells you:**
- ✅ Success: WinRM is fully functional
- ❌ Failure: Authentication or communication issue

#### Test 4b: PowerShell Cmdlet Execution

```bash
# Get Windows version
vagrant winrm dc01 -c "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion"

# Get IP configuration
vagrant winrm dc01 -c "Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -match '192.168'}"

# Check WinRM service
vagrant winrm dc01 -c "(Get-Service WinRM).Status"
# Expected: Running
```

### Step 5: Inter-VM Connectivity

Once multiple VMs are running:

```bash
# From DC01, ping SCCM01
vagrant winrm dc01 -c "Test-Connection -ComputerName 192.168.56.11 -Count 2"

# From SCCM01, ping DC01
vagrant winrm sccm01 -c "Test-Connection -ComputerName 192.168.56.10 -Count 2"

# Test DNS resolution (after DC is configured)
vagrant winrm client01 -c "Resolve-DnsName dc01.lab.local"
```

### Step 6: Snapshot Management

```bash
# Create snapshots for rollback capability
vagrant snapshot save dc01 "base-install"
vagrant snapshot save sccm01 "base-install"
vagrant snapshot save client01 "base-install"

# List snapshots
vagrant snapshot list dc01

# Restore from snapshot
vagrant snapshot restore dc01 "base-install"

# Delete snapshot
vagrant snapshot delete dc01 "base-install"
```

---

## Common Issues and Solutions

### Issue: "Cannot ping DC01"

**Symptoms:**
```bash
ping -c 4 192.168.56.10
# 100% packet loss
```

**Possible Causes:**
1. VM is not running
2. VM is still booting
3. Network adapter misconfigured
4. VirtualBox host-only network issue

**Troubleshooting:**
```bash
# 1. Check if VM is running
vagrant status dc01
VBoxManage list runningvms | grep dc01

# 2. Check VirtualBox network
VBoxManage list hostonlyifs
# Look for vboxnet0 with IP 192.168.56.1

# 3. Check VM network adapters
VBoxManage showvminfo "sccm-lab-dc01" | grep NIC
# Should show two adapters: NAT and Host-only

# 4. Try restarting the VM
vagrant reload dc01
```

### Issue: "WinRM port not accessible"

**Symptoms:**
```bash
nc -zv 192.168.56.10 5985
# Connection refused or timeout
```

**Possible Causes:**
1. Windows still booting
2. enable-winrm.ps1 script failed
3. Windows Firewall blocking
4. WinRM service not started

**Troubleshooting:**
```bash
# 1. Wait for Windows to fully boot (can take 5-10 minutes first boot)
sleep 60
nc -zv 192.168.56.10 5985

# 2. Check provisioning logs
vagrant provision dc01

# 3. Try to access via Vagrant's SSH tunnel (fallback)
vagrant ssh dc01

# 4. Check logs inside VM
vagrant winrm dc01 -c "Get-Content C:\tmp\vagrant-shell*.log | Select-Object -Last 50"
```

### Issue: "vagrant winrm fails"

**Symptoms:**
```bash
vagrant winrm dc01 -c "hostname"
# Error: WinRM not ready
```

**Possible Causes:**
1. Authentication failure
2. WinRM not configured
3. Network issue
4. Vagrant box issue

**Troubleshooting:**
```bash
# 1. Verify WinRM port is accessible first
nc -zv 192.168.56.10 5985

# 2. Try re-provisioning
vagrant provision dc01

# 3. Check Vagrant's WinRM settings
vagrant winrm-config dc01

# 4. Destroy and recreate (nuclear option)
vagrant destroy -f dc01
vagrant up dc01
```

### Issue: "VMs can't communicate with each other"

**Symptoms:**
```bash
vagrant winrm dc01 -c "Test-Connection -ComputerName 192.168.56.11"
# Fails
```

**Possible Causes:**
1. VMs on different networks
2. Windows Firewall blocking
3. Routing issue

**Troubleshooting:**
```bash
# 1. Verify both VMs have host-only adapter
VBoxManage showvminfo "sccm-lab-dc01" | grep -A3 "NIC 2"
VBoxManage showvminfo "sccm-lab-sccm01" | grep -A3 "NIC 2"

# 2. Check IP addresses
vagrant winrm dc01 -c "ipconfig"
vagrant winrm sccm01 -c "ipconfig"
# Both should have 192.168.56.x addresses

# 3. Temporarily disable Windows Firewall
vagrant winrm dc01 -c "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False"
# Test again, then re-enable
```

---

## Key Concepts Explained

### WinRM (Windows Remote Management)

**What it is:**
- Microsoft's implementation of WS-Management protocol
- Allows remote PowerShell execution
- Similar to SSH for Linux

**Ports:**
- **5985**: HTTP (unencrypted) - **Used in our lab**
- **5986**: HTTPS (encrypted) - Production use

**Authentication Methods:**
- **Basic**: Username/password (must use HTTPS in production)
- **Negotiate**: Kerberos or NTLM
- **Kerberos**: Domain-based (most secure)
- **CredSSP**: Credential delegation (for double-hop scenarios)

**In our lab:**
- Using HTTP (port 5985) because it's isolated
- Using Basic authentication with Vagrant credentials
- TrustedHosts set to "*" (allows any host)

### Vagrant's WinRM Integration

**How it works:**
1. Vagrant connects to VM's WinRM port (5985)
2. Authenticates with VM credentials
3. Executes PowerShell commands remotely
4. Returns output to host

**Commands:**
```bash
# Execute single command
vagrant winrm <vm-name> -c "<powershell-command>"

# Execute script file
vagrant winrm <vm-name> -s </path/to/script.ps1>

# Interactive shell (if configured)
vagrant winrm-shell <vm-name>

# Show WinRM configuration
vagrant winrm-config <vm-name>
```

### VirtualBox Networking Modes

Our VMs use two network adapters:

#### Adapter 1: NAT (Network Address Translation)
- **Purpose**: Internet access
- **Configuration**: Automatic (VirtualBox default)
- **IP Range**: 10.0.2.0/24 (VirtualBox internal)
- **Access**: VMs can reach internet, internet can't reach VMs

#### Adapter 2: Host-Only Network
- **Purpose**: VM-to-VM and Host-to-VM communication
- **Configuration**: Manual (vboxnet0, 192.168.56.0/24)
- **IP Range**: 192.168.56.1-254
- **Access**: VMs and host can communicate, isolated from internet

**Why two adapters?**
- NAT alone: VMs can't talk to each other or host
- Host-Only alone: VMs can't reach internet
- Both: Best of both worlds

---

## Next Steps

Once all tests pass:

1. **Update checklist:**
   ```bash
   # Edit .claude/phase2-checklist.md
   # Mark completed items
   ```

2. **Create documentation:**
   - Screenshot successful tests
   - Document any issues encountered
   - Note VM IP addresses

3. **Take snapshots:**
   ```bash
   vagrant snapshot save dc01 "phase2-complete"
   vagrant snapshot save sccm01 "phase2-complete"
   vagrant snapshot save client01 "phase2-complete"
   ```

4. **Proceed to Phase 3:**
   - Active Directory Domain Services configuration
   - DNS and DHCP setup
   - Domain join operations

---

## Reference: All Testing Commands

```bash
# === Environment Checks ===
vagrant --version
VBoxManage --version
pwsh --version

# === VM Status ===
vagrant status
vagrant global-status
VBoxManage list runningvms

# === Network Tests (Linux tools) ===
ping -c 4 192.168.56.10
nc -zv 192.168.56.10 5985
curl -v telnet://192.168.56.10:5985

# === Network Tests (PowerShell Core) ===
pwsh -c "Test-Connection -ComputerName 192.168.56.10 -Count 4"
pwsh ./scripts/Test-Phase2.ps1

# === Vagrant WinRM Tests ===
vagrant winrm dc01 -c "hostname"
vagrant winrm dc01 -c "ipconfig"
vagrant winrm dc01 -c "Get-Service WinRM"
vagrant winrm dc01 -c "Test-Connection -ComputerName 192.168.56.11 -Count 2"

# === VirtualBox Network Checks ===
VBoxManage list hostonlyifs
VBoxManage showvminfo "sccm-lab-dc01" | grep NIC

# === Snapshot Management ===
vagrant snapshot save <vm> "<snapshot-name>"
vagrant snapshot list <vm>
vagrant snapshot restore <vm> "<snapshot-name>"
vagrant snapshot delete <vm> "<snapshot-name>"
```

---

## Additional Resources

- **Vagrant WinRM Documentation**: https://developer.hashicorp.com/vagrant/docs/provisioning/winrm
- **VirtualBox Networking**: https://www.virtualbox.org/manual/ch06.html
- **PowerShell Remoting**: https://learn.microsoft.com/en-us/powershell/scripting/learn/remoting/
- **Test-Connection Cmdlet**: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-20  
**Phase**: 2 (Vagrant Multi-VM Topology)
