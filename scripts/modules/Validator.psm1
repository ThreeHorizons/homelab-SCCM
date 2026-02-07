#Requires -Version 5.1
<#
.SYNOPSIS
    Validation module for SCCM lab automation scripts.

.DESCRIPTION
    This module provides functions to check the state of various lab components.
    It's used for:
    1. Prerequisite checks - Verify conditions before running scripts
    2. Idempotency - Determine if a step has already been completed
    3. Validation - Confirm that operations succeeded
    4. Diagnostics - Troubleshoot issues in the lab

    WHY VALIDATION MATTERS:
    -----------------------
    In infrastructure automation, you need to:
    - Skip steps that are already done (idempotency)
    - Fail fast if prerequisites aren't met
    - Verify that changes took effect
    - Provide clear diagnostics when things go wrong

    DESIGN PRINCIPLES:
    ------------------
    1. Each Test-* function returns $true or $false
    2. Functions use -ErrorAction SilentlyContinue to avoid throwing
    3. Functions are self-contained and don't depend on each other
    4. Get-LabStatus provides a comprehensive status object

.EXAMPLE
    Import-Module C:\Lab\scripts\modules\Validator.psm1

    # Check if AD DS is installed
    if (Test-ADDSInstalled) {
        Write-Host "AD DS is already installed"
    }

    # Get complete lab status
    $status = Get-LabStatus
    $status | Format-List

.NOTES
    Author: SCCM Homelab Project
    Version: 1.0
#>

# =============================================================================
# ACTIVE DIRECTORY VALIDATION FUNCTIONS
# =============================================================================

