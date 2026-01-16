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

Before using this project, configure your NixOS system:

1. **Enable Nix Flakes** - Add to `/etc/nixos/configuration.nix`:
   ```nix
   nix.settings.experimental-features = [ "nix-command" "flakes" ];
   ```

2. **Enable VirtualBox** - Add to `/etc/nixos/configuration.nix`:
   ```nix
   virtualisation.virtualbox.host.enable = true;
   nixpkgs.config.allowUnfree = true;
   users.users.yourusername.extraGroups = [ "vboxusers" ];
   ```
   Replace `yourusername` with your actual username.

3. **Apply configuration**:
   ```bash
   sudo nixos-rebuild switch
   sudo reboot
   ```

📖 **Detailed setup instructions**: See [docs/nix-setup.md](docs/nix-setup.md)

### Usage

```bash
# Clone repository
git clone <repository-url>
cd homelab-SCCM

# Enter development environment
nix develop

# Verify tools (should show no warnings)
vagrant --version   # Should show: Vagrant 2.4.1
VBoxManage --version  # Should show: 7.0.22r165102
pwsh --version       # Should show: PowerShell 7.4.2

# Start lab (Phase 2+)
cd vagrant
vagrant up
```

## Project Status

Currently in **Phase 1** development. See [CLAUDE.md](./CLAUDE.md) for the complete development roadmap and detailed documentation.

### Roadmap

- 🟡 **Phase 1**: Repository & Flake Foundation (Current)
- ⚪ **Phase 2**: Vagrant Multi-VM Topology
- ⚪ **Phase 3**: WinRM Automation Layer
- ⚪ **Phase 4**: PXE Booting & OSD
- ⚪ **Phase 5**: Linux Cross-Platform Support
- ⚪ **Phase 6**: macOS Support
- ⚪ **Phase 7**: Container Alternative (Optional)

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
- Architecture and topology diagrams
- Setup guides for different platforms
- WinRM automation details
- PXE/OSD implementation
- Task sequence design

## Requirements

### Hardware
- **CPU**: 4+ cores (VT-x/AMD-V enabled)
- **RAM**: 16GB minimum, 32GB+ recommended
- **Storage**: 100GB+ (SSD recommended)

### Software
- NixOS 23.11+ (or Nix with flakes on other platforms in later phases)
- VirtualBox 7.0.x or 7.1.x
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
