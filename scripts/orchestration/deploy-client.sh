#!/usr/bin/env bash
# ============================================================================
# Client Deployment Orchestration Script
# ============================================================================
#
# This script orchestrates the deployment of SCCM clients (CLIENT01, etc.):
# - DNS configuration to point to DC01
# - Domain join
# - SCCM client installation
#
# Usage: ./deploy-client.sh <client_name> [options]
#
# Arguments:
#   client_name         Name of the client VM (e.g., client01)
#
# Options:
#   --skip-domain       Skip domain join (if already joined)
#   --skip-client       Skip SCCM client installation
#   --dry-run           Show what would be done without doing it
#   --help              Show this help message
#
# Examples:
#   ./deploy-client.sh client01
#   ./deploy-client.sh client01 --skip-domain
#
# Prerequisites:
# - DC01 must be fully deployed and operational
# - SCCM01 must be installed and configured
# - Client VM must be running and accessible via Vagrant
#
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
CLIENT_NAME=""
SKIP_DOMAIN=false
SKIP_CLIENT=false
DRY_RUN=false

# Lab configuration
DOMAIN_NAME="lab.local"
DOMAIN_NETBIOS="LAB"
DC_IP="192.168.56.10"
SCCM_SERVER="SCCM01"
SITE_CODE="PS1"

# Service account passwords (in production, use secure password management)
ADMIN_PASSWORD='P@ssw0rd123!'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN} $1${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
}

show_help() {
    head -30 "$0" | tail -25
    exit 0
}

# Execute PowerShell on client via Vagrant WinRM
run_ps() {
    local script="$1"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute on $CLIENT_NAME:"
        echo "$script" | head -5
        echo "..."
        return 0
    fi

    cd "$PROJECT_ROOT/vagrant"
    vagrant winrm "$CLIENT_NAME" -c "$script"
}

# Upload a file to client
upload_file() {
    local local_path="$1"
    local remote_path="$2"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would upload: $local_path -> $remote_path"
        return 0
    fi

    cd "$PROJECT_ROOT/vagrant"
    vagrant upload "$local_path" "$remote_path" "$CLIENT_NAME"
}

# Wait for client to be accessible after reboot
wait_for_vm() {
    log_info "Waiting for $CLIENT_NAME to become accessible..."

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would wait for VM"
        return 0
    fi

    local max_wait=300  # 5 minutes
    local waited=0

    cd "$PROJECT_ROOT/vagrant"

    while [ $waited -lt $max_wait ]; do
        if vagrant winrm "$CLIENT_NAME" -c 'Write-Host "OK"' &>/dev/null; then
            log_success "$CLIENT_NAME is accessible"
            return 0
        fi
        sleep 10
        waited=$((waited + 10))
        echo -n "."
    done

    log_error "Timeout waiting for $CLIENT_NAME"
    return 1
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

# First positional argument is client name
if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
    CLIENT_NAME="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-domain)
            SKIP_DOMAIN=true
            shift
            ;;
        --skip-client)
            SKIP_CLIENT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            if [ -z "$CLIENT_NAME" ]; then
                CLIENT_NAME="$1"
            else
                log_error "Unknown option: $1"
                show_help
            fi
            shift
            ;;
    esac
done

# ============================================================================
# VALIDATION
# ============================================================================

if [ -z "$CLIENT_NAME" ]; then
    log_error "Client name is required."
    echo "Usage: $0 <client_name> [options]"
    echo "Example: $0 client01"
    exit 1
fi

log_section "Deploying $CLIENT_NAME"

# Verify project structure
if [ ! -d "$PROJECT_ROOT/scripts" ]; then
    log_error "Scripts directory not found. Run from project root."
    exit 1
fi

# Verify VM exists
cd "$PROJECT_ROOT/vagrant"
if ! vagrant status "$CLIENT_NAME" 2>/dev/null | grep -q "running\|poweroff\|saved"; then
    log_error "VM '$CLIENT_NAME' not found in Vagrant. Check VM name."
    exit 1
fi

log_success "Configuration validated"

# ============================================================================
# UPLOAD SCRIPTS
# ============================================================================

log_section "Uploading Scripts to $CLIENT_NAME"

# Create directories
log_info "Creating script directories..."
run_ps 'New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\modules" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\common" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\client" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Logs\Lab" -ItemType Directory -Force | Out-Null
Write-Host "Directories created"'

