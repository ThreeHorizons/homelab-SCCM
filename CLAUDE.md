# Homelab SCCM - NixOS-Based Configuration Manager Lab Environment

## Project Overview

This project provides a **fully reproducible, declarative homelab environment** for learning and testing Microsoft System Center Configuration Manager (SCCM/ConfigMgr) using NixOS, Vagrant, and VirtualBox. The infrastructure is defined as code, enabling quick teardown and rebuild cycles ideal for learning, testing, and experimentation.

### Key Technologies

- **NixOS Flakes**: Reproducible development environment and dependency management
- **Vagrant**: Multi-VM orchestration and topology definition
- **VirtualBox**: Hypervisor for Windows Server and Client VMs
- **PowerShell/WinRM**: Windows automation and configuration management
- **SCCM/ConfigMgr**: Microsoft enterprise endpoint management platform

---

## Architecture

This lab supports two operational modes:

1. **Traditional Mode** (Phase 1-3): Isolated on-premises SCCM environment
2. **Cloud-Integrated Mode** (Phase 3.5+): Hybrid environment with Azure AD, Intune, and Cloud Management Gateway

For detailed network architecture diagrams including both traditional and cloud-integrated topologies, VM specifications, DNS/DHCP configuration, and Azure cost estimates, see [docs/topology.md](docs/topology.md).

### Quick Network Summary

- **NAT Network**: Provides internet access for all VMs
- **Host-Only Network**: Isolated network for lab communication (192.168.56.0/24)
  - DC01: 192.168.56.10 (Domain Controller, DNS, DHCP, optional Azure AD Connect)
  - SCCM01: 192.168.56.11 (SQL, SCCM Primary Site, optional Azure Services Connection)
  - CLIENT01-0n: 192.168.56.100+ (DHCP-assigned, optional Hybrid Azure AD Join)

---

## Development Phases

This project follows a structured, phase-based development approach to ensure each layer is stable before building the next.

### Phase 1: Repository & Flake Foundation (NixOS-only)

**Status**: Initial phase - Start here

**Goals**:
- Create reproducible development environment
- Establish repository structure
- Pin all dependencies with Nix flakes
- Document entry and usage

**Tasks**:
1. Initialize git repository structure
2. Create `flake.nix` with core dependencies:
   - Vagrant (latest stable)
   - VirtualBox (7.0.x or 7.1.x)
   - PowerShell Core (7.x)
   - WinRM/WinRS tools
   - Python (for tooling)
3. Define `devShell` for NixOS users
4. Pin nixpkgs to stable release
5. Create comprehensive documentation
6. Test flake on fresh NixOS system

**Sub-tasks & Considerations**:
- [ ] Verify VirtualBox kernel module compatibility with current NixOS kernel
- [ ] Test VirtualBox host-only networking interface creation
- [ ] Ensure PowerShell modules can access WinRM (may require dotnet runtime)
- [ ] Document how to enable Nix flakes if not already enabled
- [ ] Add pre-commit hooks for nix formatting (nixpkgs-fmt or alejandra)

**Deliverables**:
- `flake.nix` - Main flake definition
- `flake.lock` - Pinned dependencies
- `README.md` - Quick start guide
- `docs/topology.md` - Network and VM architecture
- `docs/nix-setup.md` - Detailed Nix environment setup

**Potential Issues**:
- VirtualBox kernel modules may require `allowUnfree = true` in Nix config
- Host-only networks limited to 192.168.56.0/21 range on Linux hosts
- VirtualBox may require manual `/etc/vbox/networks.conf` configuration
- PowerShell Core may need `icu` library dependencies

---

### Phase 2: Vagrant Multi-VM Topology

**Goals**:
- Define declarative VM infrastructure
- Automate VM provisioning
- Create base Windows boxes
- Establish network connectivity

**Tasks**:
1. Create `Vagrantfile` with multi-machine configuration
2. Define VirtualBox provider settings:
   - Memory allocations (DC: 2GB, SCCM: 4GB, Clients: 2GB)
   - CPU allocations
   - Network adapters (NAT + Host-Only)
   - Disk configurations
3. Configure Windows Server 2022 base box
4. Configure Windows 10/11 client base box
5. Create bootstrap PowerShell scripts for initial setup
6. Parameterize client VM count (default: 2, configurable)
7. Test VM creation and networking

**Sub-tasks & Considerations**:
- [ ] Research available Windows Server 2022 Vagrant boxes (gusztavvargadr/windows-server, StefanScherer/windows_2022)
- [ ] Consider building custom Windows boxes with Packer for evaluation licenses
- [ ] Test VirtualBox guest additions installation
- [ ] Configure WinRM during initial bootstrap for automation
- [ ] Set up shared folders if needed for file transfers
- [ ] Document Windows licensing requirements (evaluation vs. MSDN)
- [ ] Test snapshot functionality for quick rollback
- [ ] Implement naming convention for VMs (prefix-based)

