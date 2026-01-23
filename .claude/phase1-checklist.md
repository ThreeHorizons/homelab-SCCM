# Phase 1: Repository & Flake Foundation (NixOS-only)

**Status**: Complete  
**Start Date**: 2026-01-15  
**Completion Date**: 2026-01-16

## Overview

Create the reproducible development environment and establish repository structure using Nix flakes.

## Goals

- [x] Create reproducible development environment
- [x] Establish repository structure
- [x] Pin all dependencies with Nix flakes
- [x] Document entry and usage

---

## Main Tasks

### 1. Repository Initialization

- [x] Initialize git repository
- [x] Create .gitignore file
- [x] Set up branch protection/workflow (optional)
- [x] Create initial commit

### 2. Flake Development

- [x] Create `flake.nix` with core dependencies
  - [x] Add Vagrant (latest stable)
  - [x] Add PowerShell Core (7.x)
  - [x] Add WinRM/WinRS tools (available via PowerShell)
  - [x] Add Python (for tooling/automation)
  - [x] Add git (version control)
- [x] Define `devShell` for NixOS users
- [x] Pin nixpkgs to nixos-unstable
- [x] Test flake builds successfully: `nix flake check`
- [x] Test dev shell enters successfully: `nix develop`

**Note**: VirtualBox is a system-level prerequisite, not provided by the flake. It requires kernel modules and setuid wrappers that must be installed at the OS level.

### 3. Documentation

- [x] Create comprehensive README.md
- [x] Create CLAUDE.md (project documentation)
- [x] Create docs/topology.md (network architecture) - Pre-existing
- [x] Create docs/nix-setup.md (Nix environment guide with VirtualBox installation)
- [x] Document flake usage and commands
- [x] Add troubleshooting section to docs

### 4. Testing & Validation

- [x] Test flake on fresh NixOS system (if possible)
- [x] Verify all tools are available in dev shell
  - [x] `vagrant --version`
  - [x] `VBoxManage --version` (from system installation)
  - [x] `pwsh --version`
  - [x] `python --version`
- [x] Verify VirtualBox loads correctly (system-installed)
- [x] Document any platform-specific issues encountered

---

## Sub-tasks & Considerations

### VirtualBox Setup (System Prerequisite)

VirtualBox must be installed at the system level. Installation varies by platform:

| Platform | Installation |
|----------|-------------|
| **NixOS** | `virtualisation.virtualbox.host.enable = true;` in configuration.nix |
| **Ubuntu/Debian** | `sudo apt install virtualbox` |
| **Fedora** | `sudo dnf install VirtualBox` |
| **Arch Linux** | `sudo pacman -S virtualbox virtualbox-host-modules-arch` |
| **macOS** | Download from virtualbox.org |

- [x] Document VirtualBox installation for each supported platform
- [x] Test VirtualBox kernel modules load: `lsmod | grep vbox`
- [x] Test VirtualBox host-only networking interface creation
- [x] Verify user is in `vboxusers` group: `groups | grep vboxusers`
- [x] Test creating host-only adapter: `VBoxManage hostonlyif create`

### PowerShell & WinRM

