# Phase 1 Revision: NixVirt-Based Architecture Proposal

## Executive Summary

This document proposes revising the project from Vagrant+VirtualBox to NixVirt+libvirt/QEMU, transforming it from an SCCM-specific lab into a **generic, OS-agnostic homelab framework** while maintaining the SCCM use case as the primary example.

**Implementation guide**: See [phase1-revision-implementation-steps.md](phase1-revision-implementation-steps.md) for the step-by-step execution plan optimized for agentic coding.

---

## Why Revise Phase 1?

### Current Limitations (Vagrant + VirtualBox):
1. **Hardware/OS coupling**: Vagrant boxes bundle OS with hardware config
2. **Platform-specific**: VirtualBox kernel modules, Extension Pack licensing
3. **Not truly declarative**: Vagrantfile is Ruby DSL, not pure Nix
4. **Limited reusability**: SCCM-specific topology can't easily adapt to other use cases

### Benefits of NixVirt + libvirt:
1. **True separation**: Hardware topology defined in Nix, OS installed separately
2. **OS-agnostic**: Same hardware can run Windows, Linux, BSD, or NixOS
3. **Fully declarative**: Everything in Nix expressions
4. **Nix-native**: No Ruby, no Vagrant, pure Nix flakes
5. **Better performance**: libvirt/QEMU often faster than VirtualBox
6. **No licensing**: Fully open-source stack

---

## Project Structure (Phase 1 Target)

```
homelab-SCCM/
├── flake.nix                    # Flake: NixVirt input, NixOS module, devShell
├── flake.lock                   # Pinned dependencies (nixpkgs + NixVirt)
├── nixvirt/                     # NixVirt configuration (NEW)
│   ├── domains.nix              # VM definitions (DC01, SCCM01, CLIENTs)
│   ├── networks.nix             # Network definitions (lab-net, default)
│   └── pools.nix                # Storage pool + volume definitions
├── scripts/                     # PowerShell automation (UNCHANGED from Phase 3)
│   ├── dc/                      # AD, DNS, DHCP scripts
│   ├── sql/                     # SQL Server installation
│   ├── sccm/                    # SCCM installation + config
│   ├── client/                  # Client installation
│   ├── common/                  # Domain join, DNS config
│   ├── modules/                 # Logger, Validator
│   └── orchestration/           # Bash wrappers (UPDATED for direct WinRM)
├── vagrant/                     # DEPRECATED — kept for reference
│   ├── Vagrantfile
│   └── scripts/
├── docs/                        # Documentation
└── .claude/                     # Phase checklists
```

The aspirational `scenarios/`, `lib/`, `topology/`, `images/packer/` directories from the original proposal are **deferred** until Phase 4+ when we have concrete patterns to generalize.

---

## Concrete NixVirt Configuration (SCCM Lab)

The examples below use the **actual NixVirt API** (v0.6.0) — not an aspirational DSL. These are the real Nix expressions the implementation will use.

### `nixvirt/networks.nix` — Network Definitions

```nix
{ nixvirt, ... }:

{
  # Lab network: 192.168.56.0/24 with NAT for internet + inter-VM communication
  # Uses custom XML because the bridge template only supports subnet_byte (192.168.X.0/24)
  # and doesn't allow custom bridge names or DHCP ranges
  lab-net = {
    definition = nixvirt.lib.network.writeXML {
      name = "lab-net";
      uuid = "70b08691-28dc-4b47-90a1-45bbeac9ab5a";
      forward = { mode = "nat"; };
      bridge = { name = "virbr56"; };
      ip = {
        address = "192.168.56.1";
        netmask = "255.255.255.0";
        dhcp = {
          range = { start = "192.168.56.100"; end = "192.168.56.200"; };
        };
      };
    };
    active = true;
  };

  # Default NAT network for general internet access
  default = {
    definition = nixvirt.lib.network.writeXML
      (nixvirt.lib.network.templates.bridge {
        uuid = "cda3b7dd-71fd-44e3-8093-340f47a88c83";
        subnet_byte = 122;  # 192.168.122.0/24
      });
    active = true;
  };
}
```

> **Note**: The custom XML structure for `lab-net` needs validation against NixVirt's
> actual network XML schema. The `nixvirt.lib.network.writeXML` function accepts a Nix
> attrset that maps to libvirt network XML. If the attrset structure doesn't match,
> we may need to provide raw XML via `builtins.toFile`. This is the primary technical
> risk in Phase 1 and should be validated first.

### `nixvirt/domains.nix` — VM Definitions

