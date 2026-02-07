# Phase 1 Revision: Implementation Steps

This document provides the step-by-step execution plan for implementing the NixVirt-based architecture. Each step is self-contained with clear inputs, outputs, and validation criteria — optimized for agentic coding execution.

**Parent document**: [phase1-revision-nixvirt-architecture.md](phase1-revision-nixvirt-architecture.md)

---

## Prerequisites (User Must Complete Before Implementation)

These cannot be automated by the coding agent — they require NixOS system configuration changes and a `nixos-rebuild switch`.

### NixOS System Configuration

Add the following to your `/etc/nixos/configuration.nix` (or equivalent):

```nix
{
  # Enable libvirtd
  virtualisation.libvirtd.enable = true;

  # Enable swtpm (required for Windows 11 TPM 2.0)
  virtualisation.libvirt.swtpm.enable = true;  # NixVirt-provided option, or:
  # environment.systemPackages = [ pkgs.swtpm ];  # if NixVirt module handles this

  # Add your user to libvirt group
  users.users.<your-username>.extraGroups = [ "libvirt" ];

  # Install virt-manager for GUI VM management
  programs.virt-manager.enable = true;
  # Or: environment.systemPackages = [ pkgs.virt-manager ];

  # Nix flakes (should already be enabled from Phase 1)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

Then run: `sudo nixos-rebuild switch` and **log out/in** (for group membership).

### Verify Prerequisites

```bash
# libvirtd is running
systemctl status libvirtd

# User can access libvirt
virsh -c qemu:///system list --all

# virt-manager works
virt-manager --version

# swtpm is available
which swtpm
```

### Download ISOs

Place these in `/var/lib/libvirt/iso/` (create directory if needed):

- **Windows Server 2022 Evaluation**: `windows-server-2022.iso`
  - https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- **Windows 11 Evaluation** (optional, for clients): `windows-11.iso`
  - https://www.microsoft.com/en-us/software-download/windows11

```bash
sudo mkdir -p /var/lib/libvirt/iso
# Copy downloaded ISOs there
sudo cp ~/Downloads/SERVER_EVAL_*.iso /var/lib/libvirt/iso/windows-server-2022.iso
```

---

## Step 1: NixVirt API Validation Spike

**Goal**: Validate our assumptions about NixVirt's API before writing production code. This is the highest-risk step — if the API doesn't work as documented, we need to know before investing in the full implementation.

**Why first**: The architecture document identifies 6 known API limitations. Three of them are blocking unknowns:
1. Can `nixvirt.lib.network.writeXML` accept a custom attrset (not just the bridge template)?
2. Do `nixvirt.lib.pool.writeXML` / `nixvirt.lib.volume.writeXML` exist?
3. Can we attach multiple NICs to a `windows` template VM?

### Tasks

1. **Create a minimal test flake** (temporary, in `/tmp/nixvirt-spike/`):
   ```nix
   {
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
       NixVirt = {
         url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
         inputs.nixpkgs.follows = "nixpkgs";
       };
     };
     outputs = { self, nixpkgs, NixVirt }: {
       # Minimal NixOS module to test NixVirt
       nixosConfigurations.test = nixpkgs.lib.nixosSystem {
         system = "x86_64-linux";
         modules = [
           NixVirt.nixosModules.default
           ./test-config.nix
         ];
       };
     };
   }
   ```

2. **Test network creation** — try the custom attrset approach for lab-net:
   ```nix
   virtualisation.libvirt.connections."qemu:///system".networks = [
     {
       definition = NixVirt.lib.network.writeXML {
         name = "test-lab";
         uuid = "70b08691-28dc-4b47-90a1-45bbeac9ab5a";
         forward = { mode = "nat"; };
         bridge = { name = "virbr99"; };
         ip = {
           address = "192.168.99.1";
           netmask = "255.255.255.0";
           dhcp = { range = { start = "192.168.99.100"; end = "192.168.99.200"; }; };
         };
       };
       active = true;
     }
   ];
   ```
   **Validation**: Run `nix eval .#nixosConfigurations.test.config.virtualisation.libvirt` or attempt `nixos-rebuild build` to see if the XML generates correctly. If it fails, try passing raw XML via `builtins.toFile "lab-net.xml" ''<network>...</network>''`.

3. **Test pool/volume creation** — check if the functions exist:
   ```nix
   # In nix repl:
   :lf .
   NixVirt.lib.pool  # Does this exist?
   NixVirt.lib.volume  # Does this exist?
   ```
   If they don't exist, plan B is to create volumes via a shell script (`qemu-img create -f qcow2`).

