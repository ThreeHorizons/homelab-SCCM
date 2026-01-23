# Homelab SCCM - Reproducible SCCM Lab Environment

A fully reproducible, NixOS-based homelab for learning and testing Microsoft System Center Configuration Manager (SCCM/ConfigMgr) using declarative infrastructure.

## Overview

This project provides a complete SCCM lab environment built with:
- **NixOS Flakes** for reproducible dependencies
- **Vagrant** for VM orchestration
- **VirtualBox** for virtualization
- **PowerShell/WinRM** for Windows automation

## Quick Start

### Prerequisites

**1. Install VirtualBox**

VirtualBox must be installed at the system level before using this project.

| Platform | Installation |
|----------|-------------|
| **NixOS** | Add to `/etc/nixos/configuration.nix`:<br>`virtualisation.virtualbox.host.enable = true;`<br>`users.users.yourusername.extraGroups = [ "vboxusers" ];`<br>Then run: `sudo nixos-rebuild switch && sudo reboot` |
| **Ubuntu/Debian** | `sudo apt install virtualbox` |
| **Fedora** | `sudo dnf install VirtualBox` |
| **Arch Linux** | `sudo pacman -S virtualbox virtualbox-host-modules-arch` |
| **macOS** | Download from [virtualbox.org](https://www.virtualbox.org/wiki/Downloads) |

**2. Enable Nix Flakes** (if not already enabled)

Add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

Or on NixOS, add to `/etc/nixos/configuration.nix`:
```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

For detailed setup instructions, see [docs/nix-setup.md](docs/nix-setup.md).

### Usage

```bash
# Clone repository
git clone <repository-url>
cd homelab-SCCM

# (Optional) Configure custom storage location for VMs
# Recommended if you have limited space in your home directory
./scripts/configure-storage.sh /mnt/vms
# This will configure Vagrant and VirtualBox to use /mnt/vms
# See docs/storage-configuration.md for details

# Enter development environment
nix develop

# Verify tools
vagrant --version     # Vagrant 2.4.x
VBoxManage --version  # 7.x.x (from system)
pwsh --version        # PowerShell 7.x

# Start lab (Phase 2+)
cd vagrant
vagrant up
```

## Project Status

Currently in **Phase 1** development. See [CLAUDE.md](./CLAUDE.md) for the complete development roadmap and detailed documentation.

### Roadmap

- **Phase 1**: Repository & Flake Foundation (Complete)
- **Phase 2**: Vagrant Multi-VM Topology
- **Phase 3**: WinRM Automation Layer
- **Phase 3.5**: Azure Integration (Optional)
- **Phase 4**: PXE Booting & OSD
- **Phase 5**: Linux Cross-Platform Support
- **Phase 6**: macOS Support
- **Phase 7**: Container Alternative (Optional)

## Infrastructure

### Lab Topology

- **DC01**: Windows Server 2022 (AD DS, DNS, DHCP)
- **SCCM01**: Windows Server 2022 (SQL Server, SCCM Primary Site)
- **CLIENT01-0n**: Windows 10/11 (Domain-joined, SCCM clients)

### Network Configuration

- **Host-Only Network**: 192.168.56.0/24
  - DC01: 192.168.56.10
  - SCCM01: 192.168.56.11
  - Clients: 192.168.56.100+

## Documentation

Comprehensive documentation is available in [CLAUDE.md](./CLAUDE.md), including:

- Detailed phase breakdowns with sub-tasks
- Technical specifications and requirements
- Troubleshooting guides
- Platform-specific considerations
- Official resource links

Additional documentation in `docs/`:
- [docs/nix-setup.md](docs/nix-setup.md) - Nix environment setup
- [docs/topology.md](docs/topology.md) - Network architecture

## Requirements

### Hardware
- **CPU**: 4+ cores (VT-x/AMD-V enabled)
- **RAM**: 16GB minimum, 32GB+ recommended
- **Storage**: 100GB+ (SSD recommended)

### Software
- **VirtualBox** 7.0+ (installed at system level)
- **Nix** with flakes enabled (provides Vagrant, PowerShell, etc.)
- Windows Server 2022 evaluation ISOs
- Windows 10/11 evaluation ISOs

## Development

```bash
# Enter dev shell
nix develop

# Start VMs
cd vagrant && vagrant up

# Run automation scripts
pwsh scripts/dc-setup.ps1
pwsh scripts/sccm-install.ps1

# Create snapshots
vagrant snapshot save checkpoint-name

# Cleanup
vagrant destroy -f
```

## Contributing

1. Follow the phased development approach
2. Test on clean NixOS installation
3. Update documentation for changes
4. Add validation tests where appropriate

## Resources

- [Full Documentation (CLAUDE.md)](./CLAUDE.md)
- [NixOS Wiki - Flakes](https://wiki.nixos.org/wiki/Flakes)
- [Vagrant VirtualBox Provider](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox)
- [Configuration Manager Docs](https://learn.microsoft.com/en-us/intune/configmgr/)

## License

[Specify license - MIT, GPL, Apache, etc.]

## Author

[Your name/handle]

---

For detailed information about implementation phases, troubleshooting, and official resources, see [CLAUDE.md](./CLAUDE.md).
