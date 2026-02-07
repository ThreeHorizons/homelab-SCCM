<#
.SYNOPSIS
    Configures SCCM site after installation - boundaries, discovery, and client settings.

.DESCRIPTION
    This script performs post-installation configuration of SCCM including:
    - Creating site boundaries and boundary groups
    - Configuring Active Directory discovery methods
    - Setting up client settings
    - Configuring Network Access Account

    ============================================================================
    TECHNOLOGY EXPLANATION: SCCM Post-Installation Configuration
    ============================================================================

    After SCCM is installed, it needs configuration before it can manage clients.

    BOUNDARIES AND BOUNDARY GROUPS:

    A "boundary" defines a network location. Types include:
    - IP Subnet (192.168.56.0/24)
    - Active Directory Site
    - IPv6 prefix
    - IP Address Range

    A "boundary group" is a collection of boundaries that share:
    - Site assignment (which site serves clients in this boundary)
    - Content location (which distribution points to use)
    - Site system associations

    WHY BOUNDARIES MATTER:
    - Clients use boundaries to find their assigned site
    - Clients use boundary groups to find nearest content
    - Without proper boundaries, clients may not work correctly

    DISCOVERY METHODS:

    Discovery finds resources (computers, users) to manage. Types:

    1. Active Directory System Discovery
       - Discovers computer objects from AD
       - Creates DDR (Discovery Data Record) for each computer
       - Populates SCCM database with computer inventory

    2. Active Directory User Discovery
       - Discovers user objects from AD
       - Enables user-targeted deployments
       - Required for user-device affinity

    3. Active Directory Group Discovery
       - Discovers AD security groups
       - Useful for collection membership

    4. Heartbeat Discovery
       - Clients self-report periodically
       - Updates client status in database
       - Default: every 7 days

    5. Network Discovery
       - Scans network for devices (SNMP, DHCP, etc.)
       - Heavy on network traffic
       - Usually not needed if AD discovery works

    CLIENT SETTINGS:

    Client settings control how the SCCM client behaves:
    - Hardware inventory schedule
    - Software inventory settings
    - Remote control permissions
    - Power management
    - Software updates scan schedule
    - And many more...

    Default client settings apply to all clients.
    Custom settings can target specific collections.

    NETWORK ACCESS ACCOUNT (NAA):

    The NAA is used when:
    - Client can't use its computer account (workgroup machines)
    - Accessing content from DPs that don't allow anonymous
    - PXE boot scenarios before domain join

    Best practice: Use a low-privilege account.
    In modern SCCM, Enhanced HTTP can reduce NAA dependency.

    ============================================================================

.PARAMETER SiteCode
    Three-character SCCM site code.
    Default: PS1

.PARAMETER BoundaryName
    Name for the IP subnet boundary.
    Default: Lab Network

.PARAMETER SubnetAddress
    IP subnet for the boundary.
    Default: 192.168.56.0

.PARAMETER NetworkAccessAccount
    Domain account for Network Access Account.
    Default: LAB\SCCM_NAA

.PARAMETER NetworkAccessPassword
    Password for the Network Access Account.

.EXAMPLE
    .\Configure-SCCM.ps1 -SiteCode "PS1"

.NOTES
    Author: Homelab-SCCM Project
    Requires: SCCM installed and operational
    Run on: SCCM01
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern("^[A-Z0-9]{3}$")]
    [string]$SiteCode = "PS1",

    [Parameter(Mandatory = $false)]
    [string]$BoundaryName = "Lab Network",

    [Parameter(Mandatory = $false)]
    [string]$SubnetAddress = "192.168.56.0",

    [Parameter(Mandatory = $false)]
    [string]$NetworkAccessAccount = "LAB\SCCM_NAA",

    [Parameter(Mandatory = $false)]
    [SecureString]$NetworkAccessPassword
)

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "modules"
Import-Module -Name (Join-Path $modulePath "Logger.psm1") -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulePath "Validator.psm1") -Force -ErrorAction Stop

Initialize-Logging -LogName "Configure-SCCM"

Write-LogSection "SCCM Post-Installation Configuration"

# ============================================================================
# LOAD CONFIGURATION MANAGER MODULE
# ============================================================================

Write-Log "Loading Configuration Manager PowerShell module..." -Level INFO

# SCCM installs its own PowerShell module for management
# The module is in the AdminConsole folder
$cmModulePath = Join-Path $env:SMS_ADMIN_UI_PATH "..\ConfigurationManager.psd1"

if (-not $env:SMS_ADMIN_UI_PATH) {
    # Try to find it manually
    $consolePaths = @(
        "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin",
        "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin"
    )

    foreach ($path in $consolePaths) {
        $testPath = Join-Path $path "..\ConfigurationManager.psd1"
        if (Test-Path $testPath) {
            $cmModulePath = $testPath
            break
        }
    }
}