4. **Test Windows domain template** — inspect the generated XML:
   ```nix
   # In nix repl:
   :lf .
   builtins.readFile (NixVirt.lib.domain.writeXML (NixVirt.lib.domain.templates.windows {
     name = "test-win";
     uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
     memory = { count = 2; unit = "GiB"; };
     storage_vol = "/tmp/test.qcow2";
     install_vol = "/tmp/test.iso";
     nvram_path = "/tmp/test.nvram";
     bridge_name = "virbr99";
     virtio_net = false;
     virtio_drive = false;
     install_virtio = true;
   }))
   ```
   **Check**: How many `<interface>` elements are in the XML? Is there a way to add a second NIC? Look at whether the template output can be modified/extended with `//` before passing to `writeXML`.

### Output

A findings document (can be notes in this file or a separate spike-results file) recording:
- [ ] Custom network XML: works / needs raw XML fallback
- [ ] Pool/volume functions: exist / need shell script fallback
- [ ] Windows template multi-NIC: supported / needs XML extension / needs raw XML
- [ ] Any other surprises

### Decision gate

If all three work with NixVirt's Nix API → proceed to Step 2 as planned.
If any require raw XML → document the workaround and adjust Steps 2-4 accordingly.
If NixVirt is fundamentally incompatible → escalate to user for architectural decision.

---

## Step 2: Create `nixvirt/` Directory and Network Configuration

**Goal**: Define the two lab networks in Nix and verify they're created by NixOS.

**Inputs**: Spike results from Step 1 (which approach works for custom networks).

### Tasks

