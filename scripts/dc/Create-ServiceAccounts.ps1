#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates service accounts in Active Directory for the SCCM lab.

.DESCRIPTION
    This script creates the service accounts needed for SQL Server and SCCM.
    Service accounts are special user accounts used by applications to run
    services and access resources.

    WHY USE SERVICE ACCOUNTS?
    -------------------------
    1. SECURITY: Don't run services as Administrator or a real user account
    2. AUDITING: Track what each service is doing separately
    3. LEAST PRIVILEGE: Give each service only the permissions it needs
    4. PASSWORD MANAGEMENT: Can rotate passwords without affecting users
    5. COMPLIANCE: Many security frameworks require dedicated service accounts

    SERVICE ACCOUNTS FOR THIS LAB:
    ------------------------------

    SQL_Service:
        - Purpose: Run SQL Server services (Database Engine, Agent)
        - Needs: Log on as a service, access to SQL data files
        - Used by: SQL Server on SCCM01

    SCCM_NAA (Network Access Account):
        - Purpose: Access content when computer account can't
        - Needs: Read access to distribution point shares
        - Used by: SCCM clients accessing content
        - When: Client not yet domain-joined or from untrusted forest

    SCCM_ClientPush:
        - Purpose: Install SCCM client on remote machines
        - Needs: Local admin on target computers
        - Used by: SCCM site server for client push installation

    SCCM_JoinDomain:
        - Purpose: Join computers to domain during OSD
        - Needs: Permission to create computer objects in AD
        - Used by: SCCM task sequences for OS deployment

    BEST PRACTICES FOR SERVICE ACCOUNTS:
    ------------------------------------
    1. Use descriptive names (SQL_Service, not svc1)
    2. Set passwords to never expire (for service stability)
    3. Disable interactive logon where possible
    4. Document the purpose of each account
    5. Store in a dedicated OU for easy management
    6. Grant minimum necessary permissions

.PARAMETER ServiceAccountPassword
    Password for service accounts. If not provided, uses a default (lab only!).

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Create-ServiceAccounts.ps1

.EXAMPLE
    $securePass = ConvertTo-SecureString "MyP@ssw0rd!" -AsPlainText -Force
    .\Create-ServiceAccounts.ps1 -ServiceAccountPassword $securePass -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Server must be a domain controller
    - OUs should exist (run Create-OUs.ps1 first)

    SECURITY WARNING:
    The default password is for LAB USE ONLY. In production, use unique
    strong passwords for each service account!
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [SecureString]$ServiceAccountPassword = $null,

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

Initialize-Logging -ScriptName "Create-ServiceAccounts"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default password for lab service accounts
# WARNING: Change this in production!
$DefaultPassword = "P@ssw0rd123!"

