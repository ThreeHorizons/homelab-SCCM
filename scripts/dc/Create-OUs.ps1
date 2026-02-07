#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates organizational units (OUs) in Active Directory for the SCCM lab.

.DESCRIPTION
    This script creates a logical OU structure in Active Directory for organizing
    computers, users, and service accounts. A well-designed OU structure enables:
    - Easier administration (find objects quickly)
    - Group Policy targeting (apply policies to specific OUs)
    - Delegation (give admins control over specific OUs)
    - Reporting (group objects logically)

    WHAT IS AN ORGANIZATIONAL UNIT?
    -------------------------------
    An OU is a container in Active Directory that can hold:
    - Users
    - Computers
    - Groups
    - Other OUs (nested structure)

    Unlike groups, OUs are used for ORGANIZATION and POLICY, not permissions.
    Groups = Permissions (who can access what)
    OUs = Organization (where things are stored, what policies apply)

    OU STRUCTURE FOR THIS LAB:
    --------------------------
    lab.local (Domain Root)
    ├── Servers                    # All server computers
    ├── Workstations               # All client computers
    ├── Lab Users                  # Top-level user container
    │   ├── Administrators         # Admin user accounts
    │   └── Standard Users         # Regular user accounts
    └── Service Accounts           # Accounts for services (SQL, SCCM, etc.)

    WHY THIS STRUCTURE:
    -------------------
    - Servers: Separate from workstations for different GPOs
    - Workstations: Where SCCM-managed clients go
    - Lab Users: Keeps users organized by privilege level
    - Service Accounts: Easy to find and audit service accounts

.PARAMETER DomainDN
    The distinguished name of the domain. Auto-detected if not specified.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Create-OUs.ps1

.EXAMPLE
    .\Create-OUs.ps1 -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Server must be a domain controller
    - Active Directory PowerShell module available
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainDN = $null,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# =============================================================================
# SCRIPT INITIALIZATION
# =============================================================================

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSScriptRoot

try {
    Import-Module (Join-Path $ScriptDir "modules\Logger.psm1") -Force
    Import-Module (Join-Path $ScriptDir "modules\Validator.psm1") -Force
}
catch {
    Write-Host "[ERROR] Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Initialize-Logging -ScriptName "Create-OUs"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Define the OU structure
# Each entry: Name, ParentPath (relative to domain root), Description
# ParentPath of "" means directly under the domain root
# ParentPath of "OU=Lab Users" means under the Lab Users OU
$OUStructure = @(
    @{ Name = "Servers";           ParentPath = "";                  Description = "Domain member servers" }
    @{ Name = "Workstations";      ParentPath = "";                  Description = "Domain workstations and client computers" }
    @{ Name = "Lab Users";         ParentPath = "";                  Description = "Lab user accounts" }
    @{ Name = "Administrators";    ParentPath = "OU=Lab Users";      Description = "Administrative user accounts" }
    @{ Name = "Standard Users";    ParentPath = "OU=Lab Users";      Description = "Standard user accounts" }
    @{ Name = "Service Accounts";  ParentPath = "";                  Description = "Service and automation accounts" }
)

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Creating Organizational Units"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    # Must be a domain controller
    if (-not (Test-IsDomainController)) {
        Write-Log "This server is not a domain controller!" -Level ERROR
        Write-Log "OUs must be created on a domain controller." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Server is a domain controller" -Level SUCCESS

    # Import Active Directory module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "  ActiveDirectory module loaded" -Level SUCCESS
    }
    catch {
        Write-Log "  Failed to load ActiveDirectory module!" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # -------------------------------------------------------------------------
    # STEP 2: Get Domain Information
    # -------------------------------------------------------------------------
    Write-Log "Getting domain information..." -Level INFO

    <#
    DISTINGUISHED NAMES EXPLAINED:
    ------------------------------
    In Active Directory, every object has a Distinguished Name (DN) that
    uniquely identifies it. The format is:

    CN=ObjectName,OU=ParentOU,DC=domain,DC=extension

    Components:
    - CN (Common Name): The object's name
    - OU (Organizational Unit): Container for the object
    - DC (Domain Component): Parts of the domain name

    Examples:
    - Domain: DC=lab,DC=local
    - User: CN=John Smith,OU=Users,DC=lab,DC=local
    - OU: OU=Servers,DC=lab,DC=local
    - Nested OU: OU=Admins,OU=Lab Users,DC=lab,DC=local

    The DN is read right-to-left (domain first, then container, then object).
    #>

    if ([string]::IsNullOrEmpty($DomainDN)) {
        # Auto-detect the domain DN
        $domain = Get-ADDomain
        $DomainDN = $domain.DistinguishedName
    }

    Write-Log "  Domain DN: $DomainDN" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 3: Display Planned OU Structure
    # -------------------------------------------------------------------------
    Write-LogSection "Planned OU Structure"

    Write-Log "The following OUs will be created:" -Level INFO
    Write-Log "" -Level INFO

    foreach ($ou in $OUStructure) {
        $fullPath = if ($ou.ParentPath) {
            "OU=$($ou.Name),$($ou.ParentPath),$DomainDN"
        }
        else {
            "OU=$($ou.Name),$DomainDN"
        }
        Write-Log "  $($ou.Name)" -Level INFO
        Write-Log "    Path: $fullPath" -Level DEBUG
        Write-Log "    Description: $($ou.Description)" -Level DEBUG
    }

    # -------------------------------------------------------------------------
    # STEP 4: Confirmation
    # -------------------------------------------------------------------------
    if (-not $Force) {
        Write-Log "" -Level INFO
        $confirm = Read-Host "Do you want to create these OUs? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "OU creation cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 5: Create OUs
    # -------------------------------------------------------------------------
    Write-LogSection "Creating Organizational Units"

    $createdCount = 0
    $skippedCount = 0

    foreach ($ou in $OUStructure) {
        # Build the full path for this OU
        $parentDN = if ($ou.ParentPath) {
            "$($ou.ParentPath),$DomainDN"
        }
        else {
            $DomainDN
        }

        $ouDN = "OU=$($ou.Name),$parentDN"

        Write-Log "Processing: $($ou.Name)..." -Level INFO

        # Check if OU already exists
        try {
            $existing = Get-ADOrganizationalUnit -Identity $ouDN -ErrorAction Stop
            Write-Log "  Already exists, skipping" -Level SUCCESS
            $skippedCount++
            continue
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            # OU doesn't exist, we'll create it
        }

        # Create the OU
        try {
            <#
            NEW-ADORGANIZATIONALUNIT PARAMETERS:
            ------------------------------------
            -Name: The name of the OU
            -Path: The DN of the parent container
            -Description: Optional description
            -ProtectedFromAccidentalDeletion: If $true, prevents deletion
                without first removing protection. Default is $true.

            We set ProtectedFromAccidentalDeletion to $false for lab
            convenience (easier to clean up). In production, keep it $true!
            #>

            New-ADOrganizationalUnit `
                -Name $ou.Name `
                -Path $parentDN `
                -Description $ou.Description `
                -ProtectedFromAccidentalDeletion $false

            Write-Log "  Created: $ouDN" -Level SUCCESS
            $createdCount++
        }
        catch {
            Write-Log "  Failed to create: $($_.Exception.Message)" -Level ERROR
        }
    }

    # -------------------------------------------------------------------------
    # STEP 6: Summary
    # -------------------------------------------------------------------------
    Write-LogSection "OU Creation Summary"

    Write-Log "Created: $createdCount OUs" -Level INFO
    Write-Log "Skipped: $skippedCount OUs (already existed)" -Level INFO
    Write-Log "" -Level INFO

    # Show the final OU structure
    Write-Log "Current OU Structure:" -Level INFO

    # Get all OUs and display them
    $allOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN |
        Sort-Object DistinguishedName

    foreach ($existingOU in $allOUs) {
        # Calculate indent based on nesting level
        $depth = ($existingOU.DistinguishedName.Split(',').Count - $DomainDN.Split(',').Count)
        $indent = "  " * $depth

        Write-Log "$indent$($existingOU.Name)" -Level INFO
    }

    Write-Log "" -Level INFO
    Write-Log "Next Steps:" -Level INFO
    Write-Log "  1. Run Create-ServiceAccounts.ps1 to create service accounts" -Level INFO
    Write-Log "  2. When joining computers to the domain, specify the target OU:" -Level INFO
    Write-Log "     - Servers -> OU=Servers,$DomainDN" -Level INFO
    Write-Log "     - Clients -> OU=Workstations,$DomainDN" -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during OU creation"
    Complete-Logging -Success $false
    exit 1
}
