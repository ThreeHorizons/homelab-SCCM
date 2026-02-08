# nixvirt/pools.nix
#
# Storage pool and volume definitions for the SCCM homelab environment
#
# Returns a LIST of pool objects.
# NixVirt's module type is: nullOr (listOf (submodule { definition, active, restart, volumes }))
#
# Each pool object has:
#   definition: path to XML file (from NixVirt.lib.pool.writeXML)
#   active:     bool or null - whether the pool should be started
#   restart:    bool or null - whether to restart on activation
#   volumes:    list of { present, name, definition } - volumes to manage
#
# IMPORTANT: When this list is non-null, NixVirt will DELETE any libvirt
# pools not present in this list. Volumes not listed are left alone (not deleted).
# Set present = false to explicitly delete a volume.

{ NixVirt }:

[
  # ============================================================================
  # HOMELAB STORAGE POOL
  # ============================================================================
  # Type: Directory-based (/var/lib/libvirt/images/homelab/)
  # Contains QCOW2 disk images for all VMs
  # QCOW2 uses sparse allocation - a 60 GiB volume starts ~200 KB on disk
  # ============================================================================
  {
    definition = NixVirt.lib.pool.writeXML {
      name = "homelab";
      uuid = "31c47f9a-9ee8-4fd2-9f83-25733e81b978";
      type = "dir";
      target = {
        path = "/var/lib/libvirt/images/homelab";
      };
    };
    active = true;

    volumes = [
      # DC01: Domain Controller (AD DS, DNS, DHCP) - 60 GiB
      {
        present = true;
        name = "dc01.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "dc01.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        };
      }

      # SCCM01: SCCM Primary Site (SQL Server + ConfigMgr) - 100 GiB
      {
        present = true;
        name = "sccm01.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "sccm01.qcow2";
          capacity = { count = 100; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        };
      }

      # CLIENT01: Windows 11 client - 60 GiB
      {
        present = true;
        name = "client01.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "client01.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        };
      }

      # CLIENT02: Windows 11 client - 60 GiB
      {
        present = true;
        name = "client02.qcow2";
        definition = NixVirt.lib.volume.writeXML {
          name = "client02.qcow2";
          capacity = { count = 60; unit = "GiB"; };
          target = { format = { type = "qcow2"; }; };
        };
      }
    ];
  }
]
