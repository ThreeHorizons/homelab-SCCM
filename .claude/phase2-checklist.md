# Phase 2: Vagrant Multi-VM Topology

**Status**: ⚪ Planned  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Define declarative VM infrastructure using Vagrant and VirtualBox, establishing the base topology for the SCCM lab.

## Goals

- [ ] Define declarative VM infrastructure
- [ ] Automate VM provisioning
- [ ] Create base Windows boxes
- [ ] Establish network connectivity

---

## Prerequisites

- ✅ Phase 1 completed (Nix flake and dev environment ready)
- [ ] Windows Server 2022 evaluation ISO downloaded or Vagrant box identified
- [ ] Windows 10/11 evaluation ISO downloaded or Vagrant box identified
- [ ] Sufficient disk space available (100GB+ recommended)

---

## Main Tasks

### 1. Base Box Selection & Preparation

- [ ] Research and select Windows Server 2022 base box
  - [ ] Option: `gusztavvargadr/windows-server-2022-standard`
  - [ ] Option: `StefanScherer/windows_2022`
  - [ ] Option: Build custom box with Packer
- [ ] Research and select Windows 10/11 client base box
  - [ ] Option: `gusztavvargadr/windows-10`
  - [ ] Option: `gusztavvargadr/windows-11`
  - [ ] Option: Build custom box with Packer
- [ ] Add selected boxes to Vagrant: `vagrant box add <box-name>`
- [ ] Verify boxes downloaded successfully: `vagrant box list`
- [ ] Document box versions and sources in `vagrant/boxes/README.md`

### 2. Vagrantfile Development

- [ ] Create `vagrant/Vagrantfile`
- [ ] Define multi-machine configuration
- [ ] Configure DC01 (Domain Controller)
  - [ ] Set VM name and hostname
  - [ ] Set base box
  - [ ] Configure memory (2GB)
  - [ ] Configure CPUs (2)
  - [ ] Configure disk size (60GB)
  - [ ] Configure network adapters (Host-Only + NAT)
  - [ ] Set static IP: 192.168.56.10
- [ ] Configure SCCM01 (SCCM Server)
  - [ ] Set VM name and hostname
  - [ ] Set base box
  - [ ] Configure memory (4GB)
  - [ ] Configure CPUs (2)
  - [ ] Configure disk size (100GB)
  - [ ] Configure network adapters (Host-Only + NAT)
  - [ ] Set static IP: 192.168.56.11
- [ ] Configure CLIENT01 (Windows Client)
  - [ ] Set VM name and hostname
  - [ ] Set base box
  - [ ] Configure memory (2GB)
  - [ ] Configure CPUs (2)
  - [ ] Configure disk size (60GB)
  - [ ] Configure network adapters (Host-Only + NAT)
  - [ ] Use DHCP for IP assignment
- [ ] Parameterize client VM count (environment variable or config)
- [ ] Add VirtualBox-specific customizations
  - [ ] GUI mode settings (headless by default)
  - [ ] Graphics controller configuration
  - [ ] Clipboard/drag-and-drop settings

### 3. Network Configuration

- [ ] Create/verify VirtualBox host-only network (vboxnet0)
  - [ ] Run: `VBoxManage hostonlyif create`
  - [ ] Configure: `VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0`
- [ ] Disable VirtualBox DHCP on host-only network (DC01 will handle DHCP)
  - [ ] Run: `VBoxManage dhcpserver modify --ifname vboxnet0 --disable`
- [ ] Test NAT network provides internet access
- [ ] Document network topology in Vagrantfile comments

### 4. Bootstrap Scripts

- [ ] Create `vagrant/scripts/bootstrap.ps1`
  - [ ] Set computer name
  - [ ] Configure timezone
  - [ ] Disable Windows Firewall (temporarily for setup)
  - [ ] Set network adapter priorities
  - [ ] Configure Windows Update settings (disable for lab)
  - [ ] Enable Remote Desktop
  - [ ] Set execution policy for PowerShell scripts
