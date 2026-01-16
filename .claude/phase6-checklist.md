# Phase 6: macOS Support (Darwin)

**Status**: ⚪ Future  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Enable macOS users to run the SCCM homelab by adapting the Nix flake for Darwin, handling macOS-specific VirtualBox behavior and filesystem considerations.

## Goals

- [ ] Enable macOS users to run the lab
- [ ] Handle Darwin-specific VirtualBox behavior
- [ ] Adapt for macOS filesystem and permissions
- [ ] Document macOS-specific workflows

---

## Prerequisites

- ✅ Phase 1-4 completed and tested
- [ ] Access to macOS system for testing (Intel and/or Apple Silicon)
- [ ] Understanding of Nix on Darwin
- [ ] VirtualBox compatibility verification

---

## Main Tasks

### 1. Apple Silicon Compatibility Assessment

- [ ] Research VirtualBox status on Apple Silicon
  - [ ] Check VirtualBox 7.x ARM64 support status
  - [ ] Evaluate performance vs. Intel
  - [ ] Document limitations
- [ ] Determine feasibility
  - [ ] VirtualBox on Apple Silicon is EXPERIMENTAL (as of 7.1.x)
  - [ ] Nested virtualization may not work
  - [ ] Performance may be poor
- [ ] Document alternatives if VirtualBox doesn't work
  - [ ] VMware Fusion (commercial)
  - [ ] UTM (open-source, QEMU-based)
  - [ ] Parallels Desktop (commercial)
- [ ] Set expectations in documentation

### 2. Flake Darwin Support

- [ ] Add Darwin-specific package overrides to `flake.nix`
  - [ ] Use `nix-darwin` inputs if needed
  - [ ] Conditional logic for `aarch64-darwin` and `x86_64-darwin`
  - [ ] Handle different package names on macOS
- [ ] Test flake structure
  - [ ] `nix flake check`
  - [ ] Verify Darwin outputs defined
- [ ] Handle macOS-specific dependencies
  - [ ] Xcode Command Line Tools (required for Nix)
  - [ ] Homebrew integration (if needed)

### 3. VirtualBox Installation on macOS

- [ ] Document VirtualBox installation process
  - [ ] Download from virtualbox.org
  - [ ] Install .dmg package
  - [ ] Handle macOS Gatekeeper warnings
  - [ ] Allow in System Settings → Security & Privacy
- [ ] Document kernel extension approval
  - [ ] System Settings → Security & Privacy → General
  - [ ] Click "Allow" for Oracle kernel extensions
  - [ ] Reboot may be required
- [ ] Document Full Disk Access requirement
  - [ ] System Settings → Privacy & Security → Full Disk Access
  - [ ] Add VirtualBox.app
  - [ ] Required for some operations
- [ ] Test VirtualBox installation
  - [ ] Launch VirtualBox.app
  - [ ] Create test VM
  - [ ] Verify kernel extensions loaded

### 4. Handle macOS Networking Quirks

- [ ] Test host-only networking on macOS
  - [ ] VirtualBox creates `vboxnet0` differently
  - [ ] Network interface naming conventions differ
  - [ ] Test adapter creation: `VBoxManage hostonlyif create`
- [ ] Document macOS network configuration
  - [ ] System Preferences → Network
  - [ ] VirtualBox adapters appear as "vboxnetX"
  - [ ] Firewall considerations
- [ ] Test NAT networking
  - [ ] VirtualBox NAT behavior on macOS
  - [ ] Port forwarding differences
- [ ] Handle macOS Firewall
  - [ ] Allow VirtualBox in firewall settings
  - [ ] Allow incoming connections if needed

### 5. Handle macOS-Specific Permissions

- [ ] Document System Integrity Protection (SIP) impacts
  - [ ] VirtualBox kernel extensions require SIP configuration
  - [ ] Normally doesn't need to be disabled
  - [ ] Document if issues arise
