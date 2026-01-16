# Phase 5: Cross-Platform Support (Linux Distros)

**Status**: ⚪ Future  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Extend the Nix flake to support major Linux distributions (Ubuntu, Fedora, Arch, Debian), making the lab accessible to non-NixOS users.

## Goals

- [ ] Make flake usable on Ubuntu, Fedora, Arch, Debian
- [ ] Handle distribution-specific differences
- [ ] Maintain NixOS experience on non-NixOS systems
- [ ] Document platform-specific requirements

---

## Prerequisites

- ✅ Phase 1-4 completed and tested on NixOS
- [ ] Access to test VMs or systems for each target distribution
- [ ] Understanding of Nix on non-NixOS systems

---

## Main Tasks

### 1. Flake Cross-Platform Logic

- [ ] Add conditional logic to `flake.nix` for Linux variations
- [ ] Detect host system using `builtins.currentSystem`
- [ ] Create distribution-specific package overrides
- [ ] Handle different package names across distros
- [ ] Test flake structure with `nix flake check`

### 2. VirtualBox Installation Handling

- [ ] Document VirtualBox installation per distribution
  - [ ] Ubuntu/Debian: apt repository
  - [ ] Fedora: RPM Fusion repository
  - [ ] Arch: AUR or official repos
- [ ] Handle kernel module compilation differences
  - [ ] DKMS automatic builds
  - [ ] Manual module compilation fallbacks
  - [ ] Kernel version compatibility checks
- [ ] Handle different package names
  - [ ] Ubuntu: `virtualbox`, `virtualbox-ext-pack`
  - [ ] Fedora: `VirtualBox`, `VirtualBox-server`
  - [ ] Arch: `virtualbox`, `virtualbox-host-modules-arch`
- [ ] Create distribution detection script
  - [ ] Check `/etc/os-release`
  - [ ] Parse `ID` and `VERSION_ID` fields
  - [ ] Provide appropriate instructions

### 3. Vagrant Installation Handling

- [ ] Document Vagrant installation per distribution
  - [ ] HashiCorp official repository (recommended)
  - [ ] Distribution packages (may be outdated)
- [ ] Handle plugin installation differences
  - [ ] Plugin path variations
  - [ ] Ruby version dependencies
  - [ ] System vs. user installation
- [ ] Test Vagrant compatibility
  - [ ] Minimum version: 2.4.0
  - [ ] VirtualBox provider compatibility

### 4. Test on Major Distributions

#### Ubuntu Testing
- [ ] Test on Ubuntu 22.04 LTS
  - [ ] Install Nix
  - [ ] Enable flakes
  - [ ] Run `nix develop`
  - [ ] Verify all tools available
  - [ ] Test VirtualBox VM creation
- [ ] Test on Ubuntu 24.04 LTS
  - [ ] Repeat all tests
  - [ ] Document any differences

#### Fedora Testing
- [ ] Test on Fedora 39
  - [ ] Install Nix
  - [ ] Handle SELinux considerations
  - [ ] Enable flakes
  - [ ] Test VirtualBox with Fedora kernel
- [ ] Test on Fedora 40
  - [ ] Repeat all tests
  - [ ] Test with latest kernel

#### Arch Linux Testing
- [ ] Test on Arch Linux (rolling)
  - [ ] Install Nix from AUR or official
  - [ ] Test with bleeding-edge kernel
  - [ ] Verify VirtualBox DKMS builds
  - [ ] Test Vagrant from AUR

#### Debian Testing
- [ ] Test on Debian 12 (Bookworm)
  - [ ] Install Nix
  - [ ] Handle older package versions
  - [ ] Test VirtualBox from backports if needed

### 5. Handle Distribution-Specific Issues

#### Package Manager Variations
- [ ] Document apt (Debian/Ubuntu) usage
- [ ] Document dnf (Fedora) usage
- [ ] Document pacman (Arch) usage
- [ ] Create helper scripts for common tasks

#### SELinux on Fedora/RHEL
- [ ] Test VirtualBox with SELinux enforcing
- [ ] Document SELinux policy modifications if needed
- [ ] Provide audit2allow rules for common issues
- [ ] Test with SELinux in permissive mode as fallback

