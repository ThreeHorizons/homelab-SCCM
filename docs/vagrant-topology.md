# Vagrant VM Topology

This document describes the virtual machine topology for the SCCM homelab, including network configuration, resource allocation, and provisioning details.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST MACHINE                                   │
│                         (Linux/macOS/Windows)                               │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    VirtualBox Host-Only Network                      │   │
│   │                         vboxnet0 (192.168.56.0/24)                   │   │
│   │                              │                                       │   │
│   │              ┌───────────────┼───────────────┬───────────────┐       │   │
│   │              │               │               │               │       │   │
│   │       ┌──────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐        │       │   │
│   │       │    DC01     │ │   SCCM01    │ │  CLIENT01   │  ...   │       │   │
│   │       │ .56.10      │ │ .56.11      │ │ DHCP        │        │       │   │
│   │       │ (Static)    │ │ (Static)    │ │ (.100-.200) │        │       │   │
│   │       └──────┬──────┘ └──────┬──────┘ └──────┬──────┘        │       │   │
│   │              │               │               │               │       │   │
│   └──────────────┼───────────────┼───────────────┼───────────────┘       │   │
│                  │               │               │                       │   │
│   ┌──────────────┼───────────────┼───────────────┼───────────────────┐   │   │
│   │              │               │               │                   │   │   │
│   │       ┌──────┴───────────────┴───────────────┴──────┐            │   │   │
│   │       │            VirtualBox NAT Network            │            │   │   │
│   │       │              (10.0.2.0/24)                   │            │   │   │
│   │       └───────────────────────┬──────────────────────┘            │   │   │
│   │                               │                                   │   │   │
│   └───────────────────────────────┼───────────────────────────────────┘   │   │
│                                   │                                       │   │
│                          ┌────────┴────────┐                              │   │
│                          │  Host Network   │                              │   │
│                          │   (Internet)    │                              │   │
│                          └─────────────────┘                              │   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Network Details

### Host-Only Network (vboxnet0)

The host-only network provides isolated communication between VMs and the host machine.

| Setting | Value |
|---------|-------|
| Network Address | 192.168.56.0/24 |
| Host IP | 192.168.56.1 |
| Subnet Mask | 255.255.255.0 |
| DHCP | Disabled (DC01 provides DHCP) |

**VirtualBox Configuration Commands:**

```bash
# List existing host-only networks
VBoxManage list hostonlyifs

# Create new host-only network (if needed)
VBoxManage hostonlyif create

# Configure IP address
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0

# Disable VirtualBox DHCP server (DC01 will handle DHCP)
VBoxManage dhcpserver modify --ifname vboxnet0 --disable
```

### NAT Network

VirtualBox NAT provides internet access to all VMs through the host's network connection.

| Setting | Value |
|---------|-------|
| Internal Network | 10.0.2.0/24 |
| Gateway | 10.0.2.2 |
| DNS | 10.0.2.3 |
| Purpose | Internet access |

## Virtual Machine Specifications

### DC01 - Domain Controller

| Resource | Value |
|----------|-------|
| **Role** | Active Directory Domain Services |
| **Base Box** | gusztavvargadr/windows-server-2022-standard |
| **Memory** | 2048 MB (2 GB) |
| **vCPUs** | 2 |
| **Disk** | 60 GB (dynamic) |
| **Host-Only IP** | 192.168.56.10 (static) |
| **NAT IP** | 10.0.2.15 (DHCP) |

**Services:**
- Active Directory Domain Services (AD DS)
- DNS Server (lab.local zone)
- DHCP Server (192.168.56.100-200)

**Port Forwarding:**

| Service | Guest Port | Host Port |
|---------|------------|-----------|
| RDP | 3389 | 33891 |
| WinRM | 5985 | 55851 |

### SCCM01 - Configuration Manager Server

| Resource | Value |
|----------|-------|
| **Role** | SCCM Primary Site + SQL Server |
| **Base Box** | gusztavvargadr/windows-server-2022-standard |
| **Memory** | 4096 MB (4 GB) |
| **vCPUs** | 2 |
| **Disk** | 100 GB (dynamic) |
| **Host-Only IP** | 192.168.56.11 (static) |
| **NAT IP** | 10.0.2.15 (DHCP) |

**Services:**
- SQL Server 2022
- SCCM/ConfigMgr Current Branch
- IIS (Management Point, Distribution Point)
- WSUS (optional)

**Port Forwarding:**

| Service | Guest Port | Host Port |
|---------|------------|-----------|
| RDP | 3389 | 33892 |
| WinRM | 5985 | 55852 |

### CLIENT01-nn - Windows Clients

| Resource | Value |
|----------|-------|
| **Role** | Managed Client |
| **Base Box** | gusztavvargadr/windows-11 |
| **Memory** | 2048 MB (2 GB) |
| **vCPUs** | 2 |
| **Disk** | 60 GB (dynamic) |
| **Host-Only IP** | DHCP (192.168.56.100-200) |
| **NAT IP** | 10.0.2.15 (DHCP) |

**Port Forwarding (per client):**