# Upload modules
log_info "Uploading PowerShell modules..."
upload_file "$PROJECT_ROOT/scripts/modules/Logger.psm1" "C:\\Scripts\\modules\\Logger.psm1"
upload_file "$PROJECT_ROOT/scripts/modules/Validator.psm1" "C:\\Scripts\\modules\\Validator.psm1"

# Upload common scripts
log_info "Uploading common scripts..."
upload_file "$PROJECT_ROOT/scripts/common/Set-LabDNS.ps1" "C:\\Scripts\\common\\Set-LabDNS.ps1"
upload_file "$PROJECT_ROOT/scripts/common/Join-LabDomain.ps1" "C:\\Scripts\\common\\Join-LabDomain.ps1"

# Upload client scripts
log_info "Uploading client scripts..."
upload_file "$PROJECT_ROOT/scripts/client/Install-SCCMClient.ps1" "C:\\Scripts\\client\\Install-SCCMClient.ps1"

log_success "Scripts uploaded successfully"

# ============================================================================
# PHASE 1: CONFIGURE DNS
# ============================================================================

log_section "Phase 1: Configure DNS"

log_info "Setting DNS to point to DC01 ($DC_IP)..."

run_ps 'Set-Location C:\Scripts\common
.\Set-LabDNS.ps1'

log_success "DNS configured"

# ============================================================================
# PHASE 2: JOIN DOMAIN
# ============================================================================

if [ "$SKIP_DOMAIN" = false ]; then
    log_section "Phase 2: Join Domain"

    # Check if already domain-joined
    DOMAIN_STATUS=$(run_ps '(Get-WmiObject Win32_ComputerSystem).Domain' 2>/dev/null || echo "WORKGROUP")

    if [[ "$DOMAIN_STATUS" == *"$DOMAIN_NAME"* ]]; then
        log_info "$CLIENT_NAME is already joined to $DOMAIN_NAME"
    else
        log_info "Joining $CLIENT_NAME to $DOMAIN_NAME domain..."

        # Create credential and join domain
        run_ps "\$securePassword = ConvertTo-SecureString '$ADMIN_PASSWORD' -AsPlainText -Force
\$credential = New-Object System.Management.Automation.PSCredential('$DOMAIN_NETBIOS\\Administrator', \$securePassword)
Set-Location C:\\Scripts\\common
.\\Join-LabDomain.ps1 -Credential \$credential -Restart"

        log_info "Domain join initiated, waiting for reboot..."
        sleep 30
        wait_for_vm

        log_success "Domain join complete"
    fi
else
    log_info "Skipping domain join (--skip-domain specified)"
fi

# ============================================================================
# PHASE 3: INSTALL SCCM CLIENT
# ============================================================================

if [ "$SKIP_CLIENT" = false ]; then
    log_section "Phase 3: Install SCCM Client"

    log_info "Installing SCCM client..."

    run_ps "Set-Location C:\\Scripts\\client
.\\Install-SCCMClient.ps1 -SCCMServer '$SCCM_SERVER' -SiteCode '$SITE_CODE'"

    log_success "SCCM client installation initiated"
else
    log_info "Skipping SCCM client installation (--skip-client specified)"
fi

# ============================================================================
# VERIFICATION
# ============================================================================

log_section "Verification"

# Check domain membership
log_info "Checking domain membership..."
FINAL_DOMAIN=$(run_ps '(Get-WmiObject Win32_ComputerSystem).Domain' 2>/dev/null || echo "Unknown")
echo "  Domain: $FINAL_DOMAIN"

# Check SCCM client
log_info "Checking SCCM client..."
CLIENT_STATUS=$(run_ps 'if (Get-Service CcmExec -ErrorAction SilentlyContinue) { "Running" } else { "Not Installed" }' 2>/dev/null || echo "Unknown")
echo "  SCCM Client: $CLIENT_STATUS"

# ============================================================================
# SUMMARY
# ============================================================================

log_section "Client Deployment Summary"

echo ""
echo "Deployment Status for $CLIENT_NAME:"
echo "  DNS Configuration: Complete"
echo "  Domain: $FINAL_DOMAIN"
echo "  SCCM Client: $CLIENT_STATUS"
echo ""
echo "Next Steps:"
echo "  1. Wait 5-10 minutes for client to fully register"
echo "  2. Check SCCM Console > Assets and Compliance > Devices"
echo "  3. Look for $CLIENT_NAME in the device list"
echo "  4. Right-click > Client Notification > Download Computer Policy"
echo ""

log_success "$CLIENT_NAME deployment complete!"