```nix
{ nixvirt, ... }:

let
  # Configurable paths — user sets these
  isoDir = /var/lib/libvirt/iso;
  nvramDir = /var/lib/libvirt/qemu/nvram;
  pool = "homelab";

  # Helper to reduce boilerplate for Windows Server VMs
  mkWindowsServer = { name, uuid, memory, volName }: {
    definition = nixvirt.lib.domain.writeXML
      (nixvirt.lib.domain.templates.windows {
        inherit name uuid memory;
        storage_vol = { inherit pool; volume = "${volName}.qcow2"; };
        install_vol = isoDir + /windows-server-2022.iso;
        nvram_path = nvramDir + /${volName}.nvram;
        bridge_name = "virbr56";   # Connect to lab-net
        virtio_net = false;
        virtio_drive = false;
        install_virtio = true;
      });
    active = null;  # Don't auto-start — user starts manually after OS install
  };

  mkWindowsClient = { name, uuid, volName }: {
    definition = nixvirt.lib.domain.writeXML
      (nixvirt.lib.domain.templates.windows {
        inherit name uuid;
        memory = { count = 2; unit = "GiB"; };
        storage_vol = { inherit pool; volume = "${volName}.qcow2"; };
        install_vol = isoDir + /windows-11.iso;
        nvram_path = nvramDir + /${volName}.nvram;
        bridge_name = "virbr56";
        virtio_net = false;
        virtio_drive = false;
        install_virtio = true;
      });
    active = null;
  };

in
{
  dc01 = mkWindowsServer {
    name = "DC01";
    uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    memory = { count = 2; unit = "GiB"; };
    volName = "dc01";
  };

  sccm01 = mkWindowsServer {
    name = "SCCM01";
    uuid = "b2c3d4e5-f6a7-8901-bcde-f12345678901";
    memory = { count = 4; unit = "GiB"; };
    volName = "sccm01";
  };

  client01 = mkWindowsClient {
    name = "CLIENT01";
    uuid = "c3d4e5f6-a7b8-9012-cdef-123456789012";
    volName = "client01";
  };

  client02 = mkWindowsClient {
    name = "CLIENT02";
    uuid = "d4e5f6a7-b8c9-0123-defa-234567890123";
    volName = "client02";
  };
}
```

### `nixvirt/pools.nix` — Storage Pool

```nix
{ nixvirt, ... }:

{
  homelab = {
    definition = nixvirt.lib.pool.writeXML {
      name = "homelab";
      uuid = "e5f6a7b8-c9d0-1234-efab-345678901234";
      type = "dir";
      target = { path = "/var/lib/libvirt/images/homelab"; };
    };
    active = true;
    # Volumes are created manually via qemu-img or by NixVirt pool volume definitions
    volumes = [
      { name = "dc01.qcow2"; definition = nixvirt.lib.volume.writeXML {
          name = "dc01.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        }; present = true; }
      { name = "sccm01.qcow2"; definition = nixvirt.lib.volume.writeXML {
          name = "sccm01.qcow2";
          capacity = { count = 100; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        }; present = true; }
      { name = "client01.qcow2"; definition = nixvirt.lib.volume.writeXML {
          name = "client01.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        }; present = true; }
      { name = "client02.qcow2"; definition = nixvirt.lib.volume.writeXML {
          name = "client02.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        }; present = true; }
    ];
  };
}
```

> **Note**: NixVirt's pool/volume XML generation functions (`nixvirt.lib.pool.writeXML`,
> `nixvirt.lib.volume.writeXML`) need to be verified — they may not exist in v0.6.0.
> If not, volumes can be created via `qemu-img create -f qcow2` in a setup script,
> and pools defined via raw XML. This is a known risk flagged for Step 2 of implementation.

### Known NixVirt API Limitations (v0.6.0)

These were identified during research and must be accounted for during implementation:

1. **Network bridge template is limited**: `nixvirt.lib.network.templates.bridge` only accepts `uuid`, `subnet_byte`, and optionally `name`/`bridge_name`. No custom DHCP ranges or arbitrary subnets. Custom networks require using `nixvirt.lib.network.writeXML` with a raw attrset.

2. **XML schema coverage is incomplete**: The README states "the Nix structure roughly follows the XML format, but is currently missing elements." If our attrset doesn't map cleanly, we may need to generate XML manually and pass it as a file path.

3. **`virtdeclare` only controls domains and networks**: Storage pools/volumes may need `virsh` commands or NixOS module configuration. The NixOS module *does* support pools with volumes.