- [ ] Create `vagrant/scripts/enable-winrm.ps1`
  - [ ] Enable PowerShell Remoting
  - [ ] Configure WinRM listeners (HTTP/HTTPS)
  - [ ] Configure TrustedHosts
  - [ ] Set WinRM service to automatic
  - [ ] Open firewall ports for WinRM (5985, 5986)
  - [ ] Test WinRM connectivity
- [ ] Add provisioning steps to Vagrantfile
  - [ ] Use `shell` provisioner for PowerShell scripts
  - [ ] Set appropriate execution order

### 5. Testing & Validation

- [ ] Test Vagrantfile syntax: `vagrant validate`
- [ ] Bring up DC01 only: `vagrant up dc01`
  - [ ] Verify VM boots successfully
  - [ ] Verify network connectivity (ping host)
  - [ ] Verify WinRM is accessible
  - [ ] RDP to DC01 and verify settings
- [ ] Bring up SCCM01: `vagrant up sccm01`
  - [ ] Verify VM boots successfully
  - [ ] Verify network connectivity (ping DC01)
  - [ ] Verify WinRM is accessible
  - [ ] Test connectivity between DC01 and SCCM01
- [ ] Bring up CLIENT01: `vagrant up client01`
  - [ ] Verify VM boots successfully
  - [ ] Verify DHCP assignment (should get 192.168.56.x)
  - [ ] Verify network connectivity
  - [ ] Verify WinRM is accessible
- [ ] Test multiple client provisioning (if parameterized)
- [ ] Create snapshots: `vagrant snapshot save <vm> <snapshot-name>`

---

## Sub-tasks & Considerations

### Base Box Evaluation

- [ ] Research available Windows Server 2022 Vagrant boxes
- [ ] Check VirtualBox Guest Additions version compatibility
- [ ] Verify WinRM is pre-configured in base boxes
- [ ] Consider building custom boxes with Packer for long-term use
- [ ] Test box compatibility with VirtualBox 7.0.x/7.1.x
- [ ] Document evaluation license expiration dates
  - Server 2022: 180 days
  - Windows 10/11: 90 days

### Vagrantfile Best Practices

- [ ] Use Ruby variables for common settings (memory, CPU)
- [ ] Parameterize client count via environment variable
- [ ] Add descriptive comments throughout Vagrantfile
- [ ] Use consistent naming conventions
- [ ] Implement error handling for network creation
- [ ] Add provider checks (ensure VirtualBox is available)

### VirtualBox Configuration

- [ ] Test with both BIOS and UEFI boot modes
- [ ] Configure VirtualBox guest additions auto-update
- [ ] Set up shared folders if needed for file transfers
- [ ] Document Windows licensing requirements
- [ ] Test snapshot functionality for quick rollback
- [ ] Implement naming convention for VMs (prefix-based)
- [ ] Configure VM group in VirtualBox GUI (optional)

### Network Troubleshooting

- [ ] Verify host-only adapter created: `VBoxManage list hostonlyifs`
- [ ] Check routing between VMs: `ping` tests
- [ ] Verify NAT provides internet access: `ping 8.8.8.8`
- [ ] Test DNS resolution from VMs
- [ ] Document `/etc/vbox/networks.conf` if custom ranges needed

### Performance Optimization

- [ ] Enable nested virtualization if needed (not for this project)
- [ ] Configure VirtualBox paravirtualization (KVM on Linux host)
- [ ] Use dynamically allocated disks to save space
- [ ] Consider using linked clones for clients (saves disk space)

---

## Deliverables

- [ ] `vagrant/Vagrantfile` - Multi-machine topology definition
- [ ] `vagrant/scripts/bootstrap.ps1` - Initial Windows configuration
- [ ] `vagrant/scripts/enable-winrm.ps1` - WinRM setup for automation
- [ ] `vagrant/boxes/README.md` - Documentation on base box selection (already exists)
- [ ] `docs/vagrant-topology.md` - VM specifications and networking details