| Client | RDP Host Port | WinRM Host Port |
|--------|---------------|-----------------|
| CLIENT01 | 33901 | 55901 |
| CLIENT02 | 33902 | 55902 |
| CLIENT03 | 33903 | 55903 |

## Resource Summary

### Default Configuration (1 Client)

| Resource | DC01 | SCCM01 | CLIENT01 | Total |
|----------|------|--------|----------|-------|
| Memory | 2 GB | 4 GB | 2 GB | **8 GB** |
| vCPUs | 2 | 2 | 2 | **6** |
| Disk | 60 GB | 100 GB | 60 GB | **220 GB** |

### With 3 Clients

| Resource | DC01 | SCCM01 | Clients (x3) | Total |
|----------|------|--------|--------------|-------|
| Memory | 2 GB | 4 GB | 6 GB | **12 GB** |
| vCPUs | 2 | 2 | 6 | **10** |
| Disk | 60 GB | 100 GB | 180 GB | **340 GB** |

## Network Communication Matrix

| From → To | DC01 | SCCM01 | Clients | Host | Internet |
|-----------|------|--------|---------|------|----------|
| **DC01** | - | ✅ Host-Only | ✅ Host-Only | ✅ Host-Only | ✅ NAT |
| **SCCM01** | ✅ Host-Only | - | ✅ Host-Only | ✅ Host-Only | ✅ NAT |
| **Clients** | ✅ Host-Only | ✅ Host-Only | ✅ Host-Only | ✅ Host-Only | ✅ NAT |
| **Host** | ✅ 192.168.56.10 | ✅ 192.168.56.11 | ✅ DHCP | - | ✅ Direct |

## Vagrant Commands Reference

### Basic Operations

```bash
# Validate Vagrantfile syntax
vagrant validate

# Check status of all VMs
vagrant status

# Start all VMs
vagrant up

# Start specific VM
vagrant up dc01

# Stop all VMs gracefully
vagrant halt

# Stop specific VM
vagrant halt sccm01

# Restart VM
vagrant reload dc01

# Destroy all VMs (delete)
vagrant destroy -f
```

### Accessing VMs

```bash
# RDP to DC01 (from host)
# Using xfreerdp (Linux):
xfreerdp /v:localhost:33891 /u:vagrant /p:vagrant

# Using rdesktop:
rdesktop localhost:33891 -u vagrant -p vagrant

# WinRM command execution
vagrant winrm dc01 -c "hostname"

# PowerShell remoting (from host with pwsh):
pwsh -c "Enter-PSSession -ComputerName 192.168.56.10 -Credential (Get-Credential)"
```

### Snapshots

```bash
# Create snapshot
vagrant snapshot save dc01 "fresh-install"

# List snapshots
vagrant snapshot list dc01

# Restore snapshot
vagrant snapshot restore dc01 "fresh-install"

# Delete snapshot
vagrant snapshot delete dc01 "fresh-install"
```

### Provisioning

```bash
# Re-run provisioners on a VM
vagrant provision dc01

# Re-run specific provisioner
vagrant provision dc01 --provision-with shell

# Force provision on next up
vagrant up dc01 --provision
```

## Configuration Variables

The Vagrantfile uses environment variables for customization:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLIENT_COUNT` | 1 | Number of client VMs to create |

**Usage:**

```bash
# Create 3 client VMs
CLIENT_COUNT=3 vagrant up
```

## Troubleshooting

### VM Won't Start

1. Check VT-x/AMD-V is enabled in BIOS
2. Verify no other hypervisor is running (Hyper-V, Docker Desktop with Hyper-V)
3. Check VirtualBox logs: `~/.config/VirtualBox/VBoxSVC.log`

### Network Connectivity Issues

1. Verify host-only adapter exists:
   ```bash
   VBoxManage list hostonlyifs
   ```

2. Check VirtualBox DHCP is disabled:
   ```bash
   VBoxManage list dhcpservers
   ```

3. Ping host from VM (should work):
   ```powershell
   ping 192.168.56.1
   ```

### WinRM Connection Timeout

1. Wait for Windows to fully boot (can take 5-10 minutes on first run)
2. Check WinRM port is open:
   ```bash
   nc -zv 192.168.56.10 5985
   ```
3. RDP to VM and verify WinRM service is running:
   ```powershell
   Get-Service WinRM
   Test-WSMan
   ```

### Large Box Download Times

The base boxes are 6-8 GB each. To pre-download:

```bash
vagrant box add gusztavvargadr/windows-server-2022-standard
vagrant box add gusztavvargadr/windows-11
```

## Files Reference

| File | Purpose |
|------|---------|
| `vagrant/Vagrantfile` | Main VM topology definition |
| `vagrant/scripts/bootstrap.ps1` | Initial Windows configuration |
| `vagrant/scripts/enable-winrm.ps1` | WinRM setup for remote management |
| `vagrant/boxes/README.md` | Base box documentation |

## Next Steps

After Phase 2 completion:

1. **Phase 3**: Configure AD DS, DNS, DHCP on DC01
2. **Phase 3**: Install SQL Server and SCCM on SCCM01
3. **Phase 3**: Join clients to domain
4. **Phase 3**: Deploy SCCM client to managed devices

See `.claude/phase3-checklist.md` for detailed Phase 3 tasks.
