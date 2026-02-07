#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Joins this computer to the lab.local Active Directory domain.

.DESCRIPTION
    This script joins the computer to the lab.local domain and moves it to
    the appropriate Organizational Unit (OU).

    WHAT HAPPENS DURING DOMAIN JOIN:
    ---------------------------------
    1. DNS lookup finds the domain controller (using _ldap._tcp.lab.local)
    2. Computer contacts DC and authenticates with provided credentials
    3. Computer account is created in Active Directory
    4. Computer receives a machine account password
    5. Computer's security identifier (SID) is updated
    6. Local security settings are modified to trust the domain
    7. REBOOT is required to complete the process

    AFTER DOMAIN JOIN:
    ------------------
    - Domain users can log in to this computer
    - Group Policies will apply
    - The computer can access domain resources
    - Domain administrators have local admin access

    WHY THE REBOOT:
    ---------------
    The domain join process modifies fundamental security settings:
    - The computer's trust relationship with the domain
    - Local security policies
    - The Security Accounts Manager (SAM)
    - Network authentication providers

    These changes require a reboot to take effect properly.

.PARAMETER DomainName
    The domain to join. Defaults to "lab.local".

.PARAMETER DomainUser
    The user account to use for joining. Defaults to "Administrator".
    Must have permission to join computers to the domain.

.PARAMETER DomainPassword
    The password for the domain user. If not provided, will prompt or use default.

.PARAMETER TargetOU
    The OU to place the computer in. Auto-detected based on OS type if not specified.
    - Servers -> OU=Servers,DC=lab,DC=local
    - Workstations -> OU=Workstations,DC=lab,DC=local

.PARAMETER NewComputerName
    Optionally rename the computer during domain join.

.PARAMETER NoReboot
    Don't reboot automatically (you must reboot manually).

.PARAMETER Force
    Skip confirmation prompts and use default password.

.EXAMPLE
    .\Join-LabDomain.ps1

.EXAMPLE
    .\Join-LabDomain.ps1 -TargetOU "OU=Servers,DC=lab,DC=local" -Force

.EXAMPLE
    $securePass = ConvertTo-SecureString "vagrant" -AsPlainText -Force
    .\Join-LabDomain.ps1 -DomainPassword $securePass -NoReboot

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - DNS must be configured to point to DC01 (run Set-LabDNS.ps1 first)
    - DC01 must be running and reachable
    - Domain must exist

    RUN THIS ON:
    - SCCM01 (to join the SCCM server to the domain)
    - CLIENT01, CLIENT02, etc. (to join clients to the domain)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

    [Parameter(Mandatory = $false)]
    [string]$DomainUser = "Administrator",

    [Parameter(Mandatory = $false)]
    [SecureString]$DomainPassword = $null,

    [Parameter(Mandatory = $false)]
    [string]$TargetOU = $null,

    [Parameter(Mandatory = $false)]
    [string]$NewComputerName = $null,

    [Parameter(Mandatory = $false)]
    [switch]$NoReboot,

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
    # Fallback if modules not available
    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        $colors = @{ DEBUG = 'Gray'; INFO = 'White'; SUCCESS = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
    }
    function Initialize-Logging { param([string]$ScriptName) }
    function Complete-Logging { param([bool]$Success) }
    function Write-LogSection { param([string]$Title) Write-Host "`n=== $Title ===`n" -ForegroundColor Cyan }
    function Write-LogError { param($ErrorRecord, [string]$Message) Write-Log "$Message : $($ErrorRecord.Exception.Message)" -Level ERROR }
    function Test-DomainJoined { param([string]$ExpectedDomain) return ((Get-CimInstance Win32_ComputerSystem).Domain -eq $ExpectedDomain) }
}

Initialize-Logging -ScriptName "Join-LabDomain"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default password for domain admin (matches Vagrant setup)
$DefaultPassword = "vagrant"

