# Phase 3: Complete Lab Setup Guide (2026 Edition)

This comprehensive guide covers setting up an enterprise-ready SCCM lab environment with Active Directory, SQL Server, Configuration Manager, and optional Intune integration. Updated with the latest best practices and security recommendations.

**Document Version**: 2.0  
**Last Updated**: 2026-02-03  
**Target Versions**: Windows Server 2022, SQL Server 2022, SCCM 2403/2503

---

## Table of Contents

1. [Overview and Architecture](#overview-and-architecture)
2. [Prerequisites and Downloads](#prerequisites-and-downloads)
3. [Phase 3A: Domain Controller Setup (DC01)](#phase-3a-domain-controller-setup-dc01)
4. [Phase 3B: SQL Server Installation (SCCM01)](#phase-3b-sql-server-installation-sccm01)
5. [Phase 3C: SCCM Installation (SCCM01)](#phase-3c-sccm-installation-sccm01)
6. [Phase 3D: Client Configuration](#phase-3d-client-configuration)
7. [Phase 3.5: Intune Integration (Optional)](#phase-35-intune-integration-optional)
8. [Verification and Testing](#verification-and-testing)
9. [Troubleshooting](#troubleshooting)
10. [Security Hardening](#security-hardening)

---

## Overview and Architecture

### Lab Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Host Machine (NixOS)                           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         VirtualBox                                   │   │
│  │                                                                      │   │
│  │   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐            │   │
│  │   │    DC01      │   │   SCCM01     │   │  CLIENT01+   │            │   │
│  │   │              │   │              │   │              │            │   │
│  │   │ • AD DS      │   │ • SQL 2022   │   │ • Windows 10 │            │   │
│  │   │ • DNS        │   │ • SCCM 2403  │   │ • SCCM Client│            │   │
│  │   │ • DHCP       │   │ • MP/DP      │   │ • Domain     │            │   │
│  │   │ • CA (opt)   │   │ • WSUS (opt) │   │   Joined     │            │   │
│  │   │              │   │              │   │              │            │   │
│  │   │ 192.168.56.10│   │ 192.168.56.11│   │ DHCP Assigned│            │   │
│  │   └──────────────┘   └──────────────┘   └──────────────┘            │   │
│  │          │                   │                   │                   │   │
│  │          └───────────────────┴───────────────────┘                   │   │
│  │                    Host-Only Network                                 │   │
│  │                    192.168.56.0/24                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What You'll Build

| Component | Purpose | Server |
|-----------|---------|--------|
| Active Directory Domain Services | Centralized identity management | DC01 |
| DNS Server | Name resolution for lab.local | DC01 |
| DHCP Server | Automatic IP assignment for clients | DC01 |
| SQL Server 2022 | Database backend for SCCM | SCCM01 |
| Configuration Manager 2403+ | Endpoint management platform | SCCM01 |
| Management Point | Client communication endpoint | SCCM01 |
| Distribution Point | Content distribution | SCCM01 |

---

## Prerequisites and Downloads

### Required Software Downloads

| Component | Version | Download Link | Notes |
|-----------|---------|---------------|-------|
| **SQL Server 2022 Developer** | Latest | [Microsoft Downloads](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) | Free for dev/test |
| **SQL Server Management Studio** | 20.x | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) | Optional but recommended |
| **Microsoft ODBC Driver 18** | 18.4.1.1+ | [ODBC Driver](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) | **Required for SCCM 2403+** |
| **Windows ADK** | 10.1.26100.2454+ | [ADK Download](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) | December 2024 or newer |
| **Windows PE Addon** | Matching ADK | Same page as ADK | Required for OSD |
| **SCCM Current Branch** | 2403 (baseline) | [Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager) | 2403 is latest baseline |

> **Important**: SCCM 2403+ requires ODBC Driver 18 (version 18.4.1.1+). Install this before SCCM setup or the prerequisite check will fail.
> 
> **Reference**: [Checklist for installing update 2403](https://learn.microsoft.com/en-us/intune/configmgr/core/servers/manage/checklist-for-installing-update-2403)

### Hardware Requirements

| VM | vCPUs | RAM | Disk | Purpose |
|----|-------|-----|------|---------|
| DC01 | 2 | 4GB | 60GB | Domain Controller |
| SCCM01 | 4 | 8GB | 150GB | SQL + SCCM |
| CLIENT01+ | 2 | 4GB | 60GB | Test clients |

**Host Requirements**: Minimum 32GB RAM, SSD storage recommended

### VM Access Methods

```bash
# Method 1: Vagrant WinRM (scripting)
vagrant winrm dc01 -c "hostname"

# Method 2: RDP (GUI tasks)
vagrant rdp dc01
# Or connect manually: localhost:33891 (vagrant/vagrant)

# Method 3: VirtualBox Console
# Open VirtualBox GUI → double-click VM
```

---

## Phase 3A: Domain Controller Setup (DC01)

### Overview

The Domain Controller provides:
- **Active Directory Domain Services (AD DS)**: Centralized identity and authentication
- **DNS**: Name resolution for the domain
- **DHCP**: Automatic IP configuration for clients

### Step 1: Install AD DS Role

**What we're doing**: Installing the Active Directory Domain Services binaries.

#### PowerShell Method (Recommended)

```powershell
# Install AD DS role with management tools
# Documentation: https://learn.microsoft.com/en-us/powershell/module/servermanager/install-windowsfeature
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature

# Verify installation
Get-WindowsFeature -Name AD-Domain-Services | Format-List Name, InstallState
```

#### GUI Method

1. Open **Server Manager** (starts automatically on login)
2. Click **Manage** → **Add Roles and Features**
3. Click **Next** through wizard pages until **Server Roles**
4. Check **Active Directory Domain Services**
5. Click **Add Features** when prompted for management tools
6. Click **Next** → **Install**
7. Wait for installation to complete

### Step 2: Promote to Domain Controller

**What we're doing**: Creating a new Active Directory forest with the domain `lab.local`.

#### PowerShell Method

```powershell
# Import the AD DS Deployment module
# Documentation: https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest
Import-Module ADDSDeployment

# Create secure password for Directory Services Restore Mode (DSRM)
# IMPORTANT: Save this password securely - needed for AD recovery
$DSRMPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Promote to domain controller and create new forest
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetBIOSName "LAB" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDNS:$true `
    -SafeModeAdministratorPassword $DSRMPassword `
    -Force:$true `
    -NoRebootOnCompletion:$false

# Server will automatically reboot
# After reboot, login as: LAB\Administrator (password: vagrant)
```

**Parameter Explanations**:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `-DomainName` | "lab.local" | FQDN of the new domain |
| `-DomainNetBIOSName` | "LAB" | Legacy name (max 15 characters) |
| `-ForestMode` | "WinThreshold" | Windows Server 2016+ functional level |
| `-DomainMode` | "WinThreshold" | Same as forest (cannot be higher) |
| `-InstallDNS` | $true | Install DNS Server role |
| `-SafeModeAdministratorPassword` | SecureString | DSRM recovery password |

> **Reference**: [Install-ADDSForest Documentation](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest)

#### GUI Method

1. In Server Manager, click the **notification flag** (yellow warning icon)
2. Click **Promote this server to a domain controller**
3. Select **Add a new forest**
4. Enter Root domain name: `lab.local`
5. Click **Next**
6. Set Forest/Domain functional level to **Windows Server 2016**
7. Keep **Domain Name System (DNS) server** checked
8. Enter DSRM password (save this securely!)
9. Click **Next** through remaining screens (accept defaults)
10. Click **Install**
11. Server will reboot automatically

### Step 3: Verify AD DS Installation

After reboot, verify the domain controller is functioning:

```powershell
# Login as LAB\Administrator

# Verify domain exists
# Documentation: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomain
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode

# Expected output:
# DNSRoot      : lab.local
# NetBIOSName  : LAB
# DomainMode   : Windows2016Domain

# Verify this server is a domain controller
Get-ADDomainController -Filter * | Select-Object Name, Domain, IsGlobalCatalog

# Verify DNS zones were created
Get-DnsServerZone | Select-Object ZoneName, ZoneType

# Verify AD services are running
Get-Service NTDS, DNS, Kdc, Netlogon | Format-Table Name, Status, StartType
```

### Step 4: Configure DNS

**What we're doing**: Setting up reverse DNS lookup and forwarders for internet resolution.

#### PowerShell Method

```powershell
# 1. Create reverse lookup zone for the lab network
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dnsserver/add-dnsserverprimaryzone
Add-DnsServerPrimaryZone `
    -NetworkId "192.168.56.0/24" `
    -ReplicationScope "Forest" `
    -DynamicUpdate "Secure"

# 2. Create static A record for SCCM01
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dnsserver/add-dnsserverresourcerecorda
Add-DnsServerResourceRecordA `
    -ZoneName "lab.local" `
    -Name "sccm01" `
    -IPv4Address "192.168.56.11" `
    -CreatePtr  # Also creates reverse PTR record

# 3. Configure DNS forwarders for internet resolution
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverforwarder
Set-DnsServerForwarder -IPAddress "8.8.8.8", "1.1.1.1"

# 4. Verify configuration
Get-DnsServerZone | Format-Table ZoneName, ZoneType
Get-DnsServerForwarder
Resolve-DnsName -Name sccm01.lab.local
Resolve-DnsName -Name www.google.com
```

#### GUI Method

1. Open **DNS Manager** (Server Manager → Tools → DNS)
2. **Create Reverse Lookup Zone**:
   - Right-click **Reverse Lookup Zones** → **New Zone**
   - Select **Primary zone**, check **Store in Active Directory**
   - Select **To all DNS servers in this forest**
   - Select **IPv4 Reverse Lookup Zone**
   - Enter Network ID: `192.168.56`
   - Allow only secure dynamic updates
   - Click **Finish**
3. **Create A Record for SCCM01**:
   - Expand **Forward Lookup Zones** → **lab.local**
   - Right-click → **New Host (A or AAAA)**
   - Name: `sccm01`, IP: `192.168.56.11`
   - Check **Create associated pointer (PTR) record**
   - Click **Add Host**
4. **Configure Forwarders**:
   - Right-click **DC01** (server name) → **Properties**
   - Click **Forwarders** tab
   - Click **Edit** → Add `8.8.8.8` and `1.1.1.1`
   - Click **OK**

### Step 5: Install and Configure DHCP

**What we're doing**: Setting up DHCP so clients automatically receive IP addresses.

#### PowerShell Method

```powershell
# 1. Install DHCP Server role
# Documentation: https://learn.microsoft.com/en-us/powershell/module/servermanager/install-windowsfeature
Install-WindowsFeature -Name DHCP -IncludeManagementTools

# 2. Authorize DHCP server in Active Directory
# NOTE: Requires Enterprise Admins membership - add vagrant to this group if needed
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dhcpserver/add-dhcpserverindc
Add-DhcpServerInDC -DnsName "dc01.lab.local" -IPAddress 192.168.56.10

# 3. Suppress Server Manager configuration notification
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2

# 4. Create DHCP scope for lab network
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dhcpserver/add-dhcpserverv4scope
Add-DhcpServerv4Scope `
    -Name "Lab Network" `
    -StartRange 192.168.56.100 `
    -EndRange 192.168.56.200 `
    -SubnetMask 255.255.255.0 `
    -State Active `
    -LeaseDuration (New-TimeSpan -Hours 8)

# 5. Set DHCP options (DNS, Gateway, Domain)
# Documentation: https://learn.microsoft.com/en-us/powershell/module/dhcpserver/set-dhcpserverv4optionvalue
Set-DhcpServerv4OptionValue `
    -ScopeId 192.168.56.0 `
    -Router 192.168.56.1 `
    -DnsServer 192.168.56.10 `
    -DnsDomain "lab.local"

# 6. Verify DHCP configuration
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, State
Get-DhcpServerv4OptionValue -ScopeId 192.168.56.0 | Format-Table OptionId, Name, Value
```

#### GUI Method

1. Open **Server Manager** → **Tools** → **DHCP**
2. **Authorize Server**:
   - Right-click **dc01.lab.local** → **Authorize**
   - Press F5 to refresh (icons should turn green)
3. **Create Scope**:
   - Right-click **IPv4** → **New Scope**
   - Name: `Lab Network`
   - Start IP: `192.168.56.100`, End IP: `192.168.56.200`
   - Subnet mask: `255.255.255.0`
   - No exclusions needed
   - Lease duration: 8 hours (or default)
   - Select **Yes, configure options now**
4. **Configure Options**:
   - Router: `192.168.56.1`
   - Parent domain: `lab.local`, DNS: `192.168.56.10`
   - Skip WINS
   - Select **Yes, activate scope now**
   - Click **Finish**

### Step 6: Create Organizational Units

**What we're doing**: Creating an organized structure for AD objects.

#### PowerShell Method

```powershell
# Create OU structure
# Documentation: https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adorganizationalunit

# Top-level OUs
New-ADOrganizationalUnit -Name "Servers" -Path "DC=lab,DC=local" -Description "Domain member servers"
New-ADOrganizationalUnit -Name "Workstations" -Path "DC=lab,DC=local" -Description "Domain workstations"
New-ADOrganizationalUnit -Name "Lab Users" -Path "DC=lab,DC=local" -Description "Lab user accounts"
New-ADOrganizationalUnit -Name "Service Accounts" -Path "DC=lab,DC=local" -Description "Service and automation accounts"

# Sub-OUs under Lab Users
New-ADOrganizationalUnit -Name "Administrators" -Path "OU=Lab Users,DC=lab,DC=local" -Description "Admin accounts"
New-ADOrganizationalUnit -Name "Standard Users" -Path "OU=Lab Users,DC=lab,DC=local" -Description "Standard user accounts"

# Verify
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Format-Table
```

#### GUI Method

1. Open **Active Directory Users and Computers** (Server Manager → Tools)
2. Right-click **lab.local** → **New** → **Organizational Unit**
3. Create each OU:
   - `Servers`
   - `Workstations`
   - `Lab Users`
   - `Service Accounts`
4. Expand `Lab Users`, create sub-OUs:
   - `Administrators`
   - `Standard Users`

### Step 7: Create Service Accounts

**What we're doing**: Creating dedicated accounts for SQL Server and SCCM services.

> **Best Practice (2026)**: Consider using Group Managed Service Accounts (gMSA) for automatic password rotation. For this lab, we'll use standard service accounts for simplicity.

#### PowerShell Method

```powershell
# Create secure password for service accounts
# In production, use unique passwords for each account!
$ServicePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# SQL_Service - Runs SQL Server services
# Documentation: https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser
New-ADUser `
    -Name "SQL_Service" `
    -SamAccountName "SQL_Service" `
    -UserPrincipalName "SQL_Service@lab.local" `
    -Path "OU=Service Accounts,DC=lab,DC=local" `
    -AccountPassword $ServicePassword `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -Description "SQL Server service account"

# SCCM_NAA - Network Access Account for SCCM client content access
New-ADUser `
    -Name "SCCM_NAA" `
    -SamAccountName "SCCM_NAA" `
    -UserPrincipalName "SCCM_NAA@lab.local" `
    -Path "OU=Service Accounts,DC=lab,DC=local" `
    -AccountPassword $ServicePassword `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -Description "SCCM Network Access Account"

# SCCM_ClientPush - Client push installation account
New-ADUser `
    -Name "SCCM_ClientPush" `
    -SamAccountName "SCCM_ClientPush" `
    -UserPrincipalName "SCCM_ClientPush@lab.local" `
    -Path "OU=Service Accounts,DC=lab,DC=local" `
    -AccountPassword $ServicePassword `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -Description "SCCM Client Push Installation Account"

# SCCM_JoinDomain - OSD domain join account
New-ADUser `
    -Name "SCCM_JoinDomain" `
    -SamAccountName "SCCM_JoinDomain" `
    -UserPrincipalName "SCCM_JoinDomain@lab.local" `
    -Path "OU=Service Accounts,DC=lab,DC=local" `
    -AccountPassword $ServicePassword `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -Description "SCCM OSD Domain Join Account"

# Grant SCCM_JoinDomain permission to create computer objects
$WorkstationsOU = "OU=Workstations,DC=lab,DC=local"
dsacls $WorkstationsOU /G "LAB\SCCM_JoinDomain:CCDC;computer"
dsacls $WorkstationsOU /G "LAB\SCCM_JoinDomain:RPWPCA;;computer"

# Verify accounts
Get-ADUser -Filter * -SearchBase "OU=Service Accounts,DC=lab,DC=local" | 
    Select-Object Name, SamAccountName, Enabled | Format-Table
```

#### GUI Method

1. Open **Active Directory Users and Computers**
2. Navigate to **lab.local** → **Service Accounts**
3. For each account (SQL_Service, SCCM_NAA, SCCM_ClientPush, SCCM_JoinDomain):
   - Right-click → **New** → **User**
   - Enter name and logon name
   - Set password
   - Check **Password never expires**
   - Finish
4. For SCCM_JoinDomain permissions:
   - Right-click **Workstations** OU → **Properties**
   - Click **Security** tab → **Advanced**
   - Click **Add** → Enter `SCCM_JoinDomain`
   - Select **This object and all descendant objects**
   - Grant: Create/Delete Computer objects, Reset Password, Write all properties

### Step 8: Prepare AD for SCCM

**What we're doing**: Extending the AD schema and creating the System Management container.

> **Note**: This step requires SCCM installation media. Complete this after mounting the SCCM ISO.

#### PowerShell Method

```powershell
# Run from DC01 as Enterprise Admin
# Assumes SCCM media is at D:\ or C:\SCCM_Install

# 1. Extend AD Schema (run extadsch.exe from SCCM media)
# Documentation: https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/network/extend-the-active-directory-schema
Set-Location "D:\SMSSETUP\BIN\X64"  # Adjust path as needed
.\extadsch.exe

# Check the log for success
Get-Content "C:\ExtADSch.log" | Select-Object -Last 20
# Should show: "Successfully extended the Active Directory schema."

# 2. Create System Management container
Import-Module ActiveDirectory
$DomainDN = (Get-ADDomain).DistinguishedName
$SystemContainer = "CN=System,$DomainDN"

$ExistingContainer = Get-ADObject -Filter {Name -eq "System Management"} -SearchBase $SystemContainer -ErrorAction SilentlyContinue
if (-not $ExistingContainer) {
    New-ADObject -Type Container -Name "System Management" -Path $SystemContainer
    Write-Host "System Management container created successfully" -ForegroundColor Green
} else {
    Write-Host "System Management container already exists" -ForegroundColor Yellow
}

# 3. Grant SCCM01 Full Control on System Management container
# Run this AFTER SCCM01 has joined the domain
$SystemManagementDN = "CN=System Management,CN=System,$DomainDN"
dsacls $SystemManagementDN /G "LAB\SCCM01$:GA" /I:T

# Verify
dsacls $SystemManagementDN | Select-String "SCCM01"
```

#### GUI Method

1. **Extend Schema**:
   - Mount SCCM ISO
   - Open Command Prompt as Administrator
   - Navigate to `D:\SMSSETUP\BIN\X64`
   - Run `extadsch.exe`
   - Check `C:\ExtADSch.log` for success
   NOTE: You likely need to run extadsch.exe from C: so that it can easily find all needed .dll files.

2. **Create System Management Container**:
   - Open **ADSI Edit** (Run: `adsiedit.msc`)
   - Connect to Default naming context
   - Navigate to **DC=lab,DC=local** → **CN=System**
   - Right-click **CN=System** → **New** → **Object**
   - Select **container**, name it `System Management`

3. **Grant Permissions**:
   - Right-click **CN=System Management** → **Properties**
   - Click **Security** tab → **Advanced**
   - Click **Add** → Enter `SCCM01$` (note the $ for computer account)
   - Select **This object and all descendant objects**
   - Grant **Full control**
   - Click **OK**

---

## Phase 3B: SQL Server Installation (SCCM01)

### Overview

SQL Server provides the database backend for Configuration Manager. Critical configuration:
- **Collation**: Must be `SQL_Latin1_General_CP1_CI_AS`
- **Memory**: Leave 2-4GB for OS, allocate rest to SQL
- **Authentication**: Windows Authentication only

> **Reference**: [Supported SQL Server versions for Configuration Manager](https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/support-for-sql-server-versions)

### Step 9: Join SCCM01 to Domain

**Before SQL installation, join SCCM01 to the domain.**

#### PowerShell Method

```powershell
# On SCCM01

# 1. Configure DNS to point to DC01
$HostOnlyAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*Ethernet 2*" -or $_.InterfaceDescription -like "*Host-Only*" }
Set-DnsClientServerAddress -InterfaceIndex $HostOnlyAdapter.InterfaceIndex -ServerAddresses "192.168.56.10"

# 2. Verify DNS resolution
Resolve-DnsName -Name dc01.lab.local
Resolve-DnsName -Name lab.local

# 3. Join domain
# Documentation: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer
$Credential = Get-Credential -Message "Enter domain admin credentials (LAB\Administrator)"
Add-Computer `
    -DomainName "lab.local" `
    -Credential $Credential `
    -OUPath "OU=Servers,DC=lab,DC=local" `
    -Restart

# After reboot, login as LAB\Administrator
```

#### GUI Method

1. Open **Settings** → **System** → **About** → **Rename this PC (advanced)**
2. Click **Change** next to "To rename this computer or change its domain..."
3. Select **Domain**, enter `lab.local`
4. Enter credentials: `LAB\Administrator` / `vagrant`
5. Click **OK**, restart when prompted

### Step 10: Install SQL Server Prerequisites

```powershell
# On SCCM01 (logged in as LAB\Administrator)

# Install .NET Framework 3.5
# NOTE: May require Windows installation media as source
Install-WindowsFeature -Name NET-Framework-Core

# Verify .NET 4.8 is present (included in Server 2022)
$release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
if ($release -ge 528040) {
    Write-Host ".NET Framework 4.8 or later is installed" -ForegroundColor Green
}

# Open firewall for SQL Server
New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow
New-NetFirewallRule -DisplayName "SQL Server Browser (UDP 1434)" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow
```

### Step 11: Install SQL Server 2022

**Critical**: The collation setting cannot be changed after installation. Ensure you select `SQL_Latin1_General_CP1_CI_AS`.

> **Reference**: [Install SQL Server 2022 for SCCM](https://www.prajwaldesai.com/install-sql-server-2022-for-sccm-configmgr/)

#### PowerShell Method (Unattended)

```powershell
# Create SQL Server configuration file
$SQLConfigContent = @"
[OPTIONS]
ACTION="Install"
FEATURES=SQLENGINE,REPLICATION,FULLTEXT
INSTANCENAME="MSSQLSERVER"
INSTANCEID="MSSQLSERVER"

; Collation - CRITICAL FOR SCCM!
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"

; Service accounts (use domain accounts)
SQLSVCACCOUNT="LAB\SQL_Service"
SQLSVCPASSWORD="P@ssw0rd123!"
SQLSVCSTARTUPTYPE="Automatic"
AGTSVCACCOUNT="LAB\SQL_Service"
AGTSVCPASSWORD="P@ssw0rd123!"
AGTSVCSTARTUPTYPE="Automatic"
BROWSERSVCSTARTUPTYPE="Automatic"

; Security - Windows Authentication only
SECURITYMODE="Windows"
SQLSYSADMINACCOUNTS="LAB\Administrator" "LAB\Domain Admins" "BUILTIN\Administrators"

; Installation paths
INSTALLSQLDATADIR="C:\Program Files\Microsoft SQL Server"

; Quiet install
QUIET="True"
QUIETSIMPLE="True"
IACCEPTSQLSERVERLICENSETERMS="True"
UpdateEnabled="False"
"@

# Save configuration file
$SQLConfigContent | Out-File -FilePath "C:\SQLConfig.ini" -Encoding ASCII

# Run SQL Server setup (adjust path to your ISO/media location)
# Documentation: https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt
Start-Process -FilePath "D:\setup.exe" -ArgumentList "/ConfigurationFile=C:\SQLConfig.ini" -Wait -NoNewWindow

# Check installation log
Get-Content "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt" | Select-Object -Last 30
```

#### GUI Method

1. Mount SQL Server 2022 ISO
2. Run `setup.exe`
3. Click **Installation** → **New SQL Server stand-alone installation**
4. Enter product key or select **Developer** (free)
5. Accept license terms
6. **Feature Selection**:
   - ☑ Database Engine Services
   - ☑ SQL Server Replication
   - ☑ Full-Text and Semantic Extractions for Search
7. **Instance Configuration**: Default instance (MSSQLSERVER)
8. **Server Configuration**:
   - SQL Server Agent: `LAB\SQL_Service`, Automatic
   - SQL Server Database Engine: `LAB\SQL_Service`, Automatic
   - SQL Server Browser: Automatic
9. **Database Engine Configuration**:
   - **Authentication**: Windows authentication mode
   - Click **Add Current User** (adds LAB\Administrator)
   - Click **Add** → Add `LAB\Domain Admins`
   - **CRITICAL**: Click **Collation** tab → Click **Customize**
   - Select `SQL_Latin1_General_CP1_CI_AS`
10. Click **Next** → **Install**
11. Wait for installation to complete (10-20 minutes)

### Step 12: Configure SQL Server Post-Installation

```powershell
# 1. VERIFY COLLATION (Critical!)
# Documentation: https://www.prajwaldesai.com/sccm-prerequisite-required-sql-server-collation/
$Collation = Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation"
if ($Collation.Collation -eq "SQL_Latin1_General_CP1_CI_AS") {
    Write-Host "✓ Collation is correct: $($Collation.Collation)" -ForegroundColor Green
} else {
    Write-Host "✗ WRONG COLLATION: $($Collation.Collation) - REINSTALL SQL SERVER!" -ForegroundColor Red
    throw "SQL Server must be reinstalled with correct collation"
}

# 2. Configure max server memory (leave 4GB for OS on 8GB VM)
$TotalMemoryMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$SQLMemoryMB = $TotalMemoryMB - 4096
Invoke-Sqlcmd -Query @"
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory', $SQLMemoryMB;
RECONFIGURE;
"@
Write-Host "SQL Server max memory set to $SQLMemoryMB MB" -ForegroundColor Green

# 3. Enable TCP/IP protocol
Import-Module SqlServer -ErrorAction SilentlyContinue
# If SqlServer module not available, use SQL Server Configuration Manager GUI

# 4. Restart SQL Server to apply changes
Restart-Service -Name MSSQLSERVER -Force
Start-Sleep -Seconds 10

# 5. Verify SQL Server is running
Get-Service MSSQLSERVER, SQLSERVERAGENT | Format-Table Name, Status, StartType

# 6. Test connection
Invoke-Sqlcmd -Query "SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version" | Format-List
```

### Step 13: Install ODBC Driver 18

**Required for SCCM 2403+**. This is a blocking prerequisite.

```powershell
# Download ODBC Driver 18
# Documentation: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
$ODBCUrl = "https://go.microsoft.com/fwlink/?linkid=2249006"  # x64 version
$ODBCPath = "C:\Temp\msodbcsql.msi"

New-Item -ItemType Directory -Path "C:\Temp" -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri $ODBCUrl -OutFile $ODBCPath

# Install silently
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ODBCPath`" /quiet /norestart IACCEPTMSODBCSQLLICENSETERMS=YES" -Wait

# Verify installation
Get-ItemProperty "HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server" -ErrorAction SilentlyContinue
```

---

## Phase 3C: SCCM Installation (SCCM01)

### Overview

Configuration Manager installation involves:
1. Installing Windows prerequisites (IIS, BITS, etc.)
2. Installing Windows ADK and WinPE
3. Running the SCCM setup
4. Post-installation configuration

> **Reference**: [Site and site system prerequisites](https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/site-and-site-system-prerequisites)

### Step 14: Install SCCM Prerequisites

#### Windows Features

```powershell
# Install required Windows features for SCCM site server, MP, and DP
# Documentation: https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/site-and-site-system-prerequisites

$Features = @(
    # .NET Framework
    "NET-Framework-Core",           # .NET 3.5
    "NET-Framework-45-Features",    # .NET 4.5+
    
    # Background Intelligent Transfer Service
    "BITS",
    "BITS-IIS-Ext",
    
    # Remote Differential Compression
    "RDC",
    
    # Windows Process Activation Service
    "WAS",
    "WAS-Config-APIs",
    "WAS-Process-Model",
    
    # IIS (Web Server)
    "Web-Server",
    "Web-WebServer",
    "Web-Common-Http",
    "Web-Default-Doc",
    "Web-Dir-Browsing",
    "Web-Http-Errors",
    "Web-Static-Content",
    "Web-Http-Redirect",
    "Web-Health",
    "Web-Http-Logging",
    "Web-Log-Libraries",
    "Web-Request-Monitor",
    "Web-Http-Tracing",
    "Web-Performance",
    "Web-Stat-Compression",
    "Web-Dyn-Compression",
    "Web-Security",
    "Web-Filtering",
    "Web-Basic-Auth",
    "Web-Windows-Auth",
    "Web-URL-Auth",
    "Web-IP-Security",
    "Web-App-Dev",
    "Web-Net-Ext",
    "Web-Net-Ext45",
    "Web-ASP",
    "Web-ASP-Net",
    "Web-ASP-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Mgmt-Tools",
    "Web-Mgmt-Console",
    "Web-Mgmt-Compat",
    "Web-Metabase",
    "Web-WMI",
    "Web-Scripting-Tools"
)

Install-WindowsFeature -Name $Features -IncludeManagementTools

# Verify installation
Get-WindowsFeature | Where-Object { $_.Installed -eq $true -and $_.Name -like "Web-*" } | 
    Select-Object Name, InstallState | Format-Table
```

#### Windows ADK and WinPE

```powershell
# Download Windows ADK (December 2024 or later recommended)
# Documentation: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
$ADKUrl = "https://go.microsoft.com/fwlink/?linkid=2243390"
$ADKPath = "C:\Temp\adksetup.exe"

Invoke-WebRequest -Uri $ADKUrl -OutFile $ADKPath

# Install ADK with required features for SCCM
# Features needed: Deployment Tools, User State Migration Tool
Start-Process -FilePath $ADKPath -ArgumentList "/features OptionId.DeploymentTools OptionId.UserStateMigrationTool /quiet /norestart" -Wait

# Download and install WinPE addon
$WinPEUrl = "https://go.microsoft.com/fwlink/?linkid=2243391"
$WinPEPath = "C:\Temp\adkwinpesetup.exe"

Invoke-WebRequest -Uri $WinPEUrl -OutFile $WinPEPath
Start-Process -FilePath $WinPEPath -ArgumentList "/features + /quiet /norestart" -Wait

# Verify ADK installation
$ADKPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
if (Test-Path $ADKPath) {
    $ADKVersion = (Get-ItemProperty $ADKPath).KitsRoot10
    Write-Host "ADK installed at: $ADKVersion" -ForegroundColor Green
}
```

### Step 15: Install SCCM

> **Reference**: [Install a primary site using the Setup Wizard](https://learn.microsoft.com/en-us/mem/configmgr/core/servers/deploy/install/use-the-setup-wizard-to-install-sites)

#### Run Prerequisite Checker First

```powershell
# Mount SCCM ISO and run prerequisite checker
Set-Location "D:\SMSSETUP\BIN\X64"

# Run prerequisite check
.\prereqchk.exe /LOCAL

# Review output - all checks should pass
# Common failures:
# - Wrong SQL collation (reinstall SQL)
# - Missing Windows features (install them)
# - ODBC Driver 18 missing (install it)
# - Pending reboot (reboot and re-run)
```

#### PowerShell Method (Unattended)

```powershell
# Create SCCM installation configuration file
# Documentation: https://learn.microsoft.com/en-us/mem/configmgr/core/servers/deploy/install/command-line-script-file
$SCCMConfigContent = @"
[Identification]
Action=InstallPrimarySite

[Options]
ProductID=EVAL
SiteCode=PS1
SiteName=Primary Site 1
SMSInstallDir=C:\Program Files\Microsoft Configuration Manager
SDKServer=SCCM01.lab.local
PrerequisiteComp=1
PrerequisitePath=C:\SCCM_Prereqs
AdminConsole=1
JoinCEIP=0

[SQLConfigOptions]
SQLServerName=SCCM01.lab.local
DatabaseName=CM_PS1
SQLServerPort=1433
SQLSSBPort=4022

[CloudConnectorOptions]
CloudConnector=0

[SABranchOptions]
SAActive=0
CurrentBranch=1
"@

$SCCMConfigContent | Out-File -FilePath "C:\Temp\ConfigMgrSetup.ini" -Encoding ASCII

# Create prerequisites download folder
New-Item -ItemType Directory -Path "C:\SCCM_Prereqs" -Force

# Download prerequisites (optional - setup can download them)
# .\setupdl.exe C:\SCCM_Prereqs

# Run SCCM installation
# This takes 30-60 minutes!
Start-Process -FilePath "D:\SMSSETUP\BIN\X64\setup.exe" -ArgumentList "/SCRIPT `"C:\Temp\ConfigMgrSetup.ini`"" -Wait

# Monitor installation progress in another window:
# Get-Content "C:\ConfigMgrSetup.log" -Tail 50 -Wait
```

#### GUI Method

1. Mount SCCM ISO
2. Run `splash.hta` or `D:\SMSSETUP\BIN\X64\setup.exe`
3. Click **Install**
4. **Before You Begin**: Click **Next**
5. **Getting Started**: Select **Install a Configuration Manager primary site**
6. **Product Key**: Enter key or select **Install the evaluation edition**
7. **License Terms**: Accept all license terms
8. **Prerequisite Downloads**: Specify path (`C:\SCCM_Prereqs`) or use previously downloaded
9. **Server Language**: English (or your preference)
10. **Client Language**: English
11. **Site and Installation Settings**:
    - Site code: `PS1`
    - Site name: `Primary Site 1`
    - Installation folder: Accept default
12. **Primary Site Installation**: Select **Install as stand-alone primary site**
13. **Database Information**:
    - SQL Server name: `SCCM01.lab.local`
    - Instance: (leave blank for default)
    - Database name: `CM_PS1`
14. **SMS Provider Settings**: Accept default (`SCCM01.lab.local`)
15. **Client Communication**: Select **Configure each site system role to use HTTPs or HTTP** (Enhanced HTTP)
    - Check **Use Configuration Manager-generated certificates for HTTP site systems**
16. **Site System Roles**: Check both **Management Point** and **Distribution Point**
17. **Usage Data**: Choose your preference
18. **Service Connection Point**: Accept default (Online)
19. **Settings Summary**: Review and click **Next**
20. **Prerequisite Check**: All should pass (green). Click **Begin Install**
21. Wait 30-60 minutes for installation

### Step 16: Verify SCCM Installation

```powershell
# Check SCCM services
Get-Service SMS_EXECUTIVE, SMS_SITE_COMPONENT_MANAGER | Format-Table Name, Status, StartType

# Both should show: Running

# Check site status via WMI
Get-WmiObject -Namespace "root\SMS\site_PS1" -Class SMS_Site | 
    Select-Object SiteCode, SiteName, Version

# Open SCCM Console
& "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
```

### Step 17: Configure SCCM Post-Installation

> **Reference**: [Configure discovery methods](https://learn.microsoft.com/en-us/mem/configmgr/core/servers/deploy/configure/configure-discovery-methods)

#### PowerShell Method

```powershell
# Import Configuration Manager module
# Documentation: https://learn.microsoft.com/en-us/powershell/sccm/overview
$SiteCode = "PS1"
Import-Module "$($env:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
Set-Location "$($SiteCode):"

# 1. Create IP Subnet Boundary
# Documentation: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmboundary
New-CMBoundary -Type IPSubnet -Name "Lab Network - 192.168.56.0/24" -Value "192.168.56.0/24"

# 2. Create Boundary Group
# Documentation: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmboundarygroup
New-CMBoundaryGroup -Name "Lab Network Boundary Group"

# 3. Add boundary to boundary group
$Boundary = Get-CMBoundary -BoundaryName "Lab Network - 192.168.56.0/24"
$BoundaryGroup = Get-CMBoundaryGroup -Name "Lab Network Boundary Group"
Add-CMBoundaryToGroup -BoundaryId $Boundary.BoundaryID -BoundaryGroupId $BoundaryGroup.GroupID

# 4. Configure boundary group for site assignment and content
Set-CMBoundaryGroup `
    -Name "Lab Network Boundary Group" `
    -DefaultSiteCode "PS1"

# Add site system server (SCCM01) to boundary group
$SiteServer = Get-CMSiteSystemServer -SiteSystemServerName "SCCM01.lab.local"
Add-CMBoundaryGroupSiteSystem -BoundaryGroupName "Lab Network Boundary Group" -SiteSystemServer $SiteServer

# 5. Enable Active Directory System Discovery
# Documentation: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/set-cmdiscoverymethod
Set-CMDiscoveryMethod -ActiveDirectorySystemDiscovery -SiteCode "PS1" -Enabled $true

# Add AD container for discovery
$ADContainer = New-CMActiveDirectoryForest -ForestFqdn "lab.local" -EnableDiscovery $true
Set-CMDiscoveryMethod -ActiveDirectorySystemDiscovery -SiteCode "PS1" `
    -ActiveDirectoryContainer "LDAP://OU=Workstations,DC=lab,DC=local" -Recursive

# 6. Enable Active Directory User Discovery
Set-CMDiscoveryMethod -ActiveDirectoryUserDiscovery -SiteCode "PS1" -Enabled $true

# 7. Configure Network Access Account
# Documentation: https://learn.microsoft.com/en-us/powershell/module/configurationmanager/set-cmaccount
$NAAPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force
New-CMAccount -Name "LAB\SCCM_NAA" -Password $NAAPassword -SiteCode "PS1"
Set-CMSoftwareDistributionComponent -SiteCode "PS1" -NetworkAccessAccountName "LAB\SCCM_NAA"

# 8. Verify configuration
Write-Host "`n=== SCCM Configuration Summary ===" -ForegroundColor Cyan
Get-CMBoundary | Format-Table DisplayName, BoundaryType, Value
Get-CMBoundaryGroup | Format-Table Name, SiteSystemCount
```

#### GUI Method (SCCM Console)

1. **Create Boundary**:
   - Navigate to **Administration** → **Hierarchy Configuration** → **Boundaries**
   - Right-click → **Create Boundary**
   - Description: `Lab Network`
   - Type: **IP subnet**
   - Network: `192.168.56.0`, Subnet mask: `255.255.255.0`

2. **Create Boundary Group**:
   - Navigate to **Boundary Groups**
   - Right-click → **Create Boundary Group**
   - Name: `Lab Network Boundary Group`
   - Click **Add** → Select `Lab Network` boundary
   - **References** tab:
     - Check **Use this boundary group for site assignment**
     - Site: `PS1 - Primary Site 1`
   - Click **Add** under Site system servers → Add `SCCM01.lab.local`

3. **Configure Discovery**:
   - Navigate to **Administration** → **Hierarchy Configuration** → **Discovery Methods**
   - **Active Directory System Discovery**: Right-click → **Properties**
     - Check **Enable Active Directory System Discovery**
     - Click **New** (yellow star) → Browse to `OU=Workstations,DC=lab,DC=local`
     - Check **Recursively search Active Directory child containers**
   - **Active Directory User Discovery**: Enable similarly

4. **Configure Network Access Account**:
   - Navigate to **Administration** → **Site Configuration** → **Sites**
   - Select **PS1** → Click **Configure Site Components** → **Software Distribution**
   - **Network Access Account** tab → **Specify the account**
   - Click **Set** → **New Account** → Enter `LAB\SCCM_NAA` with password

---

## Phase 3D: Client Configuration

### Step 18: Join Clients to Domain

```powershell
# On CLIENT01

# 1. Set DNS to DC01
$Adapter = Get-NetAdapter | Where-Object { $_.Name -like "*Ethernet 2*" }
Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses "192.168.56.10"

# 2. Verify DNS
Resolve-DnsName -Name dc01.lab.local
Resolve-DnsName -Name sccm01.lab.local

# 3. Join domain
$Credential = Get-Credential -Message "Enter LAB\Administrator credentials"
Add-Computer -DomainName "lab.local" -Credential $Credential -OUPath "OU=Workstations,DC=lab,DC=local" -Restart
```

### Step 19: Install SCCM Client

#### Option 1: Client Push (Automatic)

Configure in SCCM Console:
1. Navigate to **Administration** → **Site Configuration** → **Client Installation Settings** → **Client Push Installation**
2. Right-click → **Properties**
3. **General** tab:
   - Check **Enable automatic site-wide client push installation**
   - Check **Workstations**
4. **Accounts** tab:
   - Click **New** → Enter `LAB\SCCM_ClientPush` with password
   - This account needs local admin rights on target computers

#### Option 2: Manual Installation

```powershell
# On CLIENT01 (after domain join)

# Copy client files from SCCM01
$Source = "\\SCCM01\SMS_PS1\Client"
$Dest = "C:\Temp\CCMSetup"
New-Item -ItemType Directory -Path $Dest -Force
Copy-Item -Path "$Source\*" -Destination $Dest -Recurse

# Install SCCM client
# Documentation: https://learn.microsoft.com/en-us/mem/configmgr/core/clients/deploy/about-client-installation-properties
Start-Process -FilePath "$Dest\ccmsetup.exe" -ArgumentList "/mp:SCCM01.lab.local SMSSITECODE=PS1" -Wait

# Monitor installation
Get-Content "C:\Windows\ccmsetup\Logs\ccmsetup.log" -Tail 20 -Wait
```

### Step 20: Verify Client Installation

```powershell
# Check SCCM client service
Get-Service CcmExec | Format-List Name, Status, StartType

# Check assigned site code
$Client = New-Object -ComObject Microsoft.SMS.Client
$Client.GetAssignedSite()
# Should return: PS1

# Check client version
(Get-WmiObject -Namespace "root\ccm" -Class SMS_Client).ClientVersion

# Force policy refresh
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}"
```

---

## Phase 3.5: Intune Integration (Optional)

This section covers connecting your SCCM environment to Microsoft Intune for hybrid management.

> **Reference**: [Tutorial: Enable co-management for existing clients](https://learn.microsoft.com/en-us/mem/configmgr/comanage/tutorial-co-manage-clients)

### Prerequisites for Intune Integration

| Requirement | Details |
|-------------|---------|
| Azure subscription | Free trial acceptable |
| Microsoft Intune license | E3/E5 trial or developer subscription |
| Microsoft Entra ID P1/P2 | Included with E3/E5 |
| Global Administrator account | For initial setup |
| Hybrid Azure AD Join OR Azure AD Join | For co-management |

### Option 1: Tenant Attach (Simplest)

Tenant attach uploads your SCCM devices to Intune admin center without changing workload management.

> **Reference**: [Enable tenant attach](https://learn.microsoft.com/en-us/mem/configmgr/tenant-attach/device-sync-actions)

**SCCM Console Steps**:

1. Navigate to **Administration** → **Cloud Services** → **Cloud Attach**
2. Right-click **Cloud Attach** → **Configure Cloud Attach**
3. Sign in with Global Administrator account
4. Select **Customize settings**
5. Configure:
   - ☑ Upload to Microsoft Intune admin center
   - ☑ Enable Endpoint analytics
   - Device upload: **All my devices managed by Microsoft Configuration Manager**
6. Click **Next** → **Close**

### Option 2: Co-Management (Full Integration)

Co-management enables shared device management between SCCM and Intune.

#### Step 1: Configure Microsoft Entra Connect

Install Microsoft Entra Connect on DC01 to sync identities to Azure AD.

> **Warning**: Upgrade to version 2.5.79.0+ before September 30, 2026 or sync will stop.
>
> **Reference**: [Microsoft Entra Connect Prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-install-prerequisites)

```powershell
# Download Microsoft Entra Connect
$AADConnectUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=47594"
# Download manually from this page

# Install and configure via wizard:
# 1. Use Express Settings for lab
# 2. Enter Azure AD Global Admin credentials
# 3. Enter on-premises AD Enterprise Admin credentials
# 4. Enable Password Hash Synchronization
```

#### Step 2: Configure Hybrid Azure AD Join

> **Reference**: [Configure Microsoft Entra hybrid join](https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join)

1. In Microsoft Entra Connect wizard, configure device options:
   - Enable **Hybrid Azure AD Join**
   - Select Windows 10/11 devices
2. Create GPO for Service Connection Point (SCP):

```powershell
# On DC01 - Create GPO for Hybrid Join
# This configures clients to register with Azure AD

# The SCP should be configured by Entra Connect
# Verify SCP exists:
Get-ADObject -Filter "Name -like '*62a0ff2e-97b9-4513-943f-0d221bd30080*'" -SearchBase "CN=Configuration,DC=lab,DC=local"
```

#### Step 3: Enable Co-Management

In SCCM Console:

1. Navigate to **Administration** → **Cloud Services** → **Co-management**
2. Click **Configure co-management**
3. Sign in with Intune admin account
4. **Enablement** tab:
   - Automatic enrollment: **Pilot** (start with test collection)
   - Select pilot collection
5. **Workloads** tab:
   - Start with **Compliance policies** (easiest to migrate)
   - Keep other workloads in Configuration Manager initially
6. **Staging** tab: Configure rollout settings
7. Click **OK**

### Workload Migration Best Practices

| Workload | Initial Setting | When to Migrate |
|----------|-----------------|-----------------|
| Compliance policies | Intune (Pilot) | First - immediate value |
| Device configuration | Configuration Manager | After validating profiles |
| Windows Updates | Configuration Manager | After WUfB testing |
| Resource access | Configuration Manager | With certificate migration |
| Endpoint Protection | Configuration Manager | After Defender validation |
| Client apps | Configuration Manager | Keep complex apps in SCCM |

> **Reference**: [Best Practices for Co-Management Workload Distribution](https://mertefekanlikilic.com/best-practices-for-co-management-workload-distribution-in-sccm-and-intune/)

---

## Verification and Testing

### Complete Lab Verification Checklist

```powershell
# Run from your host machine or DC01

Write-Host "=== Lab Verification Checklist ===" -ForegroundColor Cyan

# 1. Active Directory
Write-Host "`n[1] Active Directory" -ForegroundColor Yellow
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode | Format-Table
Get-ADDomainController -Filter * | Select-Object Name, IsGlobalCatalog | Format-Table

# 2. DNS
Write-Host "`n[2] DNS Resolution" -ForegroundColor Yellow
Resolve-DnsName dc01.lab.local -Type A | Select-Object Name, IPAddress
Resolve-DnsName sccm01.lab.local -Type A | Select-Object Name, IPAddress
Resolve-DnsName 192.168.56.10 -Type PTR | Select-Object NameHost

# 3. DHCP
Write-Host "`n[3] DHCP Configuration" -ForegroundColor Yellow
Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State | Format-Table
Get-DhcpServerv4Lease -ScopeId 192.168.56.0 | Select-Object IPAddress, HostName | Format-Table

# 4. SQL Server (run on SCCM01)
Write-Host "`n[4] SQL Server" -ForegroundColor Yellow
Invoke-Command -ComputerName SCCM01 -ScriptBlock {
    Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation, @@VERSION AS Version"
} | Format-List

# 5. SCCM Services (run on SCCM01)
Write-Host "`n[5] SCCM Services" -ForegroundColor Yellow
Invoke-Command -ComputerName SCCM01 -ScriptBlock {
    Get-Service SMS_EXECUTIVE, SMS_SITE_COMPONENT_MANAGER | Select-Object Name, Status
} | Format-Table

# 6. Client Domain Join
Write-Host "`n[6] Domain-Joined Clients" -ForegroundColor Yellow
Get-ADComputer -Filter { OperatingSystem -like "*Windows 10*" -or OperatingSystem -like "*Windows 11*" } | 
    Select-Object Name, DistinguishedName | Format-Table

# 7. SCCM Client (run on CLIENT01)
Write-Host "`n[7] SCCM Client Status" -ForegroundColor Yellow
Invoke-Command -ComputerName CLIENT01 -ScriptBlock {
    Get-Service CcmExec | Select-Object Name, Status
    $Client = New-Object -ComObject Microsoft.SMS.Client
    [PSCustomObject]@{
        AssignedSite = $Client.GetAssignedSite()
    }
} | Format-List
```

### Network Connectivity Tests

```powershell
# From CLIENT01 - Test connectivity to all lab systems
Test-NetConnection -ComputerName dc01.lab.local -Port 389    # LDAP
Test-NetConnection -ComputerName dc01.lab.local -Port 53     # DNS
Test-NetConnection -ComputerName sccm01.lab.local -Port 80   # HTTP
Test-NetConnection -ComputerName sccm01.lab.local -Port 443  # HTTPS
Test-NetConnection -ComputerName sccm01.lab.local -Port 1433 # SQL
```

---

## Troubleshooting

### Domain Controller Issues

| Problem | Solution |
|---------|----------|
| AD DS role won't install | Check Windows features, ensure not a Nano Server |
| Domain promotion fails | Check DNS, verify network connectivity |
| DNS not resolving | Verify DNS service running, check forwarders |
| DHCP authorization fails | Add user to Enterprise Admins, logout/login |

```powershell
# Check AD services
Get-Service NTDS, DNS, Kdc, Netlogon | Format-Table Name, Status

# Check event logs
Get-WinEvent -LogName "Directory Service" -MaxEvents 20 | Format-Table TimeCreated, Message

# Clear DNS cache
Clear-DnsClientCache
ipconfig /flushdns
```

### SQL Server Issues

| Problem | Solution |
|---------|----------|
| Wrong collation | Must reinstall SQL Server |
| Service won't start | Check service account, verify log files |
| Cannot connect | Enable TCP/IP, check firewall, verify service running |

```powershell
# Verify collation (CRITICAL)
Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation')"
# Must be: SQL_Latin1_General_CP1_CI_AS

# Check SQL error logs
Get-Content "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Log\ERRORLOG" | Select-Object -Last 50

# Test SQL connectivity
Test-NetConnection -ComputerName SCCM01 -Port 1433
```

### SCCM Issues

| Problem | Solution |
|---------|----------|
| Prerequisite check fails | Install missing features, verify SQL collation, install ODBC 18 |
| Installation hangs | Check ConfigMgrSetup.log, verify SQL connectivity |
| Console won't open | Check SMS Provider, verify WMI namespace |
| Clients not appearing | Check boundaries, verify client push account |

```powershell
# Monitor SCCM setup log
Get-Content "C:\ConfigMgrSetup.log" -Tail 50 -Wait

# Check SCCM services
Get-Service SMS* | Format-Table Name, Status

# Check site status
Get-WmiObject -Namespace "root\SMS\site_PS1" -Class SMS_ComponentSummarizer | 
    Where-Object { $_.Status -ne 0 } | Select-Object ComponentName, Status

# Client installation logs
Get-Content "C:\Windows\ccmsetup\Logs\ccmsetup.log" -Tail 50
```

### Client Issues

| Problem | Solution |
|---------|----------|
| Domain join fails | Verify DNS settings, check credentials, verify DC reachable |
| Client push fails | Check firewall (445, 135), verify admin$ share, check account permissions |
| Client not assigned | Verify boundaries configured, check site code in ccmsetup |

```powershell
# Test admin share access (from SCCM01)
Test-Path "\\CLIENT01\admin$"

# Check client assignment
$Client = New-Object -ComObject Microsoft.SMS.Client
$Client.GetAssignedSite()

# Force policy update
Invoke-WmiMethod -Namespace "root\ccm" -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}"
```

---

## Security Hardening

### Active Directory Security Best Practices

> **Reference**: [Microsoft's guidance for AD DS security in 2025](https://www.microsoft.com/en-us/windows-server/blog/2025/12/09/microsofts-guidance-to-help-mitigate-critical-threats-to-active-directory-domain-services-in-2025)

#### 1. Implement Fine-Grained Password Policies

```powershell
# Create strong password policy for admin accounts
# Documentation: https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adfinegrainedpasswordpolicy
New-ADFineGrainedPasswordPolicy -Name "Admin Password Policy" `
    -Precedence 10 `
    -MinPasswordLength 14 `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled $true `
    -MaxPasswordAge "90.00:00:00" `
    -MinPasswordAge "1.00:00:00" `
    -LockoutThreshold 5 `
    -LockoutDuration "00:30:00" `
    -LockoutObservationWindow "00:30:00"

# Apply to Domain Admins
Add-ADFineGrainedPasswordPolicySubject -Identity "Admin Password Policy" -Subjects "Domain Admins"
```

#### 2. Protect Privileged Groups

```powershell
# Audit privileged group membership
$PrivilegedGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators")
foreach ($Group in $PrivilegedGroups) {
    Write-Host "`n$Group members:" -ForegroundColor Cyan
    Get-ADGroupMember -Identity $Group | Select-Object Name, ObjectClass | Format-Table
}
```

#### 3. Enable Credential Guard (Production)

For Windows Server 2022/2025 domain controllers, Credential Guard provides additional protection against credential theft.

### SCCM Security Recommendations

1. **Use Enhanced HTTP** instead of plain HTTP
2. **Configure Network Access Account** with minimal permissions
3. **Enable HTTPS** for management points in production
4. **Review boundary groups** to limit content access
5. **Audit administrative actions** via status message queries

---

## Quick Reference

### Important Paths

| Item | Path |
|------|------|
| SCCM Install Log | `C:\ConfigMgrSetup.log` |
| SCCM Site Logs | `C:\Program Files\Microsoft Configuration Manager\Logs` |
| Client Setup Log | `C:\Windows\ccmsetup\Logs\ccmsetup.log` |
| Client Logs | `C:\Windows\CCM\Logs` |
| SQL Error Log | `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Log\ERRORLOG` |
| ADK Install | `C:\Program Files (x86)\Windows Kits\10` |

### Key PowerShell Modules

| Module | Purpose | Documentation |
|--------|---------|---------------|
| ActiveDirectory | AD management | [Link](https://learn.microsoft.com/en-us/powershell/module/activedirectory/) |
| DnsServer | DNS management | [Link](https://learn.microsoft.com/en-us/powershell/module/dnsserver/) |
| DhcpServer | DHCP management | [Link](https://learn.microsoft.com/en-us/powershell/module/dhcpserver/) |
| SqlServer | SQL management | [Link](https://learn.microsoft.com/en-us/powershell/module/sqlserver/) |
| ConfigurationManager | SCCM management | [Link](https://learn.microsoft.com/en-us/powershell/sccm/overview) |

### Service Accounts Summary

| Account | Purpose | Required Permissions |
|---------|---------|---------------------|
| LAB\SQL_Service | SQL Server services | Log on as service |
| LAB\SCCM_NAA | Network Access Account | Read access to DP content |
| LAB\SCCM_ClientPush | Client push installation | Local admin on targets |
| LAB\SCCM_JoinDomain | OSD domain join | Create computer objects in Workstations OU |

---

## Additional Resources

### Official Documentation

- [Configuration Manager Documentation](https://learn.microsoft.com/en-us/mem/configmgr/)
- [Site and site system prerequisites](https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/site-and-site-system-prerequisites)
- [Supported SQL Server versions](https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/support-for-sql-server-versions)
- [Support for Windows ADK](https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/configs/support-for-windows-adk)
- [Co-management overview](https://learn.microsoft.com/en-us/mem/configmgr/comanage/overview)
- [Active Directory security best practices](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/best-practices-for-securing-active-directory)

### Community Resources

- [System Center Dudes](https://www.systemcenterdudes.com/) - SCCM tutorials and guides
- [Prajwal Desai](https://www.prajwaldesai.com/) - Step-by-step SCCM guides
- [HTMD Blog (Anoop Nair)](https://www.anoopcnair.com/) - ConfigMgr and Intune content

---

**Document Version**: 2.0  
**Last Updated**: 2026-02-03  
**Maintained By**: Homelab SCCM Project