function Test-ADDSInstalled {
    <#
    .SYNOPSIS
        Checks if the AD DS role is installed on this server.

    .DESCRIPTION
        The AD DS role must be installed before a server can be promoted to
        a domain controller. This function checks if the Windows feature
        "AD-Domain-Services" is installed.

        HOW IT WORKS:
        -------------
        Get-WindowsFeature returns information about Windows Server roles and
        features. The InstallState property tells us:
        - "Installed" - The feature is installed
        - "Available" - The feature can be installed
        - "Removed" - The feature's binaries have been removed

    .OUTPUTS
        Boolean - $true if AD DS role is installed, $false otherwise.

    .EXAMPLE
        if (-not (Test-ADDSInstalled)) {
            Install-WindowsFeature -Name AD-Domain-Services
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Get the feature information
    # -ErrorAction SilentlyContinue prevents errors if the feature doesn't exist
    $feature = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue

    # Return true if installed
    return ($feature -and $feature.InstallState -eq 'Installed')
}

function Test-IsDomainController {
    <#
    .SYNOPSIS
        Checks if this server is a domain controller.

    .DESCRIPTION
        After installing AD DS, the server must be "promoted" to actually
        become a domain controller. This function checks if that promotion
        has occurred.

        HOW IT WORKS:
        -------------
        We try to run Get-ADDomainController. This cmdlet only works on a
        domain controller. If it succeeds, we're a DC. If it fails, we're not.

        The Get-ADDomainController cmdlet is part of the ActiveDirectory module
        which is automatically available on domain controllers.

    .OUTPUTS
        Boolean - $true if this server is a domain controller, $false otherwise.

    .EXAMPLE
        if (Test-IsDomainController) {
            Write-Host "This is a domain controller for $(Get-ADDomain | Select -Expand Name)"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Try to get domain controller information
        # This will fail on non-DCs
        $dc = Get-ADDomainController -ErrorAction Stop
        return ($null -ne $dc)
    }
    catch {
        # If we get an error, we're not a domain controller
        return $false
    }
}

function Test-DomainExists {
    <#
    .SYNOPSIS
        Checks if a specific Active Directory domain exists and is reachable.

    .DESCRIPTION
        Verifies that a domain can be contacted via DNS and AD services.
        This is useful for checking if the lab domain (lab.local) has been
        created and is functional.

    .PARAMETER DomainName
        The domain name to check. Defaults to "lab.local".

    .OUTPUTS
        Boolean - $true if the domain exists and is reachable, $false otherwise.

    .EXAMPLE
        if (Test-DomainExists -DomainName "lab.local") {
            Write-Host "Lab domain is ready"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DomainName = "lab.local"
    )

    try {
        # Try to get domain information
        $domain = Get-ADDomain -Server $DomainName -ErrorAction Stop
        return ($null -ne $domain)
    }
    catch {
        return $false
    }
}

function Test-DomainJoined {
    <#
    .SYNOPSIS
        Checks if this computer is joined to a specific domain.

    .DESCRIPTION
        Verifies that the computer is a member of the expected domain.
        This is important before running scripts that require domain
        membership (like installing SQL Server with domain accounts).

        HOW IT WORKS:
        -------------
        We use WMI (Windows Management Instrumentation) to query the
        Win32_ComputerSystem class, which has a Domain property.

        For a workgroup computer, Domain = "WORKGROUP"
        For a domain member, Domain = "domain.name" (e.g., "lab.local")

    .PARAMETER ExpectedDomain
        The domain name to check for. Defaults to "lab.local".

    .OUTPUTS
        Boolean - $true if joined to the expected domain, $false otherwise.

    .EXAMPLE
        if (-not (Test-DomainJoined)) {
            Write-Host "Computer is not domain-joined. Joining now..."
            Add-Computer -DomainName "lab.local" -Credential $cred
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExpectedDomain = "lab.local"
    )

    # Get the current domain from WMI
    # Get-CimInstance is the modern replacement for Get-WmiObject
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

    if ($computerSystem) {
        # Compare domains (case-insensitive)
        return ($computerSystem.Domain -eq $ExpectedDomain)
    }

    return $false
}

# =============================================================================
# DNS VALIDATION FUNCTIONS
# =============================================================================

function Test-DNSServerInstalled {
    <#
    .SYNOPSIS
        Checks if the DNS Server role is installed.

    .DESCRIPTION
        The DNS Server role is typically installed alongside AD DS (and is
        required for AD to function). This function verifies the role is present.

    .OUTPUTS
        Boolean - $true if DNS Server role is installed, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $feature = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue
    return ($feature -and $feature.InstallState -eq 'Installed')
}

function Test-DNSZoneExists {
    <#
    .SYNOPSIS
        Checks if a DNS forward lookup zone exists.

    .DESCRIPTION
        After AD DS is promoted, a DNS zone should be created for the domain.
        This function verifies that the zone exists.

    .PARAMETER ZoneName
        The DNS zone name to check. Defaults to "lab.local".

    .OUTPUTS
        Boolean - $true if the zone exists, $false otherwise.

    .EXAMPLE
        if (-not (Test-DNSZoneExists -ZoneName "lab.local")) {
            Write-Host "DNS zone not found!"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ZoneName = "lab.local"
    )

    try {
        $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
        return ($null -ne $zone)
    }
    catch {
        return $false
    }
}

function Test-DNSResolution {
    <#
    .SYNOPSIS
        Tests if a hostname can be resolved via DNS.

    .DESCRIPTION
        Verifies that DNS is working by attempting to resolve a hostname.
        Optionally checks that it resolves to an expected IP address.

    .PARAMETER Hostname
        The hostname to resolve. Defaults to "dc01.lab.local".

    .PARAMETER ExpectedIP
        Optional. The expected IP address. If provided, the function checks
        that the hostname resolves to this specific IP.

    .OUTPUTS
        Boolean - $true if resolution succeeds (and matches expected IP if provided).

    .EXAMPLE
        # Just check if resolution works
        Test-DNSResolution -Hostname "dc01.lab.local"

        # Check for specific IP
        Test-DNSResolution -Hostname "dc01.lab.local" -ExpectedIP "192.168.56.10"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Hostname = "dc01.lab.local",

        [Parameter(Mandatory = $false)]
        [string]$ExpectedIP = $null
    )

    try {
        # Resolve-DnsName returns DNS records for the hostname
        $result = Resolve-DnsName -Name $Hostname -Type A -ErrorAction Stop

        if ($null -eq $result) {
            return $false
        }

        # If no expected IP specified, just check that resolution worked
        if ([string]::IsNullOrEmpty($ExpectedIP)) {
            return $true
        }

        # Check if any result matches the expected IP
        return ($result.IPAddress -contains $ExpectedIP)
    }
    catch {
        return $false
    }
}

