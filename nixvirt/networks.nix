# nixvirt/networks.nix
#
# Network definitions for the SCCM homelab environment
#
# This file defines two libvirt networks:
# 1. lab-net: Primary lab network (192.168.56.0/24) for inter-VM communication and SCCM
# 2. default: Standard NAT network (192.168.122.0/24) for internet access
#
# Both networks use NAT mode to provide internet connectivity while keeping
# VMs isolated from the host network.

{ NixVirt }:

{
  # ============================================================================
  # PRIMARY LAB NETWORK (lab-net)
  # ============================================================================
  # Purpose: Main network for SCCM lab VMs
  # Subnet: 192.168.56.0/24
  # Gateway: 192.168.56.1 (libvirt host)
  # DHCP Range: 192.168.56.100 - 192.168.56.200 (for dynamic assignment)
  # Static IPs: 192.168.56.10 (DC01), 192.168.56.11 (SCCM01)
  # Bridge: virbr56 (created automatically by libvirt)
  # Mode: NAT (VMs can access internet, isolated from host LAN)
  #
  # Why NAT instead of isolated?
  # - Windows VMs need internet for updates, ADK downloads, SCCM prerequisites
  # - NAT provides both inter-VM communication AND internet access
  # - Keeps lab isolated from production networks
  # ============================================================================
  lab-net = {
    # definition: Path to the libvirt XML file for this network
    # NixVirt.lib.network.writeXML takes a Nix attrset and converts it to XML
    definition = NixVirt.lib.network.writeXML {
      # Network name (shown in 'virsh net-list')
      name = "lab-net";

      # UUID: Universally Unique Identifier for this network
      # Generated with 'uuidgen' command - ensures no conflicts with other networks
      uuid = "0355c7ff-0c40-4a7a-8c0d-1f7564af25ca";

      # forward: Network forwarding configuration
      # mode = "nat": Enable NAT (Network Address Translation)
      # This allows VMs to access the internet through the host
      forward = { mode = "nat"; };

      # bridge: Linux bridge device configuration
      # name: The bridge interface name that will be created on the host
      # You can see this bridge with 'ip addr show virbr56'
      # libvirt creates and manages this bridge automatically
      bridge = { name = "virbr56"; };

      # ip: IP addressing configuration for the network
      ip = {
        # address: The gateway IP address (libvirt host's IP on this network)
        # VMs will use this as their default gateway
        address = "192.168.56.1";

        # netmask: Subnet mask defining the network size
        # 255.255.255.0 = /24 CIDR = 254 usable host addresses
        netmask = "255.255.255.0";

        # dhcp: DHCP server configuration
        # libvirt runs a built-in dnsmasq instance for DHCP
        dhcp = {
          # range: IP address range for dynamic allocation
          # Client VMs (CLIENT01, CLIENT02) will get IPs from this pool
          # DC01 and SCCM01 use static IPs outside this range
          range = {
            start = "192.168.56.100";
            end = "192.168.56.200";
          };
        };
      };
    };

    # active: Should this network be started automatically?
    # true = 'virsh net-start lab-net' runs on system boot
    # This network will be available whenever the libvirt daemon starts
    active = true;
  };

  # ============================================================================
  # DEFAULT NAT NETWORK
  # ============================================================================
  # Purpose: Secondary network for general internet access
  # Subnet: 192.168.122.0/24 (libvirt's standard default)
  # Gateway: 192.168.122.1
  # Mode: NAT
  #
  # Why use the default network?
  # - Provides a second network interface for redundancy
  # - Matches libvirt's standard configuration (less surprising)
  # - Can be used for management traffic separate from SCCM traffic
  #
  # This network uses NixVirt's 'bridge' template, which is a helper function
  # for creating standard NAT networks with 192.168.X.0/24 subnets.
  # ============================================================================
  default = {
    # Using the 'bridge' template for a standard NAT network
    # Template parameters:
    #   uuid: Unique identifier
    #   subnet_byte: The third octet of the IP address (192.168.X.0/24)
    #                subnet_byte = 122 → 192.168.122.0/24
    #
    # The bridge template automatically configures:
    # - Bridge name: virbr0 (standard libvirt default)
    # - Gateway IP: 192.168.122.1
    # - Netmask: 255.255.255.0
    # - DHCP range: 192.168.122.2 - 192.168.122.254
    # - DNS forwarder: Host's DNS servers
    definition = NixVirt.lib.network.writeXML
      (NixVirt.lib.network.templates.bridge {
        uuid = "d72183d8-b05c-42a6-9f79-96177d160f8e";
        subnet_byte = 122;
      });

    # Auto-start this network on boot
    active = true;
  };
}

# ==============================================================================
# TECHNICAL NOTES
# ==============================================================================
#
# 1. NETWORK MODES:
#    - NAT: VMs can access internet via host, isolated from LAN
#    - Isolated: VMs can only talk to each other, no internet
#    - Bridge: VMs appear on host's physical network (not used here)
#    - Route: VMs are routed through host (more complex than NAT)
#
# 2. BRIDGE DEVICES:
#    - virbr56 and virbr0 are virtual bridge devices created by libvirt
#    - These act like virtual network switches inside the host
#    - VMs connect to these bridges via virtual network interfaces (vnet0, vnet1, etc.)
#    - You can inspect bridges with: ip link show type bridge
#
# 3. DHCP AND DNS:
#    - libvirt runs dnsmasq for each network (DHCP + DNS)
#    - dnsmasq provides DNS resolution and DHCP leases
#    - You can see DHCP leases in /var/lib/libvirt/dnsmasq/
#    - DNS resolution works for VM hostnames (e.g., ping dc01 works between VMs)
#
# 4. STATIC IP ASSIGNMENT:
#    - Static IPs (DC01: .10, SCCM01: .11) are set inside the guest OS
#    - These IPs are OUTSIDE the DHCP range (.100-.200)
#    - This prevents IP conflicts between static and DHCP assignments
#    - Configure static IPs in Windows: Control Panel → Network Adapter → IPv4 Properties
#
# 5. FIREWALL CONSIDERATIONS:
#    - libvirt automatically creates iptables/nftables rules for NAT
#    - VMs can access internet, but internet cannot initiate connections to VMs
#    - If you need to access VMs from host, use libvirt's port forwarding
#    - Or connect to VMs via their IP addresses from the host
#
# 6. NETWORK ISOLATION:
#    - VMs on lab-net can talk to each other via 192.168.56.x addresses
#    - VMs on default can talk to each other via 192.168.122.x addresses
#    - VMs with both NICs can route between networks (if routing is enabled in the guest)
#    - By default, Windows Server will enable routing if DC01 has multiple NICs
#
# 7. VALIDATION COMMANDS (run after 'nixos-rebuild switch'):
#    virsh net-list --all                    # List all networks
#    virsh net-dumpxml lab-net               # Show lab-net XML configuration
#    virsh net-dhcp-leases lab-net           # Show DHCP leases
#    ip addr show virbr56                    # Show bridge interface details
#    brctl show virbr56                      # Show bridge connections (if bridge-utils installed)
#
# ==============================================================================
