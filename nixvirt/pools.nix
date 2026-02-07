# nixvirt/pools.nix
#
# Storage pool and volume definitions for the SCCM homelab environment
#
# This file defines:
# 1. A storage pool named "homelab" (directory-based)
# 2. Four QCOW2 volumes for the VM disks (DC01, SCCM01, CLIENT01, CLIENT02)
#
# QCOW2 (QEMU Copy-On-Write 2) is a disk image format that:
# - Supports sparse allocation (only uses space as data is written)
# - Enables snapshots (save VM state at a point in time)
# - Provides better performance than raw files for many workloads
# - Is the standard format for KVM/QEMU virtualization

{ NixVirt }:

{
  # ============================================================================
  # HOMELAB STORAGE POOL
  # ============================================================================
  # Purpose: Central storage location for all VM disk images
  # Type: Directory-based pool (simplest, most common)
  # Path: /var/lib/libvirt/images/homelab/
  #
  # Why directory-based?
  # - Simple: Just a directory on the filesystem
  # - Flexible: Easy to move, backup, or migrate
  # - No special setup: No LVM, ZFS, or iSCSI configuration needed
  # - Good performance on modern filesystems (ext4, xfs, btrfs)
  #
  # Alternative pool types (not used here):
  # - LVM: Logical Volume Manager (better for snapshots, more complex)
  # - ZFS: Advanced filesystem with compression, deduplication
  # - NFS: Network-attached storage (for shared storage clusters)
  # - iSCSI: Block-level network storage
  # ============================================================================
  homelab = {
    # definition: Path to the libvirt XML file for this storage pool
    # NixVirt.lib.pool.writeXML converts a Nix attrset to pool XML
    definition = NixVirt.lib.pool.writeXML {
      # Pool name (shown in 'virsh pool-list')
      name = "homelab";

      # UUID: Unique identifier for this storage pool
      # Generated with 'uuidgen' to ensure no conflicts
      uuid = "31c47f9a-9ee8-4fd2-9f83-25733e81b978";

      # type: Storage pool type
      # "dir" = directory-based pool (files stored in a regular directory)
      # Other types: "logical" (LVM), "disk" (partition), "netfs" (NFS), etc.
      type = "dir";

      # target: Where the pool's files are stored
      target = {
        # path: Absolute path to the storage directory
        # libvirt will create this directory if it doesn't exist
        # All VM disk images will be stored here
        path = "/var/lib/libvirt/images/homelab";
      };
    };

    # active: Should this pool be started automatically?
    # true = Pool is available on system boot
    # libvirt will mount/activate the pool when the daemon starts
    active = true;

    # =========================================================================
    # VOLUME DEFINITIONS
    # =========================================================================
    # Volumes are the actual disk images (QCOW2 files) used by VMs
    # Each volume represents a virtual hard drive
    #
    # Volume naming convention: {vm-name}.qcow2
    # This makes it easy to identify which disk belongs to which VM
    # =========================================================================
    volumes = [
      # -----------------------------------------------------------------------
      # DC01 VOLUME (Domain Controller)
      # -----------------------------------------------------------------------
      {
        # name: Filename of the volume (shown in 'virsh vol-list homelab')
        name = "dc01.qcow2";

        # definition: libvirt XML for this volume
        definition = NixVirt.lib.volume.writeXML {
          name = "dc01.qcow2";

          # capacity: Virtual size of the disk
          # The VM will see this as a 60GB hard drive
          # Actual space used on host will be much less (sparse allocation)
          capacity = {
            count = 60;   # Number of units
            unit = "GiB"; # Units (GiB = gibibytes, 1 GiB = 1024^3 bytes)
          };

          # target: Volume format and storage details
          target = {
            format = {
              # type: Disk image format
              # "qcow2" = QEMU Copy-On-Write version 2
              # - Sparse: Only uses space for written data
              # - Snapshots: Can save VM state at any point
              # - Compression: Optional compression support
              # - Encryption: Optional encryption support
              type = "qcow2";
            };
          };
        };

        # present: Should this volume exist?
        # true = libvirt will create the volume if it doesn't exist
        # false = libvirt will delete the volume if it exists
        present = true;
      }

      # -----------------------------------------------------------------------
      # SCCM01 VOLUME (SCCM Primary Site Server)
      # -----------------------------------------------------------------------
      # Larger capacity because SCCM requires significant disk space:
      # - SQL Server databases (10-20 GB)
      # - SCCM content library (drivers, applications, updates: 20-40 GB)
      # - Operating system deployment images (10-15 GB)
      # - Log files and temporary data
      # -----------------------------------------------------------------------
      {
        name = "sccm01.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "sccm01.qcow2";

          # 100 GiB capacity - sufficient for SCCM installation and content
          capacity = {
            count = 100;
            unit = "GiB";
          };

          target = {
            format = { type = "qcow2"; };
          };
        };
        present = true;
      }

      # -----------------------------------------------------------------------
      # CLIENT01 VOLUME (Windows Client)
      # -----------------------------------------------------------------------
      {
        name = "client01.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "client01.qcow2";

          # 60 GiB - Standard for Windows 10/11 clients
          # - Windows installation: ~20-25 GB
          # - SCCM client: ~500 MB
          # - Applications and updates: ~10-15 GB
          # - User data and temporary files: ~10-20 GB
          capacity = {
            count = 60;
            unit = "GiB";
          };

          target = {
            format = { type = "qcow2"; };
          };
        };
        present = true;
      }

      # -----------------------------------------------------------------------
      # CLIENT02 VOLUME (Windows Client)
      # -----------------------------------------------------------------------
      {
        name = "client02.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "client02.qcow2";

          # Same capacity as CLIENT01
          capacity = {
            count = 60;
            unit = "GiB";
          };

          target = {
            format = { type = "qcow2"; };
          };
        };
        present = true;
      }
    ];
  };
}

