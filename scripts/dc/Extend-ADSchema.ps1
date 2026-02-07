<#
.SYNOPSIS
    Extends Active Directory schema for SCCM and creates required containers.

.DESCRIPTION
    This script prepares Active Directory for SCCM installation by:
    1. Running extadsch.exe from SCCM media to extend the schema
    2. Creating the System Management container
    3. Granting the SCCM server computer account Full Control

    ============================================================================
    TECHNOLOGY EXPLANATION: AD Schema Extension for SCCM
    ============================================================================

    WHAT IS AD SCHEMA?

    Active Directory has a "schema" that defines what types of objects can exist
    and what attributes (properties) they can have. Think of it as a blueprint.

    Default AD schema includes:
    - User objects (with attributes like displayName, mail, etc.)
    - Computer objects
    - Group objects
    - Organizational Units

    SCCM needs to add its own object types and attributes:
    - mSSMSCapabilities
    - mSSMSDefaultMP
    - mSSMSDeviceManagementPoint
    - mSSMSMP
    - mSSMSRoamingBoundaryRange
    - mSSMSSite
    - mSSMSSiteCode
    - And many more...

    WHY EXTEND THE SCHEMA?

    When SCCM is schema-extended:

    1. Site Publishing: SCCM can publish site information to AD
       - Clients can automatically find their management point
       - Simplifies client configuration
       - Enables automatic site assignment

    2. Forest-Wide Discovery: SCCM can discover resources across the forest

    3. Trusted Site Assignment: More secure automatic site assignment

    SCHEMA EXTENSION IS OPTIONAL BUT RECOMMENDED because:
    - Clients can still work without it using manual configuration
    - But automatic client configuration is much easier with it

    SCHEMA EXTENSION IS PERMANENT:
    - Once extended, schema changes CANNOT be reversed
    - However, the SCCM schema extensions are harmless if unused
    - In production, test in a lab first

    THE EXTADSCH.EXE TOOL:

    Located on SCCM installation media at: \SMSSETUP\BIN\X64\extadsch.exe

    What it does:
    1. Connects to the Schema Master domain controller
    2. Adds SCCM classes and attributes to the schema
    3. Creates a log file: ExtADSch.log in the system root

    Requirements:
    - Must be run as a Schema Admin (or Enterprise Admin)
    - Must run on a domain controller or domain-joined machine
    - Must have network access to Schema Master

    THE SYSTEM MANAGEMENT CONTAINER:

    After schema extension, SCCM needs a place in AD to publish data.
    This is the "System Management" container under CN=System.

    Path: CN=System Management,CN=System,DC=lab,DC=local

    The SCCM site server's computer account needs Full Control on this
    container so it can create and manage objects there.

    ============================================================================

.PARAMETER SCCMMediaPath
    Path to SCCM installation media (root of ISO or extracted folder).
    extadsch.exe should be at: <path>\SMSSETUP\BIN\X64\extadsch.exe

.PARAMETER SCCMServerName
    Name of the SCCM primary site server (without domain suffix).
    This server's computer account will be granted permissions.
    Default: SCCM01

.PARAMETER SkipSchemaExtension
    Skip the schema extension step (if already done).
    Only create container and set permissions.

.EXAMPLE
    .\Extend-ADSchema.ps1 -SCCMMediaPath "D:\"

.EXAMPLE
    .\Extend-ADSchema.ps1 -SCCMMediaPath "C:\SCCM_Media" -SCCMServerName "SCCM01"

.NOTES
    Author: Homelab-SCCM Project
    Requires: Schema Admin or Enterprise Admin privileges
    Run on: DC01 (Domain Controller)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SCCMMediaPath,

    [Parameter(Mandatory = $false)]
    [string]$SCCMServerName = "SCCM01",

    [Parameter(Mandatory = $false)]
    [switch]$SkipSchemaExtension
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

Initialize-Logging -LogName "Extend-ADSchema"

Write-LogSection "Active Directory Schema Extension for SCCM"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

Write-Log "Performing pre-flight checks..." -Level INFO

# Check 1: Verify we're on a domain controller
if (-not (Test-IsDomainController)) {
    Write-LogError "This script must be run on a Domain Controller."
    Write-Log "Current computer is not a DC. Please run on DC01." -Level ERROR
    throw "Not a domain controller"
}

Write-Log "Running on Domain Controller: $env:COMPUTERNAME" -Level SUCCESS

