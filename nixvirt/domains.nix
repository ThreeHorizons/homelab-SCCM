# nixvirt/domains.nix
#
# Virtual machine (domain) definitions for the SCCM homelab environment
#
# This file defines the hardware configuration for 4 VMs:
# 1. DC01 - Domain Controller (Active Directory, DNS, DHCP)
# 2. SCCM01 - SCCM Primary Site Server (SQL Server, ConfigMgr)
# 3. CLIENT01 - Windows 11 client (managed by SCCM)
# 4. CLIENT02 - Windows 11 client (managed by SCCM)
#
# Each VM uses NixVirt's 'windows' template which provides:
# - UEFI firmware (OVMF) - modern BIOS replacement
# - TPM 2.0 emulation (required for Windows 11)
# - Secure Boot support
# - Optimized virtual hardware for Windows guests

{ NixVirt }:

let
  # ==========================================================================
  # CONFIGURATION PATHS
  # ==========================================================================
  # These paths must exist on the NixOS host before VMs can start
  #
  # isoDir: Where Windows installation ISOs are stored
  # - User must download Windows Server 2022 and Windows 11 ISOs
  # - Place them in this directory with exact filenames shown below
  # - ISOs are mounted as virtual CD-ROM drives during installation
  #
  # nvramDir: Where UEFI NVRAM files are stored
  # - NVRAM stores UEFI boot variables and Secure Boot keys
  # - Each VM needs its own NVRAM file (like BIOS settings)
  # - libvirt creates these automatically on first boot
  #
  # pool: Storage pool name (defined in pools.nix)
  # - All VM disks are stored in this pool
  # ==========================================================================

  # Use string paths (not Nix path literals) to avoid import-from-derivation
  # String paths are evaluated at runtime, not at Nix evaluation time
  isoDir = "/var/lib/libvirt/iso";
  nvramDir = "/var/lib/libvirt/qemu/nvram";
  pool = "homelab";

  # ==========================================================================
  # HELPER FUNCTION: mkWindowsServer
  # ==========================================================================
  # Creates a Windows Server VM with standardized configuration
  #
  # Parameters:
  #   name: VM name (shown in 'virsh list', virt-manager)
  #   uuid: Unique identifier for this VM
  #   memory: RAM allocation { count = X; unit = "GiB"; }
  #   volName: Name of the QCOW2 disk image (from pools.nix)
  #
  # Returns: VM domain configuration attrset
  #
  # Why use a helper function?
  # - Reduces code duplication (DRY principle)
  # - Ensures consistent configuration across similar VMs
  # - Makes it easy to change all Windows Server VMs at once
  # - Clearer intent: This is a Windows Server, not a generic VM
  # ==========================================================================
  mkWindowsServer = { name, uuid, memory, volName }:
    let
      # Base Windows VM from NixVirt template
      baseVM = NixVirt.lib.domain.templates.windows {
        inherit name uuid memory;

        # storage_vol: The main hard drive for this VM
        # Points to a QCOW2 volume defined in pools.nix
        storage_vol = {
          inherit pool;
          volume = "${volName}.qcow2";
        };

        # install_vol: Windows Server 2022 installation ISO
        # Mounted as a virtual CD-ROM drive
        # User must download this from Microsoft Evaluation Center
        install_vol = "${isoDir}/windows-server-2022.iso";

        # nvram_path: UEFI NVRAM storage file
        # Stores UEFI boot configuration and Secure Boot keys
        # libvirt creates this automatically on first boot
        nvram_path = "${nvramDir}/${volName}.nvram";

        # bridge_name: Network interface connection
        # VMs connect to the lab-net network (192.168.56.0/24)
        bridge_name = "virbr56";

        # virtio_net: Use VirtIO paravirtualized network driver?
        # false = Use emulated e1000e NIC (Intel Gigabit)
        #
        # Why false?
        # - Windows doesn't include VirtIO drivers by default
        # - Emulated e1000e works out-of-box during Windows install
        # - Can switch to VirtIO later for better performance
        # - VirtIO requires loading drivers during install (extra complexity)
        virtio_net = false;

        # virtio_drive: Use VirtIO paravirtualized disk driver?
        # false = Use emulated SATA controller
        #
        # Why false?
        # - Same reasoning as virtio_net
        # - SATA works during Windows installation without extra drivers
        # - Can migrate to VirtIO in Phase 4 with Packer base images
        virtio_drive = false;

        # install_virtio: Attach VirtIO driver ISO?
        # true = Mount virtio-win.iso as a second CD-ROM
        #
        # Why true?
        # - Makes VirtIO drivers available inside the VM after installation
        # - User can optionally install drivers for better performance
        # - Doesn't interfere with installation (just an extra CD-ROM)
        # - Useful for manual driver updates post-install
        install_virtio = true;
      };

      # Add second network interface for the default NAT network
      # NixVirt's windows template creates one NIC by default
      # We need to extend it to add a second NIC for internet access
      #
      # VM NICs:
      # - eth0/NIC1: Connected to lab-net (192.168.56.0/24) - main lab network
      # - eth1/NIC2: Connected to default (192.168.122.0/24) - internet access
      #
      # Why two NICs?
      # - lab-net: Inter-VM communication, SCCM traffic, domain services
      # - default: Internet access for Windows updates, downloads
      # - Keeps lab traffic separate from internet traffic
      # - Simulates enterprise network topology (internal + DMZ)
      withSecondNIC = baseVM // {
        devices = baseVM.devices // {
          # Extend the interfaces list with a second NIC
          # The '//' operator merges attrsets (like Object.assign in JS)
          # The '++' operator concatenates lists
          interface = (baseVM.devices.interface or []) ++ [
            {
              # type: Interface connection type
              # "network" = Connect to a libvirt virtual network
              # Other types: "bridge" (direct bridge), "direct" (macvtap)
              type = "network";

              # source: Which network to connect to
              # "default" = The standard NAT network (192.168.122.0/24)
              source = { network = "default"; };

              # model: Virtual NIC hardware model
              # "e1000e" = Intel Gigabit Ethernet (emulated)
              # Alternatives: "virtio" (paravirtualized), "rtl8139" (old Realtek)
              #
              # Why e1000e?
              # - Widely supported by Windows (driver built-in)
              # - Good performance (better than rtl8139, close to virtio)
              # - Reliable for enterprise scenarios
              model = { type = "e1000e"; };
            }
          ];
        };
      };
    in
    {
      # definition: Path to the libvirt XML file for this domain
      # NixVirt.lib.domain.writeXML converts our attrset to VM XML
      definition = NixVirt.lib.domain.writeXML withSecondNIC;

      # active: Should this VM start automatically on boot?
      # null = Don't auto-start (user must manually start with 'virsh start')
      #
      # Why null?
      # - VMs don't have an OS installed yet
      # - Auto-starting would just sit at "No bootable device" error
      # - After OS installation, user can enable auto-start:
      #   virsh autostart DC01
      active = null;
    };

  # ==========================================================================
  # HELPER FUNCTION: mkWindowsClient
  # ==========================================================================
  # Creates a Windows 10/11 client VM with standardized configuration
  #
  # Parameters:
  #   name: VM name
  #   uuid: Unique identifier
  #   volName: QCOW2 disk image name
  #
  # Differences from mkWindowsServer:
  # - Less RAM (2 GB vs. 2-4 GB for servers)
  # - Uses Windows 11 ISO instead of Server 2022
  # - Same dual-NIC configuration
  # ==========================================================================
  mkWindowsClient = { name, uuid, volName }:
    let
      baseVM = NixVirt.lib.domain.templates.windows {
        inherit name uuid;

        # memory: RAM allocation for client VMs
        # 2 GiB is sufficient for Windows 11 in a lab environment
        # Production: Consider 4-8 GB for better user experience
        memory = { count = 2; unit = "GiB"; };

        # storage_vol: Client disk image
        storage_vol = {
          inherit pool;
          volume = "${volName}.qcow2";
        };

        # install_vol: Windows 11 installation ISO
        # User must download from Microsoft
        # Note: Windows 11 requires TPM 2.0 (provided by the template)
        install_vol = "${isoDir}/windows-11.iso";

        # nvram_path: UEFI NVRAM for this client
        nvram_path = "${nvramDir}/${volName}.nvram";

        # Network and driver settings (same as mkWindowsServer)
        bridge_name = "virbr56";
        virtio_net = false;
        virtio_drive = false;
        install_virtio = true;
      };

      # Add second NIC (same logic as mkWindowsServer)
      withSecondNIC = baseVM // {
        devices = baseVM.devices // {
          interface = (baseVM.devices.interface or []) ++ [
            {
              type = "network";
              source = { network = "default"; };
              model = { type = "e1000e"; };
            }
          ];
        };
      };
    in
    {
      definition = NixVirt.lib.domain.writeXML withSecondNIC;
      active = null;  # Don't auto-start until OS is installed
    };

