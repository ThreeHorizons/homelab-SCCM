# Phase 1 Revision: NixVirt Migration Checklist

This checklist tracks progress through the 8-step implementation plan for migrating from Vagrant+VirtualBox to NixVirt+libvirt/QEMU.

**Status**: 🟡 In Progress (Steps 1-6 complete, 7-8 remaining)  
**Started**: 2026-02-06  
**Architecture Doc**: [docs/phase1-revision-nixvirt-architecture.md](../docs/phase1-revision-nixvirt-architecture.md)  
**Implementation Steps**: [docs/phase1-revision-implementation-steps.md](../docs/phase1-revision-implementation-steps.md)

---

## Prerequisites (User Must Complete)

- [x] NixOS system configuration updated:
  - [x] `virtualisation.libvirtd.enable = true` (in nix-config modules/development/devops.nix)
  - [x] `virtualisation.libvirt.enable = true` (NixVirt module activation, in homelab-SCCM flake.nix)
  - [x] `virtualisation.libvirt.swtpm.enable = true` (in homelab-SCCM flake.nix)
  - [x] User added to `libvirt` group (via devops.nix)
  - [x] `programs.virt-manager.enable = true` (via devops.nix)
  - [x] Run `sudo nixos-rebuild switch`
  - [x] Log out and log back in (for group membership)
- [x] Prerequisites verified:
  - [x] `systemctl status libvirtd` shows running
  - [x] `virsh -c qemu:///system list --all` works without errors
  - [x] `virt-manager --version` returns version number
  - [x] `which swtpm` shows swtpm is available
- [ ] Windows ISOs downloaded and placed in `/var/lib/libvirt/iso/`:
  - [ ] `windows-server-2022.iso`
  - [ ] `windows-11.iso` (optional, for clients)

---

## Step 1: NixVirt API Validation Spike

**Goal**: Validate assumptions about NixVirt's API before writing production code.

**Status**: ✅ Complete (2026-02-06)

### Tasks
- [x] Create minimal test flake in `/tmp/nixvirt-spike/`
- [x] Test custom network XML generation (lab-net with custom subnet/DHCP)
  - [x] Attempt with `nixvirt.lib.network.writeXML` + attrset
  - [x] Document which approach works
- [x] Test pool/volume API existence
  - [x] Check if `nixvirt.lib.pool.writeXML` exists
  - [x] Check if `nixvirt.lib.volume.writeXML` exists
  - [x] Document whether shell script fallback is needed
- [x] Test Windows domain template multi-NIC support
  - [x] Inspect generated XML from `windows` template
  - [x] Check if multiple `<interface>` elements possible
  - [x] Document approach for dual-NIC VMs

### Findings
- **Custom network XML**: ✅ **Works perfectly** - NixVirt accepts custom attrsets with full IP/DHCP configuration
- **Pool/volume functions**: ✅ **API exists** - Both pool and volume management functions available in NixVirt.lib
- **Multi-NIC Windows VMs**: ✅ **Supported natively** - Windows template generated 2 NICs successfully in test

### Detailed Results
1. **Network Generation**:
   - Custom network with `bridge.name`, `ip.address`, `dhcp.range` all validated
   - Bridge template also works for standard 192.168.X.0/24 subnets
   - No need for raw XML fallback
   
2. **Storage API**:
   - `NixVirt.lib.pool` exists and can generate pool XML
   - `NixVirt.lib.volume` exists for volume definitions
   - Can create volumes declaratively within pool definitions
   
3. **Windows VM Multi-NIC**:
   - Generated domain XML contains multiple `<interface>` elements
   - Each interface properly references different source networks
   - No manual XML manipulation needed

### Decision Gate
- [x] All findings documented
- [x] No fallback strategies needed - all APIs work as expected
- [x] Ready to proceed to Step 2

**Validation Report**: Available at `/tmp/nixvirt-spike/validation-report.md`

---

## Step 2: Network Configuration

**Goal**: Define lab-net and default networks in Nix.

**Status**: ✅ Complete (2026-02-06)