function Test-ReverseDNSZoneExists {
    <#
    .SYNOPSIS
        Checks if a reverse DNS lookup zone exists.

    .DESCRIPTION
        Reverse DNS zones map IP addresses back to hostnames (PTR records).
        This is needed for many Windows features to work correctly.

        For the 192.168.56.x network, the reverse zone name is:
        "56.168.192.in-addr.arpa"

    .PARAMETER NetworkID
        The network ID (first three octets). Defaults to "192.168.56".

    .OUTPUTS
        Boolean - $true if the reverse zone exists, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$NetworkID = "192.168.56"
    )

    # Convert network ID to reverse zone name
    # 192.168.56 -> 56.168.192.in-addr.arpa
    $octets = $NetworkID.Split('.')
    [array]::Reverse($octets)
    $reverseZone = ($octets -join '.') + '.in-addr.arpa'

    try {
        $zone = Get-DnsServerZone -Name $reverseZone -ErrorAction Stop
        return ($null -ne $zone)
    }
    catch {
        return $false
    }
}

# =============================================================================
# DHCP VALIDATION FUNCTIONS
# =============================================================================

function Test-DHCPServerInstalled {
    <#
    .SYNOPSIS
        Checks if the DHCP Server role is installed.

    .OUTPUTS
        Boolean - $true if DHCP Server role is installed, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $feature = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue
    return ($feature -and $feature.InstallState -eq 'Installed')
}

function Test-DHCPServerAuthorized {
    <#
    .SYNOPSIS
        Checks if this DHCP server is authorized in Active Directory.

    .DESCRIPTION
        In an AD environment, DHCP servers must be "authorized" before they
        can serve clients. This prevents rogue DHCP servers.

    .OUTPUTS
        Boolean - $true if the DHCP server is authorized, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Get list of authorized DHCP servers in AD
        $authorizedServers = Get-DhcpServerInDC -ErrorAction Stop

        # Check if our server is in the list
        $ourFQDN = "$env:COMPUTERNAME.$((Get-CimInstance Win32_ComputerSystem).Domain)"

        foreach ($server in $authorizedServers) {
            if ($server.DnsName -eq $ourFQDN -or $server.IPAddress -eq (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" } | Select-Object -First 1).IPAddress) {
                return $true
            }
        }

        return $false
    }
    catch {
        return $false
    }
}

function Test-DHCPScopeExists {
    <#
    .SYNOPSIS
        Checks if a DHCP scope exists for a specific network.

    .PARAMETER ScopeID
        The scope ID (network address). Defaults to "192.168.56.0".

    .OUTPUTS
        Boolean - $true if the scope exists, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScopeID = "192.168.56.0"
    )

    try {
        $scope = Get-DhcpServerv4Scope -ScopeId $ScopeID -ErrorAction Stop
        return ($null -ne $scope)
    }
    catch {
        return $false
    }
}

function Test-DHCPScopeActive {
    <#
    .SYNOPSIS
        Checks if a DHCP scope is active (serving addresses).

    .PARAMETER ScopeID
        The scope ID to check. Defaults to "192.168.56.0".

    .OUTPUTS
        Boolean - $true if the scope exists and is active, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScopeID = "192.168.56.0"
    )

    try {
        $scope = Get-DhcpServerv4Scope -ScopeId $ScopeID -ErrorAction Stop
        return ($scope -and $scope.State -eq 'Active')
    }
    catch {
        return $false
    }
}

# =============================================================================
# SQL SERVER VALIDATION FUNCTIONS
# =============================================================================

function Test-SQLServerInstalled {
    <#
    .SYNOPSIS
        Checks if SQL Server is installed and the service is running.

    .DESCRIPTION
        Checks for the MSSQLSERVER service (default instance) and verifies
        it's running.

    .PARAMETER InstanceName
        The SQL Server instance name. Defaults to "MSSQLSERVER" (default instance).

    .OUTPUTS
        Boolean - $true if SQL Server is installed and running, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstanceName = "MSSQLSERVER"
    )

    $service = Get-Service -Name $InstanceName -ErrorAction SilentlyContinue
    return ($service -and $service.Status -eq 'Running')
}