in
{
  # ==========================================================================
  # VM DEFINITIONS
  # ==========================================================================
  # Each VM is defined using the helper functions above
  # This keeps the configuration concise and maintainable
  # ==========================================================================

  # --------------------------------------------------------------------------
  # DC01 - Domain Controller
  # --------------------------------------------------------------------------
  # Role: Active Directory Domain Services, DNS, DHCP
  # OS: Windows Server 2022 Standard
  # Domain: lab.local
  # Static IP: 192.168.56.10 (set inside Windows after installation)
  #
  # Resources:
  # - vCPUs: 2 (from windows template default)
  # - RAM: 2 GB (minimum for DC role)
  # - Disk: 60 GB (dc01.qcow2)
  # - NICs: lab-net (primary) + default (internet)
  #
  # Post-installation tasks (automated via PowerShell scripts):
  # - Set static IP 192.168.56.10
  # - Install AD DS role
  # - Promote to domain controller (lab.local)
  # - Configure DNS zones
  # - Install DHCP role
  # - Configure DHCP scope (192.168.56.100-200)
  # --------------------------------------------------------------------------
  dc01 = mkWindowsServer {
    name = "DC01";
    uuid = "4c82c973-7299-468e-bf15-d442ee681475";
    memory = { count = 2; unit = "GiB"; };
    volName = "dc01";
  };

  # --------------------------------------------------------------------------
  # SCCM01 - SCCM Primary Site Server
  # --------------------------------------------------------------------------
  # Role: SQL Server 2022, SCCM Primary Site, Distribution Point
  # OS: Windows Server 2022 Standard
  # Domain: lab.local (joined to DC01's domain)
  # Static IP: 192.168.56.11 (set inside Windows after installation)
  #
  # Resources:
  # - vCPUs: 2
  # - RAM: 4 GB (minimum for SQL + SCCM)
  # - Disk: 100 GB (sccm01.qcow2)
  # - NICs: lab-net (primary) + default (internet)
  #
  # Post-installation tasks (automated via PowerShell scripts):
  # - Set static IP 192.168.56.11
  # - Join to lab.local domain
  # - Install SQL Server 2022 (Standard or Developer Edition)
  # - Configure SQL for SCCM (collation, memory limits)
  # - Install Windows ADK and WinPE addon
  # - Extend Active Directory schema
  # - Install SCCM Primary Site
  # - Configure Distribution Point role
  # - Configure SCCM client settings
  # --------------------------------------------------------------------------
  sccm01 = mkWindowsServer {
    name = "SCCM01";
    uuid = "880e7366-fada-4550-9dc2-dec9daa7fb5c";
    memory = { count = 4; unit = "GiB"; };  # More RAM for SQL + SCCM
    volName = "sccm01";
  };

  # --------------------------------------------------------------------------
  # CLIENT01 - Windows Client #1
  # --------------------------------------------------------------------------
  # Role: SCCM-managed Windows 11 client
  # OS: Windows 11 Pro/Enterprise
  # Domain: lab.local (joined to DC01's domain)
  # Dynamic IP: Assigned via DHCP from DC01 (192.168.56.100-200 range)
  #
  # Resources:
  # - vCPUs: 2
  # - RAM: 2 GB
  # - Disk: 60 GB (client01.qcow2)
  # - NICs: lab-net (primary) + default (internet)
  #
  # Post-installation tasks (automated via PowerShell scripts):
  # - Set computer name to CLIENT01
  # - Join to lab.local domain
  # - Install SCCM client
  # - Configure SCCM site assignment
  # - Test application deployment, policy enforcement
  # --------------------------------------------------------------------------
  client01 = mkWindowsClient {
    name = "CLIENT01";
    uuid = "0f432a26-5296-4201-9b2f-e3e5c39b03bb";
    volName = "client01";
  };

  # --------------------------------------------------------------------------
  # CLIENT02 - Windows Client #2
  # --------------------------------------------------------------------------
  # Role: SCCM-managed Windows 11 client
  # Same configuration as CLIENT01
  # Used for testing multi-client scenarios:
  # - Application deployments to collections
  # - Policy enforcement across multiple machines
  # - Operating system deployment (PXE boot testing)
  # --------------------------------------------------------------------------
  client02 = mkWindowsClient {
    name = "CLIENT02";
    uuid = "59693b4a-35bf-4587-ba07-6c960182b0ae";
    volName = "client02";
  };
}