- [ ] Document Full Disk Access requirements
  - [ ] VirtualBox may need access to certain directories
  - [ ] VM storage locations
- [ ] Test with different macOS Terminal applications
  - [ ] Terminal.app
  - [ ] iTerm2
  - [ ] Other popular terminals
- [ ] Handle macOS-specific file permissions
  - [ ] Different from Linux permissions
  - [ ] Test with case-sensitive vs. case-insensitive filesystems

### 6. PowerShell Core on macOS

- [ ] Test PowerShell Core installation
  - [ ] Via Nix flake (preferred)
  - [ ] Via Homebrew (alternative)
  - [ ] Direct download from Microsoft
- [ ] Test WinRM module compatibility
  - [ ] PowerShell remoting from macOS to Windows
  - [ ] Authentication mechanisms
  - [ ] Test `Enter-PSSession` and `Invoke-Command`
- [ ] Document Windows management framework
  - [ ] Any macOS-specific quirks
  - [ ] Performance considerations

### 7. Test on macOS Versions

#### Intel Macs
- [ ] Test on macOS Monterey (12.x)
  - [ ] VirtualBox compatibility
  - [ ] Nix installation
  - [ ] Full workflow
- [ ] Test on macOS Ventura (13.x)
  - [ ] Increased security restrictions
  - [ ] Kernel extension policies
- [ ] Test on macOS Sonoma (14.x)
  - [ ] Strictest policies
  - [ ] VirtualBox compatibility
  - [ ] Document workarounds
- [ ] Test on macOS Sequoia (15.x) if available
  - [ ] Latest restrictions
  - [ ] Compatibility status

#### Apple Silicon Macs (if pursuing)
- [ ] Test VirtualBox Developer Preview
  - [ ] Download ARM64 build
  - [ ] Test basic VM creation
  - [ ] Evaluate performance
- [ ] Test with Rosetta 2 (Intel VirtualBox on ARM Mac)
  - [ ] Install Rosetta 2: `softwareupdate --install-rosetta`
  - [ ] Test Intel VirtualBox binary
  - [ ] Evaluate performance overhead
  - [ ] Document limitations
- [ ] Consider alternative virtualization
  - [ ] UTM (native ARM64, QEMU-based)
  - [ ] Parallels Desktop (best ARM64 support)
  - [ ] VMware Fusion (if ARM64 support available)

### 8. Xcode Command Line Tools

- [ ] Document Xcode CLT installation
  - [ ] Required for Nix on macOS
  - [ ] Install: `xcode-select --install`
  - [ ] Verify: `xcode-select -p`
- [ ] Handle different Xcode CLT versions
  - [ ] Compatibility with different macOS versions
  - [ ] Update CLT when updating macOS

### 9. Filesystem Considerations

- [ ] Test on APFS (default)
  - [ ] Case-insensitive (default)
  - [ ] Case-sensitive (optional)
  - [ ] Snapshot support
- [ ] Test on HFS+ (legacy)
  - [ ] Older Macs may still use HFS+
- [ ] Handle case-sensitivity issues
  - [ ] Git repository on case-insensitive filesystem
  - [ ] Potential file naming conflicts
- [ ] Document Time Machine exclusions
  - [ ] VM disk files are large
  - [ ] Exclude `~/VirtualBox VMs/` from backups
  - [ ] `tmutil addexclusion ~/VirtualBox\ VMs/`

### 10. Create macOS-Specific Documentation

- [ ] Create `docs/macos-support.md`
  - [ ] Prerequisites
  - [ ] Nix installation on macOS
  - [ ] VirtualBox installation and configuration
  - [ ] Kernel extension approval
  - [ ] Common issues and solutions
  - [ ] Performance tuning tips
- [ ] Create `docs/apple-silicon.md`
  - [ ] Current status of VirtualBox on ARM64
  - [ ] Alternative virtualization options
  - [ ] Performance expectations
  - [ ] Recommendations (use Intel Mac or wait for better support)