#### AppArmor on Ubuntu
- [ ] Test VirtualBox with AppArmor
- [ ] Document AppArmor profile modifications if needed
- [ ] Verify no conflicts with VirtualBox operation

#### Init Systems
- [ ] Verify systemd compatibility (most modern distros)
- [ ] Document service management commands
- [ ] Handle distribution-specific service names

### 6. Create Distribution-Specific Documentation

- [ ] Create `docs/ubuntu-setup.md`
  - [ ] Prerequisites
  - [ ] Nix installation
  - [ ] VirtualBox installation
  - [ ] Vagrant installation
  - [ ] Common issues and solutions
- [ ] Create `docs/fedora-setup.md`
  - [ ] SELinux considerations
  - [ ] RPM Fusion repository setup
  - [ ] Kernel module handling
- [ ] Create `docs/arch-setup.md`
  - [ ] AUR usage
  - [ ] Rolling release considerations
  - [ ] DKMS and kernel updates
- [ ] Create `docs/debian-setup.md`
  - [ ] Backports usage
  - [ ] Older package versions
  - [ ] Manual upgrades if needed

### 7. Permission and Group Management

- [ ] Document adding user to `vboxusers` group
  - [ ] `sudo usermod -aG vboxusers $USER`
  - [ ] Logout/login required
- [ ] Handle distribution-specific group names
- [ ] Test with both regular users and sudoers
- [ ] Document systemd user services if needed

### 8. Kernel Module Management

- [ ] Document DKMS automatic builds
  - [ ] Install `dkms` package
  - [ ] Verify automatic rebuild on kernel updates
- [ ] Create manual module build instructions
  - [ ] `sudo /sbin/vboxconfig`
  - [ ] Troubleshooting module load failures
- [ ] Test with different kernel versions
  - [ ] LTS kernels
  - [ ] Latest stable kernels
  - [ ] Bleeding-edge kernels (Arch)

### 9. Alternative Package Sources

- [ ] Evaluate Flatpak VirtualBox (not recommended)
- [ ] Evaluate Snap VirtualBox (not recommended)
- [ ] Document why native packages preferred
  - [ ] Kernel module access
  - [ ] Performance
  - [ ] Network device creation

### 10. Create Distribution Detection Script

- [ ] Create `scripts/detect-distro.sh`
  - [ ] Parse `/etc/os-release`
  - [ ] Output distribution name and version
  - [ ] Provide appropriate setup instructions
  - [ ] Check for prerequisites
- [ ] Integrate into setup workflow
- [ ] Add to documentation

---

## Sub-tasks & Considerations

### Nix Installation Variations

- [ ] Single-user vs. multi-user installation
- [ ] Distribution-specific Nix packages
- [ ] Nix from official installer vs. distro repos
- [ ] Document `--daemon` vs. non-daemon modes

### Secure Boot Considerations

- [ ] VirtualBox kernel modules require Secure Boot configuration
- [ ] Document module signing process
- [ ] Provide MOK (Machine Owner Key) enrollment steps
- [ ] Alternative: Disable Secure Boot for lab

### Kernel Version Compatibility

- [ ] VirtualBox kernel modules may lag behind bleeding-edge kernels
- [ ] Document known incompatibilities
- [ ] Provide workarounds (use LTS kernel, wait for update)
- [ ] Monitor VirtualBox release notes

### Display Server Compatibility

- [ ] Test with both X11 and Wayland
- [ ] VirtualBox GUI may have Wayland issues
- [ ] Document using headless mode as workaround
- [ ] Test VNC/RDP access alternatives

### Network Manager Variations

- [ ] NetworkManager (most modern distros)
- [ ] systemd-networkd
- [ ] Test host-only adapter creation with each
- [ ] Document any conflicts or issues

---

## Deliverables

- [ ] Updated `flake.nix` with cross-platform support
- [ ] `docs/linux-support.md` - General Linux support overview
- [ ] `docs/ubuntu-setup.md` - Ubuntu-specific guide
- [ ] `docs/fedora-setup.md` - Fedora-specific guide
- [ ] `docs/arch-setup.md` - Arch-specific guide
- [ ] `docs/debian-setup.md` - Debian-specific guide
- [ ] `scripts/detect-distro.sh` - Distribution detection helper
- [ ] Test results matrix documenting compatibility

