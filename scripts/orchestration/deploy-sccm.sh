#!/usr/bin/env bash
# ============================================================================
# SCCM Server Deployment Orchestration Script
# ============================================================================
#
# This script orchestrates the complete deployment of SCCM01 including:
# - DNS configuration to point to DC01
# - Domain join
# - SQL Server installation
# - SCCM prerequisite installation
# - SCCM primary site installation
# - Post-installation configuration
#
# Usage: ./deploy-sccm.sh [options]
#
# Options:
#   --sql-iso PATH      Path to SQL Server ISO (on Windows, e.g., D:\)
#   --sccm-iso PATH     Path to SCCM ISO (on Windows, e.g., E:\)
#   --adk-path PATH     Path to ADK installer (optional)
#   --winpe-path PATH   Path to WinPE addon installer (optional)
#   --skip-sql          Skip SQL Server installation (if already installed)
#   --skip-prereqs      Skip prerequisite installation
#   --skip-sccm         Skip SCCM installation (configure only)
#   --dry-run           Show what would be done without doing it
#   --help              Show this help message
#
# Prerequisites:
# - DC01 must be fully deployed and operational
# - AD schema should be extended (run Extend-ADSchema.ps1 on DC01 first)
# - VMs must be running and accessible via Vagrant
#
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
SQL_ISO_PATH=""
SCCM_ISO_PATH=""
ADK_PATH=""
WINPE_PATH=""
SKIP_SQL=false
SKIP_PREREQS=false
SKIP_SCCM=false
DRY_RUN=false

# Lab configuration (should match DC01 setup)
DOMAIN_NAME="lab.local"
DOMAIN_NETBIOS="LAB"
DC_IP="192.168.56.10"
SCCM_IP="192.168.56.11"
SITE_CODE="PS1"
SITE_NAME="Primary Site 1"

# Service account passwords (in production, use secure password management)
ADMIN_PASSWORD='P@ssw0rd123!'
SQL_SERVICE_PASSWORD='P@ssw0rd123!'
NAA_PASSWORD='P@ssw0rd123!'

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

# Execute PowerShell on SCCM01 via Vagrant WinRM
run_ps() {
    local script="$1"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would execute on SCCM01:"
        echo "$script" | head -5
        echo "..."
        return 0
    fi

    cd "$PROJECT_ROOT/vagrant"
    vagrant winrm sccm01 -c "$script"
}

# Upload a file to SCCM01
upload_file() {
    local local_path="$1"
    local remote_path="$2"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would upload: $local_path -> $remote_path"
        return 0
    fi

    cd "$PROJECT_ROOT/vagrant"
    vagrant upload "$local_path" "$remote_path" sccm01
}

# Wait for SCCM01 to be accessible after reboot
wait_for_vm() {
    log_info "Waiting for SCCM01 to become accessible..."

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would wait for VM"
        return 0
    fi

    local max_wait=600  # 10 minutes
    local waited=0

    cd "$PROJECT_ROOT/vagrant"

    while [ $waited -lt $max_wait ]; do
        if vagrant winrm sccm01 -c 'Write-Host "OK"' &>/dev/null; then
            log_success "SCCM01 is accessible"
            return 0
        fi
        sleep 10
        waited=$((waited + 10))
        echo -n "."
    done

    log_error "Timeout waiting for SCCM01"
    return 1
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --sql-iso)
            SQL_ISO_PATH="$2"
            shift 2
            ;;
        --sccm-iso)
            SCCM_ISO_PATH="$2"
            shift 2
            ;;
        --adk-path)
            ADK_PATH="$2"
            shift 2
            ;;
        --winpe-path)
            WINPE_PATH="$2"
            shift 2
            ;;
        --skip-sql)
            SKIP_SQL=true
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --skip-sccm)
            SKIP_SCCM=true
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
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# ============================================================================
# VALIDATION
# ============================================================================

log_section "Validating Configuration"

# Check for required ISO paths if not skipping
if [ "$SKIP_SQL" = false ] && [ -z "$SQL_ISO_PATH" ]; then
    log_warn "SQL Server ISO path not provided."
    log_info "Use --sql-iso PATH or --skip-sql if already installed"
