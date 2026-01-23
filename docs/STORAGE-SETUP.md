# Quick Storage Setup Guide

If you want to store all VM-related files in `/mnt/vms` (or any other location), follow this quick guide.

## Why Configure Custom Storage?

By default, Vagrant and VirtualBox store files in your home directory:
- `~/.vagrant.d/boxes/` - Downloaded Vagrant boxes (~15-20GB)
- `~/VirtualBox VMs/` - VM disk files (~60-100GB per VM)

For this lab with 3 VMs, you'll need **~300GB** of space. If your home directory is on a smaller SSD, you may want to use a larger partition or separate disk.

---

## Quick Setup (Automated)

The easiest way is to use the provided script:

```bash
# Run the configuration script
./scripts/configure-storage.sh /mnt/vms
```

This script will:
1. Create `/mnt/vms/vagrant-boxes/` and `/mnt/vms/virtualbox-vms/`
2. Configure VirtualBox to use `/mnt/vms/virtualbox-vms/` for VM disks
3. Add `export VAGRANT_HOME=/mnt/vms/vagrant-boxes` to your shell config
4. Display current configuration and next steps

After running the script:

```bash
# Reload your shell configuration
source ~/.bashrc  # or ~/.zshrc

# Verify the configuration
echo $VAGRANT_HOME
# Should show: /mnt/vms/vagrant-boxes

VBoxManage list systemproperties | grep "Default machine folder"
# Should show: /mnt/vms/virtualbox-vms

# Now you can start using Vagrant normally
cd vagrant
vagrant up dc01
```

---

## Manual Setup (Alternative)

If you prefer to configure manually:

### 1. Create Directories

```bash
sudo mkdir -p /mnt/vms
sudo chown -R $USER:$USER /mnt/vms
mkdir -p /mnt/vms/vagrant-boxes
mkdir -p /mnt/vms/virtualbox-vms
```

### 2. Configure Vagrant

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export VAGRANT_HOME=/mnt/vms/vagrant-boxes
```

Then reload:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### 3. Configure VirtualBox

```bash
VBoxManage setproperty machinefolder /mnt/vms/virtualbox-vms
```

---

## Verification

After configuration, verify everything is set correctly:

```bash
# Enter the dev shell
nix develop

# You should see output showing:
#   Storage configuration:
#     - Vagrant home: /mnt/vms/vagrant-boxes
#     - VirtualBox VMs: /mnt/vms/virtualbox-vms
```

---

## What Happens When You Run `vagrant up`

1. **First Time**: Vagrant will download Windows boxes to `/mnt/vms/vagrant-boxes/`
   - This is a one-time download (~15-20GB total)
   - Progress is shown during download

2. **VM Creation**: VirtualBox creates VM disks in `/mnt/vms/virtualbox-vms/`
   - DC01: ~60GB
   - SCCM01: ~100GB  
   - CLIENT01: ~60GB each

3. **Total Usage**: Expect ~300GB for the complete lab (with 1 client)

---

## Monitoring Disk Usage

```bash
# Check current usage
du -h --max-depth=1 /mnt/vms/

# Watch usage in real-time during downloads
watch -n 5 "du -sh /mnt/vms/*"

# Check available space
df -h /mnt/vms
```

---

## Reverting to Default Locations

If you want to go back to using home directory:

```bash
# Unset Vagrant home
unset VAGRANT_HOME

# Remove from shell config
sed -i '/VAGRANT_HOME/d' ~/.bashrc  # or ~/.zshrc

# Reset VirtualBox to default
VBoxManage setproperty machinefolder default

# Verify
VBoxManage list systemproperties | grep "Default machine folder"
```

---

## Troubleshooting

### Permission Denied Errors

```bash
# Ensure you own the directory
sudo chown -R $USER:$USER /mnt/vms
chmod -R u+w /mnt/vms
```

### Vagrant Can't Find Boxes

```bash
# Verify VAGRANT_HOME is set
echo $VAGRANT_HOME

# Should output: /mnt/vms/vagrant-boxes
# If empty, reload your shell or set it manually:
export VAGRANT_HOME=/mnt/vms/vagrant-boxes
```

### VirtualBox Shows "Inaccessible" VMs

This happens if you move VMs after creating them. To fix:

```bash
# Set the machine folder
VBoxManage setproperty machinefolder /mnt/vms/virtualbox-vms

# Re-register VMs if needed
VBoxManage registervm /mnt/vms/virtualbox-vms/sccm-lab-dc01/sccm-lab-dc01.vbox
```

---

## For More Details

See the comprehensive guide: [docs/storage-configuration.md](./storage-configuration.md)

---

**Next Steps**: After configuring storage, proceed with [Phase 2 testing](./.claude/phase2-checklist.md) by running `vagrant up dc01`.
