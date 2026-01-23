# Storage Configuration Guide

This guide explains how to configure storage locations for Vagrant boxes and VirtualBox VMs to use a custom directory like `/mnt/vms`.

## Overview

By default, Vagrant and VirtualBox store files in these locations:

| Component | Default Location | Typical Size |
|-----------|-----------------|--------------|
| **Vagrant boxes** (base images) | `~/.vagrant.d/boxes/` | 15-20GB |
| **VM disk files** (per-VM) | `~/VirtualBox VMs/` | 60-100GB per VM |

For this lab, we'll configure everything to use `/mnt/vms/`.

---

## Step 1: Create Storage Directory

```bash
# Create the base directory
sudo mkdir -p /mnt/vms

# Set ownership to your user
sudo chown -R $USER:$USER /mnt/vms

# Create subdirectories for organization
mkdir -p /mnt/vms/vagrant-boxes      # Vagrant box cache
mkdir -p /mnt/vms/virtualbox-vms     # VirtualBox VM disks
```

---

## Step 2: Configure Vagrant Box Storage

Vagrant uses the `VAGRANT_HOME` environment variable to determine where to store downloaded boxes.

### Option A: Set Environment Variable (Temporary)

```bash
export VAGRANT_HOME=/mnt/vms/vagrant-boxes
```

This only lasts for your current shell session.

### Option B: Set Environment Variable (Permanent - Recommended)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
# Vagrant configuration
export VAGRANT_HOME=/mnt/vms/vagrant-boxes
```

Then reload your shell:

```bash
source ~/.bashrc  # or ~/.zshrc
```

### Option C: Use Nix Flake shellHook (Project-Specific)

The project's flake can automatically set this when you run `nix develop`. This is ideal because it's project-specific and doesn't affect your global environment.

We'll update the `flake.nix` to include this automatically.

---

## Step 3: Configure VirtualBox VM Storage

VirtualBox stores VM disk files separately from Vagrant boxes. There are two ways to configure this:

### Option A: VirtualBox Global Setting (Affects All VMs)

Change the default VM folder in VirtualBox:

```bash
VBoxManage setproperty machinefolder /mnt/vms/virtualbox-vms
```

Verify the change:

```bash
VBoxManage list systemproperties | grep "Default machine folder"
```

Expected output:
```
Default machine folder: /mnt/vms/virtualbox-vms
```

### Option B: Per-VM Configuration in Vagrantfile (More Flexible)

This is already handled in our Vagrantfile through the VirtualBox provider configuration. The VMs will be created in the default machine folder you set above.

---

## Step 4: Verify Configuration

```bash
# Check Vagrant home
echo $VAGRANT_HOME
# Expected: /mnt/vms/vagrant-boxes

# Check VirtualBox machine folder
VBoxManage list systemproperties | grep "Default machine folder"
# Expected: Default machine folder: /mnt/vms/virtualbox-vms

