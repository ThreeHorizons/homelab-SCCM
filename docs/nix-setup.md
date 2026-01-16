# NixOS Setup Guide for Homelab SCCM

This guide explains how to configure your NixOS system to support the Homelab SCCM development environment.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Enable Nix Flakes](#enable-nix-flakes)
3. [Configure VirtualBox](#configure-virtualbox)
4. [Verify Setup](#verify-setup)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- NixOS 23.11 or newer
- At least 16GB RAM (32GB recommended)
- CPU with VT-x/AMD-V virtualization support
- 100GB+ free disk space (SSD recommended)

---

## Enable Nix Flakes

Nix Flakes are an experimental feature that must be explicitly enabled.

### What are Flakes?

Flakes provide:
- **Reproducible builds**: Lock files ensure everyone gets the same versions
- **Declarative dependencies**: All tools specified in one file (`flake.nix`)
- **Composability**: Flakes can depend on other flakes
- **Standardized structure**: Consistent across all projects

### How to Enable Flakes

You have two options:

#### Option 1: System-wide (Recommended)

Edit `/etc/nixos/configuration.nix` and add:

```nix
{
  # Enable Nix Flakes and the unified nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

Then rebuild your system:

```bash
sudo nixos-rebuild switch
```

#### Option 2: Per-user

Create or edit `~/.config/nix/nix.conf`:

```conf
experimental-features = nix-command flakes
```

No rebuild needed, but only works for your user account.

---

## Configure VirtualBox

VirtualBox requires kernel modules and special permissions on NixOS.

### Why System Configuration is Needed

Unlike other Linux distributions, NixOS doesn't allow packages to modify the system directly. VirtualBox needs:
- **Kernel modules** (`vboxdrv`, `vboxnetflt`, `vboxnetadp`) - loaded at boot
- **vboxusers group** - for permission management
- **Kernel headers** - to compile modules for your specific kernel

These require system-level configuration.

### Add VirtualBox to System Configuration

Edit `/etc/nixos/configuration.nix` and add:

```nix
{
  # Enable VirtualBox
  virtualisation.virtualbox.host.enable = true;
  
  # Add your user to the vboxusers group
  # Replace 'yourusername' with your actual username
  users.users.yourusername.extraGroups = [ "vboxusers" ];
  
  # Allow unfree packages (VirtualBox has a proprietary license)
  nixpkgs.config.allowUnfree = true;
}
```

**Important**: Replace `yourusername` with your actual username (check with `whoami`).

### Example Complete Configuration

Here's a minimal example `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  # Import hardware configuration
  imports = [ ./hardware-configuration.nix ];

  # Boot loader configuration (example - yours may differ)
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # Enable Nix Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Enable VirtualBox
  virtualisation.virtualbox.host.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # User configuration
  users.users.myusername = {
    isNormalUser = true;
    extraGroups = [ 
      "wheel"      # Enable sudo
      "vboxusers"  # Enable VirtualBox
      "networkmanager"  # Manage network
    ];
  };

  # System packages (optional - the flake provides dev tools)
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];

  # Networking
  networking.hostName = "nixos-homelab";
  networking.networkmanager.enable = true;

  # System state version (don't change after installation)
  system.stateVersion = "24.05";
}
```

### Rebuild and Activate

After editing the configuration:

```bash
# Check for syntax errors
sudo nixos-rebuild dry-build

# Apply the configuration
sudo nixos-rebuild switch

# Reboot to ensure kernel modules load
sudo reboot
```

---

## Verify Setup

After rebooting, verify everything is configured correctly:

### 1. Check Nix Flakes

```bash
nix flake --help
```

Expected output: Help text for flake commands (no "unrecognized option" error)

### 2. Check VirtualBox Kernel Modules

```bash
lsmod | grep vbox
```

Expected output:
```
vboxnetflt             32768  0
vboxnetadp             28672  0
vboxdrv               577536  2 vboxnetadp,vboxnetflt
```

### 3. Check vboxusers Group Membership

```bash
groups | grep vboxusers
```

Expected output: Should include `vboxusers` in the list

**Important**: If you just added yourself to the group, you must **logout and login** for it to take effect.

### 4. Test VirtualBox

```bash
VBoxManage --version
```

Expected output: Version number like `7.0.22r165102`

```bash
VBoxManage list hostonlyifs
```

Expected output: Either a list of interfaces or an empty list (no permission errors)

### 5. Enter Development Environment

Navigate to the project directory and enter the flake dev shell:

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
  - Vagrant: Vagrant 2.4.1
  - VirtualBox: 7.0.22r165102
  - PowerShell: PowerShell 7.4.2
  - Python: Python 3.11.10
```

**No warnings** about vboxusers group should appear.

---

## Troubleshooting

### Flakes Not Recognized

**Problem**: `nix: unrecognized option '--flake'`

**Solution**: Enable experimental features (see [Enable Nix Flakes](#enable-nix-flakes))

---

### VirtualBox Kernel Module Not Loading

**Problem**: `lsmod | grep vbox` returns nothing

**Solution**:

```bash
# Try loading manually
sudo modprobe vboxdrv

# If it fails, check dmesg for errors
dmesg | grep -i vbox

# Rebuild NixOS configuration
sudo nixos-rebuild switch

# Reboot
sudo reboot
```

---

### Permission Denied on /dev/vboxdrv

**Problem**: `VBoxManage` commands fail with "Permission denied"

**Solution**:

```bash
# Check if you're in vboxusers group
groups | grep vboxusers

# If not, add yourself in /etc/nixos/configuration.nix
# Then logout and login (or reboot)
```

---

### VirtualBox Extension Pack Issues

**Problem**: Some VirtualBox features don't work

**Solution**: The extension pack is proprietary and requires manual installation:

```bash
# Download extension pack
cd ~/Downloads
wget https://download.virtualbox.org/virtualbox/7.0.22/Oracle_VirtualBox_Extension_Pack-7.0.22.vbox-extpack

# Install (requires accepting license)
VBoxManage extpack install Oracle_VirtualBox_Extension_Pack-7.0.22.vbox-extpack
```

---

### Unfree Package Error

**Problem**: Build fails with "unfree package 'virtualbox' is not allowed"

**Solution**: Add to `/etc/nixos/configuration.nix`:

```nix
{
  nixpkgs.config.allowUnfree = true;
}
```

Then `sudo nixos-rebuild switch`

---

### Host-Only Network Creation Fails

**Problem**: Cannot create host-only network adapter

**Solution**: On Linux, VirtualBox restricts host-only networks to specific ranges. Create `/etc/vbox/networks.conf`:

```bash
# Create VirtualBox config directory
sudo mkdir -p /etc/vbox

# Allow specific network ranges
echo "* 192.168.56.0/21" | sudo tee /etc/vbox/networks.conf
```

---

## Additional Resources

- [NixOS Manual - VirtualBox](https://nixos.org/manual/nixos/stable/index.html#sec-virtualbox)
- [Nix Flakes Manual](https://nixos.wiki/wiki/Flakes)
- [VirtualBox on Linux - Official Docs](https://www.virtualbox.org/manual/ch02.html#install-linux-host)

---

## Next Steps

Once your NixOS system is configured:

1. ✅ Flakes enabled
2. ✅ VirtualBox configured
3. ✅ User in vboxusers group
4. ✅ Can enter `nix develop` without warnings

Proceed to:
- **Phase 2**: Vagrant Multi-VM Topology (see `.claude/phase2-checklist.md`)
- Read `docs/topology.md` for network architecture overview

---

**Last Updated**: 2026-01-16  
**Tested On**: NixOS 24.05
