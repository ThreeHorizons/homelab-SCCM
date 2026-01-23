# Nix Environment Setup Guide for Homelab SCCM

This guide explains how to set up the development environment for the Homelab SCCM project across different platforms.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Install VirtualBox](#install-virtualbox)
3. [Enable Nix Flakes](#enable-nix-flakes)
4. [Verify Setup](#verify-setup)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- At least 16GB RAM (32GB recommended)
- CPU with VT-x/AMD-V virtualization support
- 100GB+ free disk space (SSD recommended)
- Nix package manager (comes with NixOS, or install separately on other systems)

---

## Install VirtualBox

VirtualBox must be installed at the **system level** before using this project. The development environment (flake) provides Vagrant and other tools, but VirtualBox requires kernel modules and platform-specific integration that cannot be provided by Nix.

### NixOS

Edit `/etc/nixos/configuration.nix`:

```nix
{
  # Enable VirtualBox
  virtualisation.virtualbox.host.enable = true;
  
  # Add your user to the vboxusers group
  # Replace 'yourusername' with your actual username
  users.users.yourusername.extraGroups = [ "vboxusers" ];
}
```

Apply the configuration:

```bash
sudo nixos-rebuild switch
sudo reboot
```

### Ubuntu / Debian

```bash
# Install VirtualBox
sudo apt update
sudo apt install virtualbox

# Add yourself to vboxusers group
sudo usermod -aG vboxusers $USER

# Logout and login for group membership to take effect
```

### Fedora

```bash
# Add RPM Fusion repository (if not already added)
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm

# Install VirtualBox
sudo dnf install VirtualBox

# Add yourself to vboxusers group
sudo usermod -aG vboxusers $USER

# Logout and login for group membership to take effect
```

### Arch Linux

```bash
# Install VirtualBox and kernel modules for your kernel
# For linux kernel:
sudo pacman -S virtualbox virtualbox-host-modules-arch

# For other kernels (e.g., linux-lts):
sudo pacman -S virtualbox virtualbox-host-dkms

# Load kernel module
sudo modprobe vboxdrv

# Add yourself to vboxusers group
sudo usermod -aG vboxusers $USER

# Logout and login for group membership to take effect
```

### macOS

1. Download VirtualBox from [virtualbox.org](https://www.virtualbox.org/wiki/Downloads)
2. Open the `.dmg` file and run the installer
3. During installation, approve the kernel extension in **System Settings > Privacy & Security**
4. Reboot after installation

**Apple Silicon (M1/M2/M3) Note**: VirtualBox support for ARM-based Macs is experimental. Check the [VirtualBox downloads page](https://www.virtualbox.org/wiki/Downloads) for the latest ARM64 builds.

### Verify VirtualBox Installation

After installation, verify VirtualBox is working:

```bash
# Check version
VBoxManage --version

# Check kernel modules (Linux only)
lsmod | grep vbox

# Test creating a host-only network
VBoxManage hostonlyif create
```

---

## Enable Nix Flakes

Nix Flakes provide reproducible dependencies for this project. If you're on NixOS, you may already have flakes enabled.

### What are Flakes?

Flakes provide:
- **Reproducible builds**: Lock files ensure everyone gets the same versions
- **Declarative dependencies**: All tools specified in one file (`flake.nix`)
- **Composability**: Flakes can depend on other flakes
- **Cross-platform support**: Same flake works on Linux and macOS

### How to Enable Flakes

#### NixOS (System-wide)

Edit `/etc/nixos/configuration.nix`:

```nix
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

#### Any Platform (Per-user)

Create or edit `~/.config/nix/nix.conf`:

```conf
experimental-features = nix-command flakes
```

No restart needed.

---

## Verify Setup

After completing the setup, verify everything works:

### 1. Check VirtualBox

```bash
VBoxManage --version
```

Expected: Version number like `7.2.4r170995`

### 2. Check Kernel Modules (Linux only)

```bash
lsmod | grep vbox
```

Expected output:
```
vboxnetflt             45056  0
vboxnetadp             32768  0
vboxdrv               679936  2 vboxnetadp,vboxnetflt
```

### 3. Check vboxusers Group (Linux only)

```bash
groups | grep vboxusers
```

Expected: `vboxusers` should appear in the list. If not, logout and login again.

### 4. Check Nix Flakes

```bash
nix flake --help
```

Expected: Help text for flake commands (no "unrecognized option" error)

### 5. Enter Development Environment

```bash
cd /path/to/homelab-SCCM
nix develop
```

Expected output:
```
==============================================
  Homelab SCCM Development Environment
==============================================

Available tools:
  - Vagrant: Vagrant 2.4.x
  - VirtualBox: 7.x.x
  - PowerShell: PowerShell 7.x
  - Python: Python 3.x
```

---

## Troubleshooting

### VirtualBox Not Found in Dev Shell

**Problem**: `nix develop` shows "VirtualBox is not installed"

**Solution**: VirtualBox must be installed at the system level, not through the flake. Follow the installation instructions for your platform above.

---

### Flakes Not Recognized

**Problem**: `nix: unrecognized option '--flake'`

**Solution**: Enable experimental features (see [Enable Nix Flakes](#enable-nix-flakes))

---

### VirtualBox Kernel Module Not Loading (Linux)

**Problem**: `lsmod | grep vbox` returns nothing

**Solution**:

```bash
# Try loading manually
sudo modprobe vboxdrv

# If it fails, check dmesg for errors
dmesg | grep -i vbox

# On NixOS, rebuild configuration
sudo nixos-rebuild switch

# On other distros, reinstall VirtualBox or kernel modules
# Then reboot
sudo reboot
```

---

### Permission Denied on /dev/vboxdrv (Linux)

**Problem**: `VBoxManage` commands fail with "Permission denied"

**Solution**:

```bash
# Check group membership
groups | grep vboxusers

# If not in group, add yourself
sudo usermod -aG vboxusers $USER

# Logout and login again (or reboot)
```

---

### Host-Only Network Creation Fails

**Problem**: Cannot create host-only network adapter

**Solution**: On Linux, VirtualBox restricts host-only networks to specific IP ranges. Create `/etc/vbox/networks.conf`:

```bash
sudo mkdir -p /etc/vbox
echo "* 192.168.56.0/21" | sudo tee /etc/vbox/networks.conf
```

---

### VirtualBox Extension Pack Issues

**Problem**: Some VirtualBox features (USB 2.0/3.0, disk encryption) don't work

**Solution**: Install the VirtualBox Extension Pack:

```bash
# Download extension pack (adjust version to match your VirtualBox)
wget https://download.virtualbox.org/virtualbox/7.2.4/Oracle_VirtualBox_Extension_Pack-7.2.4.vbox-extpack

# Install
VBoxManage extpack install Oracle_VirtualBox_Extension_Pack-7.2.4.vbox-extpack
```

---

### macOS Kernel Extension Not Approved

**Problem**: VirtualBox fails to start VMs on macOS

**Solution**:
1. Open **System Settings** > **Privacy & Security**
2. Look for a message about Oracle being blocked
3. Click **Allow** to approve the kernel extension
4. Reboot

---

### Secure Boot Blocking VirtualBox (Linux)

**Problem**: VirtualBox modules fail to load on systems with Secure Boot

**Solution**: Either disable Secure Boot in BIOS, or sign the VirtualBox kernel modules. Signing process varies by distribution - consult your distro's documentation.

---

## Additional Resources

- [VirtualBox User Manual](https://www.virtualbox.org/manual/)
- [NixOS Manual - VirtualBox](https://nixos.org/manual/nixos/stable/index.html#sec-virtualbox)
- [Nix Flakes Documentation](https://wiki.nixos.org/wiki/Flakes)

---

## Next Steps

Once your environment is configured:

1. VirtualBox installed and working
2. Nix flakes enabled
3. User in vboxusers group (Linux)
4. Can enter `nix develop` successfully

Proceed to:
- **Phase 2**: Vagrant Multi-VM Topology
- Read `docs/topology.md` for network architecture overview

---

**Last Updated**: 2026-01-16
