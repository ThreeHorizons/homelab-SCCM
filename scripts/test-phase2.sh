#!/usr/bin/env bash
# Phase 2 Testing and Validation Script
# This script walks through each test step with explanations

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

section() {
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
}

prompt() {
    echo -e "${YELLOW}$1${NC}"
    read -p "Press Enter to continue..."
}

# ============================================================================
# TEST 1: Check Vagrant Installation and VM Status
# ============================================================================
section "TEST 1: Checking Vagrant Installation and VM Status"

info "What we're testing: Verify that Vagrant is installed and can see our VMs"
info "Why this matters: Before we can test VMs, we need to know Vagrant is working"
echo ""

info "Running: vagrant --version"
vagrant --version
success "Vagrant is installed"
echo ""

info "Running: vagrant global-status"
info "This shows all Vagrant VMs on your system, not just this project"
vagrant global-status
echo ""

cd /home/myodhes-nix/projects/homelab-SCCM/vagrant || exit 1
info "Changed to: $(pwd)"
echo ""

info "Running: vagrant status"
info "This shows VMs defined in the current Vagrantfile"
vagrant status
echo ""

prompt "Did you see the VMs listed? (dc01, sccm01, client01)"

# ============================================================================
# TEST 2: Check VirtualBox Configuration
# ============================================================================
section "TEST 2: Checking VirtualBox Host-Only Network"

info "What we're testing: Verify the host-only network is configured correctly"
info "Why this matters: VMs use this network to communicate with each other"
echo ""

info "Running: VBoxManage list hostonlyifs"
info "This lists all host-only network interfaces"
VBoxManage list hostonlyifs
echo ""

info "Expected: Should see vboxnet0 with IP 192.168.56.1"
prompt "Did you see vboxnet0 configured?"

# ============================================================================
# TEST 3: Check if DC01 is Running
# ============================================================================
section "TEST 3: Checking DC01 VM Status"

info "What we're testing: Check if DC01 VM is currently running"
info "Why this matters: We need to know if we should start it or if it's already up"
echo ""

info "Running: VBoxManage list runningvms"
VBoxManage list runningvms
echo ""

DC01_RUNNING=$(VBoxManage list runningvms | grep -c "sccm-lab-dc01" || true)

if [ "$DC01_RUNNING" -eq 0 ]; then
    warn "DC01 is not running"
    echo ""
    info "We need to start DC01 with: vagrant up dc01"
    prompt "Would you like me to show you the next steps?"
else
    success "DC01 is already running!"
fi

# ============================================================================
# TEST 4: Test Network Connectivity to DC01 (if running)
# ============================================================================
if [ "$DC01_RUNNING" -gt 0 ]; then
    section "TEST 4: Testing Network Connectivity to DC01"

    info "What we're testing: Can we reach DC01's IP address from the host?"
    info "Why this matters: Verifies network configuration is working"
    echo ""

    info "Running: ping -c 4 192.168.56.10"
    info "Explanation: -c 4 means send 4 ping packets"
    echo ""

    if ping -c 4 192.168.56.10; then
        success "DC01 is reachable via network!"
    else
        error "Cannot ping DC01 - network may not be configured yet"
        warn "This is normal if DC01 just started - Windows may still be booting"
    fi
    echo ""

    prompt "Ready to test WinRM connectivity?"
fi

# ============================================================================
# TEST 5: Test WinRM Port Connectivity
# ============================================================================
if [ "$DC01_RUNNING" -gt 0 ]; then
    section "TEST 5: Testing WinRM Port Connectivity"

    info "What we're testing: Is port 5985 (WinRM HTTP) open on DC01?"
    info "Why this matters: Vagrant uses WinRM to manage Windows VMs"
    echo ""

    info "WinRM uses these ports:"
    info "  - Port 5985: HTTP (unencrypted, used in labs)"
    info "  - Port 5986: HTTPS (encrypted, used in production)"
    echo ""

    info "Running: nc -zv 192.168.56.10 5985"
    info "Explanation: nc = netcat, -z = scan only, -v = verbose"
    echo ""

    if nc -zv 192.168.56.10 5985 2>&1 | grep -q "succeeded"; then
        success "WinRM port 5985 is open!"
    else
        error "WinRM port 5985 is not responding"
        warn "This might mean:"
        warn "  1. Windows is still booting"
        warn "  2. enable-winrm.ps1 hasn't run yet"
        warn "  3. Windows Firewall is blocking the port"
    fi
    echo ""

    prompt "Ready to test with Vagrant's built-in commands?"
fi