# ==============================================================================
# TECHNICAL NOTES
# ==============================================================================
#
# 1. SPARSE ALLOCATION:
#    - QCOW2 files start very small (~200 KB) and grow as data is written
#    - A 60 GiB volume might only use 15 GB on disk after Windows installation
#    - Use 'qemu-img info dc01.qcow2' to see actual vs. virtual size
#    - Example output:
#      virtual size: 60 GiB (64424509440 bytes)
#      disk size: 15.2 GiB  <-- actual space used on host
#
# 2. PREALLOCATION (not used here):
#    - We could use <allocation> tag to preallocate space
#    - Preallocated disks have slightly better performance
#    - But they take up full space immediately (60 GB = 60 GB on disk)
#    - For a lab environment, sparse is better (saves space)
#
# 3. SNAPSHOTS:
#    - QCOW2 supports internal snapshots (saved within the same file)
#    - Useful for saving VM state before risky changes
#    - Example: 'virsh snapshot-create-as DC01 "pre-ad-install"'
#    - Restore: 'virsh snapshot-revert DC01 "pre-ad-install"'
#    - List: 'virsh snapshot-list DC01'
#
# 4. BACKING STORES (not used here, future enhancement):
#    - QCOW2 supports copy-on-write backing files
#    - Base image: windows-server-2022-base.qcow2 (read-only)
#    - Overlay: dc01.qcow2 (writes go here, reads fall back to base)
#    - Saves space when multiple VMs share the same base OS
#    - Planned for Phase 4 with Packer-built base images
#
# 5. VOLUME PERMISSIONS:
#    - libvirt runs QEMU processes as 'qemu:qemu' user (on most systems)
#    - Volume files must be readable/writable by the qemu user
#    - libvirt handles this automatically for pool-managed volumes
#    - Manual files in /var/lib/libvirt/images/ may have permission issues
#
# 6. STORAGE POOL PATHS:
#    - Default libvirt pool: /var/lib/libvirt/images/
#    - Our homelab pool: /var/lib/libvirt/images/homelab/
#    - Keeping them separate makes organization clearer
#    - You can change the path to use a different disk/partition
#    - Example: /mnt/ssd/libvirt-vms/homelab/
#
# 7. DISK I/O PERFORMANCE:
#    - QCOW2 on SSD: Excellent performance, similar to native
#    - QCOW2 on HDD: Good, but benefits from cache tuning
#    - For production: Consider raw format or preallocated QCOW2
#    - For lab: QCOW2 sparse is perfect (space savings > raw performance)
#
# 8. VALIDATION COMMANDS (run after 'nixos-rebuild switch'):
#    virsh pool-list --all                    # List all storage pools
#    virsh pool-info homelab                  # Show pool details
#    virsh vol-list homelab                   # List volumes in pool
#    virsh vol-info homelab/dc01.qcow2        # Show volume details
#    qemu-img info /var/lib/libvirt/images/homelab/dc01.qcow2  # Detailed disk info
#    ls -lh /var/lib/libvirt/images/homelab/  # See actual file sizes
#
# 9. TOTAL SPACE REQUIREMENTS:
#    - Virtual space: 60 + 100 + 60 + 60 = 280 GiB
#    - Actual space (after OS install): ~100-150 GB
#    - Ensure your filesystem has at least 200 GB free
#    - Check with: df -h /var/lib/libvirt/images/
#
# 10. MOVING VOLUMES TO ANOTHER DISK:
#     If you want to store volumes on a different disk/partition:
#
#     a) Change the pool path in this file:
#        target = { path = "/mnt/ssd/libvirt-vms/homelab"; };
#
#     b) Rebuild: sudo nixos-rebuild switch
#
#     c) If you have existing volumes to move:
#        sudo virsh pool-destroy homelab
#        sudo mv /var/lib/libvirt/images/homelab/* /mnt/ssd/libvirt-vms/homelab/
#        sudo virsh pool-start homelab
#        sudo virsh pool-refresh homelab
#
# ==============================================================================
