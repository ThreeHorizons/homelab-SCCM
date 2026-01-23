# Vagrant Windows VM Access Methods

This guide explains how to interact with Windows VMs in the SCCM lab using Vagrant.

## Quick Reference

| Method | Command | Use Case |
|--------|---------|----------|
| **SSH** | `vagrant ssh <vm>` | Interactive shell access |
| **WinRM** | `vagrant winrm <vm> -c "command"` | Execute single PowerShell commands |
| **RDP** | `vagrant rdp <vm>` | GUI desktop access |

---

## SSH Access (Interactive Shell)

The recommended way to get an interactive session on Windows VMs.

### Enter SSH Session

```bash
# SSH into DC01
vagrant ssh dc01

# SSH into SCCM01
vagrant ssh sccm01

# SSH into CLIENT01
vagrant ssh client01
```

### Once Inside via SSH

You'll land in a Windows command prompt. Switch to PowerShell:

```cmd
# Start PowerShell
powershell

# Or start PowerShell directly in one command
vagrant ssh dc01 -c "powershell"
```

### Run PowerShell Commands via SSH

```bash
# Execute a single PowerShell command
vagrant ssh dc01 -c "powershell -Command 'Get-ComputerInfo | Select CsName, OsName'"

# Execute multiple commands
vagrant ssh dc01 -c "powershell -Command 'hostname; ipconfig'"

# Run a local script on the remote VM
vagrant ssh dc01 -c "powershell" < local-script.ps1
```

---

## WinRM Access (Single Commands)

Use WinRM for executing individual PowerShell commands without entering a full session.

### Basic Command Execution

```bash
# Execute single command
vagrant winrm dc01 -c "hostname"

# Get system info
vagrant winrm dc01 -c "Get-ComputerInfo | Select CsName, OsName, OsVersion"

# Check IP configuration
vagrant winrm dc01 -c "Get-NetIPAddress -AddressFamily IPv4 | Select IPAddress, InterfaceAlias"

# Test internet connectivity
vagrant winrm dc01 -c "Test-NetConnection -ComputerName 8.8.8.8"
```

### Execute PowerShell Script

```bash
# Run a local PowerShell script on remote VM
vagrant winrm dc01 -s powershell < ../scripts/test-config.ps1
```

### WinRM vs SSH

**Use WinRM when:**
- Running automation scripts from Linux host
- Executing single commands for testing
- Integrating with CI/CD pipelines

**Use SSH when:**
- You want an interactive session
- Debugging issues interactively
- Running multiple exploratory commands

---

## RDP Access (GUI Desktop)

Access the Windows desktop interface.

### Using Vagrant RDP Command

```bash
# Launch RDP session
vagrant rdp dc01

# Vagrant will use your system's default RDP client
```

### Manual RDP Connection

```bash
# Using xfreerdp (common on Linux)
xfreerdp /v:192.168.56.10 /u:vagrant /p:vagrant

# Using remmina (GUI RDP client)
remmina -c rdp://vagrant:vagrant@192.168.56.10
```

### Default Credentials

- **Username:** `vagrant`
- **Password:** `vagrant`

---

## Testing & Verification Examples

### Check VM is Running

```bash
# Vagrant status
vagrant status dc01

# VirtualBox status
VBoxManage list runningvms
```

### Verify Network Configuration

```bash
# Via WinRM
vagrant winrm dc01 -c "Get-NetIPAddress -IPAddress 192.168.56.10"

# Via SSH
vagrant ssh dc01 -c "powershell -Command 'Get-NetIPAddress -IPAddress 192.168.56.10'"
```

### Verify WinRM is Configured

```bash
vagrant winrm dc01 -c "Get-Service WinRM | Select Name, Status, StartType"
```

### Verify Internet Access

```bash
vagrant winrm dc01 -c "Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Quiet"
```

### Get Computer Information

```bash
vagrant winrm dc01 -c "Get-ComputerInfo | Select CsName, CsDomain, OsName, OsVersion, WindowsVersion"
```

### Check Firewall Status

```bash
vagrant winrm dc01 -c "Get-NetFirewallProfile | Select Name, Enabled"
```

### Verify PowerShell Execution Policy

```bash
vagrant winrm dc01 -c "Get-ExecutionPolicy"
```

---

## Interactive PowerShell Session Workflow

For true interactive work, use SSH:

```bash
# 1. SSH into VM
vagrant ssh dc01

# 2. Start PowerShell
powershell

# 3. Now you have full interactive PowerShell
PS C:\Users\vagrant> Get-ComputerInfo
PS C:\Users\vagrant> Get-Process
PS C:\Users\vagrant> # ... any PowerShell commands

# 4. Exit PowerShell
PS C:\Users\vagrant> exit

# 5. Exit SSH
C:\Users\vagrant> exit
```

---

## Troubleshooting

### SSH Connection Refused

```bash
# Check if VM is running
vagrant status dc01

# Restart VM
vagrant reload dc01

# Check SSH port
nmap -p 22 192.168.56.10
```

### WinRM Timeout

```bash
# Verify WinRM port is open
nmap -p 5985 192.168.56.10

# Check WinRM service via SSH
vagrant ssh dc01 -c "powershell -Command 'Get-Service WinRM'"

# Restart WinRM service
vagrant ssh dc01 -c "powershell -Command 'Restart-Service WinRM'"
```

### RDP Connection Failed

```bash
# Verify Remote Desktop is enabled
vagrant winrm dc01 -c "Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections"

# Expected value: fDenyTSConnections = 0 (enabled)
```

---

## Quick Command Reference

```bash
# Enter interactive shell
vagrant ssh dc01

# Run single command via WinRM
vagrant winrm dc01 -c "hostname"

# Open RDP session
vagrant rdp dc01

# Execute PowerShell via SSH
vagrant ssh dc01 -c "powershell -Command 'Get-ComputerInfo'"

# Run script via WinRM
vagrant winrm dc01 -s powershell < script.ps1
```

---

## Notes

- **SSH** is available because the `gusztavvargadr` base boxes include OpenSSH Server
- **WinRM** is pre-configured on port 5985 (HTTP) by the base box
- **Default credentials** are `vagrant/vagrant` for all access methods
- **RDP** requires the VM to have Remote Desktop enabled (done by bootstrap.ps1)

For Phase 3 automation, we'll primarily use **WinRM** for remote script execution from the Linux host.
