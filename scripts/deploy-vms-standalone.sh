#!/usr/bin/env bash
# ==============================================================================
# deploy-vms-standalone.sh
# ==============================================================================
# Deploys the SCCM lab VMs using NixVirt's virtdeclare tool directly
# This allows testing the configuration WITHOUT modifying your NixOS system
#
# Usage:
#   ./scripts/deploy-vms-standalone.sh          # Deploy everything
#   ./scripts/deploy-vms-standalone.sh --dry-run # Show what would be created
#   ./scripts/deploy-vms-standalone.sh --clean   # Remove all lab resources
#
# Prerequisites:
#   - libvirtd running: sudo systemctl start libvirtd
#   - User in libvirt group: sudo usermod -aG libvirt $USER (then logout/login)
#   - ISOs downloaded to /var/lib/libvirt/iso/
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
DRY_RUN=false
CLEAN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--clean]"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}=============================================="
echo "  SCCM Lab Standalone Deployment"
echo "=============================================="
echo -e "${NC}"

# Check prerequisites
echo "Checking prerequisites..."

# Check libvirtd
if ! systemctl is-active --quiet libvirtd 2>/dev/null; then
  echo -e "${RED}ERROR: libvirtd is not running${NC}"
  echo "Start it with: sudo systemctl start libvirtd"
  exit 1
fi
echo -e "${GREEN}✓${NC} libvirtd is running"

# Check virsh access
if ! virsh -c qemu:///system list &>/dev/null; then
  echo -e "${RED}ERROR: Cannot access libvirt${NC}"
  echo "Make sure you're in the libvirt group:"
  echo "  sudo usermod -aG libvirt $USER"
  echo "Then logout and login again."
  exit 1
fi
echo -e "${GREEN}✓${NC} libvirt access working"

# Check ISOs (only if not cleaning)
if [ "$CLEAN" = false ]; then
  if [ ! -f /var/lib/libvirt/iso/windows-server-2022.iso ]; then
    echo -e "${YELLOW}WARNING: /var/lib/libvirt/iso/windows-server-2022.iso not found${NC}"
    echo "VMs won't be able to boot without installation media."
  else
    echo -e "${GREEN}✓${NC} Windows Server ISO found"
  fi
fi

echo ""

# ==============================================================================
# CLEAN MODE: Remove all lab resources
# ==============================================================================
if [ "$CLEAN" = true ]; then
  echo -e "${YELLOW}Cleaning up lab resources...${NC}"
  echo ""

  # Stop and undefine VMs
  for vm in DC01 SCCM01 CLIENT01 CLIENT02; do
    if virsh -c qemu:///system dominfo "$vm" &>/dev/null; then
      echo "Destroying VM: $vm"
      virsh -c qemu:///system destroy "$vm" 2>/dev/null || true
      virsh -c qemu:///system undefine "$vm" --nvram 2>/dev/null || true
    fi
  done

  # Destroy and undefine networks
  for net in lab-net; do
    if virsh -c qemu:///system net-info "$net" &>/dev/null; then
      echo "Destroying network: $net"
      virsh -c qemu:///system net-destroy "$net" 2>/dev/null || true
      virsh -c qemu:///system net-undefine "$net" 2>/dev/null || true
    fi
  done

  # Destroy pool (this doesn't delete volumes by default)
  if virsh -c qemu:///system pool-info homelab &>/dev/null; then
    echo "Destroying pool: homelab"
    virsh -c qemu:///system pool-destroy homelab 2>/dev/null || true
    virsh -c qemu:///system pool-undefine homelab 2>/dev/null || true
  fi

  echo ""
  echo -e "${GREEN}Cleanup complete!${NC}"
  echo "Note: Disk images in /var/lib/libvirt/images/homelab/ were preserved."
  echo "To delete them: sudo rm -rf /var/lib/libvirt/images/homelab/"
  exit 0
fi

# ==============================================================================
# DEPLOY MODE: Create lab resources
# ==============================================================================

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
  echo ""
fi

# Function to run virsh commands (with dry-run support)
run_virsh() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] virsh $*"
  else
    virsh -c qemu:///system "$@"
  fi
}

# ==============================================================================
# 1. CREATE NETWORKS
# ==============================================================================
echo -e "${GREEN}Step 1: Creating networks...${NC}"

# Generate lab-net XML
cat > /tmp/lab-net.xml << 'EOF'
<network>
  <name>lab-net</name>
  <uuid>0355c7ff-0c40-4a7a-8c0d-1f7564af25ca</uuid>
  <forward mode='nat'/>
  <bridge name='virbr56'/>
  <ip address='192.168.56.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.56.100' end='192.168.56.200'/>
    </dhcp>
  </ip>
</network>
EOF

# Define and start lab-net
if ! virsh -c qemu:///system net-info lab-net &>/dev/null; then
  echo "  Creating lab-net (192.168.56.0/24)..."
  run_virsh net-define /tmp/lab-net.xml
  run_virsh net-autostart lab-net
  run_virsh net-start lab-net
else
  echo "  lab-net already exists, skipping..."
fi

# Default network should already exist on most libvirt installations
if ! virsh -c qemu:///system net-info default &>/dev/null; then
  echo "  WARNING: default network doesn't exist. Creating it..."
  run_virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
  run_virsh net-autostart default
  run_virsh net-start default