# Domain DN components
$DomainDN = "DC=" + ($DomainName -replace '\.', ',DC=')

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Joining Domain: $DomainName"

    # -------------------------------------------------------------------------
    # STEP 1: Check if Already Domain Joined
    # -------------------------------------------------------------------------
    Write-Log "Checking current domain membership..." -Level INFO

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem

    Write-Log "  Computer Name: $($computerSystem.Name)" -Level INFO
    Write-Log "  Current Domain/Workgroup: $($computerSystem.Domain)" -Level INFO

    if (Test-DomainJoined -ExpectedDomain $DomainName) {
        Write-Log "This computer is already joined to $DomainName!" -Level SUCCESS
        Write-Log "No action needed." -Level INFO
        Complete-Logging -Success $true
        exit 0
    }

    if ($computerSystem.PartOfDomain) {
        Write-Log "This computer is joined to a DIFFERENT domain: $($computerSystem.Domain)" -Level WARN
        Write-Log "You must remove it from the current domain first." -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    Write-Log "  Computer is currently in workgroup mode" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 2: Test DNS Resolution
    # -------------------------------------------------------------------------
    Write-LogSection "Testing DNS Resolution"

    Write-Log "Verifying DNS can resolve the domain..." -Level INFO

    <#
    DOMAIN JOIN DNS REQUIREMENTS:
    -----------------------------
    For domain join to work, DNS must be able to resolve:
    1. The domain name (lab.local) - finds domain controllers
    2. _ldap._tcp.lab.local (SRV) - LDAP service location
    3. _kerberos._tcp.lab.local (SRV) - Kerberos authentication

    If these don't resolve, domain join will fail with:
    "The specified domain either does not exist or could not be contacted"
    #>

    # Test basic domain resolution
    try {
        $domainResult = Resolve-DnsName -Name $DomainName -Type A -ErrorAction Stop
        Write-Log "  $DomainName resolves to $($domainResult.IPAddress -join ', ')" -Level SUCCESS
    }
    catch {
        Write-Log "  Cannot resolve $DomainName!" -Level ERROR
        Write-Log "  Have you run Set-LabDNS.ps1 to configure DNS?" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # Test LDAP SRV record
    try {
        $ldapSrv = Resolve-DnsName -Name "_ldap._tcp.$DomainName" -Type SRV -ErrorAction Stop
        Write-Log "  LDAP SRV record found: $($ldapSrv.NameTarget -join ', ')" -Level SUCCESS
    }
    catch {
        Write-Log "  Cannot resolve LDAP SRV record!" -Level WARN
        Write-Log "  Domain join may fail. Is DC01 fully promoted?" -Level WARN
    }

    # Test connectivity to DC
    $dcIP = "192.168.56.10"
    Write-Log "Testing connectivity to DC ($dcIP)..." -Level INFO

    $pingResult = Test-Connection -ComputerName $dcIP -Count 2 -Quiet
    if ($pingResult) {
        Write-Log "  DC is reachable" -Level SUCCESS
    }
    else {
        Write-Log "  WARNING: DC is not responding to ping!" -Level WARN
    }

    # -------------------------------------------------------------------------
    # STEP 3: Determine Target OU
    # -------------------------------------------------------------------------
    Write-Log "Determining target OU..." -Level INFO

    if ([string]::IsNullOrEmpty($TargetOU)) {
        # Auto-detect based on OS
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem

        <#
        OU SELECTION LOGIC:
        -------------------
        - Windows Server -> Servers OU
        - Windows 10/11 -> Workstations OU
        - Unknown -> Computers container (default)
        #>

        if ($osInfo.Caption -like "*Server*") {
            $TargetOU = "OU=Servers,$DomainDN"
            Write-Log "  OS is Windows Server, using Servers OU" -Level INFO
        }
        else {
            $TargetOU = "OU=Workstations,$DomainDN"
            Write-Log "  OS is Windows Client, using Workstations OU" -Level INFO
        }
    }

    Write-Log "  Target OU: $TargetOU" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 4: Handle Credentials
    # -------------------------------------------------------------------------
    Write-Log "Configuring domain credentials..." -Level INFO

    if ($null -eq $DomainPassword) {
        if ($Force) {
            Write-Log "Using default password (automated mode)" -Level WARN
            $DomainPassword = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
        }
        else {
            Write-Log "Enter the password for $DomainName\$DomainUser" -Level INFO
            $DomainPassword = Read-Host "Password" -AsSecureString
        }
    }

    # Create credential object
    $credential = New-Object System.Management.Automation.PSCredential(
        "$DomainName\$DomainUser",
        $DomainPassword
    )

    # -------------------------------------------------------------------------
    # STEP 5: Display Summary and Confirm
    # -------------------------------------------------------------------------
    Write-LogSection "Domain Join Summary"

    Write-Log "Computer Name:    $env:COMPUTERNAME" -Level INFO
    Write-Log "Domain:           $DomainName" -Level INFO
    Write-Log "Target OU:        $TargetOU" -Level INFO
    Write-Log "Join Account:     $DomainName\$DomainUser" -Level INFO

    if ($NewComputerName) {
        Write-Log "New Name:         $NewComputerName" -Level INFO
    }

    if ($NoReboot) {
        Write-Log "Auto-Reboot:      NO (manual reboot required)" -Level WARN
    }
    else {
        Write-Log "Auto-Reboot:      YES" -Level WARN
    }

    if (-not $Force) {
        Write-Log "" -Level INFO
        Write-Log "WARNING: This will join the computer to the domain." -Level WARN
        if (-not $NoReboot) {
            Write-Log "The computer will REBOOT automatically!" -Level WARN
        }
        Write-Log "" -Level INFO

        $confirm = Read-Host "Continue? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "Domain join cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 6: Join the Domain
    # -------------------------------------------------------------------------
    Write-LogSection "Joining Domain"

    Write-Log "Executing domain join..." -Level INFO

    <#
    ADD-COMPUTER PARAMETERS:
    ------------------------
    -DomainName: The domain to join
    -Credential: Account with permission to join computers
    -OUPath: Where to create the computer account
    -NewName: Optionally rename the computer
    -Restart: Reboot after joining
    -Force: Don't prompt for confirmation

    The -OUPath parameter requires the OU to exist and the joining account
    to have "Create Computer Objects" permission in that OU.

    Common errors:
    - "Access denied" = Account doesn't have permission
    - "OU not found" = OU doesn't exist or wrong path
    - "Network path not found" = DNS not resolving domain
    #>

    $addComputerParams = @{
        DomainName = $DomainName
        Credential = $credential
        Force      = $true
    }

    # Add OUPath if we have a target OU
    if (-not [string]::IsNullOrEmpty($TargetOU)) {
        $addComputerParams['OUPath'] = $TargetOU
    }

    # Add new computer name if specified
    if (-not [string]::IsNullOrEmpty($NewComputerName)) {
        $addComputerParams['NewName'] = $NewComputerName
    }

    # Handle reboot
    if (-not $NoReboot) {
        $addComputerParams['Restart'] = $true
    }

    # Execute domain join
    Add-Computer @addComputerParams

    # If we get here without rebooting, the join succeeded
    Write-Log "Domain join completed successfully!" -Level SUCCESS

    if ($NoReboot) {
        Write-Log "" -Level INFO
        Write-Log "IMPORTANT: You must reboot to complete the domain join!" -Level WARN
        Write-Log "Run: Restart-Computer -Force" -Level INFO
        Write-Log "" -Level INFO
        Write-Log "After reboot:" -Level INFO
        Write-Log "  - Login with: $DomainName\Administrator" -Level INFO
        Write-Log "  - Or continue using local vagrant account" -Level INFO
    }
    else {
        Write-Log "The computer will reboot now..." -Level INFO
        Write-Log "" -Level INFO
        Write-Log "After reboot, login with: $DomainName\Administrator" -Level INFO
    }

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "Domain join failed"

    # Provide specific guidance for common errors
    $errorMessage = $_.Exception.Message.ToLower()

    if ($errorMessage -match "network path" -or $errorMessage -match "not exist" -or $errorMessage -match "could not be contacted") {
        Write-Log "" -Level INFO
        Write-Log "HINT: DNS might not be configured correctly." -Level INFO
        Write-Log "Run Set-LabDNS.ps1 first to point DNS to DC01." -Level INFO
        Write-Log "Verify with: Resolve-DnsName lab.local" -Level INFO
    }
    elseif ($errorMessage -match "access" -or $errorMessage -match "denied" -or $errorMessage -match "password") {
        Write-Log "" -Level INFO
        Write-Log "HINT: The credentials might be incorrect." -Level INFO
        Write-Log "Default: lab.local\Administrator with password 'vagrant'" -Level INFO
    }
    elseif ($errorMessage -match "ou" -or $errorMessage -match "organizational unit") {
        Write-Log "" -Level INFO
        Write-Log "HINT: The target OU might not exist." -Level INFO
        Write-Log "Run Create-OUs.ps1 on DC01 first." -Level INFO
        Write-Log "Or try without specifying -TargetOU" -Level INFO
    }
    elseif ($errorMessage -match "already" -or $errorMessage -match "duplicate") {
        Write-Log "" -Level INFO
        Write-Log "HINT: A computer with this name might already exist in AD." -Level INFO
        Write-Log "Try using -NewComputerName to specify a different name," -Level INFO
        Write-Log "or delete the existing account in AD Users and Computers." -Level INFO
    }

    Complete-Logging -Success $false
    exit 1
}