---

## Potential Issues & Solutions

### Issue: Large base boxes (6-8GB per Windows Server box)

**Symptoms**: Long download times, insufficient disk space

**Solutions**:
- Use wired connection for faster downloads
- Download boxes during off-hours
- Ensure 50GB+ free space for box cache
- Consider building custom boxes with minimal features

### Issue: VirtualBox 7.x compatibility with older boxes

**Symptoms**: VMs fail to boot, guest additions errors

**Solutions**:
- Use boxes specifically built for VirtualBox 7.x
- Update VirtualBox Guest Additions manually
- Check box provider compatibility before adding

### Issue: WinRM not enabled by default on base boxes

**Symptoms**: Vagrant provisioning hangs or fails

**Solutions**:
- Use boxes known to have WinRM pre-configured
- Boot VM manually, enable WinRM, repackage box
- Use `enable-winrm.ps1` as first provisioning step

### Issue: Host-only adapter routing issues

**Symptoms**: VMs can't communicate with each other

**Solutions**:
- Verify adapter IP: `VBoxManage list hostonlyifs`
- Check VM network adapter is attached to correct interface
- Disable Windows Firewall temporarily for testing
- Verify VirtualBox DHCP is disabled

### Issue: Windows evaluation licenses expire

**Symptoms**: Windows activation warnings, features disabled

**Solutions**:
- Extend license: `slmgr /rearm` (up to 5 times for servers)
- Use MSDN licenses if available
- Rebuild lab from scratch with fresh evaluation
- Build custom boxes with volume licenses

### Issue: VirtualBox requires VT-x/AMD-V CPU extensions

**Symptoms**: "VT-x is disabled" or "AMD-V is disabled" error

**Solutions**:
- Enable VT-x/AMD-V in BIOS/UEFI settings
- Disable Hyper-V on Windows hosts (conflicts with VirtualBox)
- Check CPU compatibility: `egrep -c '(vmx|svm)' /proc/cpuinfo`

---

## Testing Checklist

Run these commands to verify Phase 2 completion:

```bash
# Enter dev shell
nix develop

# Navigate to vagrant directory
cd vagrant

# Validate Vagrantfile syntax
vagrant validate
# Expected: "Vagrantfile validated successfully"

# Check Vagrant status
vagrant status
# Expected: List of all defined VMs

# Bring up DC01
vagrant up dc01
# Expected: VM boots, provisioning completes

# Test WinRM connectivity to DC01
# From PowerShell Core on host
pwsh -c "Test-NetConnection -ComputerName 192.168.56.10 -Port 5985"
# Expected: TcpTestSucceeded: True

# Bring up SCCM01
vagrant up sccm01

# Bring up CLIENT01
vagrant up client01

# Test inter-VM connectivity
vagrant ssh dc01 -c "ping -n 2 192.168.56.11"
# Expected: Successful ping to SCCM01

# List running VMs
VBoxManage list runningvms
# Expected: All VMs listed

# Create snapshots
vagrant snapshot save dc01 "base-install"
vagrant snapshot save sccm01 "base-install"
vagrant snapshot save client01 "base-install"
# Expected: Snapshots created successfully
```

---

## Success Criteria

Phase 2 is complete when:

- ✅ Vagrantfile defines all VMs (DC01, SCCM01, CLIENT01+)
- ✅ All VMs boot successfully with `vagrant up`
- ✅ VMs have correct network configuration (static IPs for servers, DHCP for clients)
- ✅ WinRM is accessible on all VMs
- ✅ VMs can communicate with each other (ping tests)
- ✅ VMs have internet access via NAT
- ✅ Bootstrap scripts execute successfully
- ✅ Snapshots can be created and restored
- ✅ Documentation accurately reflects topology

---

## Next Steps

Once Phase 2 is complete, proceed to:
- **Phase 3**: WinRM Automation Layer
- See `.claude/phase3-checklist.md`

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

---

**Phase 2 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
