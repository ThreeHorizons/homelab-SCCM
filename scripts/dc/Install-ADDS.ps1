#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the Active Directory Domain Services role on a Windows Server.

.DESCRIPTION
    This script installs the AD DS role and its management tools. This is the
    first step in creating a domain controller - installing the role only adds
    the necessary software; the server must still be "promoted" to actually
    become a domain controller.

    WHAT IS AD DS?
    --------------
    Active Directory Domain Services (AD DS) is Microsoft's directory service.
    Think of it as a database of:
    - Users (who can log in)
    - Computers (what machines are in the network)
    - Groups (collections of users/computers for permissions)
    - Policies (settings that apply to users/computers)

    WHY INSTALL THE ROLE FIRST?
    ---------------------------
    We separate role installation from DC promotion because:
    1. Installation doesn't require a reboot, but promotion does
    2. We can verify the installation before committing to promotion
    3. It follows the principle of doing one thing at a time
    4. Easier to troubleshoot if something fails

    WHAT GETS INSTALLED:
    --------------------
    - AD DS role: Core directory services
    - AD DS Management Tools: PowerShell module, GUI consoles
    - Group Policy Management: For managing GPOs
    - DNS Server: Required for AD (installed during promotion if not present)

.PARAMETER Force
    Skip confirmation prompts. Use for unattended installation.

.EXAMPLE
    # Interactive installation
    .\Install-ADDS.ps1

.EXAMPLE
    # Unattended installation
    .\Install-ADDS.ps1 -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Windows Server 2016 or later
    - Administrator privileges
    - Network connectivity (for downloading updates if needed)

    NEXT STEPS:
    After running this script, run Promote-DC.ps1 to promote to a domain controller.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

# Set strict error handling
# 'Stop' means any error will throw an exception (caught by try/catch)
$ErrorActionPreference = 'Stop'

# Determine the script's directory for finding modules
# $PSScriptRoot is an automatic variable containing the directory of the current script
$ScriptDir = Split-Path -Parent $PSScriptRoot  # Go up one level from /dc to /scripts

# Import our custom modules
# We use Join-Path for cross-platform path building (though this is Windows-only)
try {
    Import-Module (Join-Path $ScriptDir "modules\Logger.psm1") -Force
    Import-Module (Join-Path $ScriptDir "modules\Validator.psm1") -Force
}
catch {
    # If modules aren't found, use basic logging
    Write-Host "[ERROR] Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[INFO] Make sure Logger.psm1 and Validator.psm1 are in the modules folder" -ForegroundColor Yellow
    exit 1
}