# ==============================================================================
# TECHNICAL NOTES
# ==============================================================================
#
# 1. UEFI vs. BIOS:
#    - All VMs use UEFI firmware (OVMF - Open Virtual Machine Firmware)
#    - UEFI is required for Windows 11 (TPM 2.0 support)
#    - UEFI provides Secure Boot, faster boot times, GPT partition support
#    - NixVirt's windows template automatically configures OVMF
#
# 2. TPM 2.0:
#    - Windows 11 requires TPM 2.0 for installation
#    - NixVirt's windows template includes emulated TPM (swtpm)
#    - swtpm must be installed on NixOS host (see prerequisites)
#    - TPM state is stored in /var/lib/swtpm/
#
# 3. SECURE BOOT:
#    - Enabled by default in the windows template
#    - Uses Microsoft's UEFI CA keys
#    - Required for some enterprise scenarios
#    - Can be disabled if it causes issues
#
# 4. CPU CONFIGURATION:
#    - vCPUs: 2 per VM (from template default)
#    - CPU model: host-passthrough (best performance, exposes host CPU features)
#    - Topology: 2 sockets x 1 core x 1 thread (or 1 socket x 2 cores)
#    - For production: Use specific CPU models (e.g., "Skylake-Server")
#
# 5. MEMORY BALLOONING:
#    - Not enabled by default
#    - Would allow dynamic memory adjustment
#    - For lab: Static allocation is simpler and more predictable
#
# 6. DISK CACHING:
#    - Cache mode: writethrough (default)
#    - Safe for crash consistency, moderate performance
#    - Alternatives: writeback (faster, less safe), none (slowest, safest)
#    - For lab: Default is fine
#
# 7. NETWORK DRIVER PERFORMANCE:
#    - Current: e1000e (emulated Intel Gigabit)
#    - Throughput: ~1 Gbps (sufficient for lab)
#    - Latency: ~100 microseconds
#    - Future: VirtIO would give ~10 Gbps throughput, <10 microsecond latency
#    - VirtIO requires driver installation (Phase 4 with Packer)
#
# 8. GRAPHICS:
#    - QXL video adapter (SPICE protocol)
#    - Supports resizing, multi-monitor, clipboard sharing
#    - Good performance for remote desktop
#    - virt-manager uses SPICE by default
#
# 9. SOUND:
#    - Not configured (not needed for server lab)
#    - Can be added if testing Windows audio features
#
# 10. USB CONTROLLER:
#     - USB 3.0 controller included
#     - Allows USB device passthrough
#     - Useful for testing USB redirection in RDP/SCCM scenarios
#
# 11. SERIAL CONSOLE:
#     - Serial console enabled (for debugging)
#     - Access via: virsh console DC01
#     - Useful for troubleshooting boot issues
#
# 12. VALIDATION COMMANDS (run after 'nixos-rebuild switch'):
#     virsh list --all                            # List all VMs
#     virsh dumpxml DC01                          # Show full VM XML
#     virsh dumpxml DC01 | grep -A5 '<interface'  # Show network config
#     virsh dumpxml DC01 | grep -i tpm            # Verify TPM is present
#     virsh dominfo DC01                          # Show VM summary
#     virt-manager                                # Open GUI (connect to qemu:///system)
#
# 13. STARTING VMS (after OS installation):
#     virsh start DC01      # Start VM
#     virsh shutdown DC01   # Graceful shutdown (ACPI signal)
#     virsh destroy DC01    # Force power off (like pulling power cord)
#     virsh reboot DC01     # Graceful reboot
#     virsh autostart DC01  # Enable auto-start on host boot
#
# 14. VM SNAPSHOTS:
#     virsh snapshot-create-as DC01 "post-ad-install" --description "After AD DS installation"
#     virsh snapshot-list DC01
#     virsh snapshot-revert DC01 "post-ad-install"
#     virsh snapshot-delete DC01 "post-ad-install"
#
# 15. TROUBLESHOOTING:
#     - VM won't start: Check 'virsh start DC01 --console' for boot errors
#     - No network: Verify networks are active ('virsh net-list')
#     - Disk not found: Check pool and volume ('virsh vol-list homelab')
#     - TPM errors: Ensure swtpm is installed and running
#     - UEFI errors: Check NVRAM path exists and is writable
#
# ==============================================================================