# Define service accounts to create
# Each entry: SamAccountName, Name, Description, AdditionalGroups
$ServiceAccounts = @(
    @{
        SamAccountName   = "SQL_Service"
        Name             = "SQL Server Service Account"
        Description      = "Runs SQL Server database engine and agent services"
        AdditionalGroups = @()  # No additional groups needed
    },
    @{
        SamAccountName   = "SCCM_NAA"
        Name             = "SCCM Network Access Account"
        Description      = "Used by SCCM clients to access content on distribution points"
        AdditionalGroups = @()  # Read-only access, no special groups
    },
    @{
        SamAccountName   = "SCCM_ClientPush"
        Name             = "SCCM Client Push Account"
        Description      = "Used to install SCCM client on remote computers"
        AdditionalGroups = @()  # Needs local admin on targets, configured separately
    },
    @{
        SamAccountName   = "SCCM_JoinDomain"
        Name             = "SCCM Domain Join Account"
        Description      = "Used during OS deployment to join computers to the domain"
        AdditionalGroups = @()  # Needs permission on Workstations OU
    }
)

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Creating Service Accounts"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    # Must be a domain controller
    if (-not (Test-IsDomainController)) {
        Write-Log "This server is not a domain controller!" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Server is a domain controller" -Level SUCCESS

    # Import Active Directory module
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "  ActiveDirectory module loaded" -Level SUCCESS

    # Get domain information
    $domain = Get-ADDomain
    $domainDN = $domain.DistinguishedName
    $domainNetBIOS = $domain.NetBIOSName
    Write-Log "  Domain: $($domain.DNSRoot)" -Level SUCCESS

    # Check if Service Accounts OU exists
    $serviceAccountsOU = "OU=Service Accounts,$domainDN"
    try {
        Get-ADOrganizationalUnit -Identity $serviceAccountsOU -ErrorAction Stop | Out-Null
        Write-Log "  Service Accounts OU exists" -Level SUCCESS
    }
    catch {
        Write-Log "  Service Accounts OU does not exist!" -Level WARN
        Write-Log "  Creating it now..." -Level INFO

        New-ADOrganizationalUnit `
            -Name "Service Accounts" `
            -Path $domainDN `
            -Description "Service and automation accounts" `
            -ProtectedFromAccidentalDeletion $false

        Write-Log "  Service Accounts OU created" -Level SUCCESS
    }

    # -------------------------------------------------------------------------
    # STEP 2: Handle Password
    # -------------------------------------------------------------------------
    Write-Log "Configuring service account password..." -Level INFO

    if ($null -eq $ServiceAccountPassword) {
        if ($Force) {
            Write-Log "Using default password (automated mode)" -Level WARN
            Write-Log "WARNING: Default password is for LAB USE ONLY!" -Level WARN
            $ServiceAccountPassword = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
        }
        else {
            Write-Log "Enter a password for the service accounts." -Level INFO
            Write-Log "(In a lab, you can use the same password for all accounts)" -Level INFO
            $ServiceAccountPassword = Read-Host "Enter password" -AsSecureString
        }
    }

    # -------------------------------------------------------------------------
    # STEP 3: Display Planned Accounts
    # -------------------------------------------------------------------------
    Write-LogSection "Planned Service Accounts"

    foreach ($account in $ServiceAccounts) {
        Write-Log "$($account.SamAccountName)" -Level INFO
        Write-Log "  Name: $($account.Name)" -Level DEBUG
        Write-Log "  Description: $($account.Description)" -Level DEBUG
    }

    # -------------------------------------------------------------------------
    # STEP 4: Confirmation
    # -------------------------------------------------------------------------
    if (-not $Force) {
        Write-Log "" -Level INFO
        $confirm = Read-Host "Do you want to create these accounts? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "Account creation cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 5: Create Service Accounts
    # -------------------------------------------------------------------------
    Write-LogSection "Creating Service Accounts"

    $createdCount = 0
    $skippedCount = 0

    foreach ($account in $ServiceAccounts) {
        Write-Log "Processing: $($account.SamAccountName)..." -Level INFO

        # Check if account already exists
        try {
            $existing = Get-ADUser -Identity $account.SamAccountName -ErrorAction Stop
            Write-Log "  Already exists, skipping" -Level SUCCESS
            $skippedCount++
            continue
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            # Account doesn't exist, create it
        }

        # Create the account
        try {
            <#
            NEW-ADUSER PARAMETERS FOR SERVICE ACCOUNTS:
            -------------------------------------------
            -Name: Display name for the account
            -SamAccountName: Pre-Windows 2000 login name (used for services)
            -UserPrincipalName: UPN format login (account@domain.com)
            -Path: OU to create the account in
            -AccountPassword: The password (as SecureString)
            -Enabled: $true to enable the account immediately
            -PasswordNeverExpires: $true for service accounts (prevents service outages)
            -CannotChangePassword: $true to prevent accidental password changes
            -Description: Documents the account's purpose

            SERVICE ACCOUNT SPECIFIC SETTINGS:
            - PasswordNeverExpires: Services don't check their email for password
              expiration warnings. An expired password = service failure.
            - CannotChangePassword: Prevents users/admins from accidentally
              changing the password and breaking the service.
            #>

            New-ADUser `
                -Name $account.Name `
                -SamAccountName $account.SamAccountName `
                -UserPrincipalName "$($account.SamAccountName)@$($domain.DNSRoot)" `
                -Path $serviceAccountsOU `
                -AccountPassword $ServiceAccountPassword `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -CannotChangePassword $true `
                -Description $account.Description

            Write-Log "  Created: $domainNetBIOS\$($account.SamAccountName)" -Level SUCCESS
            $createdCount++

            # Add to any additional groups
            foreach ($group in $account.AdditionalGroups) {
                try {
                    Add-ADGroupMember -Identity $group -Members $account.SamAccountName
                    Write-Log "  Added to group: $group" -Level INFO
                }
                catch {
                    Write-Log "  Failed to add to group $group : $($_.Exception.Message)" -Level WARN
                }
            }
        }
        catch {
            Write-Log "  Failed to create: $($_.Exception.Message)" -Level ERROR
        }
    }

    # -------------------------------------------------------------------------
    # STEP 6: Grant SCCM_JoinDomain Permission to Join Computers
    # -------------------------------------------------------------------------
    Write-LogSection "Configuring Permissions"

    Write-Log "Granting SCCM_JoinDomain permission to create computer objects..." -Level INFO

    <#
    DELEGATION FOR DOMAIN JOIN:
    ---------------------------
    To join a computer to the domain, the account needs:
    - Create Computer Objects permission on the target OU
    - Write permissions on certain attributes

    We use dsacls.exe (Directory Services ACL tool) to grant these permissions.
    The format is:
    dsacls "OU_DN" /G "DOMAIN\User:permissions;object_type"

    Permissions for domain join:
    - GR = Generic Read
    - CC = Create Child (create computer objects)
    - DC = Delete Child
    - LC = List Contents
    - WP = Write Property
    #>

    $workstationsOU = "OU=Workstations,$domainDN"

    # Check if Workstations OU exists
    try {
        Get-ADOrganizationalUnit -Identity $workstationsOU -ErrorAction Stop | Out-Null

        # Grant permission using dsacls
        # CCDC = Create Child, Delete Child of type "computer"
        Write-Log "  Granting 'Create Computer' permission on Workstations OU..." -Level INFO

        $dsaclsResult1 = dsacls $workstationsOU /G "$domainNetBIOS\SCCM_JoinDomain:CCDC;computer" 2>&1
        $dsaclsResult2 = dsacls $workstationsOU /G "$domainNetBIOS\SCCM_JoinDomain:LC;;computer" 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "  Permissions granted successfully" -Level SUCCESS
        }
        else {
            Write-Log "  dsacls returned: $dsaclsResult1" -Level WARN
        }
    }
    catch {
        Write-Log "  Workstations OU not found. Create it first with Create-OUs.ps1" -Level WARN
        Write-Log "  You can manually grant permissions later." -Level WARN
    }

    # -------------------------------------------------------------------------
    # STEP 7: Summary
    # -------------------------------------------------------------------------
    Write-LogSection "Service Account Summary"

    Write-Log "Created: $createdCount accounts" -Level INFO
    Write-Log "Skipped: $skippedCount accounts (already existed)" -Level INFO
    Write-Log "" -Level INFO

    # List all service accounts
    Write-Log "Service Accounts in AD:" -Level INFO

    $allServiceAccounts = Get-ADUser -Filter * -SearchBase $serviceAccountsOU -Properties Description |
        Sort-Object SamAccountName

    foreach ($sa in $allServiceAccounts) {
        Write-Log "  $domainNetBIOS\$($sa.SamAccountName)" -Level INFO
        Write-Log "    $($sa.Description)" -Level DEBUG
    }

    Write-Log "" -Level INFO
    Write-Log "Account Usage:" -Level INFO
    Write-Log "  SQL Server:      $domainNetBIOS\SQL_Service" -Level INFO
    Write-Log "  SCCM NAA:        $domainNetBIOS\SCCM_NAA" -Level INFO
    Write-Log "  Client Push:     $domainNetBIOS\SCCM_ClientPush" -Level INFO
    Write-Log "  Domain Join:     $domainNetBIOS\SCCM_JoinDomain" -Level INFO
    Write-Log "" -Level INFO

    Write-Log "IMPORTANT: Additional configuration required:" -Level WARN
    Write-Log "  1. SCCM_ClientPush needs local admin rights on target computers" -Level INFO
    Write-Log "     (Configure via Group Policy or local admin group)" -Level INFO
    Write-Log "  2. SQL_Service will be configured during SQL Server installation" -Level INFO
    Write-Log "  3. SCCM_NAA and SCCM_JoinDomain are configured in SCCM console" -Level INFO
    Write-Log "" -Level INFO

    Write-Log "Next Steps:" -Level INFO
    Write-Log "  1. DC01 configuration is complete!" -Level SUCCESS
    Write-Log "  2. On SCCM01: Run Set-LabDNS.ps1 to configure DNS" -Level INFO
    Write-Log "  3. On SCCM01: Run Join-LabDomain.ps1 to join the domain" -Level INFO
    Write-Log "  4. On SCCM01: Proceed with SQL Server and SCCM installation" -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during service account creation"
    Complete-Logging -Success $false
    exit 1
}
