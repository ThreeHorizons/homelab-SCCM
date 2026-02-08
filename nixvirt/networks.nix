# nixvirt/networks.nix
#
# Network definitions for the SCCM homelab environment
#
# Returns a LIST of network objects (not an attrset).
# NixVirt's module type is: nullOr (listOf (submodule { definition, active, restart }))
#
# Each object has:
#   definition: path to XML file (from NixVirt.lib.network.writeXML)
#   active:     bool or null - whether the network should be running
#   restart:    bool or null - whether to restart on activation
#
# IMPORTANT: When this list is non-null, NixVirt will DELETE any libvirt
# networks not present in this list. Make sure all desired networks are listed.
#
# This file defines two libvirt networks:
# 1. lab-net: Primary lab network (192.168.56.0/24) for inter-VM communication
# 2. default: Standard NAT network (192.168.122.0/24) for internet access

{ NixVirt }:

[
  # ============================================================================
  # PRIMARY LAB NETWORK (lab-net)
  # ============================================================================
  # Subnet: 192.168.56.0/24
  # Gateway: 192.168.56.1 (libvirt host)
  # DHCP: DISABLED - Windows DHCP server on DC01 handles DHCP
  # Bridge: virbr56
  # Mode: NAT (inter-VM communication + internet access)
  #
  # Static IPs (configured inside Windows guests):
  #   DC01:   192.168.56.10 (Domain Controller, DNS, DHCP)
  #   SCCM01: 192.168.56.11 (SCCM Primary Site Server)
  #
  # Dynamic IPs (DHCP range managed by DC01):
  #   Clients: 192.168.56.100 - 192.168.56.200
  # ============================================================================
  {
    definition = NixVirt.lib.network.writeXML {
      name = "lab-net";
      uuid = "0355c7ff-0c40-4a7a-8c0d-1f7564af25ca";
      forward = { mode = "nat"; };
      bridge = { name = "virbr56"; };
      ip = {
        address = "192.168.56.1";
        netmask = "255.255.255.0";
        # No dhcp block = DHCP disabled on this network
        # Windows DHCP server on DC01 will handle DHCP requests
      };
    };
    active = true;
  }

  # ============================================================================
  # DEFAULT NAT NETWORK
  # ============================================================================
  # Subnet: 192.168.122.0/24 (libvirt standard default)
  # Gateway: 192.168.122.1
  # Bridge: virbr0
  # Mode: NAT
  #
  # Uses NixVirt's bridge template which auto-configures:
  #   bridge name, gateway IP, netmask, DHCP range, DNS forwarding
  # ============================================================================
  {
    definition = NixVirt.lib.network.writeXML
      (NixVirt.lib.network.templates.bridge {
        uuid = "d72183d8-b05c-42a6-9f79-96177d160f8e";
        subnet_byte = 122;
      });
    active = true;
  }
]
