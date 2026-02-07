#!/usr/bin/env bash
#
# deploy-dc.sh - Deploy and configure the Domain Controller (DC01)
#
# This script orchestrates the complete DC01 configuration from a Linux host.
# It uses Vagrant's WinRM communicator to execute PowerShell scripts on DC01.
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Uploads PowerShell scripts to DC01
# 2. Installs AD DS role
# 3. Promotes DC01 to domain controller (creates lab.local)
# 4. Waits for reboot
# 5. Configures DNS (reverse zones, forwarders)
# 6. Configures DHCP (scope, options)
# 7. Creates OUs (Servers, Workstations, etc.)
# 8. Creates service accounts (SQL_Service, SCCM_*, etc.)
#
# USAGE:
#   ./deploy-dc.sh              # Interactive mode
#   ./deploy-dc.sh --force      # Non-interactive mode (uses defaults)
#   ./deploy-dc.sh --skip-upload # Skip script upload (if already done)
#
# PREREQUISITES:
# - VMs must be running (vagrant up dc01)
# - Vagrant and VirtualBox installed
# - Running from the vagrant directory or specifying VAGRANT_DIR
#
# BASH CONCEPTS EXPLAINED:
# ------------------------
# set -e          : Exit immediately if a command fails
# set -u          : Treat unset variables as an error
# set -o pipefail : Pipeline fails if any command fails
# $?              : Exit code of the last command
# $0              : Name of the script
# $1, $2, ...     : Positional arguments
# ${VAR:-default} : Use 'default' if VAR is unset
# "$(command)"    : Command substitution (capture output)
# <<< "string"    : Here-string (pass string as stdin)

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project root (two levels up from orchestration/)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Vagrant directory
VAGRANT_DIR="${PROJECT_ROOT}/vagrant"

# Scripts directory to upload
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# Target directory on Windows VMs
WIN_SCRIPTS_DIR="C:\\Lab\\scripts"

# Default settings
FORCE_MODE=false
SKIP_UPLOAD=false

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================

# ANSI color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Run a Vagrant WinRM command on a VM
# Usage: vagrant_winrm <vm_name> <powershell_command>
vagrant_winrm() {
    local vm_name="$1"
    local command="$2"

    # Change to Vagrant directory and run command
    (cd "$VAGRANT_DIR" && vagrant winrm "$vm_name" -c "$command")
}

# Run a PowerShell script file on a VM
# Usage: run_script <vm_name> <script_path_on_vm> [additional_args]
run_script() {
    local vm_name="$1"
    local script_path="$2"
    local args="${3:-}"

    log_info "Running $script_path on $vm_name..."

    local ps_command="powershell -ExecutionPolicy Bypass -File '${WIN_SCRIPTS_DIR}\\${script_path}'"
    if [[ -n "$args" ]]; then
        ps_command="$ps_command $args"
    fi

    vagrant_winrm "$vm_name" "$ps_command"
}

# Upload scripts to a VM
# Usage: upload_scripts <vm_name>
upload_scripts() {
    local vm_name="$1"

    log_info "Uploading scripts to $vm_name..."

    # Create target directory
    vagrant_winrm "$vm_name" "New-Item -ItemType Directory -Path 'C:\\Lab\\scripts' -Force | Out-Null"

    # Upload scripts directory
    # Vagrant upload syntax: vagrant upload <local_path> <remote_path> <vm_name>
    (cd "$VAGRANT_DIR" && vagrant upload "$SCRIPTS_DIR" "C:/Lab/" "$vm_name")

    log_success "Scripts uploaded to $vm_name"
}

# Wait for a VM to come back after reboot
# Usage: wait_for_reboot <vm_name> <timeout_seconds>
wait_for_reboot() {
    local vm_name="$1"
    local timeout="${2:-300}"
    local elapsed=0
    local interval=10

    log_info "Waiting for $vm_name to reboot (timeout: ${timeout}s)..."

    # First, wait a bit for the reboot to start
    sleep 30
    elapsed=30

    # Then poll until WinRM responds
    while [[ $elapsed -lt $timeout ]]; do
        if vagrant_winrm "$vm_name" 'Write-Host "OK"' &>/dev/null; then
            log_success "$vm_name is back online!"
            return 0
        fi

        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    log_error "$vm_name did not come back within ${timeout}s!"
    return 1
}