function Test-SQLServerCollation {
    <#
    .SYNOPSIS
        Verifies SQL Server has the correct collation for SCCM.

    .DESCRIPTION
        SCCM requires SQL Server to use the collation "SQL_Latin1_General_CP1_CI_AS".
        This cannot be changed after installation, so it's critical to verify
        before installing SCCM.

        WHAT IS COLLATION?
        ------------------
        Collation defines how SQL Server sorts and compares text:
        - SQL_Latin1_General: Character set and sorting rules
        - CP1: Code Page 1252 (Western European)
        - CI: Case Insensitive (A = a)
        - AS: Accent Sensitive (e != e)

    .PARAMETER ExpectedCollation
        The expected collation. Defaults to "SQL_Latin1_General_CP1_CI_AS".

    .OUTPUTS
        Boolean - $true if collation matches, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExpectedCollation = "SQL_Latin1_General_CP1_CI_AS"
    )

    try {
        # Import SqlServer module if available
        Import-Module SqlServer -ErrorAction SilentlyContinue

        # Query the server's collation
        $result = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation" -ErrorAction Stop

        return ($result.Collation -eq $ExpectedCollation)
    }
    catch {
        return $false
    }
}

function Test-SQLServerConnection {
    <#
    .SYNOPSIS
        Tests connectivity to SQL Server.

    .PARAMETER ServerInstance
        The SQL Server instance to connect to. Defaults to local default instance.

    .OUTPUTS
        Boolean - $true if connection succeeds, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = $env:COMPUTERNAME
    )

    try {
        Import-Module SqlServer -ErrorAction SilentlyContinue
        $result = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query "SELECT 1 AS Test" -ErrorAction Stop
        return ($result.Test -eq 1)
    }
    catch {
        return $false
    }
}

# =============================================================================
# SCCM VALIDATION FUNCTIONS
# =============================================================================

function Test-SCCMInstalled {
    <#
    .SYNOPSIS
        Checks if SCCM site server is installed and running.

    .DESCRIPTION
        Checks for the core SCCM services:
        - SMS_EXECUTIVE: Main SCCM service that runs all components
        - SMS_SITE_COMPONENT_MANAGER: Manages site components

    .OUTPUTS
        Boolean - $true if SCCM is installed and running, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

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
        Checks if SCCM client (ccmexec) is installed and running.

    .DESCRIPTION
        The SCCM client service (CcmExec) runs on managed computers and
        communicates with the SCCM site server.

    .OUTPUTS
        Boolean - $true if SCCM client is installed and running, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $ccmExec = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
    return ($ccmExec -and $ccmExec.Status -eq 'Running')
}

function Test-SCCMConsoleInstalled {
    <#
    .SYNOPSIS
        Checks if the SCCM admin console is installed.

    .OUTPUTS
        Boolean - $true if SCCM console is installed, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $consolePath = "${env:ProgramFiles(x86)}\Microsoft Endpoint Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
    return (Test-Path $consolePath)
}

# =============================================================================
# WINDOWS FEATURE VALIDATION FUNCTIONS
# =============================================================================

function Test-WindowsFeatureInstalled {
    <#
    .SYNOPSIS
        Checks if a Windows feature is installed.

    .PARAMETER FeatureName
        The feature name to check.

    .OUTPUTS
        Boolean - $true if the feature is installed, $false otherwise.

    .EXAMPLE
        if (-not (Test-WindowsFeatureInstalled -FeatureName "NET-Framework-Core")) {
            Install-WindowsFeature -Name NET-Framework-Core
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FeatureName
    )

    $feature = Get-WindowsFeature -Name $FeatureName -ErrorAction SilentlyContinue
    return ($feature -and $feature.InstallState -eq 'Installed')
}

function Test-IISInstalled {
    <#
    .SYNOPSIS
        Checks if IIS (Web-Server) is installed with required sub-features for SCCM.

    .DESCRIPTION
        SCCM requires IIS with specific features. This function checks for
        the main Web-Server role.

    .OUTPUTS
        Boolean - $true if IIS is installed, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return (Test-WindowsFeatureInstalled -FeatureName "Web-Server")
}

