## Phase 1 (Original - Completed)

Let's proceed with phase 1 using the [@phase1-checklist.md](file:///home/myodhes-nix/projects/homelab-SCCM/.claude/phase1-checklist.md). I'd like to do this in a manner to best facilitate my learning. Explain the technologies, what you are doing, why you are doing it and how the syntax works for each action you do and piece of code you write. Update The checklist as you go.

---

## Phase 1 Revision: NixVirt Migration

We are migrating this project from Vagrant+VirtualBox to NixVirt+libvirt/QEMU. All planning and decisions are complete — your job is execution.

### Documents you MUST read before writing any code:

1. **Architecture & Decisions**: [docs/phase1-revision-nixvirt-architecture.md](file:///home/myodhes-nix/projects/homelab-SCCM/docs/phase1-revision-nixvirt-architecture.md) — Read the "Key Technical Decisions (Resolved)" section and the "Concrete NixVirt Configuration (SCCM Lab)" section. All 7 decisions are final. Do not revisit or propose alternatives.

2. **Implementation Steps**: [docs/phase1-revision-implementation-steps.md](file:///home/myodhes-nix/projects/homelab-SCCM/docs/phase1-revision-implementation-steps.md) — This is your step-by-step execution plan. Follow Steps 1 through 8 in order. Each step has explicit inputs, tasks, validation criteria, and fallback plans.

3. **Existing flake.nix**: [flake.nix](file:///home/myodhes-nix/projects/homelab-SCCM/flake.nix) — Understand the current structure before rewriting. The devShell pattern and cross-platform support should be preserved where applicable.

4. **NixVirt README** (external): https://github.com/AshleyYakeley/NixVirt — Reference for the actual NixVirt API. Pin to FlakeHub release, NOT GitHub master.

### Execution instructions:

- **Start with Step 1 (Validation Spike)**. This is a throwaway test in `/tmp/nixvirt-spike/` to validate three blocking API assumptions before writing production code. Do NOT skip this step. Report your findings before proceeding.

- **Follow the step order**. Steps 2-4 create `nixvirt/networks.nix`, `nixvirt/pools.nix`, `nixvirt/domains.nix`. Step 5 rewrites `flake.nix`. Step 6 is integration testing. Step 7 updates orchestration scripts. Step 8 is documentation.

- **Use the fallback plans**. The implementation steps document has specific fallbacks for each known risk (raw XML for networks, shell scripts for volumes, attrset modification for multi-NIC). If the NixVirt Nix API doesn't work for something, use the documented fallback — don't invent a new approach.

- **Do NOT modify `scripts/`**. The PowerShell scripts (dc/, sql/, sccm/, client/, common/, modules/) are hypervisor-agnostic and carry over unchanged. Only `scripts/orchestration/*.sh` gets updated (Step 7).

- **Do NOT delete `vagrant/`**. Mark it deprecated with a comment header, but keep it for reference.

- **Generate real UUIDs**. Use `uuidgen` for all UUIDs in domains, networks, and pools. Do not use placeholder values like `aaaaaaaa-...`.

- **Explain as you go**. I'm learning NixVirt and libvirt. Explain the NixVirt API, the libvirt concepts, and the Nix module system patterns as you implement them. Explain why you're making specific choices and how the code works.

- **Create `.claude/phase1-revision-checklist.md`** to track progress through the 8 steps. Update it as you complete each step.

### Known risks to watch for:

- NixVirt's `writeXML` may not accept freeform attrsets for networks — fallback is `builtins.toFile` with raw XML
- `nixvirt.lib.pool.writeXML` / `nixvirt.lib.volume.writeXML` may not exist — fallback is a shell script with `qemu-img` and `virsh`
- The `windows` template likely only supports a single NIC via `bridge_name` — you may need to modify the template's output attrset to add a second interface before passing to `writeXML`
- Nix path literals like `/var/lib/libvirt/iso/foo.iso` will fail at eval time if the file doesn't exist — use string paths instead

### What success looks like:

After all 8 steps, `sudo nixos-rebuild switch` should idempotently create:
- Two libvirt networks (lab-net at 192.168.56.0/24, default at 192.168.122.0/24)
- One storage pool with four QCOW2 volumes
- Four Windows VM definitions (DC01, SCCM01, CLIENT01, CLIENT02) with UEFI, TPM, dual NICs
- VMs can be started via `virsh start` and Windows installed via `virt-manager`
- `nix develop` provides a devShell with libvirt tools instead of Vagrant/VirtualBox