**Deliverables**:
- `vagrant/Vagrantfile` - Multi-machine topology
- `vagrant/scripts/bootstrap.ps1` - Initial Windows configuration
- `vagrant/scripts/enable-winrm.ps1` - WinRM setup for automation
- `vagrant/boxes/` - Documentation on base box selection
- `docs/vagrant-topology.md` - VM specifications and networking

**Potential Issues**:
- Windows evaluation licenses expire after 180 days
- Large base boxes (6-8GB per Windows Server box)
- VirtualBox 7.x may have compatibility issues with older boxes
- WinRM may not be enabled by default on base boxes
- Host-only adapter may not route properly without DHCP
- VirtualBox may require VT-x/AMD-V CPU extensions

---

### Phase 3: WinRM Automation Layer

**Goals**:
- Fully automate Windows Server configuration
- Implement infrastructure as code for AD, DNS, DHCP, SQL, SCCM
- Create reusable PowerShell modules
- Enable one-command deployment

**Tasks**:
1. Create PowerShell automation framework:
   - Connection management
   - Error handling
   - Logging and progress reporting
2. Automate Active Directory Domain Services:
   - Promote DC01 to domain controller
   - Create domain (lab.local)
   - Configure DNS zones
   - Create OUs and initial user/computer objects
3. Configure DHCP Server:
   - Create scope (192.168.56.100-192.168.56.200)
   - Set domain-wide DHCP options
   - Configure DHCP reservations for servers
4. Automate SQL Server installation on SCCM01:
   - Install SQL Server 2019/2022 with required features
   - Configure SQL Server for SCCM (collation, memory, etc.)
   - Create service accounts
   - Configure SQL Server network protocols
5. Automate SCCM installation:
   - Run prerequisite checker
   - Install Windows ADK and WinPE addon
   - Extend Active Directory schema
   - Install SCCM primary site
   - Configure site boundaries and boundary groups
   - Enable Distribution Point role
   - Configure SCCM client settings
6. Automate client domain join:
   - Join clients to lab.local domain
   - Configure regional settings and time zone
   - Rename computers based on pattern
7. Automate SCCM client deployment:
   - Client push installation
   - Client policy deployment
   - Verify client communication

**Sub-tasks & Considerations**:
- [ ] Create PowerShell DSC configurations as alternative to scripts
- [ ] Implement idempotent scripts (safe to re-run)
- [ ] Add validation checks before each major step
- [ ] Create rollback/cleanup scripts
- [ ] Test with PowerShell remoting in both Windows PowerShell 5.1 and PowerShell Core
- [ ] Handle password management securely (credential objects, not plaintext)
- [ ] Implement progress tracking and estimated time remaining
- [ ] Add verbose logging with timestamps
- [ ] Test script execution from Linux host via PowerShell Core
- [ ] Document required service accounts and permissions
- [ ] Create reusable PowerShell modules for common tasks
- [ ] Test SCCM installation with both SQL Server 2019 and 2022
- [ ] Validate schema extension in AD
- [ ] Test boundary detection and site assignment

**Deliverables**:
- `scripts/modules/` - Reusable PowerShell modules
- `scripts/dc-setup.ps1` - AD DS, DNS, DHCP configuration
- `scripts/sql-setup.ps1` - SQL Server installation and config
- `scripts/sccm-prereq.ps1` - SCCM prerequisite installation
- `scripts/sccm-install.ps1` - SCCM primary site installation
- `scripts/sccm-config.ps1` - Post-installation SCCM configuration
- `scripts/client-join.ps1` - Domain join automation
- `scripts/client-sccm.ps1` - SCCM client installation
- `docs/winrm-automation.md` - WinRM setup and troubleshooting
- `docs/passwords.md` - Password management strategy
- `docs/service-accounts.md` - Required accounts and permissions

**Potential Issues**:
- WinRM authentication may fail without proper TrustedHosts configuration
- CredSSP may be required for double-hop authentication scenarios
- PowerShell Core may have compatibility issues with some Windows modules
- AD schema extension requires Enterprise Admin privileges
- SQL Server collation must be SQL_Latin1_General_CP1_CI_AS
- SCCM installation can take 30-60 minutes
- Client push may fail if Windows Firewall rules not configured
- Network discovery may not work properly in VirtualBox NAT networks

---

### Phase 3.5: Azure Integration Foundation (Optional but Recommended)

**Status**: Optional - Bridges traditional SCCM with modern cloud management

**Goals**:
- Integrate on-premises Active Directory with Azure AD (Microsoft Entra ID)
- Enable hybrid Azure AD join for domain-joined devices
- Deploy Cloud Management Gateway (CMG) for internet-based client management
- Configure tenant attach to upload devices to Microsoft Endpoint Manager
- Enable co-management between SCCM and Intune
- Test modern management scenarios (Intune policies, conditional access, Endpoint Analytics)

**Why This Phase Matters**:
As of 2026, most enterprises use hybrid management combining on-premises SCCM with cloud-based Intune. This phase enables you to learn:
- Co-management workflows (SCCM + Intune)
- Hybrid Azure AD join (devices in both on-prem AD and Azure AD)
- Cloud Management Gateway (manage devices over the internet)
- Tenant attach (view SCCM devices in cloud admin center)
- Modern Windows management (Intune policies, conditional access, Endpoint Analytics)