1. Create `nixvirt/networks.nix` with lab-net and default network definitions.
   - Use the approach validated in Step 1 (Nix attrset or raw XML).
   - UUIDs: generate real UUIDs via `uuidgen` (don't use placeholder values).

2. The file should export a function or attrset that can be consumed by the NixOS module in `flake.nix`.

### Validation

```bash
# After nixos-rebuild switch:
virsh -c qemu:///system net-list --all
# Should show: lab-net (active), default (active)

virsh -c qemu:///system net-dumpxml lab-net
# Should show: 192.168.56.0/24, virbr56, DHCP 100-200

ip addr show virbr56
# Should show: 192.168.56.1/24
```

---

## Step 3: Create Storage Pool and Volume Definitions

**Goal**: Define the storage pool and QCOW2 volumes for all VMs.

**Inputs**: Spike results from Step 1 (whether pool/volume functions exist).

### Tasks

1. Create `nixvirt/pools.nix` defining the `homelab` storage pool.
   - Path: `/var/lib/libvirt/images/homelab/`
   - If NixVirt pool functions don't exist, create a shell script `scripts/create-volumes.sh` that runs:
     ```bash
     sudo mkdir -p /var/lib/libvirt/images/homelab
     sudo virsh pool-define-as homelab dir --target /var/lib/libvirt/images/homelab
     sudo virsh pool-autostart homelab
     sudo virsh pool-start homelab
     for vol in dc01:60 sccm01:100 client01:60 client02:60; do
       name="${vol%%:*}"; size="${vol##*:}"
       sudo qemu-img create -f qcow2 "/var/lib/libvirt/images/homelab/${name}.qcow2" "${size}G"
     done
     ```

2. Volume sizes (matching original Vagrantfile):
   - dc01.qcow2: 60 GiB
   - sccm01.qcow2: 100 GiB
   - client01.qcow2: 60 GiB
   - client02.qcow2: 60 GiB

### Validation

```bash
virsh -c qemu:///system pool-list --all
# Should show: homelab (active)

virsh -c qemu:///system vol-list homelab
# Should show: dc01.qcow2, sccm01.qcow2, client01.qcow2, client02.qcow2

ls -la /var/lib/libvirt/images/homelab/
# QCOW2 files should exist (sparse, so actual size is small)
```

---

## Step 4: Create Domain (VM) Definitions

**Goal**: Define all four VMs using NixVirt's `windows` template.

**Inputs**: Spike results from Step 1 (multi-NIC approach), working networks from Step 2, working storage from Step 3.

### Tasks

1. Create `nixvirt/domains.nix` with DC01, SCCM01, CLIENT01, CLIENT02.

2. Use `mkWindowsServer` and `mkWindowsClient` helpers as shown in the architecture doc.

3. **Multi-NIC handling** (based on spike results):
   - **If template supports it**: Add second `bridge_name` or interface parameter.
   - **If template doesn't support it**: Generate the base XML from the template, then modify it to add a second `<interface>` element before passing to `writeXML`. This might look like:
     ```nix
     let
       baseXML = nixvirt.lib.domain.templates.windows { ... bridge_name = "virbr56"; ... };
       # Add second NIC for default NAT network
       withSecondNIC = baseXML // {
         devices = baseXML.devices // {
           interface = baseXML.devices.interface ++ [{
             type = "network";
             source = { network = "default"; };
             model = { type = "e1000e"; };
           }];
         };
       };
     in nixvirt.lib.domain.writeXML withSecondNIC
     ```
   - **If raw XML needed**: Generate template XML, add second NIC via string manipulation, use `builtins.toFile`.

4. All VMs should have `active = null` (don't auto-start — OS isn't installed yet).

5. Generate real UUIDs for each VM (use `uuidgen`).

6. NVRAM paths: `/var/lib/libvirt/qemu/nvram/{dc01,sccm01,client01,client02}.nvram`
   - Ensure directory exists: `sudo mkdir -p /var/lib/libvirt/qemu/nvram`

### Validation

```bash
virsh -c qemu:///system list --all
# Should show: DC01, SCCM01, CLIENT01, CLIENT02 (all "shut off")

virsh -c qemu:///system dumpxml DC01 | grep -A5 '<interface'
# Should show two interfaces: virbr56 (lab-net) and virbr0 (default)

virsh -c qemu:///system dumpxml DC01 | grep '<disk'
# Should show: dc01.qcow2 volume and windows-server-2022.iso

virsh -c qemu:///system dumpxml DC01 | grep -i tpm
# Should show: TPM 2.0 emulated device
```

---

## Step 5: Rewrite `flake.nix`

**Goal**: Update the flake to add NixVirt as an input, export a NixOS module, and update the devShell.

### Tasks

1. **Add NixVirt input**:
   ```nix
   inputs.NixVirt = {
     url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. **Export NixOS module** that wires up `nixvirt/networks.nix`, `nixvirt/pools.nix`, `nixvirt/domains.nix`:
   ```nix
   nixosModules.default = { config, lib, pkgs, ... }: {
     imports = [ NixVirt.nixosModules.default ];
     virtualisation.libvirt.swtpm.enable = true;
     virtualisation.libvirt.connections."qemu:///system" = {
       networks = import ./nixvirt/networks.nix { inherit NixVirt; };
       domains = import ./nixvirt/domains.nix { inherit NixVirt; };
       pools = import ./nixvirt/pools.nix { inherit NixVirt; };
     };
   };
   ```

3. **Update devShell**:
   - Remove VirtualBox checks (no more `VBoxManage`, `vboxusers` group, KVM conflict warnings)
   - Remove Vagrant from `buildInputs`
   - Add: `virt-manager`, `libvirt` (for `virsh`), `qemu` (optional, for `qemu-img`)
   - Update welcome message to show libvirt status instead of VirtualBox
   - Update quick commands: `virsh list --all`, `virt-manager`, etc.
   - Keep: PowerShell, Python, git, curl, wget, jq, yq, freerdp

4. **Keep `supportedSystems`** but note that NixVirt NixOS module only works on Linux. The devShell can still work on Darwin for script editing (no VM management).

### Validation

```bash
# Flake builds without errors
nix flake check

# DevShell works
nix develop
# Should show updated welcome message with libvirt tools

# NixOS module can be evaluated
nix eval .#nixosModules.default
```

---

## Step 6: Integration Test — Full Topology Deployment

**Goal**: Apply the NixOS module and verify the complete topology is created.

### Tasks

1. Add the module to the user's NixOS configuration:
   ```nix
   # In /etc/nixos/flake.nix or configuration.nix:
   imports = [ homelab-sccm.nixosModules.default ];
   ```
   Or if the user's NixOS config is a flake, add homelab-sccm as an input.

2. Run `sudo nixos-rebuild switch`.

3. Verify everything:
   ```bash
   # Networks
   virsh net-list --all  # lab-net + default, both active
   ip addr show virbr56  # 192.168.56.1/24

   # Storage
   virsh pool-list --all  # homelab pool, active
   virsh vol-list homelab  # 4 QCOW2 volumes

   # VMs
   virsh list --all  # DC01, SCCM01, CLIENT01, CLIENT02 (shut off)
   ```

4. **Smoke test one VM**:
   ```bash
   virsh start DC01
   virt-manager  # Open GUI, connect to DC01 console
   # Windows installer should boot from ISO
   # Install Windows, verify network adapter is present
   # After install: verify VM gets 192.168.122.x from default NAT
   # Manually set static IP 192.168.56.10 on second adapter
   ```

5. **Idempotency test**: Run `sudo nixos-rebuild switch` again. Verify no destructive changes (VMs not redefined, volumes not deleted).

### Output

- [ ] All networks created and active
- [ ] All volumes created with correct sizes
- [ ] All VMs defined with correct hardware (TPM, UEFI, ISOs, NICs)
- [ ] At least one VM boots and installs Windows
- [ ] Rebuild is idempotent

---

## Step 7: Update Orchestration Scripts

**Goal**: Update `scripts/orchestration/*.sh` to work with libvirt VMs instead of Vagrant.

### Tasks

1. Read existing orchestration scripts (`deploy-dc.sh`, `deploy-sccm.sh`, `deploy-client.sh`).

2. Replace `vagrant winrm -c "..."` or `vagrant powershell -c "..."` with direct PowerShell remoting:
   ```bash
   # Old (Vagrant):
   vagrant winrm dc01 -c "powershell -File C:\scripts\Install-ADDS.ps1"

   # New (direct WinRM via PowerShell Core):
   pwsh -Command "Invoke-Command -ComputerName 192.168.56.10 -Credential \$cred -ScriptBlock { & C:\scripts\Install-ADDS.ps1 }"
   ```

   Or use a reusable helper:
   ```bash
   # scripts/orchestration/lib.sh
   run_on_vm() {
     local ip="$1"; shift
     local script="$1"; shift
     pwsh -Command "
       \$cred = New-Object PSCredential('Administrator', (ConvertTo-SecureString 'VagrantPass1!' -AsPlainText -Force))
       Invoke-Command -ComputerName $ip -Credential \$cred -FilePath '$script'
     "
   }
   ```

3. Replace `vagrant snapshot save/restore` with `virsh snapshot-*`:
   ```bash
   # Old: vagrant snapshot save dc01 "post-ad-install"
   # New:
   virsh snapshot-create-as DC01 "post-ad-install" --description "After AD installation"
   virsh snapshot-revert DC01 "post-ad-install"
   ```

4. Replace `vagrant up/halt/destroy` with `virsh start/shutdown/destroy`:
   ```bash
   virsh start DC01
   virsh shutdown DC01  # graceful
   virsh destroy DC01   # force stop
   ```

5. Update file transfer mechanism. Vagrant used shared folders; with libvirt we need an alternative:
   - **Option A**: Copy scripts via WinRM (`Copy-Item` over PSSession)
   - **Option B**: Use SMB share from host
   - **Option C**: Use `virt-copy-in` from libguestfs (requires guest to be shut off)
   - **Recommended**: Option A (WinRM copy) since scripts are small

### Validation

```bash
# Orchestration helper works
source scripts/orchestration/lib.sh
run_on_vm 192.168.56.10 "hostname"
# Should return "DC01" (or whatever the Windows hostname is)
```

---

## Step 8: Documentation Updates

**Goal**: Update project documentation to reflect the NixVirt architecture.

### Tasks

1. **Update README.md**:
   - Change quick start from `vagrant up` to NixOS module import + `nixos-rebuild switch`
   - Update prerequisites (libvirtd instead of VirtualBox)
   - Add note about Vagrant being deprecated

2. **Add deprecation notice to `vagrant/Vagrantfile`**:
   ```ruby
   # DEPRECATED: This Vagrantfile is from the VirtualBox-based architecture (Phase 1-2 v1).
   # The project has migrated to NixVirt+libvirt. See nixvirt/ directory.
   # Kept for reference only.
   ```

3. **Do NOT update CLAUDE.md yet** — that's a larger effort and should wait until Phase 1 Revision is validated end-to-end.

4. **Create `.claude/phase1-revision-checklist.md`** tracking the implementation status.

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| NixVirt custom network XML doesn't work | Medium | High | Fallback to `builtins.toFile` with raw XML string |
| Pool/volume functions don't exist in v0.6.0 | Medium | Low | Use shell script with `qemu-img` + `virsh pool-define-as` |
| Windows template only supports single NIC | High | Medium | Modify template output attrset or use raw XML for domains |
| swtpm path issues (like issue #52) | Low | Medium | Pin to FlakeHub release, verify swtpm is in PATH |
| NixVirt NixOS module conflicts with existing libvirt config | Low | Medium | Test on clean NixOS config first |
| Windows ISO path doesn't exist at eval time | Medium | Low | Use string paths instead of Nix path literals (avoid IFD) |

---

## Glossary

- **NixVirt**: Nix flake for declarative libvirt management ([GitHub](https://github.com/AshleyYakeley/NixVirt))
- **libvirt**: Toolkit for managing virtualization platforms (KVM/QEMU)
- **virsh**: Command-line tool for libvirt
- **virt-manager**: GUI for libvirt VM management
- **QCOW2**: QEMU Copy-On-Write disk format (sparse, supports snapshots)
- **OVMF**: Open Virtual Machine Firmware (UEFI for VMs)
- **swtpm**: Software TPM emulator (required for Windows 11)
- **VirtIO**: Paravirtualized drivers for better VM performance
- **bridge_name**: libvirt network bridge device name (e.g., virbr56)