# Initialize logging
# The script name (without extension) becomes part of the log filename
Initialize-Logging -ScriptName "Install-ADDS"

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Installing Active Directory Domain Services"

    # -------------------------------------------------------------------------
    # STEP 1: Check if already installed
    # -------------------------------------------------------------------------
    # This makes the script idempotent - safe to run multiple times
    Write-Log "Checking if AD DS role is already installed..." -Level INFO

    if (Test-ADDSInstalled) {
        Write-Log "AD DS role is already installed!" -Level SUCCESS
        Write-Log "Skipping installation. Run Promote-DC.ps1 to promote to domain controller." -Level INFO

        # Show current status
        $feature = Get-WindowsFeature -Name AD-Domain-Services
        Write-Log "Feature Name: $($feature.Name)" -Level DEBUG
        Write-Log "Install State: $($feature.InstallState)" -Level DEBUG

        Complete-Logging -Success $true
        exit 0
    }

    Write-Log "AD DS role is not installed. Proceeding with installation." -Level INFO

    # -------------------------------------------------------------------------
    # STEP 2: Confirm installation (unless -Force is specified)
    # -------------------------------------------------------------------------
    if (-not $Force) {
        Write-Log "" -Level INFO
        Write-Log "This will install the AD DS role and management tools." -Level INFO
        Write-Log "No reboot is required for role installation." -Level INFO
        Write-Log "" -Level INFO

        # In automated scenarios, Force should be used
        # This prompt is for interactive learning/testing
        $confirm = Read-Host "Do you want to continue? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "Installation cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 3: Install AD DS Role
    # -------------------------------------------------------------------------
    Write-Log "Installing AD DS role and management tools..." -Level INFO
    Write-Log "This may take a few minutes..." -Level INFO

    <#
    UNDERSTANDING INSTALL-WINDOWSFEATURE:
    -------------------------------------
    Install-WindowsFeature is the PowerShell cmdlet for adding Windows Server
    roles and features. Key parameters:

    -Name: The feature to install. Use Get-WindowsFeature to see all options.

    -IncludeManagementTools: Also install the GUI/PowerShell tools for
        managing the feature. For AD DS, this includes:
        - Active Directory Users and Computers (dsa.msc)
        - Active Directory Sites and Services
        - Active Directory Domains and Trusts
        - Active Directory module for PowerShell
        - Group Policy Management Console

    -IncludeAllSubFeature: Install all sub-features. For AD DS, this includes
        things like the AD DS Snap-ins and Command-Line Tools.

    The command returns an object with:
    - Success: Boolean indicating if installation succeeded
    - RestartNeeded: Whether a reboot is required
    - FeatureResult: Array of installed features
    - ExitCode: Numeric exit code
    #>

    $installResult = Install-WindowsFeature `
        -Name AD-Domain-Services `
        -IncludeManagementTools `
        -IncludeAllSubFeature

    # -------------------------------------------------------------------------
    # STEP 4: Verify Installation
    # -------------------------------------------------------------------------
    Write-Log "Verifying installation..." -Level INFO

    # Check the install result
    if ($installResult.Success) {
        Write-Log "AD DS role installed successfully!" -Level SUCCESS

        # Log what was installed
        foreach ($feature in $installResult.FeatureResult) {
            Write-Log "  Installed: $($feature.Name) ($($feature.DisplayName))" -Level INFO
        }

        # Check if reboot is needed
        # For AD DS role installation alone, reboot is typically NOT needed
        # However, Windows might request one if there are pending updates
        if ($installResult.RestartNeeded -eq 'Yes') {
            Write-Log "" -Level INFO
            Write-Log "A system restart is required to complete installation." -Level WARN
            Write-Log "Please restart the server before running Promote-DC.ps1" -Level WARN
        }
        else {
            Write-Log "" -Level INFO
            Write-Log "No restart required. You can proceed to promotion." -Level INFO
        }
    }
    else {
        Write-Log "AD DS role installation failed!" -Level ERROR
        Write-Log "Exit Code: $($installResult.ExitCode)" -Level ERROR

        foreach ($feature in $installResult.FeatureResult) {
            if ($feature.RestartNeeded) {
                Write-Log "  Failed: $($feature.Name) - Restart needed" -Level ERROR
            }
        }

        Complete-Logging -Success $false
        exit 1
    }

    # -------------------------------------------------------------------------
    # STEP 5: Verify using our Validator module
    # -------------------------------------------------------------------------
    Write-Log "Running validation checks..." -Level INFO

    if (Test-ADDSInstalled) {
        Write-Log "Validation passed: AD DS role is installed" -Level SUCCESS
    }
    else {
        Write-Log "Validation failed: AD DS role not detected after installation!" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # -------------------------------------------------------------------------
    # STEP 6: Display Next Steps
    # -------------------------------------------------------------------------
    Write-Log "" -Level INFO
    Write-LogSection "Next Steps"
    Write-Log "1. If a restart was requested, restart the server first" -Level INFO
    Write-Log "2. Run Promote-DC.ps1 to promote this server to a domain controller" -Level INFO
    Write-Log "3. The promotion will:" -Level INFO
    Write-Log "   - Create the lab.local domain and forest" -Level INFO
    Write-Log "   - Install and configure DNS" -Level INFO
    Write-Log "   - Require a restart to complete" -Level INFO
    Write-Log "" -Level INFO

    # -------------------------------------------------------------------------
    # COMPLETE
    # -------------------------------------------------------------------------
    Complete-Logging -Success $true
    exit 0
}
catch {
    # Handle any unexpected errors
    Write-LogError -ErrorRecord $_ -Message "An unexpected error occurred during AD DS installation"
    Complete-Logging -Success $false
    exit 1
}
