#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates and links Group Policy Objects (GPOs) for the SCCM lab environment.

.DESCRIPTION
    This script creates the baseline GPOs needed for the lab to function correctly.
    GPOs are the authoritative source of policy for all domain-joined machines —
    rather than configuring clients individually, policy is defined here on the DC
    and automatically applied to every machine in the relevant OU.

    WHAT IS A GPO?
    --------------
    A Group Policy Object (GPO) is a collection of settings that Windows applies
    to computers and/or users in Active Directory. GPOs are linked to OUs, sites,
    or the domain itself. When a machine boots (or a user logs in), Windows
    downloads and applies all GPOs that target it.

    GPO PROCESSING ORDER (LSDOU):
    ------------------------------
    GPOs are applied in this order (later overrides earlier):
    1. Local  - Settings on the machine itself
    2. Site   - GPOs linked to the AD site
    3. Domain - GPOs linked to the domain root
    4. OU     - GPOs linked to the OU containing the object
              - Nested OUs: parent OU applied before child OU

    This means an OU-level GPO wins over a domain-level GPO when they conflict.
    We use this to apply different firewall rules to Workstations vs. Servers.

    COMPUTER vs. USER SETTINGS:
    ----------------------------
    Each GPO has two halves:
    - Computer Configuration: Applied when the machine boots, regardless of who
      logs in. Firewall rules, startup scripts, software deployment go here.
    - User Configuration: Applied when a user logs in. Desktop settings,
      login scripts, mapped drives go here.

    Our firewall GPO uses Computer Configuration only, since firewall rules
    are machine-level policy, not per-user.

    GPUPDATE AND REFRESH:
    ---------------------
    By default, Windows refreshes GPOs every 90 minutes (± 30 min random offset)
    for computers, and at logon for users. You can force immediate refresh with:
        gpupdate /force
    Computer settings (like firewall rules) require either a refresh cycle or
    reboot to take full effect after the GPO is first linked.

    GPOs CREATED BY THIS SCRIPT:
    -----------------------------

    1. "Lab - Workstation Firewall Policy" (linked to OU=Workstations)
       Purpose: Opens the ports SCCM and general lab management require on clients.
       Settings (Computer Configuration > Windows Firewall):
         - ICMPv4 Echo Request (ping) inbound - All profiles
         - File and Printer Sharing (SMB TCP 445) - All profiles
         - Remote Procedure Call (TCP 135) - All profiles
         - WinRM HTTP (TCP 5985) - Domain profile
         - WinRM HTTPS (TCP 5986) - Domain profile

    2. "Lab - Server Firewall Policy" (linked to OU=Servers)
       Purpose: Opens management ports on servers. Servers already have
       role-specific ports opened by their respective setup scripts (e.g.,
       SQL 1433 opened by Install-SQLServer.ps1), so this GPO covers the
       common management baseline only.
       Settings (Computer Configuration > Windows Firewall):
         - ICMPv4 Echo Request (ping) inbound - All profiles
         - WinRM HTTP (TCP 5985) - Domain profile
         - WinRM HTTPS (TCP 5986) - Domain profile

    WHY SEPARATE WORKSTATION AND SERVER GPOs?
    ------------------------------------------
    Servers and workstations have different security requirements:
    - Workstations need SMB (445) and RPC (135) open for SCCM client push
    - Servers should have tighter rules; their role scripts open specific ports
    - Separation allows future customisation without affecting the other OU

    WHY NOT JUST DISABLE THE FIREWALL?
    ------------------------------------
    A common shortcut in lab setups is to disable Windows Firewall entirely.
    This lab deliberately avoids that because:
    - SCCM/ConfigMgr real-world deployments always run with firewall enabled
    - Learning which ports each component needs is part of the lab's value
    - Disabling the firewall masks problems that would appear in production

.PARAMETER DomainName
    The domain name. Defaults to "lab.local".

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Configure-GPOs.ps1

.EXAMPLE
    .\Configure-GPOs.ps1 -Force

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0

    PREREQUISITES:
    - Server must be a domain controller
    - OUs must exist (run Create-OUs.ps1 first)
    - GroupPolicy PowerShell module available (installed with GPMC feature)

    RUN ORDER:
    - After: Promote-DC.ps1, Configure-DNS.ps1, Create-OUs.ps1
    - Before: Clients join the domain (so policy is ready on first join)

    SCCM-SPECIFIC PORTS (opened here on workstations):
    - TCP 445  (SMB)  - Client push installation, software distribution
    - TCP 135  (RPC)  - Remote administration, client push
    - ICMP            - Client health monitoring, ping-based discovery
    - TCP 5985 (WinRM)- Remote PowerShell management from host
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "lab.local",

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

Initialize-Logging -ScriptName "Configure-GPOs"