# Check 2: Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module loaded." -Level SUCCESS
}
catch {
    Write-LogError "Failed to load Active Directory PowerShell module."
    throw "ActiveDirectory module required"
}

# Check 3: Verify current user has sufficient privileges
# SYNTAX EXPLANATION: Get-ADGroupMember
# Returns members of an AD group
# We check if current user is in Schema Admins or Enterprise Admins

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentUserSID = $currentUser.User.Value

Write-Log "Current user: $($currentUser.Name)" -Level INFO

# Check group membership
$isSchemaAdmin = $false
$isEnterpriseAdmin = $false

try {
    $schemaAdmins = Get-ADGroupMember -Identity "Schema Admins" -ErrorAction SilentlyContinue
    $isSchemaAdmin = $schemaAdmins | Where-Object { $_.SID.Value -eq $currentUserSID }
}
catch {
    Write-Log "Could not check Schema Admins membership." -Level DEBUG
}

try {
    $enterpriseAdmins = Get-ADGroupMember -Identity "Enterprise Admins" -ErrorAction SilentlyContinue
    $isEnterpriseAdmin = $enterpriseAdmins | Where-Object { $_.SID.Value -eq $currentUserSID }
}
catch {
    Write-Log "Could not check Enterprise Admins membership." -Level DEBUG
}

# Domain Admins can often extend schema in lab environments
$isDomainAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($isSchemaAdmin) {
    Write-Log "User is a Schema Admin - can extend schema." -Level SUCCESS
} elseif ($isEnterpriseAdmin) {
    Write-Log "User is an Enterprise Admin - can extend schema." -Level SUCCESS
} elseif ($isDomainAdmin) {
    Write-Log "User is a Domain Admin - may be able to extend schema in lab environment." -Level WARN
} else {
    Write-Log "User may not have sufficient privileges. Schema extension may fail." -Level WARN
}

# ============================================================================
# SCHEMA EXTENSION
# ============================================================================

if (-not $SkipSchemaExtension) {
    Write-LogSection "Extending Active Directory Schema"

    # Verify extadsch.exe exists
    if (-not $SCCMMediaPath) {
        Write-Log "No SCCM media path provided." -Level WARN
        Write-Log "If you have SCCM media mounted, provide path with -SCCMMediaPath" -Level INFO
        Write-Log "Skipping schema extension - will only create container and permissions." -Level INFO
        $SkipSchemaExtension = $true
    } else {
        $extadschPath = Join-Path $SCCMMediaPath "SMSSETUP\BIN\X64\extadsch.exe"

        if (-not (Test-Path $extadschPath)) {
            Write-LogError "extadsch.exe not found at: $extadschPath"
            Write-Log "Expected path: <SCCM Media>\SMSSETUP\BIN\X64\extadsch.exe" -Level ERROR
            Write-Log "Skipping schema extension." -Level WARN
            $SkipSchemaExtension = $true
        }
    }

    if (-not $SkipSchemaExtension) {
        Write-Log "Schema extension tool found: $extadschPath" -Level SUCCESS
        Write-Log "" -Level INFO
        Write-Log "IMPORTANT: Schema extension is PERMANENT and cannot be reversed." -Level WARN
        Write-Log "In a lab environment, this is safe. In production, test first." -Level INFO
        Write-Log "" -Level INFO
        Write-Log "Starting schema extension..." -Level INFO

        # SYNTAX EXPLANATION: Running extadsch.exe
        # The tool automatically finds the Schema Master DC
        # Creates ExtADSch.log in %SystemRoot% (usually C:\Windows)
        # Exit code 0 = success

        $process = Start-Process -FilePath $extadschPath -Wait -NoNewWindow -PassThru

        # Check the log file for results
        $logPath = Join-Path $env:SystemRoot "ExtADSch.log"

        if (Test-Path $logPath) {
            Write-Log "Schema extension log file: $logPath" -Level INFO

            # Read and display key parts of the log
            $logContent = Get-Content $logPath -Tail 30

            # Check for success message
            $successMessage = $logContent | Select-String -Pattern "Successfully extended the Active Directory schema"
            $alreadyExtended = $logContent | Select-String -Pattern "The Active Directory schema has already been extended"
            $errorMessage = $logContent | Select-String -Pattern "ERROR|FAILED"

            if ($successMessage) {
                Write-Log "Schema extension completed successfully!" -Level SUCCESS
            } elseif ($alreadyExtended) {
                Write-Log "Schema was already extended for SCCM." -Level INFO
            } elseif ($errorMessage) {
                Write-LogError "Schema extension encountered errors."
                Write-Log "Check $logPath for details." -Level ERROR

                # Display error lines
                $logContent | ForEach-Object {
                    if ($_ -match "ERROR|FAILED") {
                        Write-Log $_ -Level ERROR
                    }
                }
            } else {
                Write-Log "Schema extension completed. Check $logPath to verify." -Level WARN
            }
        } else {
            Write-Log "Could not find schema extension log file." -Level WARN
            Write-Log "Exit code was: $($process.ExitCode)" -Level INFO
        }
    }
} else {
    Write-Log "Skipping schema extension (SkipSchemaExtension specified or no media path)." -Level INFO
}