4. **Master branch is "frequently broken"**: Pin to FlakeHub release (0.6.0), not GitHub master.

5. **Windows template requires swtpm**: `virtualisation.libvirt.swtpm.enable = true` must be set. A past issue (#52) showed TPM failures when swtpm paths weren't configured correctly — this was fixed in later versions.

6. **Multi-NIC VMs**: The `windows` template's `bridge_name` parameter configures a single NIC. Attaching a second NIC (for the default NAT network) may require extending the template output or using raw XML. This needs investigation during Step 2.

### What Carries Over from Vagrant/VirtualBox

| Component | Status | Notes |
|-----------|--------|-------|
| `scripts/dc/` (7 scripts) | **Keep as-is** | PowerShell runs inside Windows VMs, hypervisor-agnostic |
| `scripts/sql/` | **Keep as-is** | Same |
| `scripts/sccm/` (3 scripts) | **Keep as-is** | Same |
| `scripts/client/` | **Keep as-is** | Same |
| `scripts/common/` (2 scripts) | **Keep as-is** | Same |
| `scripts/modules/` (Logger, Validator) | **Keep as-is** | Same |
| `scripts/orchestration/` (bash wrappers) | **Update** | Change from `vagrant winrm` to direct `pwsh` over WinRM |
| `vagrant/Vagrantfile` | **Keep for reference** | Mark as deprecated, don't delete |
| `vagrant/scripts/` | **Review** | `bootstrap.ps1` and `enable-winrm.ps1` may need manual execution post-OS-install |
| `flake.nix` | **Rewrite** | Add NixVirt input, NixOS module output, update devShell |
| Network config (192.168.56.0/24) | **Same subnet** | Keeps PowerShell scripts' hardcoded IPs valid |

---

## Implementation Phases (Revised)

### Phase 1 (Revised): NixVirt Foundation
**Goal**: Replace Vagrant+VirtualBox with NixVirt+libvirt for VM lifecycle management.

**Scope**: Flake rewrite, NixVirt config for SCCM lab topology, NixOS module, devShell update. No PowerShell changes.

**Tasks**:
1. Rewrite `flake.nix`: add NixVirt input, export NixOS module, update devShell (replace VirtualBox checks with libvirt checks)
2. Create `nixvirt/networks.nix`: lab-net (192.168.56.0/24) + default NAT
3. Create `nixvirt/pools.nix`: storage pool for QCOW2 volumes
4. Create `nixvirt/domains.nix`: DC01, SCCM01, CLIENT01, CLIENT02 using `windows` template
5. Validate: `sudo nixos-rebuild switch` creates networks, pools, volumes, and domain definitions
6. Test: Start a VM via `virsh start DC01`, install Windows manually via virt-manager, verify network connectivity

**Deliverables**:
- Working `flake.nix` with NixVirt
- `nixvirt/` directory with networks, pools, domains
- Updated devShell with libvirt tooling
- Deprecation notice on `vagrant/`

**Success criteria**: `sudo nixos-rebuild switch` idempotently creates the full lab topology. VMs can be started and Windows installed manually.

**Detailed implementation steps**: See [phase1-revision-implementation-steps.md](phase1-revision-implementation-steps.md)

---

### Phase 2 (Revised): WinRM Automation Validation
**Goal**: Verify existing PowerShell scripts work against NixVirt-created VMs.

**Tasks**:
1. Manually install Windows Server 2022 on DC01, SCCM01 via virt-manager
2. Manually install Windows 11 on CLIENT01
3. Run `enable-winrm.ps1` inside each VM (from `vagrant/scripts/`)
4. Update `scripts/orchestration/*.sh` to use direct WinRM instead of `vagrant winrm`
5. Run DC automation: `deploy-dc.sh` → verify AD, DNS, DHCP
6. Run SCCM automation: `deploy-sccm.sh` → verify SQL, SCCM
7. Run client automation: `deploy-client.sh` → verify domain join, SCCM client

**Deliverables**:
- Updated orchestration scripts
- Verified end-to-end automation on NixVirt VMs
- Documentation of any script changes needed

---

### Phase 3 (Revised): Packer Base Images
**Goal**: Automate OS installation for faster iteration.

Corresponds to original Phase 4. Creates unattended Windows images with VirtIO drivers pre-installed.

---

### Phase 4+: PXE/OSD, Cross-Platform, Framework Extraction
Later phases remain as originally planned. Framework generalization (scenarios, lib, topology DSL) happens here — not before we have working concrete code.

---

## Migration Path from Current State

**Decision**: Pivot now. The PowerShell scripts (17 scripts across dc/, sql/, sccm/, client/, common/) are hypervisor-agnostic and carry over unchanged. Only the orchestration layer (flake, VM creation, bash wrappers) needs rewriting.

**What happens to existing work**:
- `scripts/` → Kept entirely. No changes needed.
- `vagrant/` → Kept in repo for reference, marked deprecated in README.
- `flake.nix` → Rewritten (NixVirt replaces Vagrant+VirtualBox).
- `.claude/phase1-checklist.md`, `phase2-checklist.md` → Archived as "v1" completion records.
- New `.claude/phase1-revision-checklist.md` tracks the NixVirt implementation.

---

## Key Technical Decisions (Resolved)

All decisions below are **resolved** — no further discussion needed during implementation.

### 1. OS Installation: Manual First, Packer Later

**Decision**: Manual installation via virt-manager for Phase 1-3. Packer base images deferred to Phase 4.

- User downloads ISOs and places them at a configured path
- User installs Windows/Linux manually via virt-manager GUI
- All PowerShell/WinRM automation starts *after* OS is installed and WinRM is reachable
- This matches the existing Phase 3 workflow — scripts don't care how the VM was created

### 2. libvirt Connection: `qemu:///system`

**Decision**: Use `qemu:///system` exclusively.

- Required for proper bridge networking (isolated + NAT)
- Persistent VMs across user sessions
- User must be in `libvirt` group (documented in prerequisites)
- NixOS: `virtualisation.libvirtd.enable = true` + `users.users.<name>.extraGroups = ["libvirt"]`

### 3. Storage: Direct QCOW2 Volumes (Phase 1-3)

**Decision**: Direct QCOW2 volumes in a dedicated storage pool. No backing stores yet.

```nix
# Phase 1-3: Direct volumes
storage_vol = { pool = "homelab"; volume = "dc01.qcow2"; };
```

The storage pool `homelab` will be defined in Nix and point to a configurable path (default: `/var/lib/libvirt/images/homelab/`). Users who want volumes on a different disk can change the pool path.

Backing stores (copy-on-write overlays) will be introduced in Phase 4 alongside Packer.

### 4. Network Configuration: Two Networks

**Decision**: Two libvirt networks, both managed by NixVirt.

| Network | Purpose | Subnet | Bridge | Mode | DHCP |
|---------|---------|--------|--------|------|------|
| `lab-net` | Inter-VM communication | 192.168.56.0/24 | virbr56 | NAT (route) | 192.168.56.100-200 |
| `default` | Internet access | 192.168.122.0/24 | virbr0 | NAT | libvirt default |

**Why `lab-net` is NAT, not isolated**: Windows VMs need internet for updates, ADK downloads, and SCCM prerequisite downloads. Using NAT on both networks simplifies things — the `lab-net` serves double duty as both the "lab communication" network and a routable path. Static IPs (.10, .11) are set inside the guest OS, not via DHCP reservations.

**NixVirt API mapping**:
- `lab-net`: Use `nixvirt.lib.network.writeXML` with a **custom network definition** (not the bridge template, which only supports `subnet_byte` for 192.168.X.0/24 with no control over bridge name or DHCP range). The custom definition gives us full control over subnet, bridge name, and DHCP range.
- `default`: Use `nixvirt.lib.network.templates.bridge { subnet_byte = 122; }` — this matches libvirt's standard default network.

**All VMs get both NICs attached.**

### 5. NixOS Module vs. Home Manager Module

**Decision**: NixOS module (`nixosModules.default`).

This project targets NixOS hosts. The NixOS module automatically enables `virtualisation.libvirtd` and manages domains/networks/pools as system services. Home Manager module is only relevant for non-NixOS hosts (deferred to Phase 7).

### 6. Windows VM Template Configuration

**Decision**: Use NixVirt's `windows` domain template with these settings:

```nix
nixvirt.lib.domain.templates.windows {
  name = "DC01";
  uuid = "...";
  memory = { count = 2; unit = "GiB"; };
  storage_vol = { pool = "homelab"; volume = "dc01.qcow2"; };
  install_vol = /path/to/windows-server-2022.iso;
  nvram_path = /var/lib/libvirt/qemu/nvram/dc01.nvram;
  virtio_net = false;   # Use emulated e1000e during initial install
  virtio_drive = false;  # Use emulated SATA during initial install
  install_virtio = true; # Attach VirtIO driver ISO for optional driver install
}
```

**VirtIO strategy**: Start with emulated hardware (`virtio_net = false`, `virtio_drive = false`) so Windows installs without needing driver loading during setup. The VirtIO driver ISO is attached (`install_virtio = true`) so the user *can* install drivers post-OS-install for better performance, but it's not required for initial functionality. This can be revisited in Phase 4 when Packer handles unattended installs with VirtIO drivers baked in.

**TPM/Secure Boot**: The `windows` template includes UEFI (OVMF) and TPM 2.0 by default. Requires `virtualisation.libvirt.swtpm.enable = true` in the NixOS config.

### 7. Scope: SCCM-First, Not Framework-First

**Decision**: Build the SCCM scenario first. Abstract into a generic framework later.

The original proposal suggests building a generic `homelab-framework` with `lib/`, `topology/`, `scenarios/` from day one. This is premature abstraction. Instead:

1. **Phase 1**: Build a working NixVirt flake that creates the SCCM lab topology (DC01, SCCM01, CLIENT01-02) with proper networking and storage.
2. **Phase 2-3**: Port PowerShell automation, verify end-to-end flow.
3. **Phase 4+**: Extract common patterns into `lib/` and `topology/` only after we have concrete working code to generalize from.

The directory structure will start simpler:

```
homelab-SCCM/
├── flake.nix              # Flake with NixVirt, devShell, NixOS module
├── nixvirt/               # NixVirt configuration
│   ├── domains.nix        # VM definitions (DC01, SCCM01, CLIENTs)
│   ├── networks.nix       # Network definitions (lab-net, default)
│   └── pools.nix          # Storage pool definitions
├── scripts/               # Existing PowerShell automation (keep as-is)
├── vagrant/               # Existing Vagrant config (keep for reference, mark deprecated)
└── docs/
```

The `scenarios/`, `lib/`, `images/packer/` directories are **not created** until they're needed.

---

## Frequently Asked Questions

### Q: Can I still use VirtualBox?
**A**: Yes, but it's no longer the recommended approach. NixVirt+libvirt is superior for:
- Pure Nix declarative configuration
- Better performance
- No licensing concerns
- OS-agnostic topology

### Q: Will my PowerShell scripts still work?
**A**: Yes! PowerShell automation is independent of hypervisor. WinRM works the same whether VMs are created by VirtualBox or libvirt/QEMU.

### Q: Do I need to learn libvirt XML?
**A**: No, NixVirt provides Nix-based templates. You write Nix expressions, not XML.

### Q: Can I use this for production?
**A**: The framework is for **learning and testing** only. Production deployments should use enterprise hypervisors (Proxmox, VMware, Hyper-V) or cloud (AWS, Azure, GCP).

### Q: How do I get Windows ISOs?
**A**: Download evaluation ISOs from Microsoft Evaluation Center:
- Windows Server 2022: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- Windows 11: https://www.microsoft.com/en-us/software-download/windows11

### Q: What about Windows licensing?
**A**: Evaluation licenses are free for 180 days. For extended use, you need MSDN/Visual Studio subscriptions or volume licensing.

### Q: Can I mix NixOS and Windows VMs?
**A**: Yes! The topology is OS-agnostic. Define hardware in Nix, install any OS you want.

---

## Comparison: Vagrant+VirtualBox vs. NixVirt+libvirt

| Aspect | Vagrant+VirtualBox | NixVirt+libvirt |
|--------|-------------------|-----------------|
| **Declarative** | Partial (Ruby DSL) | Full (Nix expressions) |
| **OS-Agnostic Topology** | No (boxes bundle OS) | Yes (hardware separate from OS) |
| **Nix-Native** | No | Yes |
| **Cross-Platform** | Good (VBox everywhere) | Linux-focused (macOS partial) |
| **Performance** | Good | Better (native KVM) |
| **Licensing** | Extension Pack restricted | Fully open-source |
| **Learning Curve** | Lower | Higher |
| **Maturity** | Very mature | Newer (NixVirt ~2024) |
| **Windows Support** | Excellent | Good (requires VirtIO drivers) |

**Verdict**: NixVirt+libvirt is the future for Nix-based homelabs

---

## Next Steps

1. **Review this document** — all decisions are resolved, no open questions remain
2. **Review the implementation steps** — see [phase1-revision-implementation-steps.md](phase1-revision-implementation-steps.md) for the agentic execution plan
3. **Ensure NixOS prerequisites** are met on the host (libvirtd enabled, user in libvirt group, swtpm available)
4. **Begin implementation** — Step 1 of the implementation guide is a spike to validate NixVirt API assumptions before writing production code