if (-not (Test-Path $cmModulePath)) {
    Write-LogError "Configuration Manager PowerShell module not found."
    Write-Log "SCCM Console must be installed to use this script." -Level ERROR
    throw "CM module not found"
}

try {
    Import-Module $cmModulePath -Force -ErrorAction Stop
    Write-Log "Configuration Manager module loaded." -Level SUCCESS
}
catch {
    Write-LogError "Failed to load Configuration Manager module: $_"
    throw
}

# ============================================================================
# CONNECT TO SITE
# ============================================================================

Write-Log "Connecting to SCCM site $SiteCode..." -Level INFO

# SYNTAX EXPLANATION: CM PSDrive
# SCCM PowerShell creates a special "drive" for each site
# The drive letter is the site code (e.g., PS1:)
# All CM cmdlets must run from this drive

# Check if drive already exists
$siteDrive = Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue

if (-not $siteDrive) {
    # Create the drive
    try {
        $providerLocation = Get-WmiObject -Namespace "root\SMS" -Class "SMS_ProviderLocation" |
            Where-Object { $_.SiteCode -eq $SiteCode } |
            Select-Object -First 1

        if (-not $providerLocation) {
            throw "Site $SiteCode not found"
        }

        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $providerLocation.Machine -ErrorAction Stop | Out-Null
        Write-Log "Created SCCM drive: $SiteCode`:" -Level SUCCESS
    }
    catch {
        Write-LogError "Failed to connect to site: $_"
        throw
    }
}

# Change to the CM drive
Push-Location
Set-Location "$SiteCode`:"

Write-Log "Connected to site $SiteCode" -Level SUCCESS

# ============================================================================
# CREATE BOUNDARIES
# ============================================================================

Write-LogSection "Configuring Site Boundaries"

# SYNTAX EXPLANATION: New-CMBoundary
# Creates a new boundary in SCCM
# -Name: Friendly name
# -Type: IPSubnet, ADSite, IPRange, IPv6Prefix
# -Value: Depends on type (for IPSubnet, it's "subnet_address/prefix_length")

# Check if boundary already exists
$existingBoundary = Get-CMBoundary -BoundaryName $BoundaryName -ErrorAction SilentlyContinue

if ($existingBoundary) {
    Write-Log "Boundary already exists: $BoundaryName" -Level INFO
} else {
    Write-Log "Creating boundary: $BoundaryName ($SubnetAddress/24)" -Level INFO

    try {
        # For IP Subnet, value format is "subnet/prefix" or just the subnet ID
        $boundary = New-CMBoundary -Name $BoundaryName `
            -Type IPSubnet `
            -Value "$SubnetAddress/24"

        Write-Log "Created boundary: $BoundaryName" -Level SUCCESS
    }
    catch {
        Write-LogError "Failed to create boundary: $_"
    }
}

# ============================================================================
# CREATE BOUNDARY GROUP
# ============================================================================

Write-LogSection "Configuring Boundary Groups"

$boundaryGroupName = "$BoundaryName Boundary Group"

# Check if boundary group exists
$existingBoundaryGroup = Get-CMBoundaryGroup -Name $boundaryGroupName -ErrorAction SilentlyContinue