---

## Potential Issues & Solutions

### Issue: VirtualBox kernel modules won't compile

**Symptoms**: `vboxdrv` module fails to load

**Solutions**:
- Ensure kernel headers installed
- Ubuntu/Debian: `sudo apt install linux-headers-$(uname -r)`
- Fedora: `sudo dnf install kernel-devel kernel-headers`
- Arch: `sudo pacman -S linux-headers`
- Run: `sudo /sbin/vboxconfig`
- Check dmesg for errors: `dmesg | grep -i vbox`

### Issue: Secure Boot prevents module loading

**Symptoms**: "Required key not available" when loading module

**Solutions**:
- Sign kernel modules with MOK
- Enroll key with `mokutil --import`
- Reboot and enroll key via MOK Manager
- Alternative: Disable Secure Boot in BIOS

### Issue: Nix flakes not enabled by default

**Symptoms**: `nix: unrecognized option '--flake'`

**Solutions**:
- Enable in `~/.config/nix/nix.conf`:
  ```
  experimental-features = nix-command flakes
  ```
- May require root on some systems

### Issue: VirtualBox from Flatpak/Snap doesn't work

**Symptoms**: Can't create host-only networks, kernel module issues

**Solutions**:
- Uninstall Flatpak/Snap version
- Install from distribution repository or Oracle
- Native packages required for kernel module access

### Issue: SELinux denials on Fedora

**Symptoms**: VirtualBox operations fail with permission errors

**Solutions**:
- Check audit log: `sudo ausearch -m avc -ts recent`
- Create policy: `sudo ausearch -m avc -ts recent | audit2allow -M vbox_custom`
- Load policy: `sudo semodule -i vbox_custom.pp`
- Alternative: Set SELinux to permissive for testing

### Issue: Old Vagrant version in distro repos

**Symptoms**: Missing features or compatibility issues

**Solutions**:
- Add HashiCorp repository
- Ubuntu/Debian: https://apt.releases.hashicorp.com
- Fedora: https://rpm.releases.hashicorp.com
- Install from HashiCorp repo instead of distro

---

## Testing Checklist

Test on each distribution:

```bash
# Install Nix (if not already installed)
curl -L https://nixos.org/nix/install | sh

# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Clone repo
git clone <repo-url>
cd homelab-SCCM

# Enter dev shell
nix develop

# Verify tools
vagrant --version
VBoxManage --version
pwsh --version

# Test VirtualBox kernel module
lsmod | grep vboxdrv
# Expected: vboxdrv module loaded

# Test host-only network creation
VBoxManage hostonlyif create
VBoxManage list hostonlyifs
# Expected: Interface created

# Test creating a simple VM (from vagrant directory)
cd vagrant
vagrant status
# Expected: Vagrantfile validated

# Exit dev shell
exit
```

---

## Success Criteria

Phase 5 is complete when:

- ✅ Flake works on Ubuntu 22.04 and 24.04 LTS
- ✅ Flake works on Fedora 39 and 40
- ✅ Flake works on Arch Linux (rolling)
- ✅ Flake works on Debian 12
- ✅ VirtualBox kernel modules load on all platforms
- ✅ Vagrant can create VMs on all platforms
- ✅ Documentation covers all distribution-specific issues
- ✅ Distribution detection script works correctly
- ✅ Test matrix documents compatibility status

---

## Next Steps

Once Phase 5 is complete, proceed to:
- **Phase 6**: macOS Support (Darwin)
- See `.claude/phase6-checklist.md`

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

**Distribution Test Results**:
- Ubuntu 22.04: ☐ Pass / ☐ Fail
- Ubuntu 24.04: ☐ Pass / ☐ Fail
- Fedora 39: ☐ Pass / ☐ Fail
- Fedora 40: ☐ Pass / ☐ Fail
- Arch Linux: ☐ Pass / ☐ Fail
- Debian 12: ☐ Pass / ☐ Fail

---

**Phase 5 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
