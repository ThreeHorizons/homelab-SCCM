# Phase 3: Automation Plan

This document outlines the strategy for automating the SCCM lab infrastructure setup, with special attention to cross-platform considerations when running automation from Linux (NixOS) to Windows VMs.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Cross-Platform Challenges](#cross-platform-challenges)
4. [Automation Strategy](#automation-strategy)
5. [Implementation Approach](#implementation-approach)
6. [Script Structure](#script-structure)
7. [Error Handling & Idempotency](#error-handling--idempotency)
8. [Testing Strategy](#testing-strategy)
9. [Caveats & Known Issues](#caveats--known-issues)

---

## Executive Summary

### Goals

1. **One-command deployment**: `./deploy-lab.sh` should configure the entire lab
2. **Cross-platform execution**: Scripts work from Linux (NixOS) and Windows hosts
3. **Idempotent operations**: Safe to re-run if something fails
4. **Educational value**: Well-documented code that explains concepts
5. **Modular design**: Reusable components for future projects

### Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **Use Vagrant WinRM** for primary orchestration | Works reliably from Linux, abstracts WinRM complexity |
| **Use native PowerShell** on Windows VMs | Full module compatibility, no cross-platform issues |
| **Bash wrapper scripts** for orchestration | Natural on Linux, can call Vagrant commands |
| **PowerShell modules** for reusable code | Organized, testable, maintainable |
| **Explicit credential passing** | Avoids double-hop issues, works in all scenarios |

---

## Architecture Overview

### Execution Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Linux Host (NixOS)                          │
│                                                                     │
│  ┌─────────────────────┐                                           │
│  │  deploy-lab.sh      │  Bash orchestration script                │
│  │  (Entry Point)      │  Handles sequencing and error recovery    │
│  └──────────┬──────────┘                                           │
│             │                                                       │
│             ▼                                                       │
│  ┌─────────────────────┐                                           │
│  │  Vagrant WinRM      │  vagrant winrm <vm> -c "script"           │
│  │  (Transport Layer)  │  Handles authentication & transport       │
│  └──────────┬──────────┘                                           │
│             │                                                       │
└─────────────┼───────────────────────────────────────────────────────┘
              │ WinRM Protocol (HTTP 5985)
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Windows VMs (VirtualBox)                       │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    PowerShell 5.1 Host                       │   │
│  │                                                              │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │   │
│  │  │ Logger.psm1  │ │WinRMHelper   │ │ Validator    │        │   │
│  │  │              │ │.psm1         │ │ .psm1        │        │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘        │   │
│  │           Reusable PowerShell Modules                        │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ dc-setup.ps1 │ sql-setup.ps1 │ sccm-*.ps1 │ etc.     │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │           Configuration Scripts (executed locally)           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Script Execution Flow

```
deploy-lab.sh
    │
    ├─► Phase 1: Copy scripts to VMs
    │       vagrant upload scripts/ DC01:C:\Lab\scripts
    │       vagrant upload scripts/ SCCM01:C:\Lab\scripts
    │
    ├─► Phase 2: Configure DC01
    │       vagrant winrm dc01 -c "C:\Lab\scripts\dc-setup.ps1 -Phase 1"
    │       (wait for reboot)
    │       vagrant winrm dc01 -c "C:\Lab\scripts\dc-setup.ps1 -Phase 2"
    │       vagrant winrm dc01 -c "C:\Lab\scripts\dc-setup.ps1 -Phase 3"
    │
    ├─► Phase 3: Configure SCCM01
    │       vagrant winrm sccm01 -c "C:\Lab\scripts\sccm-join-domain.ps1"
    │       (wait for reboot)
    │       vagrant winrm sccm01 -c "C:\Lab\scripts\sql-setup.ps1"
    │       vagrant winrm sccm01 -c "C:\Lab\scripts\sccm-prereq.ps1"
    │       vagrant winrm sccm01 -c "C:\Lab\scripts\sccm-install.ps1"
    │
    ├─► Phase 4: Configure Clients
    │       for client in CLIENT01 CLIENT02 ...
    │           vagrant winrm $client -c "C:\Lab\scripts\client-join.ps1"
    │
    └─► Phase 5: Validation
            vagrant winrm dc01 -c "C:\Lab\scripts\Validate-Lab.ps1"
```

---

## Cross-Platform Challenges

### Challenge 1: PowerShell Core Cannot Use WinRM from Linux

**The Problem**:
PowerShell Core (pwsh) on Linux does **not support WinRM-based remoting**. This means you cannot run:

```bash
# THIS DOES NOT WORK FROM LINUX!
pwsh -c "Invoke-Command -ComputerName 192.168.56.10 -ScriptBlock { Get-Process }"
```

**Why**: WinRM depends on Windows-specific libraries (WS-Management, NTLM/Kerberos authentication) that aren't available on Linux.

**Solution**: Use Vagrant as the transport layer:

```bash
# THIS WORKS FROM LINUX!
vagrant winrm dc01 -c "Get-Process"
```

Vagrant internally handles the WinRM protocol, authentication, and transport.

### Challenge 2: Double-Hop Authentication

**The Problem**:
When you connect to a Windows machine via WinRM and then try to access another resource (network share, another computer), your credentials don't follow.

```
Linux Host → DC01 (credentials work) → SCCM01 (ACCESS DENIED!)
```

**Why**: WinRM doesn't forward Kerberos tickets or NTLM credentials by default (security feature).

**Solutions**:

| Approach | Pros | Cons | Use When |
|----------|------|------|----------|
| **Explicit Credentials** | Simple, works everywhere | Credentials in scripts | Lab environments |
| **CredSSP** | Credentials forwarded | Security risk, complex setup | Controlled environments |
| **Kerberos Delegation** | Secure, no stored creds | Requires AD, complex | Production |
| **Avoid Multi-Hop** | Simplest | May require script changes | Most scenarios |

**Our Strategy**: Design scripts to avoid multi-hop. Run scripts locally on each VM.

```powershell
# BAD: Multi-hop from DC01 to SCCM01
Invoke-Command -ComputerName sccm01 -ScriptBlock { Install-Something }

# GOOD: Run directly on SCCM01
vagrant winrm sccm01 -c "Install-Something"
```

### Challenge 3: Module Availability

**The Problem**:
Many Windows PowerShell modules don't work in PowerShell Core on Linux:

| Module | Works on Linux | Notes |
|--------|----------------|-------|
| `ActiveDirectory` | No | Requires ADWS/LDAP Windows bindings |
| `DnsServer` | No | Requires Windows DNS management |
| `DhcpServer` | No | Requires RSAT on Windows |
| `SqlServer` | Partial | Some cmdlets work via SQLPS |
| `ConfigurationManager` | No | Requires Windows and SCCM console |

**Solution**: Run Windows-specific commands on Windows VMs via Vagrant:

```bash
# Wrong - trying to use ActiveDirectory module from Linux
pwsh -c "Get-ADUser -Filter *"  # FAILS

# Correct - run on DC01 where the module exists
vagrant winrm dc01 -c "Get-ADUser -Filter *"  # WORKS
```

### Challenge 4: Path and Escaping Differences

**The Problem**:
Bash and PowerShell have different escaping rules, and paths differ between Linux and Windows.

**Examples**:

```bash
# Bash variable expansion conflicts with PowerShell
vagrant winrm dc01 -c "Write-Host $env:COMPUTERNAME"
# Bash expands $env before sending! Result: "Write-Host :COMPUTERNAME"

# Fix: Escape the $ for Bash
vagrant winrm dc01 -c "Write-Host \$env:COMPUTERNAME"
# Or use single quotes (no expansion)
vagrant winrm dc01 -c 'Write-Host $env:COMPUTERNAME'

# Backslashes in Windows paths
vagrant winrm dc01 -c "Get-ChildItem C:\Windows"  # Works
vagrant winrm dc01 -c 'Get-ChildItem C:\Windows'  # Works
```

**Quoting Rules**:

| Quote Type | Bash Behavior | PowerShell Behavior |
|------------|---------------|---------------------|
| `"double"` | Expands `$variables` | Expands `$variables` |
| `'single'` | Literal string | Literal string |
| `` `backtick` `` | Command substitution | Escape character (PS) |

**Best Practice**: Use single quotes in Bash to pass commands literally to PowerShell:

```bash
# Preferred: Single quotes prevent Bash expansion
vagrant winrm dc01 -c 'Get-ADUser -Filter { Name -like "Admin*" }'

# If you need Bash variable interpolation, escape PowerShell variables
VM_NAME="dc01"
vagrant winrm "$VM_NAME" -c "Write-Host 'Configuring' ; Get-Service | Where-Object { \$_.Status -eq 'Running' }"
```

### Challenge 5: Reboot Handling

**The Problem**:
Many Windows operations require reboots (domain join, AD promotion, feature installation). Scripts must handle this gracefully.

**Solution**: Phase-based execution with reboot detection:

```bash
#!/bin/bash

# Run phase 1 (ends with reboot)
vagrant winrm dc01 -c 'C:\Lab\scripts\dc-setup.ps1 -Phase 1'

# Wait for VM to go down
echo "Waiting for DC01 to reboot..."
sleep 30

# Wait for VM to come back up
until vagrant winrm dc01 -c 'Write-Host "DC01 is back"' 2>/dev/null; do
    echo "Waiting for WinRM..."
    sleep 10
done

# Run phase 2
vagrant winrm dc01 -c 'C:\Lab\scripts\dc-setup.ps1 -Phase 2'
```

---

## Automation Strategy

### Principle 1: Scripts Run Locally on Target VMs

Instead of trying to manage VMs from a central location, copy scripts to each VM and execute them locally.

**Why**:
- Avoids double-hop authentication issues
- Full access to local modules
- Simpler error handling
- Scripts can be tested independently

**Implementation**:

```bash
# Step 1: Copy scripts to VM
vagrant upload scripts/ dc01:C:/Lab/scripts/

# Step 2: Execute script on VM
vagrant winrm dc01 -c 'powershell -ExecutionPolicy Bypass -File C:\Lab\scripts\dc-setup.ps1'
```

### Principle 2: Idempotent Operations

Scripts should be safe to run multiple times. If a step is already complete, skip it.

**Example**:

```powershell
# Check if AD DS role is already installed
$addsRole = Get-WindowsFeature -Name AD-Domain-Services

if ($addsRole.InstallState -eq 'Installed') {
    Write-Log "AD DS role already installed, skipping..."
} else {
    Write-Log "Installing AD DS role..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
}
```

### Principle 3: Phase-Based Execution

Break complex operations into phases separated by reboots or major state changes.

```powershell
param(
    [ValidateSet('All', 'InstallADDS', 'PromoteDC', 'ConfigureDNS', 'ConfigureDHCP', 'CreateOUs')]
    [string]$Phase = 'All'
)

switch ($Phase) {
    'InstallADDS' {
        # Install role, will require reboot
        Install-WindowsFeature -Name AD-Domain-Services
    }
    'PromoteDC' {
        # Promote to DC, will require reboot
        Install-ADDSForest -DomainName "lab.local" ...
    }
    'ConfigureDNS' {
        # Configure DNS after DC promotion
        Add-DnsServerPrimaryZone ...
    }
    # ... etc
    'All' {
        # Run all phases in sequence (for manual execution)
    }
}
```

### Principle 4: Explicit Dependencies

Each script clearly declares what must be true before it runs.

```powershell
# At the start of sql-setup.ps1
function Test-Prerequisites {
    # Check domain join
    if ((Get-WmiObject Win32_ComputerSystem).Domain -ne 'lab.local') {
        throw "Server must be joined to lab.local domain first!"
    }
    
    # Check DNS resolution
    if (-not (Resolve-DnsName dc01.lab.local -ErrorAction SilentlyContinue)) {
        throw "Cannot resolve DC01 - DNS configuration required!"
    }
    
    # Check .NET 3.5
    $dotnet35 = Get-WindowsFeature -Name NET-Framework-Core
    if ($dotnet35.InstallState -ne 'Installed') {
        throw ".NET Framework 3.5 required for SQL Server!"
    }
    
    Write-Log "All prerequisites verified"
}

# Run prerequisite check
Test-Prerequisites
```

### Principle 5: Comprehensive Logging

Every operation is logged with timestamps and context.

```powershell
# Logger module provides consistent formatting
Import-Module C:\Lab\scripts\modules\Logger.psm1

Write-Log "Starting SQL Server installation" -Level INFO
Write-Log "SQL Collation: SQL_Latin1_General_CP1_CI_AS" -Level INFO

try {
    # ... installation code ...
    Write-Log "SQL Server installed successfully" -Level SUCCESS
} catch {
    Write-Log "SQL Server installation failed: $($_.Exception.Message)" -Level ERROR
    throw
}
```

---

## Implementation Approach

### Directory Structure

```
scripts/
├── modules/                     # Reusable PowerShell modules
│   ├── Logger.psm1              # Logging functions
│   ├── WinRMHelper.psm1         # Remote session helpers
│   └── Validator.psm1           # Configuration validators
│
├── dc/                          # Domain Controller scripts
│   ├── Install-ADDS.ps1         # Install AD DS role
│   ├── Promote-DC.ps1           # Promote to domain controller
│   ├── Configure-DNS.ps1        # DNS configuration
│   ├── Configure-DHCP.ps1       # DHCP configuration
│   ├── Create-OUs.ps1           # Create organizational units
│   ├── Create-ServiceAccounts.ps1
│   └── Prepare-ADForSCCM.ps1    # Schema extension, System Management
│
├── sql/                         # SQL Server scripts
│   ├── Install-Prerequisites.ps1
│   ├── Install-SQLServer.ps1    # Silent SQL installation
│   └── Configure-SQLServer.ps1  # Post-install configuration
│
├── sccm/                        # SCCM scripts
│   ├── Install-Prerequisites.ps1
│   ├── Install-SCCM.ps1         # Silent SCCM installation
│   └── Configure-SCCM.ps1       # Site configuration
│
├── client/                      # Client scripts
│   ├── Join-Domain.ps1
│   └── Install-SCCMClient.ps1
│
├── common/                      # Shared scripts
│   ├── Set-LabDNS.ps1           # Configure DNS to point to DC01
│   └── Join-LabDomain.ps1       # Domain join helper
│
└── orchestration/               # Bash orchestration scripts
    ├── deploy-lab.sh            # Main entry point
    ├── deploy-dc.sh             # DC01 deployment
    ├── deploy-sccm.sh           # SCCM01 deployment
    ├── deploy-clients.sh        # Client deployment
    └── lib/                     # Bash helper functions
        ├── logging.sh
        ├── vagrant-helpers.sh
        └── wait-for-reboot.sh
```

### Orchestration Script Design (Bash)

The main orchestration script (`deploy-lab.sh`) coordinates the deployment:

```bash
#!/usr/bin/env bash
#
# deploy-lab.sh - Main SCCM Lab Deployment Script
#
# This script orchestrates the complete lab deployment from a Linux host.
# It uses Vagrant to communicate with Windows VMs via WinRM.
#
# Usage:
#   ./deploy-lab.sh              # Deploy entire lab
#   ./deploy-lab.sh --dc-only    # Only deploy domain controller
#   ./deploy-lab.sh --resume     # Resume from last checkpoint
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script directory (resolves symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/vagrant-helpers.sh"
source "${SCRIPT_DIR}/lib/wait-for-reboot.sh"

# Configuration
VAGRANT_DIR="${SCRIPT_DIR}/../../vagrant"
SCRIPTS_DIR="${SCRIPT_DIR}/../"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

upload_scripts() {
    local vm_name="$1"
    log_info "Uploading scripts to ${vm_name}..."
    
    # Create target directory
    vagrant_cmd "${vm_name}" 'New-Item -ItemType Directory -Path C:\Lab\scripts -Force | Out-Null'
    
    # Upload scripts
    (cd "${VAGRANT_DIR}" && vagrant upload "${SCRIPTS_DIR}" "${vm_name}:C:/Lab/scripts/")
    
    log_success "Scripts uploaded to ${vm_name}"
}

run_script() {
    local vm_name="$1"
    local script_path="$2"
    local script_args="${3:-}"
    
    log_info "Running ${script_path} on ${vm_name}..."
    
    # Execute with bypass execution policy
    local cmd="powershell -ExecutionPolicy Bypass -File 'C:\\Lab\\scripts\\${script_path}'"
    if [[ -n "${script_args}" ]]; then
        cmd="${cmd} ${script_args}"
    fi
    
    vagrant_cmd "${vm_name}" "${cmd}"
}

# ============================================================================
# PHASE 1: DOMAIN CONTROLLER
# ============================================================================

deploy_dc() {
    log_header "Phase 1: Domain Controller (DC01)"
    
    # Upload scripts
    upload_scripts "dc01"
    
    # Step 1: Install AD DS role
    log_step "Installing AD DS Role..."
    run_script "dc01" "dc/Install-ADDS.ps1"
    
    # Step 2: Promote to DC (requires reboot)
    log_step "Promoting to Domain Controller..."
    run_script "dc01" "dc/Promote-DC.ps1"
    
    # Wait for reboot
    wait_for_reboot "dc01" 300
    
    # Step 3: Configure DNS
    log_step "Configuring DNS..."
    run_script "dc01" "dc/Configure-DNS.ps1"
    
    # Step 4: Configure DHCP
    log_step "Configuring DHCP..."
    run_script "dc01" "dc/Configure-DHCP.ps1"
    
    # Step 5: Create OUs and service accounts
    log_step "Creating OUs and Service Accounts..."
    run_script "dc01" "dc/Create-OUs.ps1"
    run_script "dc01" "dc/Create-ServiceAccounts.ps1"
    
    log_success "DC01 deployment complete!"
}

# ============================================================================
# PHASE 2: SCCM SERVER
# ============================================================================

deploy_sccm() {
    log_header "Phase 2: SCCM Server (SCCM01)"
    
    # Upload scripts
    upload_scripts "sccm01"
    
    # Step 1: Set DNS and join domain
    log_step "Configuring DNS and joining domain..."
    run_script "sccm01" "common/Set-LabDNS.ps1"
    run_script "sccm01" "common/Join-LabDomain.ps1"
    
    # Wait for reboot after domain join
    wait_for_reboot "sccm01" 300
    
    # Step 2: Install SQL prerequisites
    log_step "Installing SQL Server prerequisites..."
    run_script "sccm01" "sql/Install-Prerequisites.ps1"
    
    # Step 3: Install SQL Server
    log_step "Installing SQL Server (this takes 10-15 minutes)..."
    run_script "sccm01" "sql/Install-SQLServer.ps1"
    
    # Step 4: Configure SQL Server
    log_step "Configuring SQL Server..."
    run_script "sccm01" "sql/Configure-SQLServer.ps1"
    
    # Step 5: Install SCCM prerequisites
    log_step "Installing SCCM prerequisites..."
    run_script "sccm01" "sccm/Install-Prerequisites.ps1"
    
    # Step 6: Prepare AD for SCCM (runs on DC01)
    log_step "Preparing Active Directory for SCCM..."
    run_script "dc01" "dc/Prepare-ADForSCCM.ps1"
    
    # Step 7: Install SCCM (this takes 30-60 minutes!)
    log_step "Installing SCCM (this takes 30-60 minutes)..."
    run_script "sccm01" "sccm/Install-SCCM.ps1"
    
    # Step 8: Configure SCCM
    log_step "Configuring SCCM..."
    run_script "sccm01" "sccm/Configure-SCCM.ps1"
    
    log_success "SCCM01 deployment complete!"
}

# ============================================================================
# PHASE 3: CLIENTS
# ============================================================================

deploy_clients() {
    log_header "Phase 3: Client Machines"
    
    # Get list of client VMs from Vagrant
    local clients
    clients=$(cd "${VAGRANT_DIR}" && vagrant status --machine-readable | \
              grep ',state,' | grep -v 'dc01\|sccm01' | cut -d',' -f2)
    
    for client in ${clients}; do
        log_step "Deploying ${client}..."
        
        # Upload scripts
        upload_scripts "${client}"
        
        # Configure DNS and join domain
        run_script "${client}" "common/Set-LabDNS.ps1"
        run_script "${client}" "common/Join-LabDomain.ps1"
        
        # Wait for reboot
        wait_for_reboot "${client}" 180
        
        # Install SCCM client
        run_script "${client}" "client/Install-SCCMClient.ps1"
        
        log_success "${client} deployment complete!"
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_header "SCCM Lab Deployment"
    log_info "Starting deployment at $(date)"
    
    # Change to Vagrant directory
    cd "${VAGRANT_DIR}"
    
    # Ensure VMs are running
    log_step "Ensuring VMs are running..."
    vagrant up
    
    # Deploy phases
    deploy_dc
    deploy_sccm
    deploy_clients
    
    # Final validation
    log_header "Deployment Complete!"
    log_info "Run validation: vagrant winrm dc01 -c 'C:\\Lab\\scripts\\Validate-Lab.ps1'"
}

main "$@"
```

### PowerShell Module Design

#### Logger.psm1

```powershell
<#
.SYNOPSIS
    Logging module for SCCM lab automation scripts.

.DESCRIPTION
    Provides consistent logging with timestamps, levels, colors, and file output.
    
    LOG LEVELS:
    - DEBUG:   Detailed diagnostic information (gray)
    - INFO:    General informational messages (white)
    - SUCCESS: Successful operations (green)
    - WARN:    Warning conditions (yellow)
    - ERROR:   Error conditions (red)

.EXAMPLE
    Import-Module .\Logger.psm1
    Write-Log "Starting installation" -Level INFO
    Write-Log "Installation complete!" -Level SUCCESS
#>

# Module-level configuration
$script:LogPath = "C:\Lab\logs"
$script:LogFile = $null

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes the logging system.
    .PARAMETER ScriptName
        Name of the calling script (used for log file name)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path $script:LogPath)) {
        New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
    }
    
    # Create log file with timestamp
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $script:LogPath "$ScriptName-$timestamp.log"
    
    Write-Log "Logging initialized: $($script:LogFile)" -Level DEBUG
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log message to console and file.
    
    .PARAMETER Message
        The message to log.
    
    .PARAMETER Level
        Log level: DEBUG, INFO, SUCCESS, WARN, ERROR
    
    .EXAMPLE
        Write-Log "Processing started" -Level INFO
        Write-Log "File not found" -Level WARN
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    # Timestamp format: 2026-01-27 14:30:45
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    # Color mapping for console output
    $colors = @{
        'DEBUG'   = 'Gray'
        'INFO'    = 'White'
        'SUCCESS' = 'Green'
        'WARN'    = 'Yellow'
        'ERROR'   = 'Red'
    }
    
    # Format the log line
    # PadRight ensures consistent column alignment
    $logLine = "[$timestamp] [$($Level.PadRight(7))] $Message"
    
    # Write to console with color
    Write-Host $logLine -ForegroundColor $colors[$Level]
    
    # Write to file if initialized
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logLine
    }
}

function Write-LogSection {
    <#
    .SYNOPSIS
        Writes a section header to the log for visual separation.
    
    .PARAMETER Title
        The section title
    
    .EXAMPLE
        Write-LogSection "Installing SQL Server"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )
    
    $separator = "=" * 60
    Write-Log $separator -Level INFO
    Write-Log $Title -Level INFO
    Write-Log $separator -Level INFO
}

# Export functions
Export-ModuleMember -Function Initialize-Logging, Write-Log, Write-LogSection
```

#### Validator.psm1

```powershell
<#
.SYNOPSIS
    Validation module for SCCM lab automation scripts.

.DESCRIPTION
    Provides functions to validate the state of lab components.
    Used for prerequisite checks and post-installation verification.

.EXAMPLE
    Import-Module .\Validator.psm1
    Test-ADDSInstalled
    Test-DomainJoined -ExpectedDomain "lab.local"
#>

function Test-ADDSInstalled {
    <#
    .SYNOPSIS
        Checks if AD DS role is installed on this server.
    .OUTPUTS
        Boolean indicating if AD DS is installed
    #>
    $feature = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
    return ($feature -and $feature.InstallState -eq 'Installed')
}

function Test-DomainController {
    <#
    .SYNOPSIS
        Checks if this server is a domain controller.
    .OUTPUTS
        Boolean indicating if server is a DC
    #>
    try {
        $dc = Get-ADDomainController -ErrorAction Stop
        return ($dc -ne $null)
    } catch {
        return $false
    }
}

function Test-DomainJoined {
    <#
    .SYNOPSIS
        Checks if computer is joined to specified domain.
    .PARAMETER ExpectedDomain
        The domain name to check (e.g., "lab.local")
    .OUTPUTS
        Boolean indicating if computer is joined to expected domain
    #>
    param(
        [string]$ExpectedDomain = "lab.local"
    )
    
    $currentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
    return ($currentDomain -eq $ExpectedDomain)
}

function Test-DNSConfiguration {
    <#
    .SYNOPSIS
        Validates DNS is configured correctly for the lab.
    .OUTPUTS
        Boolean indicating if DNS is properly configured
    #>
    param(
        [string]$DCHostname = "dc01.lab.local",
        [string]$ExpectedIP = "192.168.56.10"
    )
    
    try {
        $result = Resolve-DnsName -Name $DCHostname -Type A -ErrorAction Stop
        return ($result.IPAddress -eq $ExpectedIP)
    } catch {
        return $false
    }
}

function Test-DHCPConfiguration {
    <#
    .SYNOPSIS
        Validates DHCP scope is configured correctly.
    .OUTPUTS
        Boolean indicating if DHCP is properly configured
    #>
    try {
        $scope = Get-DhcpServerv4Scope -ErrorAction Stop
        return ($scope.State -eq 'Active')
    } catch {
        return $false
    }
}

function Test-SQLServerInstalled {
    <#
    .SYNOPSIS
        Checks if SQL Server is installed and running.
    .OUTPUTS
        Boolean indicating if SQL Server is installed and running
    #>
    $service = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
    return ($service -and $service.Status -eq 'Running')
}

function Test-SQLServerCollation {
    <#
    .SYNOPSIS
        Verifies SQL Server collation is correct for SCCM.
    .OUTPUTS
        Boolean indicating if collation is correct
    #>
    param(
        [string]$ExpectedCollation = "SQL_Latin1_General_CP1_CI_AS"
    )
    
    try {
        $result = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ErrorAction Stop
        return ($result.Collation -eq $ExpectedCollation)
    } catch {
        return $false
    }
}

function Test-SCCMInstalled {
    <#
    .SYNOPSIS
        Checks if SCCM is installed and site services are running.
    .OUTPUTS
        Boolean indicating if SCCM is installed and running
    #>
    $smsExec = Get-Service -Name "SMS_EXECUTIVE" -ErrorAction SilentlyContinue
    $siteComp = Get-Service -Name "SMS_SITE_COMPONENT_MANAGER" -ErrorAction SilentlyContinue
    
    return (
        ($smsExec -and $smsExec.Status -eq 'Running') -and
        ($siteComp -and $siteComp.Status -eq 'Running')
    )
}

function Test-SCCMClientInstalled {
    <#
    .SYNOPSIS
        Checks if SCCM client is installed and running.
    .OUTPUTS
        Boolean indicating if SCCM client is installed and running
    #>
    $ccmExec = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
    return ($ccmExec -and $ccmExec.Status -eq 'Running')
}

function Get-LabStatus {
    <#
    .SYNOPSIS
        Returns comprehensive status of all lab components.
    .OUTPUTS
        PSCustomObject with status of each component
    #>
    [PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ADDSInstalled   = Test-ADDSInstalled
        IsDC            = Test-DomainController
        DomainJoined    = Test-DomainJoined
        DNSConfigured   = Test-DNSConfiguration
        DHCPConfigured  = Test-DHCPConfiguration
        SQLInstalled    = Test-SQLServerInstalled
        SQLCollation    = if (Test-SQLServerInstalled) { Test-SQLServerCollation } else { $null }
        SCCMInstalled   = Test-SCCMInstalled
        SCCMClient      = Test-SCCMClientInstalled
    }
}

# Export all functions
Export-ModuleMember -Function *
```

---

## Error Handling & Idempotency

### Error Handling Strategy

```powershell
# Standard error handling pattern for all scripts
$ErrorActionPreference = 'Stop'

try {
    # Risky operation
    Install-WindowsFeature -Name AD-Domain-Services
} catch {
    Write-Log "Operation failed: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    
    # Optionally perform cleanup
    # ...
    
    # Re-throw to stop script execution
    throw
}
```

### Idempotency Patterns

**Pattern 1: Check Before Action**

```powershell
# Only install if not already installed
if (-not (Test-ADDSInstalled)) {
    Write-Log "Installing AD DS role..."
    Install-WindowsFeature -Name AD-Domain-Services
} else {
    Write-Log "AD DS role already installed, skipping..."
}
```

**Pattern 2: Use -ErrorAction SilentlyContinue for Idempotent Commands**

```powershell
# Creating a user that might already exist
try {
    New-ADUser -Name "SQL_Service" -Path "OU=Service Accounts,DC=lab,DC=local" -ErrorAction Stop
    Write-Log "Created SQL_Service account"
} catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
    Write-Log "SQL_Service account already exists, skipping..."
}
```

**Pattern 3: State File Tracking**

```powershell
# Track completed steps in a state file
$StateFile = "C:\Lab\state\dc-setup.json"

function Get-CompletedSteps {
    if (Test-Path $StateFile) {
        return (Get-Content $StateFile | ConvertFrom-Json).CompletedSteps
    }
    return @()
}

function Save-CompletedStep {
    param([string]$StepName)
    
    $state = if (Test-Path $StateFile) {
        Get-Content $StateFile | ConvertFrom-Json
    } else {
        [PSCustomObject]@{ CompletedSteps = @() }
    }
    
    $state.CompletedSteps += $StepName
    $state | ConvertTo-Json | Set-Content $StateFile
}

# Usage
$completedSteps = Get-CompletedSteps

if ($completedSteps -notcontains "InstallADDS") {
    Install-WindowsFeature -Name AD-Domain-Services
    Save-CompletedStep "InstallADDS"
}
```

---

## Testing Strategy

### Unit Testing PowerShell Modules

```powershell
# Test-Logger.ps1 - Pester tests for Logger module
Describe "Logger Module" {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\Logger.psm1" -Force
    }
    
    It "Initialize-Logging creates log directory" {
        Initialize-Logging -ScriptName "test"
        Test-Path "C:\Lab\logs" | Should -Be $true
    }
    
    It "Write-Log creates log entry" {
        $logFile = (Get-ChildItem "C:\Lab\logs\test-*.log" | 
                   Sort-Object LastWriteTime -Descending | 
                   Select-Object -First 1).FullName
        
        Write-Log "Test message" -Level INFO
        
        Get-Content $logFile | Should -Contain "*Test message*"
    }
}
```

### Integration Testing

```bash
#!/bin/bash
# test-deployment.sh - Integration tests for lab deployment

# Test DC01 configuration
echo "Testing DC01..."
vagrant winrm dc01 -c '
    Import-Module C:\Lab\scripts\modules\Validator.psm1
    $status = Get-LabStatus
    
    if (-not $status.ADDSInstalled) { throw "AD DS not installed" }
    if (-not $status.IsDC) { throw "Not a domain controller" }
    if (-not $status.DNSConfigured) { throw "DNS not configured" }
    if (-not $status.DHCPConfigured) { throw "DHCP not configured" }
    
    Write-Host "DC01: All tests passed!"
'

# Test SCCM01 configuration
echo "Testing SCCM01..."
vagrant winrm sccm01 -c '
    Import-Module C:\Lab\scripts\modules\Validator.psm1
    $status = Get-LabStatus
    
    if (-not $status.DomainJoined) { throw "Not domain joined" }
    if (-not $status.SQLInstalled) { throw "SQL Server not installed" }
    if (-not $status.SQLCollation) { throw "Wrong SQL collation" }
    if (-not $status.SCCMInstalled) { throw "SCCM not installed" }
    
    Write-Host "SCCM01: All tests passed!"
'

echo "All integration tests passed!"
```

---

## Caveats & Known Issues

### Issue 1: Vagrant WinRM Timeout on Large Scripts

**Symptom**: Long-running scripts (like SCCM installation) cause WinRM timeout.

**Solution**: Increase Vagrant WinRM timeout or use background jobs:

```ruby
# In Vagrantfile
config.winrm.timeout = 3600  # 1 hour
```

Or split into monitoring script:

```bash
# Start installation in background
vagrant winrm sccm01 -c 'Start-Process powershell -ArgumentList "-File C:\Lab\scripts\sccm\Install-SCCM.ps1" -NoNewWindow'

# Monitor progress
while true; do
    status=$(vagrant winrm sccm01 -c 'Get-Content C:\ConfigMgrSetup.log -Tail 1' 2>/dev/null)
    echo "$status"
    
    if echo "$status" | grep -q "Setup has successfully installed"; then
        echo "Installation complete!"
        break
    fi
    
    sleep 60
done
```

### Issue 2: WinRM Authentication After DC Promotion

**Symptom**: After DC promotion, Vagrant can't connect with `vagrant/vagrant` credentials.

**Reason**: Local `vagrant` user no longer exists after domain promotion.

**Solution**: Use domain credentials:

```ruby
# In Vagrantfile (after DC promotion)
# You may need to update credentials
config.winrm.username = "LAB\\Administrator"
config.winrm.password = "vagrant"
```

Or maintain local vagrant account by running before promotion:

```powershell
# Create domain user matching local vagrant user
$password = ConvertTo-SecureString "vagrant" -AsPlainText -Force
New-ADUser -Name "vagrant" -SamAccountName "vagrant" -AccountPassword $password -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember -Identity "Domain Admins" -Members "vagrant"
```

### Issue 3: File Upload Encoding Issues

**Symptom**: Scripts uploaded via `vagrant upload` have wrong encoding.

**Solution**: Ensure scripts are saved with UTF-8 encoding (without BOM):

```bash
# Check file encoding
file scripts/dc/Install-ADDS.ps1

# Convert to UTF-8 if needed
iconv -f UTF-16 -t UTF-8 scripts/dc/Install-ADDS.ps1 > scripts/dc/Install-ADDS.ps1.new
mv scripts/dc/Install-ADDS.ps1.new scripts/dc/Install-ADDS.ps1
```

### Issue 4: PowerShell Execution Policy

**Symptom**: Scripts fail with execution policy error.

**Solution**: Always bypass execution policy when running scripts:

```bash
vagrant winrm dc01 -c 'powershell -ExecutionPolicy Bypass -File C:\Lab\scripts\dc\Install-ADDS.ps1'
```

### Issue 5: Credential Expiration

**Symptom**: Scripts fail with "password has expired" error.

**Solution**: Set passwords to never expire for service accounts:

```powershell
Set-ADUser -Identity "SQL_Service" -PasswordNeverExpires $true
```

### Issue 6: Network Timing Issues

**Symptom**: Scripts fail because network isn't ready after reboot.

**Solution**: Add retry logic:

```powershell
function Wait-ForNetwork {
    param([int]$TimeoutSeconds = 120)
    
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        if ($adapter) {
            $ip = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ip) {
                Write-Log "Network ready: $($ip.IPAddress)"
                return $true
            }
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    throw "Network not ready after $TimeoutSeconds seconds"
}
```

---

## Summary

This automation plan provides a robust foundation for deploying the SCCM lab from a Linux host. Key points:

1. **Use Vagrant WinRM** as the transport layer (abstracts WinRM complexity)
2. **Run scripts locally** on each VM (avoids double-hop issues)
3. **Phase-based execution** with reboot handling
4. **Idempotent operations** (safe to re-run)
5. **Comprehensive logging** for troubleshooting
6. **Modular design** for maintainability

The next step is to implement the scripts according to this plan, starting with the Logger and Validator modules, then proceeding through DC01, SCCM01, and client configurations.

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-27  
**Author**: SCCM Homelab Project