fi

if [ "$SKIP_SCCM" = false ] && [ -z "$SCCM_ISO_PATH" ]; then
    log_warn "SCCM ISO path not provided."
    log_info "Use --sccm-iso PATH or --skip-sccm to skip installation"
fi

# Verify project structure
if [ ! -d "$PROJECT_ROOT/scripts" ]; then
    log_error "Scripts directory not found. Run from project root."
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/vagrant/Vagrantfile" ]; then
    log_error "Vagrantfile not found. Run from project root."
    exit 1
fi

log_success "Configuration validated"

# ============================================================================
# UPLOAD SCRIPTS
# ============================================================================

log_section "Uploading Scripts to SCCM01"

# Create directories on SCCM01
log_info "Creating script directories..."
run_ps 'New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\modules" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\common" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\sql" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\Scripts\sccm" -ItemType Directory -Force | Out-Null
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

# Upload SQL scripts
log_info "Uploading SQL scripts..."
upload_file "$PROJECT_ROOT/scripts/sql/Install-SQLServer.ps1" "C:\\Scripts\\sql\\Install-SQLServer.ps1"

# Upload SCCM scripts
log_info "Uploading SCCM scripts..."
upload_file "$PROJECT_ROOT/scripts/sccm/Install-Prerequisites.ps1" "C:\\Scripts\\sccm\\Install-Prerequisites.ps1"
upload_file "$PROJECT_ROOT/scripts/sccm/Install-SCCM.ps1" "C:\\Scripts\\sccm\\Install-SCCM.ps1"
upload_file "$PROJECT_ROOT/scripts/sccm/Configure-SCCM.ps1" "C:\\Scripts\\sccm\\Configure-SCCM.ps1"

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

log_section "Phase 2: Join Domain"

# Check if already domain-joined
DOMAIN_STATUS=$(run_ps '(Get-WmiObject Win32_ComputerSystem).Domain' 2>/dev/null || echo "WORKGROUP")

if [[ "$DOMAIN_STATUS" == *"$DOMAIN_NAME"* ]]; then
    log_info "SCCM01 is already joined to $DOMAIN_NAME"
else
    log_info "Joining SCCM01 to $DOMAIN_NAME domain..."

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

# ============================================================================
# PHASE 3: INSTALL SQL SERVER
# ============================================================================

if [ "$SKIP_SQL" = false ]; then
    log_section "Phase 3: Install SQL Server"

    if [ -n "$SQL_ISO_PATH" ]; then
        log_info "Installing SQL Server from $SQL_ISO_PATH..."

        # Create secure string for password
        run_ps "\$securePassword = ConvertTo-SecureString '$SQL_SERVICE_PASSWORD' -AsPlainText -Force
Set-Location C:\\Scripts\\sql
.\\Install-SQLServer.ps1 -SQLISOPath '$SQL_ISO_PATH' -SQLServicePassword \$securePassword -SQLServiceAccount '$DOMAIN_NETBIOS\\SQL_Service'"

        log_success "SQL Server installation complete"
    else
        log_warn "SQL Server ISO path not provided - skipping installation"
        log_info "Install SQL Server manually or provide --sql-iso PATH"
    fi
else
    log_info "Skipping SQL Server installation (--skip-sql specified)"
fi

# ============================================================================
# PHASE 4: INSTALL PREREQUISITES
# ============================================================================

if [ "$SKIP_PREREQS" = false ]; then
    log_section "Phase 4: Install SCCM Prerequisites"

    log_info "Installing Windows features and prerequisites..."

    ADK_PARAM=""
    WINPE_PARAM=""

    if [ -n "$ADK_PATH" ]; then
        ADK_PARAM="-ADKPath '$ADK_PATH'"
    fi

    if [ -n "$WINPE_PATH" ]; then
        WINPE_PARAM="-WinPEPath '$WINPE_PATH'"
    fi

    run_ps "Set-Location C:\\Scripts\\sccm
