# nixvirt/domains.nix
#
# Virtual machine (domain) definitions for the SCCM homelab environment
#
# Returns a LIST of domain objects.
# NixVirt's module type is: nullOr (listOf (submodule { definition, active, restart }))
#
# Each object has:
#   definition: path to XML file (from NixVirt.lib.domain.writeXML)
#   active:     bool or null - true=running, false=stopped, null=don't manage state
#   restart:    bool or null - true=always restart, false=never, null=only if changed
#
# IMPORTANT: When this list is non-null, NixVirt will DELETE any libvirt
# domains not present in this list. Domain deletion does NOT delete disk
# images, NVRAM files, or TPM state.
#
# VMs defined here:
#   DC01     - Domain Controller (AD DS, DNS, DHCP)
#   CLIENT01 - Windows 11 managed client
#   CLIENT02 - Windows 11 managed client

{ NixVirt }:

let
  # ==========================================================================
  # CONFIGURATION
  # ==========================================================================
  # String paths (not Nix path literals) to avoid eval-time file existence checks
  isoDir = "/mnt/vms/iso";
  nvramDir = "/var/lib/libvirt/qemu/nvram";
  pool = "homelab";

  # Shared directories (virtiofs)
  # These host directories are mounted into each VM via virtiofs.
  # Windows guests need WinFsp + virtio-win virtiofs service to access them.
  scriptsDir = "/home/myodhes-nix/projects/homelab-SCCM/scripts";
  windowsDir = "/mnt/vms/windows";  # SQL Server, ADK, WinPE, ConfigMgr installers

  # Explicit path to virtiofsd binary.
  # libvirtd's systemd service cannot find virtiofsd via PATH alone, so we
  # specify it explicitly in each <filesystem> definition via <binary path="...">.
  virtiofsdPath = "/run/current-system/sw/bin/virtiofsd";

  # ==========================================================================
  # HELPER: mkWindowsVM
  # ==========================================================================
  # Creates a Windows VM with dual NICs (lab-net + default).
  #
  # The NixVirt windows template returns devices.interface as a SINGLE attrset
  # (not a list). The XML generator's map1 function handles both forms, but
  # to add a second NIC we must convert it to a list of two attrsets.
  #
  # NIC layout:
  #   NIC 1: virbr56 (lab-net, 192.168.56.0/24) - SCCM/AD traffic
  #   NIC 2: virbr0  (default, 192.168.122.0/24) - internet access
  # ==========================================================================
  mkWindowsVM = { name, uuid, memory, volName, isoFile }:
    let
      baseVM = NixVirt.lib.domain.templates.windows {
        inherit name uuid memory;
        storage_vol = { inherit pool; volume = "${volName}.qcow2"; };
        install_vol = "${isoDir}/${isoFile}";
        nvram_path = "${nvramDir}/${volName}.nvram";
        bridge_name = "virbr56";
        virtio_net = false;
        virtio_drive = false;
        install_virtio = true;
      };

      # The template sets devices.interface as a single attrset:
      #   { type = "bridge"; source = { bridge = "virbr56"; }; model = null; mac = null; }
      #
      # We wrap it in a list and append a second NIC for the default network.
      # Both use type = "bridge" (direct bridge attachment) for consistency.
      #
      # Also adds:
      #   - memoryBacking: shared memory (memfd) required for virtiofs and KSM
      #   - filesystem: virtiofs mounts for scripts/ and /mnt/vms/windows/
      #   - memballoon: virtio balloon for dynamic memory management
      withDualNIC = baseVM // {
        # Shared memory backing: required for virtiofs, also enables KSM page merging.
        # Host must have hardware.ksm.enable = true for KSM to take effect.
        memoryBacking = {
          source = { type = "memfd"; };
          access = { mode = "shared"; };
        };

        devices = baseVM.devices // {
          interface = [
            baseVM.devices.interface
            {
              type = "bridge";
              source = { bridge = "virbr0"; };
              model = { type = "e1000e"; };
            }
          ];

          # virtiofs shared directories
          # Mount tags ("scripts", "windows") are used inside the guest to identify shares.
          # WinFsp + virtio-win virtiofs service auto-mounts these in the guest.
          # Each tag maps to a separate drive letter (configured in WinFsp).
          filesystem = [
            {
              type = "mount";
              accessmode = "passthrough";
              driver = { type = "virtiofs"; };
              binary = { path = virtiofsdPath; };
              source = { dir = scriptsDir; };
              target = { dir = "scripts"; };
            }
            {
              type = "mount";
              accessmode = "passthrough";
              driver = { type = "virtiofs"; };
              binary = { path = virtiofsdPath; };
              source = { dir = windowsDir; };
              target = { dir = "windows"; };
            }
          ];

          # Virtio memory balloon for dynamic memory management
          memballoon = { model = "virtio"; };
        };
      };
    in
    {
      definition = NixVirt.lib.domain.writeXML withDualNIC;
      # Don't manage VM state - no OS installed yet.
      # After installing Windows, enable auto-start with: virsh autostart DC01
      active = null;
    };

in
[
  # DC01 - Domain Controller
  # OS: Windows Server 2022 | RAM: 2 GiB | Disk: 60 GiB
  # Static IP: 192.168.56.10 (configured inside Windows)
  (mkWindowsVM {
    name = "DC01";
    uuid = "4c82c973-7299-468e-bf15-d442ee681475";
    memory = { count = 2; unit = "GiB"; };
    volName = "dc01";
    isoFile = "windows-server-2022.iso";
  })

  # SCCM01 - SCCM Primary Site Server (SQL + ConfigMgr)
  # OS: Windows Server 2022 | RAM: 4 GiB | Disk: 100 GiB
  # Static IP: 192.168.56.11 (configured inside Windows)
  (mkWindowsVM {
    name = "SCCM01";
    uuid = "880e7366-fada-4550-9dc2-dec9daa7fb5c";
    memory = { count = 4; unit = "GiB"; };
    volName = "sccm01";
    isoFile = "windows-server-2022.iso";
  })

  # CLIENT01 - Windows 11 managed client
  # OS: Windows 11 | RAM: 2 GiB | Disk: 60 GiB
  # Dynamic IP via DHCP (192.168.56.100-200 range)
  (mkWindowsVM {
    name = "CLIENT01";
    uuid = "0f432a26-5296-4201-9b2f-e3e5c39b03bb";
    memory = { count = 2; unit = "GiB"; };
    volName = "client01";
    isoFile = "windows-11.iso";
  })

  # CLIENT02 - Windows 11 managed client
  # OS: Windows 11 | RAM: 2 GiB | Disk: 60 GiB
  # Dynamic IP via DHCP (192.168.56.100-200 range)
  (mkWindowsVM {
    name = "CLIENT02";
    uuid = "59693b4a-35bf-4587-ba07-6c960182b0ae";
    memory = { count = 2; unit = "GiB"; };
    volName = "client02";
    isoFile = "windows-11.iso";
  })
]