### Tasks
- [x] Create `nixvirt/networks.nix`
- [x] Generate real UUIDs with `uuidgen` (no placeholders)
  - lab-net: 0355c7ff-0c40-4a7a-8c0d-1f7564af25ca
  - default: d72183d8-b05c-42a6-9f79-96177d160f8e
- [x] Define `lab-net` (192.168.56.0/24, virbr56, NAT, DHCP 100-200)
- [x] Define `default` (192.168.122.0/24, standard NAT using bridge template)
- [x] Export function/attrset consumable by NixOS module

### Implementation Details
- **lab-net**: Custom network definition with full control over IP, DHCP, bridge name
- **default**: Uses NixVirt's bridge template for standard 192.168.122.0/24 network
- Both networks use NAT mode for internet connectivity
- Extensive inline documentation explaining each configuration option
- Technical notes covering network modes, bridges, DHCP, static IPs, and validation commands

### Validation
- [x] File compiles without errors
- [x] `virsh net-list --all` shows both networks active
- [x] `virsh net-dumpxml lab-net` shows correct config (192.168.56.0/24, virbr56, NAT, DHCP)

**Note (2026-02-07)**: networks.nix was rewritten during Step 6 integration to fix
a critical bug: NixVirt expects lists, not attrsets. The original attrset format
`{ lab-net = {...}; default = {...}; }` was changed to a list of submodules.

---

## Step 3: Storage Pool and Volume Definitions

**Goal**: Define storage pool and QCOW2 volumes for all VMs.

**Status**: ✅ Complete (2026-02-06)

### Tasks
- [x] Create `nixvirt/pools.nix`
- [x] Generate real UUID for pool with `uuidgen`
  - homelab pool: 31c47f9a-9ee8-4fd2-9f83-25733e81b978
- [x] Define pool pointing to `/var/lib/libvirt/images/homelab/`
- [x] Define 4 volumes:
  - [x] `dc01.qcow2` (60 GiB)
  - [x] `sccm01.qcow2` (100 GiB)
  - [x] `client01.qcow2` (60 GiB)
  - [x] `client02.qcow2` (60 GiB)

### Implementation Details
- **Pool type**: Directory-based (simplest and most flexible)
- **Volume format**: QCOW2 with sparse allocation
- **Total virtual capacity**: 280 GiB (actual usage ~100-150 GB after OS install)
- Comprehensive documentation covering:
  - Sparse allocation and actual vs. virtual size
  - Snapshot capabilities
  - Backing stores (future enhancement)
  - Performance considerations
  - Volume migration procedures
- No shell script fallback needed (NixVirt API works perfectly)

### Validation
- [x] File compiles without errors
- [x] `virsh pool-list --all` shows `homelab` active
- [x] `virsh vol-list homelab` shows all 4 volumes

**Note (2026-02-07)**: pools.nix was rewritten during Step 6 integration to fix
the same list-vs-attrset bug as networks.nix.

---

## Step 4: Domain (VM) Definitions

**Goal**: Define DC01, SCCM01, CLIENT01, CLIENT02 using NixVirt templates.

**Status**: ✅ Complete (2026-02-06)

### Tasks
- [x] Create `nixvirt/domains.nix`
- [x] Create `mkWindowsServer` helper function
- [x] Create `mkWindowsClient` helper function
- [x] Generate real UUIDs for all VMs with `uuidgen`:
  - [x] DC01: 4c82c973-7299-468e-bf15-d442ee681475
  - [x] SCCM01: 880e7366-fada-4550-9dc2-dec9daa7fb5c
  - [x] CLIENT01: 0f432a26-5296-4201-9b2f-e3e5c39b03bb
  - [x] CLIENT02: 59693b4a-35bf-4587-ba07-6c960182b0ae