fi

echo ""

# ==============================================================================
# 2. CREATE STORAGE POOL AND VOLUMES
# ==============================================================================
echo -e "${GREEN}Step 2: Creating storage pool and volumes...${NC}"

# Create pool directory
if [ "$DRY_RUN" = false ]; then
  sudo mkdir -p /var/lib/libvirt/images/homelab
fi

# Generate pool XML
cat > /tmp/homelab-pool.xml << 'EOF'
<pool type='dir'>
  <name>homelab</name>
  <uuid>31c47f9a-9ee8-4fd2-9f83-25733e81b978</uuid>
  <target>
    <path>/var/lib/libvirt/images/homelab</path>
  </target>
</pool>
EOF

# Define and start pool
if ! virsh -c qemu:///system pool-info homelab &>/dev/null; then
  echo "  Creating homelab storage pool..."
  run_virsh pool-define /tmp/homelab-pool.xml
  run_virsh pool-autostart homelab
  run_virsh pool-start homelab
else
  echo "  homelab pool already exists, ensuring it's started..."
  run_virsh pool-start homelab 2>/dev/null || true
fi

# Create volumes
declare -A VOLUMES=(
  ["dc01.qcow2"]="60G"
  ["sccm01.qcow2"]="100G"
  ["client01.qcow2"]="60G"
  ["client02.qcow2"]="60G"
)

for vol in "${!VOLUMES[@]}"; do
  if ! virsh -c qemu:///system vol-info "homelab/$vol" &>/dev/null; then
    echo "  Creating volume: $vol (${VOLUMES[$vol]})..."
    if [ "$DRY_RUN" = false ]; then
      run_virsh vol-create-as homelab "$vol" "${VOLUMES[$vol]}" --format qcow2
    else
      echo "  [DRY RUN] Would create: $vol (${VOLUMES[$vol]})"
    fi
  else
    echo "  Volume $vol already exists, skipping..."
  fi
done

echo ""

# ==============================================================================
# 3. CREATE VMS (using virt-install)
# ==============================================================================
echo -e "${GREEN}Step 3: Creating VMs...${NC}"

# Ensure NVRAM directory exists
if [ "$DRY_RUN" = false ]; then
  sudo mkdir -p /var/lib/libvirt/qemu/nvram
fi

# Helper function to create a VM
create_vm() {
  local name=$1
  local uuid=$2
  local memory=$3
  local disk=$4
  local iso=$5

  if virsh -c qemu:///system dominfo "$name" &>/dev/null; then
    echo "  VM $name already exists, skipping..."
    return
  fi

  echo "  Creating VM: $name (${memory}MB RAM)..."

  if [ "$DRY_RUN" = false ]; then
    virt-install \
      --connect qemu:///system \
      --name "$name" \
      --uuid "$uuid" \
      --memory "$memory" \
      --vcpus 2 \
      --disk vol=homelab/"$disk",bus=sata \
      --cdrom "$iso" \
      --network network=lab-net,model=e1000e \
      --network network=default,model=e1000e \
      --graphics spice \
      --video qxl \
      --os-variant win2k22 \
      --boot uefi \
      --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
      --noautoconsole \
      --print-xml > "/tmp/${name}.xml"

    virsh -c qemu:///system define "/tmp/${name}.xml"
  else
    echo "  [DRY RUN] Would create VM: $name"
  fi
}

# Create VMs
create_vm "DC01" "4c82c973-7299-468e-bf15-d442ee681475" 2048 "dc01.qcow2" "/var/lib/libvirt/iso/windows-server-2022.iso"
create_vm "SCCM01" "880e7366-fada-4550-9dc2-dec9daa7fb5c" 4096 "sccm01.qcow2" "/var/lib/libvirt/iso/windows-server-2022.iso"
create_vm "CLIENT01" "0f432a26-5296-4201-9b2f-e3e5c39b03bb" 2048 "client01.qcow2" "/var/lib/libvirt/iso/windows-11.iso"
create_vm "CLIENT02" "59693b4a-35bf-4587-ba07-6c960182b0ae" 2048 "client02.qcow2" "/var/lib/libvirt/iso/windows-11.iso"

echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "${GREEN}=============================================="
echo "  Deployment Complete!"
echo "=============================================="
echo -e "${NC}"

if [ "$DRY_RUN" = false ]; then
  echo "Resources created:"
  echo ""
  echo "Networks:"
  virsh -c qemu:///system net-list
  echo ""
  echo "Storage pools:"
  virsh -c qemu:///system pool-list
  echo ""
  echo "Volumes:"
  virsh -c qemu:///system vol-list homelab
  echo ""
  echo "Virtual machines:"
  virsh -c qemu:///system list --all
  echo ""
  echo "Next steps:"
  echo "  1. Start a VM: virsh -c qemu:///system start DC01"
  echo "  2. Open virt-manager: virt-manager"
  echo "  3. Install Windows on each VM"
  echo "  4. Run PowerShell automation scripts"
  echo ""
  echo "To clean up everything: $0 --clean"
else
  echo "This was a dry run. No changes were made."
  echo "Run without --dry-run to actually create resources."
fi

echo ""