# =============================================================================
# NETWORK VALIDATION FUNCTIONS
# =============================================================================

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to a remote host.

    .PARAMETER ComputerName
        The computer or IP address to test.

    .PARAMETER Port
        Optional. The TCP port to test. If not specified, uses ICMP ping.

    .OUTPUTS
        Boolean - $true if connectivity test succeeds, $false otherwise.

    .EXAMPLE
        # Test ping
        Test-NetworkConnectivity -ComputerName "dc01.lab.local"

        # Test specific port
        Test-NetworkConnectivity -ComputerName "sccm01" -Port 1433
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $false)]
        [int]$Port = 0
    )

    try {
        if ($Port -gt 0) {
            # Test TCP port
            $result = Test-NetConnection -ComputerName $ComputerName -Port $Port -WarningAction SilentlyContinue -ErrorAction Stop
            return $result.TcpTestSucceeded
        }
        else {
            # Test ICMP ping
            $result = Test-NetConnection -ComputerName $ComputerName -WarningAction SilentlyContinue -ErrorAction Stop
            return $result.PingSucceeded
        }
    }
    catch {
        return $false
    }
}

# =============================================================================
# COMPREHENSIVE STATUS FUNCTION
# =============================================================================

function Get-LabStatus {
    <#
    .SYNOPSIS
        Returns comprehensive status of all lab components.

    .DESCRIPTION
        Runs all validation checks and returns a single object with the
        status of each component. Useful for diagnostics and automated
        validation.

    .OUTPUTS
        PSCustomObject with properties for each validation check.

    .EXAMPLE
        $status = Get-LabStatus
        $status | Format-List

        # Check specific items
        if (-not $status.DomainJoined) {
            Write-Host "Computer needs to join the domain"
        }
    #>
    [CmdletBinding()]
    param()

    # Create and return status object
    # Each property runs a validation function
    [PSCustomObject]@{
        # Metadata
        ComputerName       = $env:COMPUTERNAME
        Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        # AD DS Status
        ADDSInstalled      = Test-ADDSInstalled
        IsDomainController = Test-IsDomainController
        DomainJoined       = Test-DomainJoined

        # DNS Status
        DNSServerInstalled = Test-DNSServerInstalled
        DNSZoneExists      = Test-DNSZoneExists
        ReverseDNSExists   = Test-ReverseDNSZoneExists

        # DHCP Status
        DHCPInstalled      = Test-DHCPServerInstalled
        DHCPScopeExists    = Test-DHCPScopeExists
        DHCPScopeActive    = Test-DHCPScopeActive

        # SQL Server Status
        SQLServerRunning   = Test-SQLServerInstalled
        SQLCollationOK     = if (Test-SQLServerInstalled) { Test-SQLServerCollation } else { $null }

        # SCCM Status
        SCCMInstalled      = Test-SCCMInstalled
        SCCMClientRunning  = Test-SCCMClientInstalled

        # Prerequisites
        DotNet35           = Test-WindowsFeatureInstalled -FeatureName "NET-Framework-Core"
        IISInstalled       = Test-IISInstalled
    }
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

Export-ModuleMember -Function @(
    # AD DS Functions
    'Test-ADDSInstalled',
    'Test-IsDomainController',
    'Test-DomainExists',
    'Test-DomainJoined',

    # DNS Functions
    'Test-DNSServerInstalled',
    'Test-DNSZoneExists',
    'Test-DNSResolution',
    'Test-ReverseDNSZoneExists',

    # DHCP Functions
    'Test-DHCPServerInstalled',
    'Test-DHCPServerAuthorized',
    'Test-DHCPScopeExists',
    'Test-DHCPScopeActive',

    # SQL Server Functions
    'Test-SQLServerInstalled',
    'Test-SQLServerCollation',
    'Test-SQLServerConnection',

    # SCCM Functions
    'Test-SCCMInstalled',
    'Test-SCCMClientInstalled',
    'Test-SCCMConsoleInstalled',

    # Windows Feature Functions
    'Test-WindowsFeatureInstalled',
    'Test-IISInstalled',

    # Network Functions
    'Test-NetworkConnectivity',

    # Comprehensive Status
    'Get-LabStatus'
)