# =============================================================================
# CONFIGURATION
# =============================================================================

# GPO definitions
# Each entry defines a GPO name, the OU it links to, and the firewall rules
# to create inside it.
#
# FirewallRules format:
#   Name        - Unique rule name (used as the registry value name in the GPO)
#   DisplayName - Friendly name shown in Group Policy Management Console
#   Direction   - "Inbound" or "Outbound"
#   Protocol    - "TCP", "UDP", or "ICMPv4"
#   LocalPort   - Port number(s), or $null for ICMP
#   IcmpType    - ICMP type number, or $null for TCP/UDP ("8" = Echo Request)
#   Profile     - "Any", "Domain", "Private", "Public", or combinations
#   Action      - "Allow" or "Block"
#   Description - Explains why this port is needed (shown in GPMC)

$GPODefinitions = @(
    @{
        Name        = "Lab - Workstation Firewall Policy"
        OUPath      = "OU=Workstations"
        Description = "Baseline firewall rules for SCCM-managed workstations"
        FirewallRules = @(
            @{
                Name        = "Lab-ICMPv4-Echo-In"
                DisplayName = "Lab - ICMPv4 Echo Request (Ping) Inbound"
                Direction   = "Inbound"
                Protocol    = "ICMPv4"
                LocalPort   = $null
                IcmpType    = "8"
                Profile     = "Any"
                Action      = "Allow"
                Description = "Allows ping from DC/SCCM for client health monitoring and discovery"
            }
            @{
                Name        = "Lab-SMB-In"
                DisplayName = "Lab - SMB Inbound (TCP 445)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "445"
                IcmpType    = $null
                Profile     = "Any"
                Action      = "Allow"
                Description = "Required for SCCM client push installation and software distribution"
            }
            @{
                Name        = "Lab-RPC-In"
                DisplayName = "Lab - RPC Inbound (TCP 135)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "135"
                IcmpType    = $null
                Profile     = "Any"
                Action      = "Allow"
                Description = "Required for SCCM client push and remote administration"
            }
            @{
                Name        = "Lab-WinRM-HTTP-In"
                DisplayName = "Lab - WinRM HTTP Inbound (TCP 5985)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "5985"
                IcmpType    = $null
                Profile     = "Domain"
                Action      = "Allow"
                Description = "Allows PowerShell remoting from the lab host machine"
            }
            @{
                Name        = "Lab-WinRM-HTTPS-In"
                DisplayName = "Lab - WinRM HTTPS Inbound (TCP 5986)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "5986"
                IcmpType    = $null
                Profile     = "Domain"
                Action      = "Allow"
                Description = "Allows encrypted PowerShell remoting from the lab host machine"
            }
        )
    }
    @{
        Name        = "Lab - Server Firewall Policy"
        OUPath      = "OU=Servers"
        Description = "Baseline firewall rules for lab servers (DC, SCCM). Role-specific ports are opened by individual setup scripts."
        FirewallRules = @(
            @{
                Name        = "Lab-ICMPv4-Echo-In"
                DisplayName = "Lab - ICMPv4 Echo Request (Ping) Inbound"
                Direction   = "Inbound"
                Protocol    = "ICMPv4"
                LocalPort   = $null
                IcmpType    = "8"
                Profile     = "Any"
                Action      = "Allow"
                Description = "Allows ping for server health monitoring"
            }
            @{
                Name        = "Lab-WinRM-HTTP-In"
                DisplayName = "Lab - WinRM HTTP Inbound (TCP 5985)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "5985"
                IcmpType    = $null
                Profile     = "Domain"
                Action      = "Allow"
                Description = "Allows PowerShell remoting from the lab host machine"
            }
            @{
                Name        = "Lab-WinRM-HTTPS-In"
                DisplayName = "Lab - WinRM HTTPS Inbound (TCP 5986)"
                Direction   = "Inbound"
                Protocol    = "TCP"
                LocalPort   = "5986"
                IcmpType    = $null
                Profile     = "Domain"
                Action      = "Allow"
                Description = "Allows encrypted PowerShell remoting from the lab host machine"
            }
        )
    }
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Add-GPOFirewallRule {
    <#
    .SYNOPSIS
        Writes a firewall rule into a GPO via the registry.

    .DESCRIPTION
        GPO firewall rules are stored as registry values under:
            HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules

        Each value name is the rule's unique identifier. The value data is a
        semicolon-delimited string encoding all rule properties.

        This function writes that registry value into the GPO using
        Set-GPRegistryValue, which modifies the GPO's registry.pol file
        without needing to apply the policy to a live machine.

        FORMAT OF THE VALUE DATA STRING:
        ---------------------------------
        The format is a versioned, semicolon-delimited string:
            v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|
            Name=Rule Name|Desc=Description|

        Key fields:
            Action   - Allow or Block
            Active   - TRUE (rule is enabled)
            Dir      - In or Out
            Protocol - 6=TCP, 17=UDP, 1=ICMPv4, 58=ICMPv6
            LPort    - Local port(s), or omitted for ICMP
            ICMP4    - ICMP type:code (e.g., 8:* for echo request), for ICMPv4
            Profile  - Domain=2, Private=4, Public=8, Any=2147483647
            Name     - Display name
            Desc     - Description

        PROFILE BITMASK:
        -----------------
        Windows firewall profiles use a bitmask:
            Domain  = 2
            Private = 4
            Public  = 8
            Any     = 2147483647 (all profiles, 0x7FFFFFFF)
        Combined values: Domain+Private = 6, Domain+Private+Public = 14
    #>
    param(
        [string]$GPOName,
        [hashtable]$Rule
    )

    # Map protocol name to number
    $protocolMap = @{ "TCP" = 6; "UDP" = 17; "ICMPv4" = 1 }
    $protocolNumber = $protocolMap[$Rule.Protocol]

    # Map profile name to bitmask value
    $profileMap = @{
        "Any"     = 2147483647
        "Domain"  = 2
        "Private" = 4
        "Public"  = 8
    }
    $profileValue = $profileMap[$Rule.Profile]

    # Map direction
    $dirMap = @{ "Inbound" = "In"; "Outbound" = "Out" }
    $dirValue = $dirMap[$Rule.Direction]

    # Map action
    $actionValue = $Rule.Action  # "Allow" or "Block"

    # Build the firewall rule value string
    # Start with mandatory fields
    $ruleParts = @(
        "v2.30"
        "Action=$actionValue"
        "Active=TRUE"
        "Dir=$dirValue"
        "Protocol=$protocolNumber"
    )

    # Add port or ICMP type depending on protocol
    if ($Rule.Protocol -eq "ICMPv4") {
        # ICMP type:code format. "*" means any code for that type.
        # Type 8 = Echo Request (ping)
        $ruleParts += "ICMP4=$($Rule.IcmpType):*"
    }
    else {
        $ruleParts += "LPort=$($Rule.LocalPort)"
    }

    # Add profile, name, and description
    $ruleParts += "Profile=$profileValue"
    $ruleParts += "Name=$($Rule.DisplayName)"
    $ruleParts += "Desc=$($Rule.Description)"

    $ruleValue = $ruleParts -join "|"

    <#
    SET-GPREGISTRYVALUE:
    --------------------
    This cmdlet writes a registry value into a GPO's registry settings.
    The GPO stores these values in a "registry.pol" file. When the GPO
    is applied to a machine, these registry values are written to the
    machine's registry under HKLM\SOFTWARE\Policies\...

    Windows Firewall reads its policy settings from that registry path
    at startup and during policy refresh.

    -Name: Name of the GPO
    -Key:  Registry key path (under HKLM in the GPO's computer settings)
    -ValueName: The registry value name (our rule's unique ID)
    -Value: The data string encoding the rule
    -Type:  REG_SZ (plain string)
    #>

    $registryKey = "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules"

    Set-GPRegistryValue `
        -Name $GPOName `
        -Key $registryKey `
        -ValueName $Rule.Name `
        -Value $ruleValue `
        -Type String | Out-Null

    Write-Log "    Added rule: $($Rule.DisplayName) ($($Rule.Protocol) / $($Rule.Profile))" -Level SUCCESS
}

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

try {
    Write-LogSection "Configuring Group Policy Objects"

    # -------------------------------------------------------------------------
    # STEP 1: Prerequisite Checks
    # -------------------------------------------------------------------------
    Write-Log "Performing prerequisite checks..." -Level INFO

    if (-not (Test-IsDomainController)) {
        Write-Log "This server is not a domain controller!" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }
    Write-Log "  Server is a domain controller" -Level SUCCESS

    # Import required modules
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "  ActiveDirectory module loaded" -Level SUCCESS
    }
    catch {
        Write-Log "  Failed to load ActiveDirectory module: $($_.Exception.Message)" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # GPMC (Group Policy Management Console) must be installed for the
    # GroupPolicy PowerShell module to be available.
    try {
        Import-Module GroupPolicy -ErrorAction Stop
        Write-Log "  GroupPolicy module loaded" -Level SUCCESS
    }
    catch {
        Write-Log "  Failed to load GroupPolicy module!" -Level ERROR
        Write-Log "  Install GPMC first: Install-WindowsFeature GPMC" -Level ERROR
        Complete-Logging -Success $false
        exit 1
    }

    # Get domain info
    $domain = Get-ADDomain
    $DomainDN = $domain.DistinguishedName
    Write-Log "  Domain DN: $DomainDN" -Level INFO

    # -------------------------------------------------------------------------
    # STEP 2: Display Plan
    # -------------------------------------------------------------------------
    Write-LogSection "GPOs to Configure"

    foreach ($gpoDef in $GPODefinitions) {
        Write-Log "GPO: $($gpoDef.Name)" -Level INFO
        Write-Log "  Link: $($gpoDef.OUPath),$DomainDN" -Level INFO
        Write-Log "  Rules: $($gpoDef.FirewallRules.Count) firewall rules" -Level INFO
    }

    # -------------------------------------------------------------------------
    # STEP 3: Confirmation
    # -------------------------------------------------------------------------
    if (-not $Force) {
        Write-Log "" -Level INFO
        $confirm = Read-Host "Create and link these GPOs? (Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            Write-Log "Cancelled by user." -Level WARN
            Complete-Logging -Success $false
            exit 0
        }
    }

    # -------------------------------------------------------------------------
    # STEP 4: Create and Configure Each GPO
    # -------------------------------------------------------------------------
    foreach ($gpoDef in $GPODefinitions) {
        Write-LogSection "Processing: $($gpoDef.Name)"

        # Create the GPO if it doesn't already exist
        $existingGPO = Get-GPO -Name $gpoDef.Name -ErrorAction SilentlyContinue

        if ($existingGPO) {
            Write-Log "GPO already exists, updating rules..." -Level INFO
        }
        else {
            Write-Log "Creating GPO..." -Level INFO

            <#
            NEW-GPO:
            --------
            Creates a new, empty GPO in the domain. The GPO exists in the
            Group Policy Objects container but is not linked to anything yet.
            Linking (associating the GPO with an OU) is a separate step.

            -Name:    Display name shown in GPMC
            -Domain:  The domain to create the GPO in
            -Comment: Description shown in GPMC
            #>

            New-GPO `
                -Name $gpoDef.Name `
                -Domain $DomainName `
                -Comment $gpoDef.Description | Out-Null

            Write-Log "  GPO created" -Level SUCCESS
        }

        # Add firewall rules into the GPO
        Write-Log "Writing firewall rules..." -Level INFO

        foreach ($rule in $gpoDef.FirewallRules) {
            Add-GPOFirewallRule -GPOName $gpoDef.Name -Rule $rule
        }

        # Link the GPO to its target OU
        $ouDN = "$($gpoDef.OUPath),$DomainDN"

        <#
        NEW-GPLINK:
        -----------
        Links a GPO to an OU (or domain/site). Until a GPO is linked, it
        exists in AD but has no effect on any machines.

        A single GPO can be linked to multiple OUs. Multiple GPOs can be
        linked to the same OU (processed in link order).

        -Name:   The GPO to link
        -Target: The DN of the OU/domain/site to link it to
        -Domain: The domain containing both the GPO and the OU

        ErrorAction SilentlyContinue: New-GPLink throws if the link already
        exists. We suppress the error and log it as informational instead.
        #>

        $existingLink = Get-GPInheritance -Target $ouDN |
            Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $gpoDef.Name }

        if ($existingLink) {
            Write-Log "GPO already linked to $($gpoDef.OUPath)" -Level SUCCESS
        }
        else {
            Write-Log "Linking GPO to $ouDN..." -Level INFO

            New-GPLink `
                -Name $gpoDef.Name `
                -Target $ouDN `
                -Domain $DomainName | Out-Null

            Write-Log "  GPO linked" -Level SUCCESS
        }
    }

    # -------------------------------------------------------------------------
    # STEP 5: Summary
    # -------------------------------------------------------------------------
    Write-LogSection "GPO Configuration Summary"

    foreach ($gpoDef in $GPODefinitions) {
        $gpo = Get-GPO -Name $gpoDef.Name
        Write-Log "GPO: $($gpo.DisplayName)" -Level INFO
        Write-Log "  ID:     $($gpo.Id)" -Level INFO
        Write-Log "  Status: $($gpo.GpoStatus)" -Level INFO
        Write-Log "  Linked: $($gpoDef.OUPath)" -Level INFO
    }

    Write-Log "" -Level INFO
    Write-Log "GPOs are active. Policy will apply to domain members within 90 minutes" -Level INFO
    Write-Log "or immediately after: gpupdate /force" -Level INFO
    Write-Log "" -Level INFO
    Write-Log "Next Steps:" -Level INFO
    Write-Log "  1. Run Create-ServiceAccounts.ps1" -Level INFO
    Write-Log "  2. Run Configure-DHCP.ps1" -Level INFO
    Write-Log "  3. Join clients to the domain - firewall policy will auto-apply" -Level INFO

    Complete-Logging -Success $true
    exit 0
}
catch {
    Write-LogError -ErrorRecord $_ -Message "An error occurred during GPO configuration"
    Complete-Logging -Success $false
    exit 1
}