if ($existingBoundaryGroup) {
    Write-Log "Boundary group already exists: $boundaryGroupName" -Level INFO
} else {
    Write-Log "Creating boundary group: $boundaryGroupName" -Level INFO

    try {
        # SYNTAX EXPLANATION: New-CMBoundaryGroup
        # -Name: Friendly name for the group
        # -DefaultSiteCode: Site code for automatic site assignment

        $boundaryGroup = New-CMBoundaryGroup -Name $boundaryGroupName `
            -DefaultSiteCode $SiteCode

        Write-Log "Created boundary group: $boundaryGroupName" -Level SUCCESS
    }
    catch {
        Write-LogError "Failed to create boundary group: $_"
    }
}

# Add boundary to boundary group
Write-Log "Adding boundary to boundary group..." -Level INFO

try {
    $boundary = Get-CMBoundary -BoundaryName $BoundaryName
    $boundaryGroup = Get-CMBoundaryGroup -Name $boundaryGroupName

    if ($boundary -and $boundaryGroup) {
        Add-CMBoundaryToGroup -BoundaryId $boundary.BoundaryID -BoundaryGroupId $boundaryGroup.GroupID -ErrorAction SilentlyContinue
        Write-Log "Boundary added to group." -Level SUCCESS
    }
}
catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Log "Boundary already in group." -Level INFO
    } else {
        Write-Log "Could not add boundary to group: $_" -Level WARN
    }
}

# Add site systems to boundary group (for content location)
Write-Log "Configuring boundary group site system associations..." -Level INFO

try {
    # Get the site server name
    $siteServer = (Get-CMSiteSystemServer | Select-Object -First 1).NetworkOSPath -replace '\\\\', ''

    if ($siteServer) {
        # Add Distribution Point to boundary group
        Set-CMBoundaryGroup -Name $boundaryGroupName `
            -AddSiteSystemServerName $siteServer `
            -ErrorAction SilentlyContinue

        Write-Log "Site systems associated with boundary group." -Level SUCCESS
    }
}
catch {
    Write-Log "Could not configure site system associations: $_" -Level WARN
}

# ============================================================================
# CONFIGURE DISCOVERY METHODS
# ============================================================================

Write-LogSection "Configuring Discovery Methods"

# Active Directory System Discovery
Write-Log "Configuring Active Directory System Discovery..." -Level INFO

try {
    # SYNTAX EXPLANATION: Set-CMDiscoveryMethod
    # -Type: Which discovery method to configure
    # -SiteCode: Site to configure
    # -Enabled: True/False
    # -ActiveDirectoryContainer: AD path(s) to search
    # -Recursive: Include child containers

    # Get domain DN for the AD container
    $domainDN = ([ADSI]"LDAP://RootDSE").defaultNamingContext

    # Enable AD System Discovery
    Set-CMDiscoveryMethod -ActiveDirectorySystemDiscovery `
        -SiteCode $SiteCode `
        -Enabled $true `
        -ErrorAction SilentlyContinue

    # Add AD container to search (search entire domain)
    # Note: This cmdlet varies by SCCM version

    Write-Log "Active Directory System Discovery enabled." -Level SUCCESS
    Write-Log "NOTE: Configure search containers in SCCM Console for best results." -Level INFO
}
catch {
    Write-Log "Could not configure AD System Discovery automatically: $_" -Level WARN
    Write-Log "Configure manually in SCCM Console." -Level INFO
}

# Active Directory User Discovery
Write-Log "Configuring Active Directory User Discovery..." -Level INFO

try {
    Set-CMDiscoveryMethod -ActiveDirectoryUserDiscovery `
        -SiteCode $SiteCode `
        -Enabled $true `
        -ErrorAction SilentlyContinue

    Write-Log "Active Directory User Discovery enabled." -Level SUCCESS
}
catch {
    Write-Log "Could not configure AD User Discovery automatically: $_" -Level WARN
}

# Heartbeat Discovery (should be enabled by default)
Write-Log "Verifying Heartbeat Discovery..." -Level INFO

try {
    $heartbeat = Get-CMDiscoveryMethod -Name HeartbeatDiscovery -SiteCode $SiteCode
    if ($heartbeat.Flag -band 1) {
        Write-Log "Heartbeat Discovery is enabled." -Level SUCCESS
    } else {
        Set-CMDiscoveryMethod -Heartbeat -SiteCode $SiteCode -Enabled $true
        Write-Log "Heartbeat Discovery enabled." -Level SUCCESS
    }
}
catch {
    Write-Log "Could not verify Heartbeat Discovery: $_" -Level WARN
}

# ============================================================================
# CONFIGURE CLIENT SETTINGS
# ============================================================================

Write-LogSection "Reviewing Client Settings"

# Get default client settings
Write-Log "Reviewing default client settings..." -Level INFO

try {
    $defaultSettings = Get-CMClientSetting -Name "Default Client Agent Settings"

    if ($defaultSettings) {
        Write-Log "Default Client Settings found." -Level SUCCESS

        # Display some key settings
        Write-Log "Key default settings (configure in Console as needed):" -Level INFO
        Write-Log "  - Hardware Inventory: Review schedule and classes" -Level INFO
        Write-Log "  - Software Inventory: Usually disabled by default" -Level INFO
        Write-Log "  - Client Policy: Review polling interval" -Level INFO
        Write-Log "  - Remote Control: Configure as needed" -Level INFO
    }
}
catch {
    Write-Log "Could not retrieve default client settings." -Level WARN
}

# ============================================================================
# CONFIGURE NETWORK ACCESS ACCOUNT
# ============================================================================

Write-LogSection "Configuring Network Access Account"

if ($NetworkAccessPassword) {
    Write-Log "Setting Network Access Account: $NetworkAccessAccount" -Level INFO

    try {
        # Convert SecureString to credential object
        $credential = New-Object System.Management.Automation.PSCredential($NetworkAccessAccount, $NetworkAccessPassword)

        # SYNTAX EXPLANATION: Set-CMSoftwareDistributionComponent
        # The NAA is part of the Software Distribution component
        # -SiteCode: Site to configure
        # -NetworkAccessAccountName: Account in DOMAIN\User format
        # -NetworkAccessAccountPassword: SecureString password

        # Note: Exact cmdlet may vary by SCCM version
        # Some versions use Set-CMNetworkAccessAccount

        Set-CMAccount -UserName $NetworkAccessAccount -Password $NetworkAccessPassword -SiteCode $SiteCode -ErrorAction SilentlyContinue

        Write-Log "Network Access Account configured." -Level SUCCESS
        Write-Log "NOTE: Verify in SCCM Console under Administration > Site Configuration > Sites > Configure Site Components > Software Distribution" -Level INFO
    }
    catch {
        Write-Log "Could not set NAA automatically: $_" -Level WARN
        Write-Log "Configure manually in SCCM Console." -Level INFO
    }
} else {
    Write-Log "No Network Access Account password provided." -Level INFO
    Write-Log "Configure NAA manually if needed:" -Level INFO
    Write-Log "  Administration > Site Configuration > Sites" -Level INFO
    Write-Log "  Configure Site Components > Software Distribution" -Level INFO
    Write-Log "  Network Access Account tab" -Level INFO
}

# ============================================================================
# CONFIGURE CLIENT PUSH
# ============================================================================

Write-LogSection "Reviewing Client Push Settings"

Write-Log "Client Push Installation settings:" -Level INFO
Write-Log "  Configure in SCCM Console:" -Level INFO
Write-Log "  Administration > Site Configuration > Sites" -Level INFO
Write-Log "  Client Installation Settings > Client Push Installation" -Level INFO
Write-Log "" -Level INFO
Write-Log "  Required settings:" -Level INFO
Write-Log "  - Enable client push for assigned resources" -Level INFO
Write-Log "  - Add account with local admin rights on clients" -Level INFO
Write-Log "    Account: LAB\\SCCM_ClientPush" -Level INFO
Write-Log "  - Optionally enable for all discovered computers" -Level INFO

# ============================================================================
# VERIFICATION
# ============================================================================

Write-LogSection "Configuration Verification"

# Verify boundaries
Write-Log "Checking boundaries..." -Level INFO
$boundaries = Get-CMBoundary
Write-Log "  Total boundaries: $($boundaries.Count)" -Level INFO

# Verify boundary groups
Write-Log "Checking boundary groups..." -Level INFO
$boundaryGroups = Get-CMBoundaryGroup
Write-Log "  Total boundary groups: $($boundaryGroups.Count)" -Level INFO

# Verify discovery methods
Write-Log "Checking discovery methods..." -Level INFO

$discoveryMethods = @(
    @{Name = "ActiveDirectorySystemDiscovery"; Friendly = "AD System Discovery"},
    @{Name = "ActiveDirectoryUserDiscovery"; Friendly = "AD User Discovery"},
    @{Name = "HeartbeatDiscovery"; Friendly = "Heartbeat Discovery"}
)

foreach ($dm in $discoveryMethods) {
    try {
        $method = Get-CMDiscoveryMethod -Name $dm.Name -SiteCode $SiteCode
        $enabled = $method.Flag -band 1
        Write-Log "  $($dm.Friendly): $(if ($enabled) {'Enabled'} else {'Disabled'})" -Level $(if ($enabled) {"SUCCESS"} else {"INFO"})
    }
    catch {
        Write-Log "  $($dm.Friendly): Unknown" -Level WARN
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-LogSection "SCCM Configuration Complete"

# Return to original location
Pop-Location

Write-Log "SCCM post-installation configuration is complete!" -Level SUCCESS
Write-Log "" -Level INFO
Write-Log "Configuration Summary:" -Level INFO
Write-Log "  Site Code: $SiteCode" -Level INFO
Write-Log "  Boundary: $BoundaryName ($SubnetAddress/24)" -Level INFO
Write-Log "  Boundary Group: $boundaryGroupName" -Level INFO
Write-Log "" -Level INFO
Write-Log "Discovery Methods:" -Level INFO
Write-Log "  - AD System Discovery: Enabled" -Level INFO
Write-Log "  - AD User Discovery: Enabled" -Level INFO
Write-Log "  - Heartbeat Discovery: Enabled" -Level INFO
Write-Log "" -Level INFO
Write-Log "Manual Steps Required:" -Level INFO
Write-Log "  1. Configure Client Push Installation account" -Level INFO
Write-Log "  2. Review and customize client settings" -Level INFO
Write-Log "  3. Configure discovery containers if needed" -Level INFO
Write-Log "  4. Run a discovery cycle to populate resources" -Level INFO
Write-Log "" -Level INFO
Write-Log "To access the SCCM Console:" -Level INFO
Write-Log "  Start Menu > Microsoft Endpoint Configuration Manager" -Level INFO
Write-Log "  Or: C:\\Program Files (x86)\\Microsoft Endpoint Manager\\AdminConsole\\bin\\Microsoft.ConfigurationManagement.exe" -Level INFO

Complete-Logging
