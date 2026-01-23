#!/usr/bin/env bash
#
# Storage Configuration Script for Homelab SCCM
#
# This script helps configure custom storage locations for Vagrant boxes
# and VirtualBox VMs. By default, these are stored in your home directory
# which may have limited space.
#
# Usage:
#   ./scripts/configure-storage.sh /mnt/vms
#   ./scripts/configure-storage.sh /path/to/storage
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if VirtualBox is installed
if ! command -v VBoxManage &> /dev/null; then
    print_error "VirtualBox is not installed!"
    echo "Please install VirtualBox first. See docs/nix-setup.md for instructions."
    exit 1
fi

# Parse command line arguments
if [ $# -eq 0 ]; then
    print_error "No storage path provided!"
    echo ""
    echo "Usage: $0 <storage-path>"
    echo ""
    echo "Example:"
    echo "  $0 /mnt/vms"
    echo ""
    exit 1
fi

STORAGE_PATH="$1"

echo "=============================================="
echo "  Homelab SCCM Storage Configuration"
echo "=============================================="
echo ""

# Step 1: Create directory structure
print_info "Creating directory structure at: $STORAGE_PATH"

mkdir -p "$STORAGE_PATH/vagrant-boxes" 2>/dev/null || {
    print_error "Failed to create $STORAGE_PATH/vagrant-boxes"
    echo "You may need to run: sudo mkdir -p $STORAGE_PATH && sudo chown -R $USER:$USER $STORAGE_PATH"
    exit 1
}

mkdir -p "$STORAGE_PATH/virtualbox-vms"
print_success "Created directories"

# Step 2: Set ownership and permissions
print_info "Setting ownership and permissions for $STORAGE_PATH"

# Check if path exists first
if [ ! -e "$STORAGE_PATH" ]; then
    print_error "Path does not exist: $STORAGE_PATH"
    echo "This should not happen - directory creation failed silently"
    exit 1
fi

# Check if we can write to the directory
if [ -w "$STORAGE_PATH" ]; then
    # We have write permission, ensure subdirectories are also writable
    if chmod -R u+w "$STORAGE_PATH" 2>/dev/null; then
        print_success "Permissions configured (user writable)"
    else
        print_warning "chmod command failed - permissions may be restrictive"
        echo "Try: sudo chmod -R u+w $STORAGE_PATH"
    fi
else
    print_warning "No write permission for $STORAGE_PATH"
    echo "You need to set ownership/permissions. Run:"
    echo "  sudo chown -R $USER:$USER $STORAGE_PATH"
    echo "  sudo chmod -R u+w $STORAGE_PATH"
    echo ""
    read -p "Continue anyway? The script may fail later. (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
fi

# Step 3: Configure VirtualBox default machine folder
print_info "Configuring VirtualBox default machine folder"
VBoxManage setproperty machinefolder "$STORAGE_PATH/virtualbox-vms"

CURRENT_FOLDER=$(VBoxManage list systemproperties | grep "Default machine folder" | cut -d: -f2 | xargs)
print_success "VirtualBox machine folder: $CURRENT_FOLDER"

# Step 4: Configure shell environment for Vagrant
print_info "Configuring Vagrant home directory"

SHELL_RC=""
if [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.profile"
fi

VAGRANT_EXPORT="export VAGRANT_HOME=\"$STORAGE_PATH/vagrant-boxes\""

# Check if already configured
if grep -q "VAGRANT_HOME" "$SHELL_RC" 2>/dev/null; then
    print_warning "VAGRANT_HOME already set in $SHELL_RC"
    echo "Current setting:"
    grep "VAGRANT_HOME" "$SHELL_RC"
    echo ""
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove old lines and add new one
        sed -i '/VAGRANT_HOME/d' "$SHELL_RC"
        echo "" >> "$SHELL_RC"
        echo "# Homelab SCCM - Vagrant storage configuration" >> "$SHELL_RC"
        echo "$VAGRANT_EXPORT" >> "$SHELL_RC"
        print_success "Updated $SHELL_RC"
    fi
else
    echo "" >> "$SHELL_RC"
    echo "# Homelab SCCM - Vagrant storage configuration" >> "$SHELL_RC"
    echo "$VAGRANT_EXPORT" >> "$SHELL_RC"
    print_success "Added VAGRANT_HOME to $SHELL_RC"
fi

# Step 5: Set for current session
export VAGRANT_HOME="$STORAGE_PATH/vagrant-boxes"
print_success "Set VAGRANT_HOME for current session"

# Step 6: Verify directories are writable
print_info "Verifying directory permissions"

VERIFICATION_FAILED=false

# Test vagrant-boxes directory
if [ -w "$STORAGE_PATH/vagrant-boxes" ]; then
    # Try to create a test file
    if touch "$STORAGE_PATH/vagrant-boxes/.test" 2>/dev/null; then
        rm -f "$STORAGE_PATH/vagrant-boxes/.test"
        print_success "Vagrant boxes directory is writable"
    else
        print_error "Cannot write to $STORAGE_PATH/vagrant-boxes"
        VERIFICATION_FAILED=true
    fi
else
    print_error "No write permission for $STORAGE_PATH/vagrant-boxes"
    VERIFICATION_FAILED=true
fi

# Test virtualbox-vms directory
if [ -w "$STORAGE_PATH/virtualbox-vms" ]; then
    if touch "$STORAGE_PATH/virtualbox-vms/.test" 2>/dev/null; then
        rm -f "$STORAGE_PATH/virtualbox-vms/.test"
        print_success "VirtualBox VMs directory is writable"
    else
        print_error "Cannot write to $STORAGE_PATH/virtualbox-vms"
        VERIFICATION_FAILED=true
    fi
else
    print_error "No write permission for $STORAGE_PATH/virtualbox-vms"
    VERIFICATION_FAILED=true
fi

if [ "$VERIFICATION_FAILED" = true ]; then
    echo ""
    print_error "Permission verification failed!"
    echo "Please fix permissions before proceeding:"
    echo "  sudo chown -R $USER:$USER $STORAGE_PATH"
    echo "  sudo chmod -R u+w $STORAGE_PATH"
    echo ""
    exit 1
fi

# Step 7: Summary
echo ""
echo "=============================================="
echo "  Configuration Complete!"
echo "=============================================="
echo ""
echo "Storage locations:"
echo "  - Vagrant boxes: $STORAGE_PATH/vagrant-boxes"
echo "  - VirtualBox VMs: $STORAGE_PATH/virtualbox-vms"
echo ""
echo "Expected disk usage:"
echo "  - Vagrant boxes: ~15-20GB"
echo "  - VirtualBox VMs: ~60-100GB per VM"
echo "  - Total (3 VMs): ~300GB"
echo ""
echo "Next steps:"
echo "  1. Reload your shell: source $SHELL_RC"
echo "  2. Or restart your terminal"
echo "  3. Verify with: echo \$VAGRANT_HOME"
echo "  4. Start VMs: cd vagrant && vagrant up dc01"
echo ""
echo "To revert to default locations, run:"
echo "  VBoxManage setproperty machinefolder default"
echo "  unset VAGRANT_HOME"
echo "  (and remove the line from $SHELL_RC)"
echo ""
echo "=============================================="

# Display current disk usage
if [ -d "$STORAGE_PATH" ]; then
    echo ""
    print_info "Current disk usage:"
    df -h "$STORAGE_PATH" | tail -n 1
    echo ""
fi