# ============================================================================
# TEST 6: Test Vagrant WinRM Connectivity
# ============================================================================
if [ "$DC01_RUNNING" -gt 0 ]; then
    section "TEST 6: Testing Vagrant WinRM Connectivity"

    info "What we're testing: Can Vagrant execute commands on DC01 via WinRM?"
    info "Why this matters: This is how Vagrant provisions and manages VMs"
    echo ""

    info "Running: vagrant winrm dc01 -c 'hostname'"
    info "Explanation: This executes the 'hostname' command on DC01"
    echo ""

    if timeout 30 vagrant winrm dc01 -c "hostname" 2>/dev/null; then
        success "Vagrant can execute commands via WinRM!"
    else
        error "Vagrant WinRM connection failed"
        warn "Troubleshooting steps:"
        warn "  1. Check if VM is fully booted: vagrant status dc01"
        warn "  2. Check logs: vagrant ssh dc01 (may not work yet)"
        warn "  3. Try provisioning again: vagrant provision dc01"
    fi
    echo ""

    prompt "Ready to check Windows configuration?"
fi

# ============================================================================
# TEST 7: Verify Windows Configuration via WinRM
# ============================================================================
if [ "$DC01_RUNNING" -gt 0 ]; then
    section "TEST 7: Verifying Windows Configuration"

    info "What we're testing: Did our bootstrap scripts configure Windows correctly?"
    info "Why this matters: Verifies provisioning was successful"
    echo ""

    info "Test 7a: Check computer name"
    info "Running: vagrant winrm dc01 -c 'echo \$env:COMPUTERNAME'"
    vagrant winrm dc01 -c 'echo $env:COMPUTERNAME' || warn "Could not get computer name"
    echo ""

    info "Test 7b: Check IP configuration"
    info "Running: vagrant winrm dc01 -c 'ipconfig'"
    vagrant winrm dc01 -c 'ipconfig | Select-String -Pattern "192.168"' || warn "Could not get IP config"
    echo ""

    info "Test 7c: Check WinRM service status"
    info "Running: vagrant winrm dc01 -c '(Get-Service WinRM).Status'"
    vagrant winrm dc01 -c '(Get-Service WinRM).Status' || warn "Could not check WinRM service"
    echo ""

    prompt "Tests complete for DC01. Ready to test SCCM01?"
fi

# ============================================================================
# TEST 8: Check Other VMs
# ============================================================================
section "TEST 8: Checking Other VMs (SCCM01, CLIENT01)"

info "Let's check if other VMs are running"
echo ""

SCCM01_RUNNING=$(VBoxManage list runningvms | grep -c "sccm-lab-sccm01" || true)
CLIENT01_RUNNING=$(VBoxManage list runningvms | grep -c "sccm-lab-client01" || true)

if [ "$SCCM01_RUNNING" -eq 0 ]; then
    warn "SCCM01 is not running"
    info "To start: vagrant up sccm01"
else
    success "SCCM01 is running"
    info "Test connectivity: ping -c 4 192.168.56.11"
fi
echo ""

if [ "$CLIENT01_RUNNING" -eq 0 ]; then
    warn "CLIENT01 is not running"
    info "To start: vagrant up client01"
else
    success "CLIENT01 is running"
    info "CLIENT01 uses DHCP, check IP with: vagrant winrm client01 -c 'ipconfig'"
fi

# ============================================================================
# SUMMARY
# ============================================================================
section "TEST SUMMARY"

info "Here's what we tested:"
echo "  1. ✓ Vagrant installation and VM definitions"
echo "  2. ✓ VirtualBox host-only network configuration"
echo "  3. ✓ VM running status"

if [ "$DC01_RUNNING" -gt 0 ]; then
    echo "  4. Network connectivity to DC01"
    echo "  5. WinRM port accessibility"
    echo "  6. Vagrant WinRM command execution"
    echo "  7. Windows configuration verification"
fi

echo ""
info "Next steps to complete Phase 2 testing:"
echo ""
echo "  1. If VMs aren't running, start them:"
echo "     cd /home/myodhes-nix/projects/homelab-SCCM/vagrant"
echo "     vagrant up dc01"
echo "     vagrant up sccm01"
echo "     vagrant up client01"
echo ""
echo "  2. Test inter-VM connectivity:"
echo "     vagrant winrm dc01 -c 'Test-Connection -ComputerName 192.168.56.11 -Count 2'"
echo ""
echo "  3. Create snapshots (for quick rollback):"
echo "     vagrant snapshot save dc01 base-install"
echo "     vagrant snapshot save sccm01 base-install"
echo "     vagrant snapshot save client01 base-install"
echo ""
echo "  4. Test snapshot restore:"
echo "     vagrant snapshot restore dc01 base-install"
echo ""

section "Testing Script Complete!"
info "Review the output above and address any warnings or errors"