- [ ] Create `scripts/macos-setup.sh`
  - [ ] Automated setup for macOS users
  - [ ] Check prerequisites
  - [ ] Install/configure VirtualBox
  - [ ] Configure permissions

---

## Sub-tasks & Considerations

### Nix Installation on macOS

- [ ] Single-user vs. multi-user installation
  - [ ] Multi-user recommended (daemon mode)
  - [ ] Requires admin privileges
- [ ] Test with official Nix installer
  - [ ] `curl -L https://nixos.org/nix/install | sh`
  - [ ] Or: `sh <(curl -L https://nixos.org/nix/install) --daemon`
- [ ] Consider nix-darwin
  - [ ] System-level configuration for macOS
  - [ ] Optional but helpful

### VirtualBox on macOS Catalina (10.15) and Later

- [ ] Stricter security policies starting with Catalina
- [ ] Kernel extension approval required
- [ ] Full Disk Access may be required
- [ ] Notarization requirements for VirtualBox
- [ ] Test with latest VirtualBox 7.x

### Apple Silicon Challenges

- [ ] VirtualBox ARM64 support is experimental
- [ ] x86_64 emulation overhead via Rosetta 2
- [ ] Windows Server ARM64 not available (Intel only)
- [ ] Nested virtualization limitations
- [ ] Performance significantly worse than Intel
- [ ] Recommendation: **Use Intel Mac or wait**

### Homebrew Integration

- [ ] Some users prefer Homebrew for tools
- [ ] Document Homebrew alternatives
  - [ ] `brew install vagrant`
  - [ ] VirtualBox via `brew install --cask virtualbox`
- [ ] Note: Nix flake preferred for reproducibility

### macOS Firewall

- [ ] Built-in firewall may block VirtualBox
- [ ] Allow VirtualBox in System Preferences → Security → Firewall
- [ ] Allow incoming connections for VM networking
- [ ] Test with firewall enabled

### Performance Tuning

- [ ] Allocate appropriate resources
  - [ ] Don't over-allocate memory (leave for macOS)
  - [ ] Typical Mac: 16GB RAM, allocate 8-10GB for VMs
- [ ] Use SSD for VM storage (most modern Macs have SSD)
- [ ] Close resource-intensive apps during lab use
- [ ] Consider headless mode to save graphics overhead

---

## Deliverables

- [ ] Darwin-compatible `flake.nix`
- [ ] `docs/macos-support.md` - macOS setup guide
- [ ] `docs/apple-silicon.md` - ARM64/Apple Silicon considerations
- [ ] `scripts/macos-setup.sh` - macOS-specific setup automation
- [ ] FAQ for common macOS issues
- [ ] Test results for different macOS versions

---

## Potential Issues & Solutions

### Issue: Kernel extensions require explicit approval

**Symptoms**: "System Extension Blocked" notification

**Solutions**:
- Open System Settings → Security & Privacy → General
- Click "Allow" next to Oracle message
- Reboot Mac
- Reinstall VirtualBox if necessary

### Issue: VirtualBox on Apple Silicon is extremely slow

**Symptoms**: Poor VM performance, high CPU usage

**Solutions**:
- Apple Silicon support is experimental
- Recommendation: Use Intel Mac for this lab
- Alternative: Wait for better ARM64 support
- Alternative: Use UTM or Parallels Desktop instead

### Issue: VirtualBox requires Full Disk Access

**Symptoms**: Permission errors creating/accessing VMs

**Solutions**:
- System Settings → Privacy & Security → Full Disk Access
- Add VirtualBox.app
- Restart VirtualBox

### Issue: macOS Sonoma (14.x) stricter kernel policies

**Symptoms**: Kernel extension won't load

**Solutions**:
- Ensure using latest VirtualBox 7.1.x
- Check System Settings → Privacy & Security → Allow
- May need to disable certain security features (not recommended)
- Verify VirtualBox is notarized by Apple

