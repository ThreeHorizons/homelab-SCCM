# Vagrant Base Boxes

## Overview

This directory contains documentation for Windows base boxes used in the SCCM homelab.

## Recommended Base Boxes

### Windows Server 2022

**Option 1: gusztavvargadr/windows-server-2022-standard**
- Publisher: Gusztáv Varga
- Size: ~6-8GB
- Features: Desktop Experience, VirtualBox Guest Additions
- Evaluation: 180-day evaluation license
- URL: https://app.vagrantup.com/gusztavvargadr/boxes/windows-server-2022-standard

**Option 2: StefanScherer/windows_2022**
- Publisher: Stefan Scherer
- Size: ~8-10GB
- Features: Desktop Experience, up-to-date patches
- Evaluation: 180-day evaluation license
- URL: https://app.vagrantup.com/StefanScherer/boxes/windows_2022

### Windows 10/11 Clients

**Option 1: gusztavvargadr/windows-10**
- Publisher: Gusztáv Varga
- Version: Various (22H2 recommended)
- Size: ~6-8GB
- Evaluation: 90-day evaluation license
- URL: https://app.vagrantup.com/gusztavvargadr/boxes/windows-10

**Option 2: gusztavvargadr/windows-11**
- Publisher: Gusztáv Varga
- Version: 23H2
- Size: ~8-10GB
- Requirements: UEFI boot (VirtualBox 7.0+)
- Evaluation: 90-day evaluation license
- URL: https://app.vagrantup.com/gusztavvargadr/boxes/windows-11

## Box Selection Criteria

When selecting a base box, consider:

1. **VirtualBox Version Compatibility**: Ensure the box works with VirtualBox 7.0.x/7.1.x
2. **Guest Additions**: Pre-installed and up-to-date
3. **Evaluation Period**: 90 days (clients) or 180 days (servers)
4. **Disk Format**: Supports dynamic allocation
5. **WinRM**: Enabled by default for Vagrant provisioning
6. **Updates**: Recent patches applied

## Evaluation Licenses

### Windows Server 2022
- **Duration**: 180 days (6 months)
- **Extensions**: Can be extended up to 5 times (3 years total) using `slmgr /rearm`
- **Download**: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022

### Windows 10/11
- **Duration**: 90 days (3 months)
- **Extensions**: Can be extended up to 3 times (1 year total) using `slmgr /rearm`
- **Download**: https://www.microsoft.com/en-us/software-download/windows10 or windows11

## Building Custom Boxes with Packer

For long-term use or specific configurations, consider building custom boxes with Packer.

### Benefits
- Full control over installed software
- Use your own licenses (MSDN, Volume License)
- Pre-configure Windows features
- Include specific drivers or tools
- Eliminate evaluation license expiration

### Resources
- [Packer Windows Templates](https://github.com/gusztavvargadr/packer-windows)
- [Official Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Windows Answer Files](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/)

## Using MSDN Licenses

If you have access to Microsoft Developer Network (MSDN) or Visual Studio subscriptions:

1. Download Windows Server and Client ISOs from MSDN
2. Use Packer to build custom boxes with your license keys
3. Store boxes locally or in private Vagrant repository
4. No evaluation expiration concerns

## Box Storage

Downloaded boxes are cached in:
- Linux/macOS: `~/.vagrant.d/boxes/`
- Windows: `%USERPROFILE%\.vagrant.d\boxes\`

Boxes can be large (6-10GB each). Ensure adequate disk space.

## Adding New Boxes

To add a box to the local cache:

```bash
# Add from Vagrant Cloud
vagrant box add gusztavvargadr/windows-server-2022-standard

# Add from local file
vagrant box add windows-server-2022 ./custom-box.box

# Specify provider
vagrant box add --provider virtualbox gusztavvargadr/windows-server-2022-standard
```

## Updating Boxes

```bash
# Check for updates
vagrant box outdated

# Update a specific box
vagrant box update --box gusztavvargadr/windows-server-2022-standard

# Update all boxes
vagrant box update
```

## Removing Old Boxes

```bash
# List all boxes
vagrant box list

# Remove old version
vagrant box remove gusztavvargadr/windows-server-2022-standard --box-version 1.0.0

# Prune all old versions
vagrant box prune
```

## WinRM Configuration

Vagrant requires WinRM to be enabled for provisioning. All recommended boxes have this pre-configured.

### Default WinRM Settings
- **Port**: 5985 (HTTP) or 5986 (HTTPS)
- **Authentication**: Negotiate (Kerberos)
- **Username**: vagrant
- **Password**: vagrant

### Manual WinRM Setup (if needed)

If using a box without WinRM enabled:

```powershell
# Enable WinRM
Enable-PSRemoting -Force

# Configure WinRM for Vagrant
winrm quickconfig -q
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Open firewall
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow
```

## Guest Additions

VirtualBox Guest Additions provide:
- Better graphics performance
- Shared folders support
- Seamless mouse integration
- Time synchronization
- Clipboard sharing

### Verifying Guest Additions

```bash
# From host
VBoxManage guestproperty get <vm-name> /VirtualBox/GuestAdd/Version

# From guest (Windows)
Get-ItemProperty "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions"
```

### Installing/Updating Guest Additions

```bash
# Insert Guest Additions CD
VBoxManage storageattach <vm-name> --storagectl IDE --port 1 --device 0 --type dvddrive --medium /usr/share/virtualbox/VBoxGuestAdditions.iso

# From Windows guest, run:
# D:\VBoxWindowsAdditions.exe /S
```

## Troubleshooting

### Box Download Fails
- Check internet connection
- Try different Vagrant Cloud mirror
- Download box manually and add locally

### Box Won't Boot
- Verify VirtualBox version compatibility
- Check VT-x/AMD-V is enabled in BIOS
- Try older box version
- Review VirtualBox logs: `VBoxManage showvminfo <vm-name> --log 0`

### WinRM Connection Fails
- Verify WinRM is enabled in guest
- Check Windows Firewall rules
- Ensure TrustedHosts configured (workgroup scenarios)
- Try `vagrant reload --provision`

### Disk Space Issues
- Boxes are large (6-10GB each)
- Each VM instance creates additional disk files
- Use `vagrant box prune` to remove old versions
- Consider external storage for VM files

## Box Security

### Evaluation Boxes
- Use default credentials (vagrant/vagrant)
- Suitable for lab/testing only
- **Never expose to internet**
- Change passwords after deployment

### Production/Enterprise
- Build custom boxes with Packer
- Use encrypted credentials
- Implement proper access controls
- Regular security updates

## Next Steps

1. Select appropriate base boxes for your use case
2. Add boxes to local Vagrant cache
3. Test boxes with simple Vagrantfile
4. Proceed to Phase 2 Vagrantfile configuration

See [CLAUDE.md](../../CLAUDE.md) for full implementation guide.
