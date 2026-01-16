# Phase 1: Repository & Flake Foundation (NixOS-only)

**Status**: 🟡 In Progress  
**Start Date**: 2026-01-15  
**Completion Date**: _____

## Overview

Create the reproducible development environment and establish repository structure using Nix flakes.

## Goals

- [ ] Create reproducible development environment
- [ ] Establish repository structure
- [ ] Pin all dependencies with Nix flakes
- [ ] Document entry and usage

---

## Main Tasks

### 1. Repository Initialization

- [ ] Initialize git repository
- [ ] Create .gitignore file
- [ ] Set up branch protection/workflow (optional)
- [ ] Create initial commit

### 2. Flake Development

- [ ] Create `flake.nix` with core dependencies
  - [ ] Add Vagrant (latest stable)
  - [ ] Add VirtualBox (7.0.x or 7.1.x)
  - [ ] Add PowerShell Core (7.x)
  - [ ] Add WinRM/WinRS tools
  - [ ] Add Python (for tooling/automation)
  - [ ] Add git (version control)
- [ ] Define `devShell` for NixOS users
- [ ] Pin nixpkgs to stable release (or specify unstable if needed)
- [ ] Test flake builds successfully: `nix flake check`
- [ ] Test dev shell enters successfully: `nix develop`

### 3. Documentation

- [ ] Create comprehensive README.md
- [ ] Create CLAUDE.md (project documentation)
- [ ] Create docs/topology.md (network architecture)
- [ ] Create docs/nix-setup.md (Nix environment guide)
- [ ] Document flake usage and commands
- [ ] Add troubleshooting section to docs

### 4. Testing & Validation

- [ ] Test flake on fresh NixOS system (if possible)
- [ ] Verify all tools are available in dev shell
  - [ ] `vagrant --version`
  - [ ] `VBoxManage --version`
  - [ ] `pwsh --version`
  - [ ] `python --version`
- [ ] Verify VirtualBox loads correctly
- [ ] Document any platform-specific issues encountered

---

## Sub-tasks & Considerations

### VirtualBox Setup

- [ ] Verify VirtualBox kernel module compatibility with current NixOS kernel
- [ ] Test VirtualBox kernel modules load: `lsmod | grep vbox`
- [ ] Test VirtualBox host-only networking interface creation
- [ ] Verify user is in `vboxusers` group: `groups | grep vboxusers`
- [ ] Test creating host-only adapter: `VBoxManage hostonlyif create`
- [ ] Document any kernel version issues

### PowerShell & WinRM

- [ ] Ensure PowerShell Core can be launched: `pwsh`
- [ ] Test PowerShell modules can access WinRM (may require dotnet runtime)
- [ ] Verify `PSWSMan` module availability (for WinRM on Linux)
- [ ] Test basic WinRM commands (will fail without Windows VM, that's OK)
- [ ] Document dotnet dependencies if needed

### Nix Configuration

- [ ] Document how to enable Nix flakes if not already enabled
- [ ] Add example `/etc/nixos/configuration.nix` snippet for VirtualBox
- [ ] Add example `~/.config/nix/nix.conf` for flakes
- [ ] Test with both NixOS system config and home-manager (if applicable)

### Code Quality

- [ ] Add pre-commit hooks for nix formatting (nixpkgs-fmt or alejandra)
- [ ] Set up consistent formatting standards
- [ ] Add `.editorconfig` for consistent style

### Directory Structure

- [ ] Verify all directories created:
  - [ ] `vagrant/`
  - [ ] `vagrant/scripts/`
  - [ ] `vagrant/boxes/`
  - [ ] `scripts/`
  - [ ] `scripts/modules/`
  - [ ] `pxe/`
  - [ ] `pxe/tftp/`
  - [ ] `docs/`
  - [ ] `container/`
  - [ ] `.devcontainer/`
  - [ ] `tests/`

---

## Deliverables

- [ ] `flake.nix` - Main flake definition
- [ ] `flake.lock` - Pinned dependencies (generated)
- [ ] `README.md` - Quick start guide
- [ ] `.gitignore` - Ignore patterns
- [ ] `docs/topology.md` - Network and VM architecture
- [ ] `docs/nix-setup.md` - Detailed Nix environment setup
- [ ] All directory structure created

---

## Potential Issues & Solutions

### Issue: VirtualBox kernel modules not loading

**Symptoms**: `VBoxManage` commands fail with "kernel driver not loaded"

**Solutions**:
- Ensure `virtualisation.virtualbox.host.enable = true` in NixOS config
- Rebuild system: `sudo nixos-rebuild switch`
- Reboot if kernel was updated
- Check kernel module: `modprobe vboxdrv`

### Issue: User not in vboxusers group

**Symptoms**: Permission denied on `/dev/vboxdrv`

**Solutions**:
- Add user to group: `sudo usermod -aG vboxusers $USER`
- Logout and login again
- Verify: `groups | grep vboxusers`

### Issue: Flakes not recognized

**Symptoms**: `nix: unrecognized option '--flake'`

**Solutions**:
- Enable flakes in `~/.config/nix/nix.conf`:
  ```
  experimental-features = nix-command flakes
  ```
- Or in `/etc/nixos/configuration.nix`:
  ```nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  ```

### Issue: VirtualBox requires unfree license acceptance

**Symptoms**: VirtualBox fails to build due to unfree license

**Solutions**:
- Enable unfree packages in NixOS config:
  ```nix
  nixpkgs.config.allowUnfree = true;
  ```
- Or allow specific package in flake

### Issue: PowerShell WinRM modules missing

**Symptoms**: WinRM commands fail in PowerShell

**Solutions**:
- Install `PSWSMan` module (Phase 3 will address this)
- For now, just verify PowerShell launches
- Document for Phase 3 automation layer

---

## Testing Checklist

Run these commands to verify Phase 1 completion:

```bash
# Enter dev shell
nix develop

# Verify Vagrant
vagrant --version
# Expected: Vagrant 2.4.0 or higher

# Verify VirtualBox
VBoxManage --version
# Expected: 7.0.x or 7.1.x

# Verify PowerShell
pwsh --version
# Expected: PowerShell 7.4.0 or higher

# Verify Python
python --version
# Expected: Python 3.11 or higher

# Test VirtualBox kernel module
lsmod | grep vboxdrv
# Expected: vboxdrv module listed

# Test host-only network creation
VBoxManage list hostonlyifs
# Expected: List of host-only interfaces (may be empty initially)

# Exit dev shell
exit
```

---

## Success Criteria

Phase 1 is complete when:

- ✅ Git repository initialized with proper structure
- ✅ `flake.nix` builds without errors
- ✅ `nix develop` enters dev shell successfully
- ✅ All required tools (Vagrant, VirtualBox, PowerShell) are accessible
- ✅ VirtualBox kernel modules load properly
- ✅ Documentation is comprehensive and accurate
- ✅ Directory structure matches specification
- ✅ Can create VirtualBox host-only network adapter

---

## Next Steps

Once Phase 1 is complete, proceed to:
- **Phase 2**: Vagrant Multi-VM Topology
- See `.claude/phase2-checklist.md`

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

---

**Phase 1 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