### Issue: Rosetta 2 translation overhead on Apple Silicon

**Symptoms**: Poor performance when running Intel VirtualBox

**Solutions**:
- Install Rosetta 2: `softwareupdate --install-rosetta`
- Expect 30-50% performance overhead
- Consider native ARM64 alternatives
- Best option: Use Intel Mac

### Issue: Port < 1024 binding restrictions

**Symptoms**: Can't bind to privileged ports

**Solutions**:
- Same as Linux - use ports > 1024
- No special workarounds for macOS
- SCCM doesn't require privileged ports

### Issue: Xcode Command Line Tools not installed

**Symptoms**: Nix installation fails, compilation errors

**Solutions**:
- Install Xcode CLT: `xcode-select --install`
- Verify: `xcode-select -p`
- Expected output: `/Library/Developer/CommandLineTools`

### Issue: Case-insensitive filesystem causes Git issues

**Symptoms**: Filename conflicts, Git strangeness

**Solutions**:
- macOS default is case-insensitive but case-preserving
- Generally not an issue for this project
- Can reformat as case-sensitive APFS if needed (not recommended)

---

## Testing Checklist

Test on Intel Mac:

```bash
# Verify Xcode Command Line Tools
xcode-select -p
# Expected: /Library/Developer/CommandLineTools

# Install Nix (if not already)
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

# Test VirtualBox kernel extension
kextstat | grep -i vbox
# Expected: VirtualBox kernel extensions loaded

# Test host-only network creation
VBoxManage hostonlyif create
VBoxManage list hostonlyifs
# Expected: Interface created (vboxnet0)

# Test creating a VM
cd vagrant
vagrant status

# Exit dev shell
exit
```

Test on Apple Silicon (if pursuing):

```bash
# Check Rosetta 2 installation
pgrep oahd
# If empty, install: softwareupdate --install-rosetta

# Follow Intel Mac steps above
# Expect poor performance and potential compatibility issues
```

---

## Success Criteria

Phase 6 is complete when:

- ✅ Flake works on macOS Monterey (12.x) Intel
- ✅ Flake works on macOS Ventura (13.x) Intel
- ✅ Flake works on macOS Sonoma (14.x) Intel
- ✅ VirtualBox kernel extensions load properly
- ✅ Host-only networking works
- ✅ Vagrant can create and manage VMs
- ✅ PowerShell Core can connect to Windows VMs
- ✅ Documentation covers all macOS-specific issues
- ✅ Apple Silicon status documented (even if not fully supported)
- ✅ macOS-specific setup script works

---

## Recommendations

### For Intel Mac Users
- ✅ **Recommended**: Proceed with this phase
- Full support expected
- Good performance
- All features work

### For Apple Silicon Mac Users
- ⚠️ **Not Recommended**: Wait for better VirtualBox ARM64 support
- VirtualBox on ARM64 is experimental (as of 2026-01)
- Poor performance expected
- Consider alternatives:
  - **UTM**: Native ARM64, QEMU-based, open-source
  - **Parallels Desktop**: Best ARM64 support, commercial
  - **VMware Fusion**: Good ARM64 support, commercial
  - **Use Intel Mac**: Best option for this lab

---

## Next Steps

Once Phase 6 is complete, proceed to:
- **Phase 7**: Optional - Containerized Tooling for Non-Nix Users
- See `.claude/phase7-checklist.md`

Or consider project complete if container support not needed.

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

**macOS Test Results**:
- macOS Monterey (Intel): ☐ Pass / ☐ Fail
- macOS Ventura (Intel): ☐ Pass / ☐ Fail
- macOS Sonoma (Intel): ☐ Pass / ☐ Fail
- macOS Sequoia (Intel): ☐ Pass / ☐ Fail
- Apple Silicon (ARM64): ☐ Pass / ☐ Fail / ☐ Not Tested

---

**Phase 6 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