- [x] Ensure PowerShell Core can be launched: `pwsh`
- [x] Test PowerShell modules can access WinRM (may require dotnet runtime) - Deferred to Phase 3
- [x] Verify `PSWSMan` module availability (for WinRM on Linux) - Deferred to Phase 3
- [x] Test basic WinRM commands (will fail without Windows VM, that's OK) - Deferred to Phase 3
- [x] Document dotnet dependencies if needed - Documented in nix-setup.md

### Nix Configuration

- [x] Document how to enable Nix flakes if not already enabled
- [x] Add example `/etc/nixos/configuration.nix` snippet for VirtualBox
- [x] Add example `~/.config/nix/nix.conf` for flakes
- [x] Test with both NixOS system config and home-manager (if applicable)

### Code Quality

- [ ] Add pre-commit hooks for nix formatting (nixpkgs-fmt or alejandra) - Optional for Phase 1
- [ ] Set up consistent formatting standards - Optional for Phase 1
- [ ] Add `.editorconfig` for consistent style - Optional for Phase 1

### Directory Structure

- [x] Verify all directories created:
  - [x] `vagrant/`
  - [x] `vagrant/scripts/`
  - [x] `vagrant/boxes/`
  - [x] `scripts/`
  - [x] `scripts/modules/`
  - [x] `pxe/`
  - [x] `pxe/tftp/`
  - [x] `docs/`
  - [x] `container/`
  - [x] `.devcontainer/`
  - [x] `tests/`

---

## Deliverables

- [x] `flake.nix` - Main flake definition
- [x] `flake.lock` - Pinned dependencies (generated)
- [x] `README.md` - Quick start guide
- [x] `.gitignore` - Ignore patterns (pre-existing)
- [x] `docs/topology.md` - Network and VM architecture (pre-existing)
- [x] `docs/nix-setup.md` - Detailed Nix environment setup (including VirtualBox installation)
- [x] All directory structure created

---

## Potential Issues & Solutions

### Issue: VirtualBox not found in dev shell

**Symptoms**: `nix develop` shows "VirtualBox is not installed"

**Solutions**:
- VirtualBox must be installed at the system level, not via the flake
- Follow platform-specific installation instructions in `docs/nix-setup.md`
- On NixOS: Add `virtualisation.virtualbox.host.enable = true;` to configuration.nix

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
# Verify VirtualBox is installed (system-level)
VBoxManage --version
# Expected: 7.0+ version

# Enter dev shell
nix develop

# Verify Vagrant
vagrant --version
# Expected: Vagrant 2.4.0 or higher

# Verify VirtualBox is accessible
VBoxManage --version
# Expected: Same version as system

# Verify PowerShell
pwsh --version
# Expected: PowerShell 7.4.0 or higher

# Verify Python
python --version
# Expected: Python 3.11 or higher

# Test VirtualBox kernel module (Linux only)
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

- Git repository initialized with proper structure
- `flake.nix` builds without errors
- `nix develop` enters dev shell successfully
- VirtualBox installed at system level and accessible
- All flake-provided tools (Vagrant, PowerShell) are accessible
- VirtualBox kernel modules load properly
- Documentation is comprehensive and accurate
- Directory structure matches specification
- Can create VirtualBox host-only network adapter

---

## Next Steps

Once Phase 1 is complete, proceed to:
- **Phase 2**: Vagrant Multi-VM Topology
- See `.claude/phase2-checklist.md`

---

## Notes

**Date**: 2026-01-16  
**Notes**: 

### Key Learnings

1. **Nix Flakes Require Git Tracking**: All flake files must be tracked by Git before `nix flake check` works. This enforces good version control practices.

2. **VirtualBox is a System Prerequisite**: VirtualBox cannot be provided by a flake because it requires:
   - Kernel modules (`vboxdrv`, `vboxnetflt`, `vboxnetadp`) compiled for the host kernel
   - Setuid wrappers for privileged operations (e.g., `VBoxNetAdpCtl`)
   - Platform-specific installation (varies by OS)
   
   The flake provides Vagrant and other tools; users must install VirtualBox at the system level.

3. **flake.lock Purpose**: The lock file pins exact Git commits (not just versions) of all dependencies, ensuring perfect reproducibility across machines and time.

4. **devShell shellHook**: Extremely useful for:
   - Checking prerequisites (like VirtualBox installation, vboxusers group membership)
   - Welcoming users with tool versions
   - Setting environment variables
   - Providing quick-start commands

5. **Cross-Platform Support**: By not including VirtualBox in the flake, the same flake works on:
   - NixOS (any version)
   - Ubuntu/Debian
   - Fedora
   - Arch Linux
   - macOS (Intel and Apple Silicon)

### Deferred to Later Phases

- **WinRM Testing**: Deferred to Phase 3 when Windows VMs are available
- **Code Quality Tools**: Pre-commit hooks and formatting tools deferred (optional for Phase 1)

---

**Phase 1 Completed**: Yes  
**Completed By**: Claude (with user)  
**Sign-off Date**: 2026-01-16