**Prerequisites**:
- ✅ Phase 1-3 completed (traditional SCCM lab operational)
- [ ] Azure subscription (free trial acceptable - see cost estimates in [docs/topology.md](docs/topology.md#azure-integration-costs-phase-35-optional))
- [ ] Microsoft Intune license (30-day trial or Microsoft 365 E5 Developer subscription)
- [ ] Global Administrator account for Azure AD tenant

**Main Tasks**:
1. **Azure Tenant Setup**:
   - Create Azure AD tenant and activate Intune trial
   - Document tenant ID, subscription ID for future reference
2. **Azure AD Connect Installation** (on DC01):
   - Install Azure AD Connect
   - Configure password hash synchronization
   - Sync on-premises users to Azure AD
   - Verify hybrid identity working
3. **Hybrid Azure AD Join Configuration**:
   - Configure Service Connection Point (SCP) in AD
   - Create Group Policy for device registration
   - Test hybrid join on CLIENT01
   - Verify device appears in Azure AD portal
4. **Cloud Management Gateway Deployment**:
   - Generate CMG server authentication certificate
   - Configure Azure Services connection in SCCM
   - Deploy CMG to Azure (B2s Lab VM size)
   - Configure management point for CMG traffic
   - Test client communication via CMG
5. **Tenant Attach Configuration**:
   - Enable tenant attach in SCCM
   - Upload devices to Microsoft Endpoint Manager admin center
   - Test remote actions from cloud portal
6. **Co-Management Enablement**:
   - Enable co-management in SCCM
   - Configure automatic Intune enrollment
   - Shift pilot workloads to Intune (e.g., Compliance Policies)
   - Verify co-managed devices reporting to both SCCM and Intune
7. **Modern Management Testing**:
   - Deploy Intune compliance policy
   - Test conditional access scenarios
   - Explore Endpoint Analytics
   - Test cloud-based remote actions

**Deliverables**:
- Azure AD Connect running on DC01 with active synchronization
- At least one hybrid Azure AD joined device (CLIENT01)
- Cloud Management Gateway deployed in Azure
- Tenant attach configured with devices in Endpoint Manager
- Co-management enabled with at least one Intune-managed workload
- Documentation of Azure tenant details and cost tracking

**Potential Issues**:
- **Azure AD Connect fails**: Verify TLS 1.2 enabled, internet connectivity, .NET Framework 4.6.2+
- **Hybrid join not working**: Check SCP configuration, GPO applied, time sync, connectivity to enterpriseregistration.windows.net
- **CMG deployment fails**: Verify Azure permissions, certificate validity, Microsoft.Compute resource provider registered
- **Co-management enrollment fails**: Verify Intune licenses, MDM authority set, device is hybrid joined first
- **Costs exceeding budget**: Stop/deallocate CMG when not testing, use free trials, monitor Azure Cost Management

**Cost Estimate** (see [docs/topology.md](docs/topology.md#azure-integration-costs-phase-35-optional) for details):
- **First month**: $0 (using trials)
- **Ongoing**: $20-50/month (CMG + Intune licenses)
- **Cost reduction**: Use Microsoft 365 Developer Program (free renewable E5), deallocate CMG when not testing

**Detailed Checklist**: See [.claude/phase3.5-checklist.md](.claude/phase3.5-checklist.md) for step-by-step implementation guide with testing procedures.

**Skip This Phase If**:
- Budget-conscious and only want traditional SCCM learning
- Not interested in modern cloud management
- Focused on OSD/PXE workflows only

**This Phase Is Essential If**:
- Want to learn modern enterprise Windows management (2026 reality)
- Need co-management experience for job market
- Want to understand hybrid identity and cloud integration
- Planning to work with Azure/Intune in production environments

---

### Phase 4: PXE Booting & OSD Automation

**Goals**:
- Enable network-based OS deployment
- Create SCCM task sequences
- Test bare-metal deployment scenarios
- Implement automated OS deployment

**Tasks**:
1. Configure SCCM Distribution Point for PXE:
   - Enable PXE responder on DP
   - Configure PXE settings (respond to all clients vs. known only)
   - Set PXE password if required
   - Configure boot image distribution
2. Alternative: Set up standalone PXE server:
   - Install dnsmasq for DHCP proxy
   - Configure TFTP server
   - Create iPXE boot configuration
3. Import and configure SCCM boot images:
   - Import Windows ADK boot images
   - Add drivers to boot images
   - Add PowerShell support to WinPE
   - Distribute boot images to DP
4. Create OS deployment task sequences:
   - Import Windows 10/11 installation media
   - Create standard client build task sequence
   - Add driver packages
   - Configure applications and updates
   - Add domain join step
   - Configure SCCM client installation
5. Configure SCCM collections and deployments:
   - Create "All Unknown Computers" collection
   - Create "OSD Deployment" collection
   - Deploy task sequence
   - Configure deployment settings (available vs. required)
6. Test PXE boot workflow:
   - Create new VirtualBox VM
   - Configure network boot as first boot device
   - Test PXE boot and task sequence execution
   - Verify deployed OS and SCCM client

**Sub-tasks & Considerations**:
- [ ] Research VirtualBox PXE boot capabilities and limitations
- [ ] Test with both BIOS and UEFI boot modes
- [ ] Consider separate VLAN for PXE traffic (optional)
- [ ] Add DHCP option 60 if using external PXE server
- [ ] Test with multiple simultaneous deployments
- [ ] Document task sequence variables and customization
- [ ] Create task sequence templates for different scenarios
- [ ] Test driver injection for common hardware
- [ ] Implement custom branding/OEM information
- [ ] Add BitLocker configuration (optional)
- [ ] Test deployment scheduling and maintenance windows
- [ ] Document recovery scenarios (failed deployments)

**Deliverables**:
- `pxe/README.md` - PXE boot overview and architecture
- `pxe/dnsmasq.conf` - dnsmasq configuration (if using)
- `pxe/tftp/` - TFTP root directory structure
- `scripts/pxe-setup.ps1` - PXE/DP configuration script
- `scripts/import-os.ps1` - OS image import automation
- `scripts/create-tasksequence.ps1` - Task sequence creation
- `docs/pxe-plan.md` - PXE implementation strategy
- `docs/osd-troubleshooting.md` - Common OSD issues and solutions
- `docs/task-sequences.md` - Task sequence design and best practices

**Potential Issues**:
- VirtualBox PXE boot may not work with all network configurations
- UEFI PXE boot requires different boot files than BIOS
- WinPE may not include drivers for VirtualBox virtual NIC
- Task sequences may fail with "No task sequences available" error (MAC address duplicates)
- Boot image distribution can take significant time
- PXE timeout issues during high network latency
- DHCP options may conflict between VirtualBox DHCP and lab DHCP
- Unknown computer approval may be required in SCCM settings

---

### Phase 5: Cross-Platform Support (Linux Distros)

**Goals**:
- Make flake usable on Ubuntu, Fedora, Arch, Debian
- Handle distribution-specific differences
- Maintain NixOS experience on non-NixOS systems
- Document platform-specific requirements

**Tasks**:
1. Add conditional logic to flake.nix for Linux variations
2. Handle VirtualBox installation differences:
   - Kernel module compilation on different kernels
   - Package names across distributions
   - Repository configuration
3. Handle Vagrant installation variations:
   - Distribution packages vs. HashiCorp repositories
   - Plugin installation differences
4. Test on major distributions:
   - Ubuntu 22.04/24.04 LTS
   - Fedora 39/40
   - Arch Linux
   - Debian 12
5. Document distribution-specific setup steps
6. Create distribution detection and auto-configuration
7. Handle permission differences (Docker/VirtualBox groups)

**Sub-tasks & Considerations**:
- [ ] Create VM snapshots for testing on different distros
- [ ] Test with both X11 and Wayland display servers
- [ ] Verify VirtualBox Extension Pack installation on all distros
- [ ] Test with different kernel versions
- [ ] Handle SELinux on Fedora/RHEL
- [ ] Document AppArmor considerations on Ubuntu
- [ ] Test with different init systems (though most use systemd)
- [ ] Handle package manager variations (apt, dnf, pacman)
- [ ] Consider Flatpak/Snap as alternative VirtualBox sources
- [ ] Test with both regular users and sudoers

**Deliverables**:
- Updated `flake.nix` with cross-platform support
- `docs/linux-support.md` - Distribution-specific guides
- `docs/ubuntu-setup.md` - Ubuntu-specific instructions
- `docs/fedora-setup.md` - Fedora-specific instructions
- `docs/arch-setup.md` - Arch-specific instructions
- `scripts/detect-distro.sh` - Distribution detection helper
- Test results matrix documenting compatibility

**Potential Issues**:
- VirtualBox kernel modules may not compile on latest kernels
- Secure Boot may prevent VirtualBox module loading
- Different VirtualBox versions across distributions
- Nix installation requires root or user namespace support
- Some distributions may require VirtualBox repository addition
- Extension Pack licensing restrictions in corporate environments

---

### Phase 6: macOS Support (Darwin)

**Goals**:
- Enable macOS users to run the lab
- Handle Darwin-specific VirtualBox behavior
- Adapt for macOS filesystem and permissions
- Document macOS-specific workflows

**Tasks**:
1. Add Darwin-specific package overrides to flake.nix
2. Handle VirtualBox networking on macOS:
   - Host-only networking configuration differences
   - Kernel extension (kext) loading
   - Network interface naming differences
3. Test PowerShell Core functionality on macOS:
   - WinRM module compatibility
   - Windows management framework
   - Authentication mechanisms
4. Handle macOS-specific permissions:
   - Full Disk Access for VirtualBox
   - Kernel extension approval
5. Test on macOS versions:
   - macOS Monterey (12.x)
   - macOS Ventura (13.x)
   - macOS Sonoma (14.x)
   - macOS Sequoia (15.x)
6. Document installation of Xcode Command Line Tools (Nix requirement)
7. Handle Apple Silicon (ARM) vs. Intel considerations

**Sub-tasks & Considerations**:
- [ ] Research VirtualBox ARM64 support status for Apple Silicon
- [ ] Document Rosetta 2 requirements if needed for Intel VirtualBox
- [ ] Test VirtualBox 7.x on macOS with System Integrity Protection (SIP)
- [ ] Handle macOS Gatekeeper warnings for VirtualBox
- [ ] Test with different macOS Terminal applications
- [ ] Verify Nix installation on macOS (single-user vs. multi-user)
- [ ] Consider macOS-specific virtualization alternatives (VMware Fusion)
- [ ] Document Time Machine exclusions for large VM files
- [ ] Test on both APFS and HFS+ filesystems
- [ ] Handle case-sensitive vs. case-insensitive filesystem issues

**Deliverables**:
- Darwin-compatible `flake.nix`
- `docs/macos-support.md` - macOS setup guide
- `docs/apple-silicon.md` - ARM64/Apple Silicon considerations
- `scripts/macos-setup.sh` - macOS-specific setup automation
- FAQ for common macOS issues

**Potential Issues**:
- VirtualBox on Apple Silicon is EXPERIMENTAL (as of 7.1.x)
- Nested virtualization may not work on Apple Silicon
- Kernel extensions require explicit approval in System Settings
- macOS Sonoma (14.x) has stricter kernel extension policies
- VirtualBox performance may be poor on Apple Silicon
- May require VirtualBox Developer Preview builds
- Rosetta 2 translation overhead for Intel VirtualBox
- Port < 1024 binding restrictions similar to Linux

---

### Phase 7: Optional - Containerized Tooling for Non-Nix Users

**Goals**:
- Provide Docker/Podman alternative to Nix
- Lower barrier to entry for users unfamiliar with Nix
- Maintain reproducibility through containerization
- Support Windows and macOS users who can't/won't install Nix

**Tasks**:
1. Create Dockerfile with all dependencies:
   - Base on official Ubuntu/Fedora image
   - Install Vagrant
   - Install VirtualBox CLI tools (headless)
   - Install PowerShell Core
   - Install WinRM tools
   - Copy project scripts
2. Create docker-compose.yml for easy orchestration
3. Handle VirtualBox nested virtualization:
   - Document hardware requirements
   - Configure /dev/vboxdrv access
4. Create wrapper scripts for container execution
5. Publish container image to registry (Docker Hub/GHCR)
6. Document container usage workflow
7. Test on Windows (Docker Desktop), macOS, and Linux

**Sub-tasks & Considerations**:
- [ ] Research VirtualBox in Docker/Podman feasibility
- [ ] Consider KVM/QEMU alternative to VirtualBox for containerized setup
- [ ] Test with rootless Podman
- [ ] Handle volume mounts for VM storage
- [ ] Document port forwarding requirements
- [ ] Create devcontainer.json for VS Code integration
- [ ] Consider GitHub Codespaces compatibility
- [ ] Evaluate cloud-based alternatives (Terraform + AWS/Azure)
- [ ] Document hardware requirements (VT-x, AMD-V)

**Deliverables**:
- `container/Dockerfile` - Container image definition
- `container/docker-compose.yml` - Orchestration configuration
- `container/entrypoint.sh` - Container entry point script
- `docs/container-support.md` - Container usage guide
- `docs/non-nix-setup.md` - Alternative setup methods
- `.devcontainer/devcontainer.json` - VS Code dev container config

**Potential Issues**:
- VirtualBox in containers is complex and may not work reliably
- Nested virtualization has significant performance overhead
- Docker Desktop on Windows/macOS has licensing changes (commercial use)
- May need to fall back to KVM/QEMU for containerized approach
- Large container image size (multiple GB)
- USB passthrough and advanced VirtualBox features may not work

---

## Technical Specifications

### Software Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| **NixOS** | 23.11+ or Unstable | Host operating system (Phase 1-4) |
| **Nix** | 2.19+ | With flakes enabled |
| **Vagrant** | 2.4.0+ | VM orchestration |
| **VirtualBox** | 7.0.x or 7.1.x | Virtualization platform |
| **PowerShell** | 7.4+ | Windows automation |
| **Windows Server** | 2022 | Domain Controller & SCCM host |
| **SQL Server** | 2019 or 2022 | SCCM database (Standard or Developer) |
| **SCCM/ConfigMgr** | Current Branch (2403+) | Target: Latest Current Branch |
| **Windows 10/11** | Latest | Client operating systems |
| **Windows ADK** | Matching Windows version | OS deployment prerequisites |

### Hardware Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **CPU** | 4 cores | 8+ cores | VT-x/AMD-V required |
| **RAM** | 16GB | 32GB+ | VMs allocate: DC=2GB, SCCM=4GB, Clients=2GB each |
| **Storage** | 100GB | 200GB+ | SSD strongly recommended |
| **Network** | 100Mbps | 1Gbps | For Windows ISO downloads |

### Resource Allocation

**Default VM Configuration:**

| VM | vCPUs | RAM | Disk | OS |
|----|-------|-----|------|-----|
| DC01 | 2 | 2GB | 60GB | Windows Server 2022 |
| SCCM01 | 2 | 4GB | 100GB | Windows Server 2022 |
| CLIENT01 | 2 | 2GB | 60GB | Windows 10/11 |
| CLIENT02+ | 2 | 2GB | 60GB | Windows 10/11 |

**Total Resources (2 clients):**
- vCPUs: 8
- RAM: 10GB
- Disk: 280GB

---

## Key Considerations & Caveats

### NixOS & Nix Flakes

**Enabling Flakes:**
```nix
# /etc/nixos/configuration.nix or ~/.config/nix/nix.conf
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

**VirtualBox on NixOS:**
- Requires `virtualisation.virtualbox.host.enable = true` in system configuration
- May need `nixpkgs.config.allowUnfree = true` for VirtualBox Extension Pack
- Kernel modules automatically managed by NixOS

**Host-Only Network Configuration:**
- Linux hosts limit host-only interfaces to 192.168.56.0/21 by default
- Custom ranges require `/etc/vbox/networks.conf`:
  ```
  * 192.168.56.0/21
  * 10.0.0.0/8
  ```

### Vagrant & VirtualBox

**Base Box Selection:**
- Official Windows boxes are large (6-10GB)
- Evaluation licenses expire after 180 days
- Consider building custom boxes with Packer for long-term use
- Popular boxes:
  - `gusztavvargadr/windows-server-2022-standard`
  - `StefanScherer/windows_2022`
  - `gusztavvargadr/windows-10` or `windows-11`

**VirtualBox Compatibility:**
- VirtualBox 7.x may have issues with older Vagrant boxes
- Always install VirtualBox Guest Additions matching host version
- UEFI boot support varies by box

**Networking Caveats:**
- VirtualBox NAT network may not support PXE boot properly (use bridged or host-only)
- DHCP options may need manual configuration
- Port forwarding can conflict with host services

### PowerShell & WinRM

**WinRM Authentication:**
- Default authentication is Kerberos (domain-joined machines)
- Non-domain requires TrustedHosts configuration:
  ```powershell
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
  ```
- CredSSP required for multi-hop authentication (enable only when needed)

**PowerShell Core vs. Windows PowerShell:**
- Some Windows management modules only work in Windows PowerShell 5.1
- Use `pwsh.exe` vs. `powershell.exe` explicitly in scripts
- Test scripts on Linux host to ensure cross-platform compatibility

**Security Considerations:**
- Use HTTPS listeners in production environments
- Avoid storing plaintext passwords in scripts
- Use `PSCredential` objects and secure strings
- Consider Just Enough Administration (JEA) for production

### SCCM/ConfigMgr

**SQL Server Requirements:**
- Collation MUST be `SQL_Latin1_General_CP1_CI_AS`
- Minimum SQL Server 2019 CU5 or SQL Server 2022
- Service accounts require specific SQL permissions
- Configure SQL memory limits (leave 2GB for OS)

**Active Directory Prerequisites:**
- Schema extension requires Enterprise Admin
- System Management container must be created
- SCCM computer account needs permissions on container

**Installation Time:**
- SCCM installation takes 30-60 minutes
- Post-installation configuration adds 15-30 minutes
- Full lab deployment: 1.5-2 hours (with automation)

**Common Issues:**
- Prerequisite checker failures (missing Windows features)
- Site installation fails on SQL connection
- Client push requires proper firewall rules
- PXE boot requires specific DHCP options

### PXE & OSD

**VirtualBox PXE Limitations:**
- PXE boot may be slow or unreliable in NAT networks
- Use host-only or bridged network for PXE
- Some boxes may not support PXE boot properly

**WinPE Driver Requirements:**
- VirtualBox virtual NIC (Intel PRO/1000) usually included
- Test boot image before deployment
- Add PowerShell and scripting support to WinPE

**Task Sequence Troubleshooting:**
- Enable command prompt support in boot image
- Press F8 during task sequence for debugging
- Check smsts.log in X:\Windows\Temp\SMSTSLog
- "No task sequences available" = duplicate MAC or deployment timing

---

## Troubleshooting Guide

### Nix/NixOS Issues

**Flake commands not recognized:**
```bash
# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**VirtualBox kernel modules not loading:**
```bash
# On NixOS, ensure configuration includes:
virtualisation.virtualbox.host.enable = true;

# Rebuild and reboot
sudo nixos-rebuild switch
```

**Permission denied on /dev/vboxdrv:**
```bash
# Add user to vboxusers group
sudo usermod -aG vboxusers $USER
# Logout and login
```

### Vagrant Issues

**Vagrant can't find VirtualBox:**
```bash
# Set VBOX_INSTALL_PATH
export VBOX_INSTALL_PATH=/usr/lib/virtualbox
```

**VMs fail to start:**
```bash
# Check VirtualBox is working
VBoxManage list vms

# Check logs
vagrant up --debug
```

**Network adapter creation fails:**
```bash
# Manually create host-only adapter
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
```

### WinRM Issues

**Cannot connect to Windows VM:**
```powershell
# Test WinRM from Windows guest
Test-WSMan -ComputerName localhost

# Enable WinRM (run on guest)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Restart-Service WinRM
```

**Authentication failures:**
```powershell
# Check TrustedHosts (run on host)
Get-Item WSMan:\localhost\Client\TrustedHosts

# Set TrustedHosts (run on host)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.56.*" -Force
```

**CredSSP errors:**
```powershell
# Enable CredSSP (for double-hop scenarios)
Enable-WSManCredSSP -Role Client -DelegateComputer "*.lab.local" -Force
# On server:
Enable-WSManCredSSP -Role Server -Force
```

### SCCM Issues

**Prerequisite check failures:**
- Install missing Windows features: `.NET Framework 3.5`, `BITS`, `RDC`
- Verify SQL Server version and collation
- Check service account permissions
- Extend AD schema before installation

**Site installation hangs:**
- Check SQL Server connectivity
- Verify SQL Server service is running
- Review ConfigMgrSetup.log in SCCM installation directory
- Ensure adequate disk space (100GB+)

**Client push fails:**
- Verify firewall rules (ports 135, 139, 445)
- Check admin$ share accessibility
- Verify Client Push Installation Account has admin rights
- Review ccm.log on site server

**PXE boot not working:**
- Verify DP role is PXE-enabled
- Check boot image distribution status
- Ensure DHCP options 66/67 are not set (conflicts with PXE responder)
- Verify network boot order in BIOS

### VirtualBox Issues

**Host-only network missing:**
```bash
# Create manually
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0

# Start DHCP server (optional)
VBoxManage dhcpserver add --ifname vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0 \
  --lowerip 192.168.56.100 --upperip 192.168.56.200 --enable
```

**VMs extremely slow:**
- Enable VT-x/AMD-V in BIOS
- Install VirtualBox Guest Additions
- Increase allocated RAM
- Use SSD for VM storage
- Disable Hyper-V on Windows hosts (conflicts with VirtualBox)

**USB passthrough not working:**
- Install VirtualBox Extension Pack
- Add user to vboxusers group
- Enable USB controller in VM settings

---

## Official Documentation & Resources

### Nix & NixOS

- [NixOS Flakes - Official Wiki](https://wiki.nixos.org/wiki/Flakes)
- [Flakes Concepts - nix.dev](https://nix.dev/concepts/flakes.html)
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/)
- [Zero to Nix - Flakes](https://zero-to-nix.com/concepts/flakes/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)

### Vagrant

- [Vagrant VirtualBox Provider Documentation](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox)
- [Vagrant VirtualBox Configuration](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox/configuration)
- [Vagrant VirtualBox Networking](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox/networking)
- [Vagrant Documentation](https://developer.hashicorp.com/vagrant/docs)

### VirtualBox

- [VirtualBox Chapter 6: Virtual Networking](https://www.virtualbox.org/manual/ch06.html)
- [VirtualBox User Manual](https://www.virtualbox.org/manual/)
- [VirtualBox Networking Details](https://www.virtualbox.org/manual/topics/networkingdetails.html)
- [VirtualBox Downloads](https://www.virtualbox.org/wiki/Downloads)

### PowerShell & WinRM

- [WinRM Security Considerations - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/winrm-security?view=powershell-7.5)
- [Enable-PSRemoting Documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/enable-psremoting?view=powershell-7.5)
- [Windows Remote Management Installation](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
- [PowerShell Remoting Ultimate Guide](https://adamtheautomator.com/psremoting/)

### SCCM/Configuration Manager

- [Configuration Manager Site Prerequisites](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/site-and-site-system-prerequisites)
- [Supported SQL Server Versions](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-sql-server-versions)
- [Prerequisites for Installing Sites](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/deploy/install/prerequisites-for-installing-sites)
- [Use PXE for OSD over Network](https://learn.microsoft.com/en-us/intune/configmgr/osd/deploy-use/use-pxe-to-deploy-windows-over-the-network)
- [Deploy a Task Sequence](https://learn.microsoft.com/en-us/intune/configmgr/osd/deploy-use/deploy-a-task-sequence)

### Community Resources

- [SCCM Installation Guide - System Center Dudes](https://www.systemcenterdudes.com/complete-sccm-installation-guide-and-configuration/)
- [SCCM OSD Ultimate Guide](https://www.anoopcnair.com/sccm-osd-task-sequence-ultimate-guide/)
- [Prajwal Desai - SCCM Blog](https://www.prajwaldesai.com/)

---

## Project Structure

```
homelab-SCCM/
├── flake.nix                    # Nix flake definition
├── flake.lock                   # Pinned dependencies
├── README.md                    # Quick start guide
├── CLAUDE.md                    # This file - comprehensive project documentation
├── .gitignore                   # Git ignore patterns
├── vagrant/
│   ├── Vagrantfile              # Multi-VM topology definition
│   ├── scripts/
│   │   ├── bootstrap.ps1        # Initial Windows setup
│   │   ├── enable-winrm.ps1     # WinRM configuration
│   │   └── provision-vm.ps1     # Post-creation provisioning
│   └── boxes/
│       └── README.md            # Base box information
├── scripts/
│   ├── modules/                 # Reusable PowerShell modules
│   │   ├── Logger.psm1          # Logging functions
│   │   ├── WinRMHelper.psm1     # WinRM connection helpers
│   │   └── Validator.psm1       # Configuration validation
│   ├── dc-setup.ps1             # AD DS, DNS, DHCP automation
│   ├── sql-setup.ps1            # SQL Server installation
│   ├── sccm-prereq.ps1          # SCCM prerequisites
│   ├── sccm-install.ps1         # SCCM installation
│   ├── sccm-config.ps1          # Post-install SCCM configuration
│   ├── client-join.ps1          # Domain join automation
│   ├── client-sccm.ps1          # SCCM client installation
│   ├── pxe-setup.ps1            # PXE/DP configuration
│   ├── import-os.ps1            # OS image import
│   ├── create-tasksequence.ps1  # Task sequence automation
│   └── cleanup.ps1              # Lab teardown script
├── pxe/
│   ├── README.md                # PXE boot overview
│   ├── dnsmasq.conf             # dnsmasq configuration (alternative)
│   └── tftp/                    # TFTP root (if using)
├── docs/
│   ├── topology.md              # Network and VM architecture
│   ├── nix-setup.md             # Nix environment setup
│   ├── vagrant-topology.md      # VM specifications
│   ├── winrm-automation.md      # WinRM setup and troubleshooting
│   ├── passwords.md             # Password management
│   ├── service-accounts.md      # Required accounts and permissions
│   ├── pxe-plan.md              # PXE implementation strategy
│   ├── osd-troubleshooting.md   # OSD issue resolution
│   ├── task-sequences.md        # Task sequence design
│   ├── linux-support.md         # Linux distribution support
│   ├── ubuntu-setup.md          # Ubuntu-specific guide
│   ├── fedora-setup.md          # Fedora-specific guide
│   ├── arch-setup.md            # Arch-specific guide
│   ├── macos-support.md         # macOS setup guide
│   ├── apple-silicon.md         # ARM64/Apple Silicon notes
│   ├── container-support.md     # Docker/Podman usage
│   └── non-nix-setup.md         # Alternative installation methods
├── container/                   # Phase 7 - Optional
│   ├── Dockerfile               # Container image
│   ├── docker-compose.yml       # Orchestration
│   └── entrypoint.sh            # Container entry point
├── .devcontainer/
│   └── devcontainer.json        # VS Code dev container
└── tests/                       # Validation scripts
    ├── test-winrm.ps1           # WinRM connectivity tests
    ├── test-ad.ps1              # AD health checks
    ├── test-sccm.ps1            # SCCM functionality tests
    └── validate-deployment.ps1  # End-to-end validation
```

---

## Quick Start (Phase 1)

Once Phase 1 is complete, you'll be able to enter the development environment with:

```bash
# Clone repository
git clone <repository-url>
cd homelab-SCCM

# Enter Nix development shell
nix develop

# Verify tools are available
vagrant --version
VBoxManage --version
pwsh --version

# Start infrastructure (Phase 2+)
cd vagrant
vagrant up
```

---

## Development Workflow

1. **Enter Development Shell**: `nix develop`
2. **Create/Start VMs**: `cd vagrant && vagrant up`
3. **Run Automation**: `pwsh scripts/dc-setup.ps1`
4. **Test Changes**: `pwsh tests/validate-deployment.ps1`
5. **Snapshot State**: `vagrant snapshot save <name>`
6. **Iterate**: Make changes, test, snapshot
7. **Cleanup**: `vagrant destroy -f`

---

## Contributing

When adding features or fixing issues:

1. Test on clean NixOS installation
2. Update relevant documentation
3. Add validation tests
4. Update CLAUDE.md with new caveats or learnings
5. Follow the phased approach - don't skip ahead

---

## Roadmap Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1: Nix Flake Foundation | 🟡 Next | Starting point |
| Phase 2: Vagrant Topology | ⚪ Planned | Depends on Phase 1 |
| Phase 3: WinRM Automation | ⚪ Planned | Core functionality |
| **Phase 3.5: Azure Integration** | ⚪ **Optional** | **Modern cloud management** |
| Phase 4: PXE & OSD | ⚪ Planned | Advanced features |
| Phase 5: Linux Support | ⚪ Future | Cross-platform |
| Phase 6: macOS Support | ⚪ Future | Cross-platform |
| Phase 7: Container Support | ⚪ Optional | Alternative approach |

---

## License

[Specify your license here - MIT, GPL, Apache, etc.]

---

## Acknowledgments

- NixOS community for reproducible infrastructure patterns
- HashiCorp for Vagrant
- Oracle for VirtualBox
- Microsoft for comprehensive ConfigMgr documentation
- System Center community blogs and forums

---

**Version**: 1.0.0  
**Last Updated**: 2026-01-15  
**Maintained By**: [Your Name/Handle]