# Verify directories exist and are writable
ls -la /mnt/vms/
```

---

## Step 5: First Vagrant Run

When you run `vagrant up` for the first time:

1. Vagrant will download boxes to `/mnt/vms/vagrant-boxes/`
2. VirtualBox will create VMs in `/mnt/vms/virtualbox-vms/`

You can monitor disk usage:

```bash
# Watch disk usage in real-time
watch -n 5 du -sh /mnt/vms/*

# Or use a more detailed view
du -h --max-depth=1 /mnt/vms/
```

---

## Expected Disk Usage

After complete setup, expect:

```
/mnt/vms/
├── vagrant-boxes/           # ~15-20GB
│   ├── gusztavvargadr-VAGRANTSLASH-windows-server-2022-standard/
│   └── gusztavvargadr-VAGRANTSLASH-windows-11/
└── virtualbox-vms/          # ~280GB for 3 VMs
    ├── sccm-lab-dc01/       # ~60GB
    ├── sccm-lab-sccm01/     # ~100GB
    └── sccm-lab-client01/   # ~60GB
```

**Total**: ~300GB (with 1 client; add ~60GB per additional client)

---

## Migrating Existing VMs (Optional)

If you already have Vagrant boxes or VMs in the default locations, you can move them:

### Move Vagrant Boxes

```bash
# If you have existing boxes in ~/.vagrant.d/boxes/
mv ~/.vagrant.d/boxes/* /mnt/vms/vagrant-boxes/

# Set the environment variable
export VAGRANT_HOME=/mnt/vms/vagrant-boxes
```

### Move VirtualBox VMs

```bash
# If you have existing VMs in ~/VirtualBox VMs/
# 1. Power off all VMs first
vagrant halt

# 2. Move VM folders
mv ~/VirtualBox\ VMs/* /mnt/vms/virtualbox-vms/

# 3. Update VirtualBox registry
VBoxManage setproperty machinefolder /mnt/vms/virtualbox-vms

# 4. Re-register VMs (if needed)
# List existing VMs
VBoxManage list vms
```

---

## NixOS-Specific Configuration

If you're on NixOS, you can set these environment variables system-wide:

Edit `/etc/nixos/configuration.nix`:

```nix
{
  # Set Vagrant home for all users
  environment.variables = {
    VAGRANT_HOME = "/mnt/vms/vagrant-boxes";
  };

  # Ensure /mnt/vms is created on boot
  systemd.tmpfiles.rules = [
    "d /mnt/vms 0755 yourusername users -"
    "d /mnt/vms/vagrant-boxes 0755 yourusername users -"
    "d /mnt/vms/virtualbox-vms 0755 yourusername users -"
  ];

  # VirtualBox configuration
  virtualisation.virtualbox.host.enable = true;
  users.users.yourusername.extraGroups = [ "vboxusers" ];
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

---

## Cleaning Up Old Locations (After Migration)

Once you've verified everything works in `/mnt/vms/`:

```bash
# Remove old Vagrant boxes (CAUTION: only if you've confirmed the new location works!)
rm -rf ~/.vagrant.d/boxes/*

# Remove old VirtualBox VMs (CAUTION: only if you've confirmed migration worked!)
rm -rf ~/VirtualBox\ VMs/*
```

---

## Troubleshooting

### Vagrant can't find boxes

**Symptom**: `vagrant up` says "Box not found"

**Solution**:
```bash
# Verify VAGRANT_HOME is set
echo $VAGRANT_HOME

# List boxes in new location
ls -la $VAGRANT_HOME/boxes/

# If empty, boxes will download automatically on next `vagrant up`
```

### VirtualBox can't find VM files

**Symptom**: VirtualBox GUI shows VMs as "inaccessible"

**Solution**:
```bash
# Check machine folder setting
VBoxManage list systemproperties | grep "Default machine folder"

# Re-register VMs if needed
VBoxManage registervm /mnt/vms/virtualbox-vms/sccm-lab-dc01/sccm-lab-dc01.vbox
```

### Permission denied errors

**Symptom**: Can't write to `/mnt/vms/`

**Solution**:
```bash
# Ensure ownership is correct
sudo chown -R $USER:$USER /mnt/vms

# Ensure directories are writable
chmod -R u+w /mnt/vms
```

### Running out of space

**Symptom**: Disk full errors during box download or VM creation

**Solution**:
```bash
# Check available space
df -h /mnt/vms

# Clean up old/unused boxes
vagrant box prune

# Remove snapshots you don't need
vagrant snapshot list
vagrant snapshot delete <vm-name> <snapshot-name>
```

---

## Summary Checklist

- [ ] Created `/mnt/vms/` directory structure
- [ ] Set ownership to your user
- [ ] Configured `VAGRANT_HOME=/mnt/vms/vagrant-boxes`
- [ ] Configured VirtualBox default machine folder
- [ ] Verified settings with commands above
- [ ] Tested with `vagrant up dc01`

---

**Next Steps**: Return to [Phase 2 checklist](./.claude/phase2-checklist.md) and run `vagrant up dc01` to begin VM provisioning.