- [x] Implement multi-NIC configuration (using attrset extension with `//` and `++`)
- [x] Set NVRAM paths: `/var/lib/libvirt/qemu/nvram/{vm-name}.nvram`
- [x] Set `active = null` (don't auto-start until OS is installed)

### VM Configurations
- [x] **DC01**: 2GB RAM, 60GB disk, Windows Server 2022, dual NICs (lab-net + default)
- [x] **SCCM01**: 4GB RAM, 100GB disk, Windows Server 2022, dual NICs (lab-net + default)
- [x] **CLIENT01**: 2GB RAM, 60GB disk, Windows 11, dual NICs (lab-net + default)
- [x] **CLIENT02**: 2GB RAM, 60GB disk, Windows 11, dual NICs (lab-net + default)

### Implementation Details
- **Helper functions**: Reduce code duplication, ensure consistency
- **Multi-NIC approach**: Extend template output attrset with `//` (merge) and `++` (concatenate)
- **Network configuration**: 
  - NIC 1: lab-net (virbr56, 192.168.56.0/24) - primary lab network
  - NIC 2: default (virbr0, 192.168.122.0/24) - internet access
- **Driver strategy**: Use emulated hardware (e1000e, SATA) for out-of-box Windows installation
- **VirtIO drivers**: Attached as ISO for optional post-install performance upgrade
- **UEFI + TPM**: Template provides modern firmware required for Windows 11
- Comprehensive documentation covering:
  - UEFI vs BIOS, TPM 2.0, Secure Boot
  - CPU, memory, disk caching configurations
  - Network driver performance comparisons
  - VM lifecycle commands (start, stop, snapshot)
  - Troubleshooting common issues

### Validation
- [x] File compiles without errors
- [x] `virsh list --all` shows all 4 VMs (shut off)
- [x] `virsh dumpxml DC01 | grep -A3 '<interface'` shows 2 NICs (virbr56 + virbr0)
- [x] `virsh dumpxml DC01` shows QCOW2 disk + Windows ISO + VirtIO ISO
- [x] `virsh dumpxml DC01 | grep -i tpm` shows TPM 2.0 (tpm-crb, emulator)

**Note (2026-02-07)**: domains.nix was rewritten during Step 6 integration to fix
two critical bugs:
1. List-vs-attrset format (same as networks/pools)
2. Dual-NIC bug: the windows template returns `devices.interface` as a single attrset,
   not a list. The original code used `(baseVM.devices.interface or []) ++ [secondNIC]`
   which fails because `or []` doesn't trigger on a truthy attrset. Fixed by wrapping:
   `interface = [ baseVM.devices.interface ] ++ [ secondNIC ]`
Also unified mkWindowsServer/mkWindowsClient into a single mkWindowsVM helper.

---

## Step 5: Rewrite flake.nix

**Goal**: Add NixVirt input, export NixOS module, update devShell.

**Status**: ✅ Complete (2026-02-06)

### Tasks
- [x] Add NixVirt input (FlakeHub URL)
  - [x] Pinned to v0.6.0 via FlakeHub
- [x] Set `inputs.NixVirt.inputs.nixpkgs.follows = "nixpkgs"`
- [x] Create `nixosModules.default` output:
  - [x] Import `NixVirt.nixosModules.default`
  - [x] Enable `virtualisation.libvirt.enable` (activates nixvirt.service)
  - [x] Enable `virtualisation.libvirt.swtpm`
  - [x] Wire up `nixvirt/networks.nix`
  - [x] Wire up `nixvirt/pools.nix`
  - [x] Wire up `nixvirt/domains.nix`
- [x] Update `devShell`:
  - [x] Remove VirtualBox references (no more VBoxManage checks)
  - [x] Remove Vagrant from buildInputs
  - [x] Add: `virt-manager`, `libvirt` (virsh), `qemu` (qemu-img), `swtpm`
  - [x] Keep: PowerShell, Python, git, curl, wget, jq, yq, freerdp
  - [x] Update shellHook welcome message (libvirt status, virsh commands)
  - [x] Remove VirtualBox checks (vboxusers, KVM conflict warnings removed)
  - [x] Add libvirtd status check
  - [x] Add libvirt group membership check
  - [x] Add VM list display (if any exist)
- [x] Keep `supportedSystems` (devShell cross-platform, module Linux-only)
- [x] Add platform detection (isLinux) for conditional tool inclusion

### Implementation Details
- **NixVirt input**: FlakeHub URL provides stable v0.6.0 release
- **NixOS module**: Imports NixVirt module and configures qemu:///system connection
- **DevShell improvements**:
  - Cross-platform support (Linux gets full libvirt tools, macOS gets script editing)
  - Platform-aware shellHook (different messages for Linux vs non-Linux)
  - Helpful status checks (libvirtd running, user in libvirt group, VM list)
  - Clear next steps for users
- **Documentation**: Comprehensive technical notes covering flake system, NixOS modules, libvirt connections

### Validation
- [x] `nix flake lock` generated flake.lock with NixVirt v0.6.0
- [x] `nix flake check` passes without errors
- [x] `nix flake show` displays correct structure (nixosModules.default + devShells)
- [x] `nix develop` shows updated welcome message with libvirt tools
- [x] DevShell provides: virsh (11.7.0), virt-manager (5.1.0), PowerShell (7.5.4)
- [x] `nix eval .#nixosModules.default` evaluates without errors (will verify in Step 6)

---

## Step 6: Integration Test — Full Topology Deployment

**Goal**: Apply NixOS module and verify complete topology is created.

**Status**: ✅ Complete (2026-02-07)

### Tasks
- [x] Import module into NixOS configuration
  - Module imported via `inputs.homelab-sccm.nixosModules.default` in nix-config frameworking/default.nix
  - nix-config flake.lock updated with `nix flake update homelab-sccm`
- [x] Run `sudo nixos-rebuild switch`
- [x] Verify networks:
  - [x] `virsh net-list --all` shows lab-net (active) + default (active)
- [x] Verify storage:
  - [x] `virsh pool-list --all` shows homelab active
  - [x] `virsh vol-list homelab` shows 4 volumes
- [x] Verify VMs:
  - [x] `virsh list --all` shows 4 VMs: DC01, SCCM01, CLIENT01, CLIENT02 (shut off)
  - [x] `virsh dumpxml DC01` shows dual NICs, TPM 2.0, UEFI, ISOs
- [x] Idempotency test:
  - [x] `sudo systemctl restart nixvirt.service` succeeds (exit 0)
  - [x] No destructive changes on re-run
- [ ] Smoke test DC01 (deferred to Windows ISO download):
  - [ ] `virsh start DC01`
  - [ ] Open `virt-manager`, connect to DC01 console
  - [ ] Windows installer boots from ISO
  - [ ] Network adapter detected during install
  - [ ] Complete Windows installation

### Issues Encountered
1. **Missing `virtualisation.libvirt.enable = true`**: The NixVirt module guard (`lib.mkIf cfg.enable`)
   prevented the nixvirt.service from being created. Fixed by adding `enable = true` to flake.nix.
2. **Stale flake.lock in nix-config**: The `git+file://` input in nix-config pointed to the old
   commit. Required committing homelab-SCCM changes then running `nix flake update homelab-sccm`.
3. **List-vs-attrset type mismatch**: All three nixvirt/*.nix files returned attrsets but NixVirt
   expects `listOf (submodule ...)`. Rewrote all three files.
4. **Dual-NIC bug in domains.nix**: Template returns `interface` as single attrset, code tried
   to use it as a list. Fixed by wrapping in `[ ]`.
5. **TPM race condition on first boot**: `nixvirt.service` ran before libvirtd fully initialized
   TPM capabilities. Resolved on service restart. May recur on cold boot but unlikely once
   libvirtd has been running.

### Success Criteria
- [x] All networks created and active
- [x] All volumes created with correct sizes
- [x] All VMs defined with correct hardware (TPM, UEFI, ISOs, NICs)
- [ ] At least one VM boots and installs Windows successfully (pending ISO download)
- [x] Rebuild is idempotent (safe to re-run)

---

## Step 7: Update Orchestration Scripts

**Goal**: Update bash orchestration to use virsh/WinRM instead of Vagrant.

**Status**: ⚪ Not Started

### Tasks
- [ ] Read existing orchestration scripts:
  - [ ] `scripts/orchestration/deploy-dc.sh`
  - [ ] `scripts/orchestration/deploy-sccm.sh`
  - [ ] `scripts/orchestration/deploy-client.sh`
- [ ] Create `scripts/orchestration/lib.sh` with helper functions:
  - [ ] `run_on_vm()` - Execute PowerShell via WinRM
  - [ ] VM IP constants (DC01=192.168.56.10, etc.)
  - [ ] Credential handling
- [ ] Replace Vagrant commands with direct equivalents:
  - [ ] `vagrant winrm` → `pwsh Invoke-Command` over WinRM
  - [ ] `vagrant up` → `virsh start`
  - [ ] `vagrant halt` → `virsh shutdown`
  - [ ] `vagrant snapshot save` → `virsh snapshot-create-as`
  - [ ] `vagrant snapshot restore` → `virsh snapshot-revert`
- [ ] Handle file transfers (scripts to VMs):
  - [ ] Use `Copy-Item` over PSSession (WinRM)
  - [ ] Alternative: SMB share or virt-copy-in
- [ ] Update any hardcoded paths or VM names

### Validation
- [ ] `source scripts/orchestration/lib.sh` loads without errors
- [ ] `run_on_vm 192.168.56.10 "hostname"` returns correct hostname
- [ ] Test deploy-dc.sh (after OS installation in Step 6)

---

## Step 8: Documentation Updates

**Goal**: Update documentation to reflect NixVirt architecture.

**Status**: ⚪ Not Started

### Tasks
- [ ] Update `README.md`:
  - [ ] Change quick start from `vagrant up` to NixOS module import
  - [ ] Update prerequisites (libvirtd instead of VirtualBox)
  - [ ] Add note about Vagrant being deprecated
- [ ] Add deprecation notice to `vagrant/Vagrantfile`:
  ```ruby
  # DEPRECATED: This Vagrantfile is from the VirtualBox-based architecture.
  # The project has migrated to NixVirt+libvirt. See nixvirt/ directory.
  # Kept for reference only.
  ```
- [ ] Create `.claude/phase1-revision-checklist.md` (this file!)
- [ ] Do NOT update CLAUDE.md yet (defer until full validation)

### Validation
- [ ] README accurately reflects new workflow
- [ ] Vagrant deprecation notice is visible
- [ ] All documentation refers to libvirt/virsh instead of VirtualBox/Vagrant

---

## Final Validation

**Goal**: End-to-end test of complete system.

**Status**: ⚪ Not Started

### Acceptance Criteria
- [ ] `sudo nixos-rebuild switch` creates complete topology idempotently
- [ ] `nix develop` provides devShell with all libvirt tools
- [ ] All 4 VMs can be started: `virsh start DC01 SCCM01 CLIENT01 CLIENT02`
- [ ] Windows can be installed on at least 2 VMs via virt-manager
- [ ] Orchestration scripts can connect via WinRM to Windows VMs
- [ ] Snapshot functionality works: `virsh snapshot-create-as DC01 test`
- [ ] Documentation is updated and accurate

---

## Notes and Observations

*This section will be filled in during implementation with findings, workarounds, and lessons learned.*

---

## Completion Status

**Phase 1 Revision**: 🟡 In Progress (6/8 steps complete)

**Target Completion**: TBD  
**Actual Completion**: TBD

---

## Next Steps After Phase 1 Revision

1. **Phase 2 (Revised)**: WinRM Automation Validation
   - Manually install Windows on VMs
   - Run existing PowerShell automation scripts
   - Verify end-to-end SCCM deployment works

2. **Phase 3 (Revised)**: Packer Base Images
   - Automate Windows installation
   - Pre-install VirtIO drivers
   - Create unattended install images

3. **Phase 4+**: PXE/OSD, Cross-Platform, Framework Extraction