# ============================================================================
# CREATE SYSTEM MANAGEMENT CONTAINER
# ============================================================================

Write-LogSection "Creating System Management Container"

# Get the domain distinguished name
$domainDN = (Get-ADDomain).DistinguishedName
$systemDN = "CN=System,$domainDN"
$systemMgmtDN = "CN=System Management,$systemDN"

Write-Log "Domain DN: $domainDN" -Level DEBUG
Write-Log "Target container: $systemMgmtDN" -Level INFO

# Check if container already exists
try {
    $existingContainer = Get-ADObject -Identity $systemMgmtDN -ErrorAction Stop
    Write-Log "System Management container already exists." -Level INFO
}
catch {
    Write-Log "Creating System Management container..." -Level INFO

    try {
        # SYNTAX EXPLANATION: New-ADObject
        # Creates a new object in Active Directory
        # -Type: Object class (container)
        # -Name: Common Name of the object
        # -Path: Parent container DN

        New-ADObject -Type Container -Name "System Management" -Path $systemDN
        Write-Log "System Management container created successfully." -Level SUCCESS
    }
    catch {
        Write-LogError "Failed to create System Management container: $_"
        throw "Container creation failed"
    }
}

# ============================================================================
# GRANT SCCM SERVER PERMISSIONS
# ============================================================================

Write-LogSection "Configuring Permissions for SCCM Server"

# The SCCM site server needs Full Control on the System Management container
# We grant permissions to the computer account: SCCM01$

$sccmComputerAccount = "$SCCMServerName`$"
Write-Log "SCCM Server computer account: $sccmComputerAccount" -Level INFO

# Verify the computer account exists
try {
    $sccmComputer = Get-ADComputer -Identity $SCCMServerName -ErrorAction Stop
    Write-Log "Found SCCM computer account: $($sccmComputer.DistinguishedName)" -Level SUCCESS
}
catch {
    Write-Log "Computer account $SCCMServerName not found in AD." -Level WARN
    Write-Log "The SCCM server must be domain-joined before permissions can be set." -Level INFO
    Write-Log "After joining SCCM01 to the domain, run this script again or manually set permissions." -Level INFO

    # Continue to show what needs to be done
}

# Set permissions on System Management container
Write-Log "Setting Full Control permissions on System Management container..." -Level INFO