.\\Install-Prerequisites.ps1 $ADK_PARAM $WINPE_PARAM"

    # Check if reboot is needed
    log_info "Checking if reboot is needed..."
    REBOOT_NEEDED=$(run_ps '(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name "RebootPending" -ErrorAction SilentlyContinue) -ne $null' 2>/dev/null || echo "False")

    if [[ "$REBOOT_NEEDED" == *"True"* ]]; then
        log_info "Reboot required after prerequisite installation..."
        run_ps 'Restart-Computer -Force'
        sleep 30
        wait_for_vm
    fi

    log_success "Prerequisites installed"
else
    log_info "Skipping prerequisite installation (--skip-prereqs specified)"
fi

# ============================================================================
# PHASE 5: INSTALL SCCM
# ============================================================================

if [ "$SKIP_SCCM" = false ]; then
    log_section "Phase 5: Install SCCM Primary Site"

    if [ -n "$SCCM_ISO_PATH" ]; then
        log_info "Installing SCCM from $SCCM_ISO_PATH..."
        log_warn "This will take 30-60 minutes. Please be patient."

        run_ps "Set-Location C:\\Scripts\\sccm
.\\Install-SCCM.ps1 -SCCMMediaPath '$SCCM_ISO_PATH' -SiteCode '$SITE_CODE' -SiteName '$SITE_NAME'"

        log_success "SCCM installation complete"
    else
        log_warn "SCCM ISO path not provided - skipping installation"
        log_info "Install SCCM manually or provide --sccm-iso PATH"
    fi
else
    log_info "Skipping SCCM installation (--skip-sccm specified)"
fi

# ============================================================================
# PHASE 6: CONFIGURE SCCM
# ============================================================================

log_section "Phase 6: Configure SCCM"

# Check if SCCM is installed before configuring
SCCM_INSTALLED=$(run_ps 'Test-Path "C:\Program Files\Microsoft Configuration Manager"' 2>/dev/null || echo "False")

if [[ "$SCCM_INSTALLED" == *"True"* ]]; then
    log_info "Configuring SCCM site..."

    # Create secure string for NAA password
    run_ps "\$securePassword = ConvertTo-SecureString '$NAA_PASSWORD' -AsPlainText -Force
Set-Location C:\\Scripts\\sccm
.\\Configure-SCCM.ps1 -SiteCode '$SITE_CODE' -NetworkAccessPassword \$securePassword"

    log_success "SCCM configuration complete"
else
    log_warn "SCCM is not installed - skipping configuration"
fi

# ============================================================================
# SUMMARY
# ============================================================================

log_section "SCCM01 Deployment Summary"

echo ""
echo "Deployment Status:"
echo "  DNS Configuration: Complete"
echo "  Domain Join: Complete"

if [ "$SKIP_SQL" = false ] && [ -n "$SQL_ISO_PATH" ]; then
    echo "  SQL Server: Installed"
else
    echo "  SQL Server: Skipped or manual installation required"
fi

if [ "$SKIP_PREREQS" = false ]; then
    echo "  SCCM Prerequisites: Installed"
else
    echo "  SCCM Prerequisites: Skipped"
fi

if [ "$SKIP_SCCM" = false ] && [ -n "$SCCM_ISO_PATH" ]; then
    echo "  SCCM Primary Site: Installed"
else
    echo "  SCCM Primary Site: Skipped or manual installation required"
fi

echo ""
echo "Server Information:"
echo "  Server Name: SCCM01"
echo "  Domain: $DOMAIN_NAME"
echo "  Site Code: $SITE_CODE"
echo "  Site Name: $SITE_NAME"
echo ""

if [[ "$SCCM_INSTALLED" == *"True"* ]]; then
    echo "Next Steps:"
    echo "  1. Log into SCCM01 as $DOMAIN_NETBIOS\\Administrator"
    echo "  2. Open SCCM Console (Microsoft Endpoint Configuration Manager)"
    echo "  3. Verify site status in Monitoring > Site Hierarchy"
    echo "  4. Configure Client Push Installation"
    echo "  5. Deploy SCCM client to workstations"
    echo ""
    echo "To deploy client to workstations:"
    echo "  Run: ./deploy-client.sh client01"
fi

log_success "SCCM01 deployment complete!"