# Check if a VM is running
# Usage: check_vm_running <vm_name>
check_vm_running() {
    local vm_name="$1"

    local status
    status=$(cd "$VAGRANT_DIR" && vagrant status "$vm_name" --machine-readable | grep ",state," | cut -d',' -f4)

    if [[ "$status" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_MODE=true
                shift
                ;;
            --skip-upload)
                SKIP_UPLOAD=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force, -f      Non-interactive mode (use defaults)"
                echo "  --skip-upload    Skip uploading scripts (if already done)"
                echo "  --help, -h       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# MAIN DEPLOYMENT LOGIC
# =============================================================================

deploy_dc01() {
    log_section "Deploying Domain Controller (DC01)"

    # -------------------------------------------------------------------------
    # Step 0: Verify DC01 is running
    # -------------------------------------------------------------------------
    log_info "Checking if DC01 is running..."

    if ! check_vm_running "dc01"; then
        log_error "DC01 is not running!"
        log_info "Start it with: cd $VAGRANT_DIR && vagrant up dc01"
        exit 1
    fi

    log_success "DC01 is running"

    # -------------------------------------------------------------------------
    # Step 1: Upload scripts
    # -------------------------------------------------------------------------
    if [[ "$SKIP_UPLOAD" == "true" ]]; then
        log_info "Skipping script upload (--skip-upload specified)"
    else
        log_section "Uploading Scripts to DC01"
        upload_scripts "dc01"
    fi

    # -------------------------------------------------------------------------
    # Step 2: Check current state
    # -------------------------------------------------------------------------
    log_section "Checking Current State"

    log_info "Checking if DC01 is already a domain controller..."

    # Import the Validator module and check status
    local is_dc
    is_dc=$(vagrant_winrm "dc01" '
        try {
            Import-Module C:\Lab\scripts\modules\Validator.psm1 -Force
            if (Test-IsDomainController) { Write-Host "YES" } else { Write-Host "NO" }
        } catch {
            Write-Host "NO"
        }
    ' 2>/dev/null | tr -d '\r\n')

    if [[ "$is_dc" == "YES" ]]; then
        log_success "DC01 is already a domain controller!"
        log_info "Skipping AD DS installation and promotion."

        # Skip to post-promotion configuration
        configure_dns_dhcp_ous
        return 0
    fi

    log_info "DC01 is not yet a domain controller. Proceeding with setup."

    # -------------------------------------------------------------------------
    # Step 3: Configure Network Adapters (CRITICAL - Must be BEFORE DC promotion!)
    # -------------------------------------------------------------------------
    log_section "Configuring Network Adapters"

    # This step prevents the multi-homed DC issues where both NAT and Host-Only
    # adapters register in DNS, causing AD/DNS confusion.
    # See scripts/dc/Configure-NetworkAdapters.ps1 for detailed explanation.
    run_script "dc01" "dc\\Configure-NetworkAdapters.ps1" "-Force"

    log_success "Network adapters configured (NAT adapter DNS registration disabled)"

    # -------------------------------------------------------------------------
    # Step 4: Install AD DS Role
    # -------------------------------------------------------------------------
    log_section "Installing AD DS Role"

    local force_arg=""
    if [[ "$FORCE_MODE" == "true" ]]; then
        force_arg="-Force"
    fi

    run_script "dc01" "dc\\Install-ADDS.ps1" "$force_arg"

    log_success "AD DS role installation complete"

    # -------------------------------------------------------------------------
    # Step 5: Promote to Domain Controller
    # -------------------------------------------------------------------------
    log_section "Promoting to Domain Controller"

    log_warn "This will create the lab.local domain and REBOOT DC01!"

    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warn "Promotion cancelled by user."
            exit 0
        fi
    fi

    # Run promotion script (will trigger reboot)
    run_script "dc01" "dc\\Promote-DC.ps1" "-Force"

    # Wait for reboot
    wait_for_reboot "dc01" 600

    log_success "DC01 is now a domain controller!"

    # -------------------------------------------------------------------------
    # Step 6: Post-promotion configuration
    # -------------------------------------------------------------------------
    configure_dns_dhcp_ous
}

configure_dns_dhcp_ous() {
    local force_arg=""
    if [[ "$FORCE_MODE" == "true" ]]; then
        force_arg="-Force"
    fi

    # -------------------------------------------------------------------------
    # Configure DNS
    # -------------------------------------------------------------------------
    log_section "Configuring DNS"

    run_script "dc01" "dc\\Configure-DNS.ps1" "$force_arg"

    log_success "DNS configuration complete"

    # -------------------------------------------------------------------------
    # Configure DHCP
    # -------------------------------------------------------------------------
    log_section "Configuring DHCP"

    run_script "dc01" "dc\\Configure-DHCP.ps1" "$force_arg"

    log_success "DHCP configuration complete"

    # -------------------------------------------------------------------------
    # Create OUs
    # -------------------------------------------------------------------------
    log_section "Creating Organizational Units"

    run_script "dc01" "dc\\Create-OUs.ps1" "$force_arg"

    log_success "OUs created"

    # -------------------------------------------------------------------------
    # Create Service Accounts
    # -------------------------------------------------------------------------
    log_section "Creating Service Accounts"

    run_script "dc01" "dc\\Create-ServiceAccounts.ps1" "$force_arg"

    log_success "Service accounts created"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_section "SCCM Lab - DC01 Deployment"

    log_info "Script Directory: $SCRIPT_DIR"
    log_info "Project Root: $PROJECT_ROOT"
    log_info "Vagrant Directory: $VAGRANT_DIR"
    log_info "Force Mode: $FORCE_MODE"
    log_info "Skip Upload: $SKIP_UPLOAD"

    # Parse command line arguments
    parse_args "$@"

    # Verify we're in the right place
    if [[ ! -f "$VAGRANT_DIR/Vagrantfile" ]]; then
        log_error "Cannot find Vagrantfile at $VAGRANT_DIR"
        log_error "Are you running from the correct directory?"
        exit 1
    fi

    # Run deployment
    deploy_dc01

    # Summary
    log_section "DC01 Deployment Complete!"

    log_success "Domain Controller Configuration Summary:"
    echo "  - Domain: lab.local"
    echo "  - DNS: Configured with forwarders"
    echo "  - DHCP: Scope 192.168.56.100-200"
    echo "  - OUs: Servers, Workstations, Lab Users, Service Accounts"
    echo "  - Service Accounts: SQL_Service, SCCM_NAA, SCCM_ClientPush, SCCM_JoinDomain"
    echo ""
    log_info "Next Steps:"
    echo "  1. On SCCM01: Run ./deploy-sccm.sh (or manually run scripts)"
    echo "  2. On Clients: Run Join-LabDomain.ps1"
    echo ""
    log_info "To test the domain:"
    echo "  vagrant winrm dc01 -c 'Get-ADDomain | Select Name, Forest'"
}

# Run main with all arguments
main "$@"