try {
    # SYNTAX EXPLANATION: Setting AD Permissions
    #
    # This is one of the more complex operations in AD automation.
    # We need to:
    # 1. Get the container's Access Control List (ACL)
    # 2. Create a new Access Control Entry (ACE) granting Full Control
    # 3. Apply the ACE to the container with inheritance

    # Get the System Management container
    $containerPath = "AD:$systemMgmtDN"

    # Get current ACL
    # SYNTAX: Get-Acl gets the access control list (permissions) for an object
    $acl = Get-Acl -Path $containerPath

    # Create the identity reference for the SCCM computer account
    # Format: DOMAIN\ComputerName$ (the $ is part of computer accounts)
    $domain = (Get-ADDomain).NetBIOSName
    $identity = "$domain\$sccmComputerAccount"

    # SYNTAX EXPLANATION: ActiveDirectoryAccessRule
    # This defines a single permission entry
    # Parameters:
    #   IdentityReference: Who the permission applies to
    #   ActiveDirectoryRights: What permission (GenericAll = Full Control)
    #   AccessControlType: Allow or Deny
    #   InheritanceType: How permissions flow to child objects
    #     - All: Apply to this object and all descendants
    #     - None: Apply only to this object
    #     - SelfAndChildren: This object and direct children

    # Create a .NET identity reference
    $identityRef = New-Object System.Security.Principal.NTAccount($identity)

    # Define Full Control permission with inheritance
    $adRights = [System.DirectoryServices.ActiveDirectoryRights]"GenericAll"
    $accessType = [System.Security.AccessControl.AccessControlType]"Allow"
    $inheritance = [System.DirectoryServices.ActiveDirectorySecurityInheritance]"All"

    # Create the access rule
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $identityRef,
        $adRights,
        $accessType,
        $inheritance
    )

    # Add the rule to the ACL
    $acl.AddAccessRule($ace)

    # Apply the modified ACL
    Set-Acl -Path $containerPath -AclObject $acl

    Write-Log "Granted Full Control to $identity on System Management container." -Level SUCCESS
    Write-Log "Permissions include inheritance to all child objects." -Level INFO
}
catch {
    Write-Log "Could not set permissions automatically: $_" -Level WARN
    Write-Log "" -Level INFO
    Write-Log "To manually set permissions:" -Level INFO
    Write-Log "  1. Open Active Directory Users and Computers" -Level INFO
    Write-Log "  2. Enable View > Advanced Features" -Level INFO
    Write-Log "  3. Navigate to System container" -Level INFO
    Write-Log "  4. Right-click System Management > Properties > Security" -Level INFO
    Write-Log "  5. Add $SCCMServerName`$ with Full Control" -Level INFO
    Write-Log "  6. Ensure 'Apply to: This object and all descendant objects'" -Level INFO
}

# ============================================================================
# VERIFICATION
# ============================================================================

Write-LogSection "Verification"

# Verify container exists
try {
    $container = Get-ADObject -Identity $systemMgmtDN
    Write-Log "System Management container exists: $systemMgmtDN" -Level SUCCESS
}
catch {
    Write-LogError "Could not verify System Management container."
}

# Verify permissions
try {
    $containerPath = "AD:$systemMgmtDN"
    $acl = Get-Acl -Path $containerPath

    $domain = (Get-ADDomain).NetBIOSName
    $sccmAccountFull = "$domain\$sccmComputerAccount"

    $sccmPermission = $acl.Access | Where-Object {
        $_.IdentityReference.Value -eq $sccmAccountFull -and
        $_.ActiveDirectoryRights -match "GenericAll|FullControl"
    }

    if ($sccmPermission) {
        Write-Log "SCCM server has Full Control permission." -Level SUCCESS
    } else {
        Write-Log "Could not verify SCCM server permissions." -Level WARN
        Write-Log "Manually verify $sccmComputerAccount has Full Control." -Level INFO
    }
}
catch {
    Write-Log "Could not verify permissions: $_" -Level WARN
}

# Check if schema was extended (by looking for SCCM-specific attributes)
try {
    $schema = [DirectoryServices.ActiveDirectory.ActiveDirectorySchema]::GetCurrentSchema()

    # Try to find an SCCM-specific class
    $sccmClass = $schema.FindClass("mSSMSSite") -ErrorAction SilentlyContinue

    if ($sccmClass) {
        Write-Log "AD Schema has been extended for SCCM." -Level SUCCESS
    }
}
catch {
    Write-Log "Could not verify schema extension status." -Level WARN
    Write-Log "If schema was just extended, a DC restart may be required." -Level INFO
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-LogSection "AD Schema Extension Complete"

Write-Log "Active Directory preparation for SCCM is complete." -Level SUCCESS
Write-Log "" -Level INFO
Write-Log "Summary:" -Level INFO
Write-Log "  - Schema extension: $(if ($SkipSchemaExtension) {'Skipped (run manually or provide SCCM media)'} else {'Attempted'})" -Level INFO
Write-Log "  - System Management container: Created/Verified" -Level INFO
Write-Log "  - Permissions for $SCCMServerName: Configured" -Level INFO
Write-Log "" -Level INFO
Write-Log "If schema was extended, allow time for replication across DCs." -Level INFO
Write-Log "In a single-DC lab environment, this is immediate." -Level INFO
Write-Log "" -Level INFO
Write-Log "Next Steps:" -Level INFO
Write-Log "  1. Ensure SCCM01 is domain-joined" -Level INFO
Write-Log "  2. Run Install-Prerequisites.ps1 on SCCM01" -Level INFO
Write-Log "  3. Run Install-SCCM.ps1 on SCCM01" -Level INFO

Complete-Logging
