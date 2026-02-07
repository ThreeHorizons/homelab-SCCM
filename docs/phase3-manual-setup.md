# Phase 3: Manual Setup Guide

This document provides detailed manual steps for configuring the SCCM lab infrastructure. Use this guide to understand each component before running automation scripts, or as a reference when troubleshooting.

**Purpose**: Learning and understanding each technology before automation

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding the Technologies](#understanding-the-technologies)
3. [Manual Setup Checklist](#manual-setup-checklist)
4. [Detailed Steps: Domain Controller (DC01)](#detailed-steps-domain-controller-dc01)
5. [Detailed Steps: SCCM Server (SCCM01)](#detailed-steps-sccm-server-sccm01)
6. [Detailed Steps: Client Machines](#detailed-steps-client-machines)
7. [Verification Procedures](#verification-procedures)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting manual configuration, ensure:

### Required Downloads

| Component | Version | Download Location | Size |
|-----------|---------|-------------------|------|
| SQL Server 2022 Developer | Latest | [Microsoft Downloads](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) | ~1.5GB |
| SQL Server Management Studio | Latest | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) | ~500MB |
| Windows ADK | Windows 11 (10.1.26100) | [ADK Download](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) | ~1.5GB |
| Windows PE Addon | Matching ADK | Same page as ADK | ~4GB |
| SCCM Current Branch | 2403 or later | [Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-microsoft-endpoint-configuration-manager) | ~1GB |

### Lab Environment State

```bash
# Verify VMs are running
cd ~/projects/homelab-SCCM/vagrant
vagrant status

# Expected output:
# dc01      running (virtualbox)
# sccm01    running (virtualbox)
# client01  running (virtualbox)
```

### Connecting to VMs

**Method 1: Vagrant WinRM (Recommended for scripting)**
```bash
# Run PowerShell command on DC01
vagrant winrm dc01 -c "hostname"

# Run multi-line script
vagrant winrm dc01 -c "
    Get-ComputerInfo | Select-Object CsName, OsVersion
    Get-NetIPAddress -AddressFamily IPv4 | Select-Object IPAddress, InterfaceAlias
"
```

**Method 2: RDP (Recommended for GUI tasks)**
```bash
# Get RDP connection info
vagrant rdp dc01

# Or manually connect:
# DC01: localhost:33891 (user: vagrant, pass: vagrant)
# SCCM01: localhost:33892
# CLIENT01: localhost:33901
```

**Method 3: VirtualBox Console**
- Open VirtualBox GUI
- Double-click on `sccm-lab-dc01`
- Login with vagrant/vagrant

---

## Understanding the Technologies

### Active Directory Domain Services (AD DS)

**What it is**: AD DS is Microsoft's directory service that stores information about network resources (users, computers, printers) and provides authentication and authorization services.

**Key concepts**:

| Term | Definition |
|------|------------|
| **Domain** | A logical grouping of objects (users, computers) that share a common directory database |
| **Domain Controller (DC)** | A server that hosts AD DS and handles authentication requests |
| **Forest** | The top-level container for one or more domains sharing a common schema |
| **Organizational Unit (OU)** | A container for organizing objects within a domain |
| **Schema** | Defines what types of objects can exist and their attributes |
| **Global Catalog** | A distributed data repository with a partial replica of all objects in the forest |

**Why we need it**:
- Centralized user management
- Single sign-on across lab resources
- Group Policy for configuration management
- Required for SCCM deployment

**PowerShell Module**: `ActiveDirectory` (only available on Windows)

```powershell
# Example: List all domain controllers
Get-ADDomainController -Filter *

# Example: Create a user
New-ADUser -Name "John Smith" -SamAccountName jsmith -Enabled $true
```

### DNS (Domain Name System)

**What it is**: DNS translates human-readable names (dc01.lab.local) to IP addresses (192.168.56.10).

**Why AD requires DNS**:
- Domain controllers register SRV records for services
- Clients use DNS to find domain controllers
- Kerberos authentication relies on DNS
- AD-integrated DNS zones replicate with AD

**Key record types**:

| Type | Purpose | Example |
|------|---------|---------|
| **A** | Hostname to IPv4 | dc01.lab.local → 192.168.56.10 |
| **PTR** | IP to hostname (reverse) | 10.56.168.192.in-addr.arpa → dc01.lab.local |
| **SRV** | Service location | _ldap._tcp.lab.local → dc01.lab.local:389 |
| **CNAME** | Alias | sccm.lab.local → sccm01.lab.local |

**PowerShell Module**: `DnsServer` (only on DNS server role)

```powershell
# Example: Create an A record
Add-DnsServerResourceRecordA -Name "sccm01" -ZoneName "lab.local" -IPv4Address "192.168.56.11"

# Example: Query DNS
Resolve-DnsName -Name dc01.lab.local -Type A
```

### DHCP (Dynamic Host Configuration Protocol)

**What it is**: DHCP automatically assigns IP addresses and network configuration to clients.

**How it works**:
1. **DISCOVER**: Client broadcasts "I need an IP"
2. **OFFER**: Server offers an IP address
3. **REQUEST**: Client requests the offered IP
4. **ACKNOWLEDGE**: Server confirms the lease

**Key concepts**:

| Term | Definition |
|------|------------|
| **Scope** | A range of IP addresses to assign |
| **Lease** | Temporary assignment of an IP address |
| **Reservation** | Permanent IP assignment based on MAC address |
| **Options** | Additional config (DNS servers, gateway, domain) |

**DHCP Options for our lab**:

| Option | Name | Value |
|--------|------|-------|
| 003 | Router (Gateway) | 192.168.56.1 |
| 006 | DNS Servers | 192.168.56.10 |
| 015 | DNS Domain Name | lab.local |

**PowerShell Module**: `DhcpServer`

```powershell
# Example: Create a scope
Add-DhcpServerv4Scope -Name "Lab Network" -StartRange 192.168.56.100 -EndRange 192.168.56.200 -SubnetMask 255.255.255.0

# Example: Set scope options
Set-DhcpServerv4OptionValue -ScopeId 192.168.56.0 -DnsServer 192.168.56.10 -Router 192.168.56.1
```

### SQL Server

**What it is**: Microsoft's relational database management system. SCCM stores all its data in SQL Server.

**SCCM Requirements**:
- **Collation**: Must be `SQL_Latin1_General_CP1_CI_AS` (case-insensitive, accent-sensitive)
- **Memory**: Leave 2GB for OS, rest for SQL
- **Features**: Database Engine, Reporting Services
- **Authentication**: Windows Authentication (not mixed mode)

**Key concepts**:

| Term | Definition |
|------|------------|
| **Instance** | A separate installation of SQL Server (can have multiple per server) |
| **Default Instance** | Named MSSQLSERVER, connects via server name only |
| **Named Instance** | Named differently, connects via SERVER\INSTANCE |
| **Collation** | Rules for sorting and comparing text |
| **TempDB** | System database for temporary operations |

**PowerShell Module**: `SqlServer` or `SQLPS`

```powershell
# Example: Test SQL connection
Invoke-Sqlcmd -Query "SELECT @@VERSION" -ServerInstance "SCCM01"

# Example: Check collation
Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation')" -ServerInstance "SCCM01"
```

### SCCM/Configuration Manager

**What it is**: Microsoft's enterprise client management platform for deploying software, updates, OS images, and compliance settings.

**Architecture components**:

| Component | Purpose |
|-----------|---------|
| **Site Server** | Core SCCM server that processes all data |
| **Site Database** | SQL database storing all SCCM data |
| **SMS Provider** | WMI interface for administration |
| **Management Point (MP)** | Client-server communication endpoint |
| **Distribution Point (DP)** | Content storage and distribution |
| **Reporting Services Point** | SQL Reporting integration |

**Key concepts**:

| Term | Definition |
|------|------------|
| **Site Code** | 3-character identifier (e.g., PS1) |
| **Boundary** | Network location definition (IP subnet, AD site) |
| **Boundary Group** | Collection of boundaries with associated site systems |
| **Collection** | Group of devices or users for targeting |
| **Client Push** | Automatic client installation method |

**PowerShell Module**: `ConfigurationManager` (only on SCCM console install)

```powershell
# Example: Import SCCM module
Import-Module "$env:SMS_ADMIN_UI_PATH\..\ConfigurationManager.psd1"
Set-Location "PS1:"

# Example: Get all devices
Get-CMDevice
```

### WinRM (Windows Remote Management)

**What it is**: Microsoft's implementation of WS-Management protocol for remote management of Windows machines.

**Architecture**:
```
┌─────────────────────┐                    ┌─────────────────────┐
│   Linux Host        │                    │   Windows VM        │
│   (NixOS)           │                    │   (DC01)            │
│                     │                    │                     │
│  ┌───────────────┐  │   HTTP/SOAP        │  ┌───────────────┐  │
│  │ Vagrant       │──┼──────────────────→ │  │ WinRM Service │  │
│  │ (WinRM client)│  │   Port 5985        │  │ (listener)    │  │
│  └───────────────┘  │                    │  └───────────────┘  │
│                     │                    │         │           │
│                     │                    │         ▼           │
│                     │                    │  ┌───────────────┐  │
│                     │   PowerShell       │  │ PowerShell    │  │
│                     │ ←──────────────────┼──│ Host          │  │
│                     │   Output           │  └───────────────┘  │
└─────────────────────┘                    └─────────────────────┘
```

**Authentication methods**:

| Method | Security | Use Case |
|--------|----------|----------|
| **Basic** | Weak (Base64) | Lab only, non-domain |
| **NTLM** | Medium | Workgroup machines |
| **Kerberos** | Strong | Domain-joined machines |
| **CredSSP** | Medium | Multi-hop scenarios |

**Key commands**:
```powershell
# Test WinRM
Test-WSMan -ComputerName 192.168.56.10

# Create remote session
$session = New-PSSession -ComputerName dc01.lab.local -Credential $cred

# Run command remotely
Invoke-Command -ComputerName dc01 -ScriptBlock { Get-Process }
```

---

## Manual Setup Checklist

Use this checklist to track manual setup progress:

### Phase 3A: Domain Controller (DC01)

- [ ] **1. Install AD DS Role**
  - [ ] Open Server Manager → Add Roles and Features
  - [ ] Select "Active Directory Domain Services"
  - [ ] Include management tools
  - [ ] Reboot if required

- [ ] **2. Promote to Domain Controller**
  - [ ] Run AD DS Configuration Wizard
  - [ ] Create new forest: `lab.local`
  - [ ] Set Directory Services Restore Mode password
  - [ ] Configure DNS (automatic with AD DS)
  - [ ] Complete wizard and reboot

- [ ] **3. Verify AD DS Installation**
  - [ ] Open Active Directory Users and Computers
  - [ ] Verify domain `lab.local` exists
  - [ ] Check DNS Manager for forward lookup zone

- [ ] **4. Configure DNS**
  - [ ] Create reverse lookup zone (192.168.56.x)
  - [ ] Add static A records for servers
  - [ ] Configure forwarders (8.8.8.8, 1.1.1.1)
  - [ ] Verify DNS resolution

- [ ] **5. Install DHCP Role**
  - [ ] Add DHCP Server role
  - [ ] Authorize DHCP in Active Directory
  - [ ] Create IPv4 scope (192.168.56.100-200)
  - [ ] Configure scope options (DNS, gateway, domain)
  - [ ] Activate scope

- [ ] **6. Create Organizational Units**
  - [ ] Servers OU
  - [ ] Workstations OU
  - [ ] Users/Administrators OU
  - [ ] Users/Standard Users OU
  - [ ] Service Accounts OU

- [ ] **7. Create Service Accounts**
  - [ ] LAB\SQL_Service (SQL Server service)
  - [ ] LAB\SCCM_NAA (Network Access Account)
  - [ ] LAB\SCCM_ClientPush (Client push installation)
  - [ ] LAB\SCCM_JoinDomain (OSD domain join)

- [ ] **8. Prepare AD for SCCM**
  - [ ] Run AD schema extension (extadsch.exe)
  - [ ] Create System Management container
  - [ ] Delegate permissions to SCCM01 computer account

### Phase 3B: SQL Server (SCCM01)

- [ ] **9. Join SCCM01 to Domain**
  - [ ] Change computer domain to lab.local
  - [ ] Reboot and verify domain join
  - [ ] Add LAB\Domain Admins to local Administrators

- [ ] **10. Install SQL Server Prerequisites**
  - [ ] Install .NET Framework 3.5
  - [ ] Install .NET Framework 4.8 (if not present)
  - [ ] Configure Windows Firewall (or disable for lab)

- [ ] **11. Install SQL Server**
  - [ ] Run SQL Server setup
  - [ ] Select Database Engine Services
  - [ ] Select Management Tools (or install SSMS separately)
  - [ ] Set collation: SQL_Latin1_General_CP1_CI_AS
  - [ ] Configure service accounts
  - [ ] Add administrators (SCCM01\Administrator, LAB\Administrator)

- [ ] **12. Configure SQL Server**
  - [ ] Verify collation is correct
  - [ ] Configure max memory (total - 2GB)
  - [ ] Enable TCP/IP in SQL Server Configuration Manager
  - [ ] Restart SQL Server service
  - [ ] Test connection from local SSMS

### Phase 3C: SCCM Installation (SCCM01)

- [ ] **13. Install SCCM Prerequisites**
  - [ ] Install Windows ADK
  - [ ] Install Windows PE Addon
  - [ ] Install required Windows features
  - [ ] Verify IIS configuration

- [ ] **14. Install SCCM**
  - [ ] Extract SCCM installation media
  - [ ] Run prerequisite checker
  - [ ] Create installation configuration
  - [ ] Execute setup (30-60 minutes)
  - [ ] Verify site installation

- [ ] **15. Configure SCCM**
  - [ ] Create boundary (IP subnet)
  - [ ] Create boundary group
  - [ ] Configure discovery methods
  - [ ] Configure client settings
  - [ ] Configure Network Access Account

### Phase 3D: Clients (CLIENT01+)

- [ ] **16. Join Clients to Domain**
  - [ ] Join each client to lab.local
  - [ ] Verify clients appear in AD
  - [ ] Verify DHCP lease from DC01

- [ ] **17. Install SCCM Client**
  - [ ] Configure client push installation
  - [ ] Or manually install ccmsetup.exe
  - [ ] Verify client in SCCM console
  - [ ] Run initial inventory

---

## Detailed Steps: Domain Controller (DC01)

### Step 1: Install AD DS Role

**What we're doing**: Installing the Active Directory Domain Services role, which includes the software components needed to make this server a domain controller.

**Why**: Windows Server comes with the ability to be a domain controller, but the feature must be explicitly installed.

Connect to DC01:
```bash
# From your Linux host
vagrant rdp dc01
# Or use VirtualBox console
```

**Using PowerShell (Recommended)**:

```powershell
# Open PowerShell as Administrator on DC01
# You can run this via vagrant winrm or RDP

# Install the AD DS role with all management tools
# -Name: The feature to install (AD-Domain-Services)
# -IncludeManagementTools: Also installs RSAT tools for managing AD
# -IncludeAllSubFeature: Includes all sub-features
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature

# Verify installation succeeded
# InstallState should be "Installed"
Get-WindowsFeature -Name AD-Domain-Services | Format-List Name, InstallState
```

**Understanding the command**:
- `Install-WindowsFeature`: PowerShell cmdlet to add Windows Server roles/features
- `-Name AD-Domain-Services`: The feature name (you can list all with `Get-WindowsFeature`)
- `-IncludeManagementTools`: Adds GUI tools (Active Directory Users and Computers, etc.)
- This doesn't make the server a DC yet - just installs the binaries

**Using Server Manager (GUI)**:
1. Open Server Manager (should open automatically)
2. Click "Add roles and features"
3. Click Next through wizard until "Server Roles"
4. Check "Active Directory Domain Services"
5. Click "Add Features" when prompted for management tools
6. Complete wizard

### Step 2: Promote to Domain Controller

**What we're doing**: Configuring this server to be the first domain controller in a new forest, creating the domain `lab.local`.

**Why**: Installing AD DS only adds the software. Promotion configures the server as a domain controller and creates/joins a domain.

**Key decisions**:
- **New Forest**: We're creating a brand new AD environment
- **Domain name**: `lab.local` (use .local for isolated labs)
- **NetBIOS name**: `LAB` (legacy compatibility, max 15 chars)
- **Forest/Domain functional level**: Determines available features

**Using PowerShell**:

```powershell
# Import the ADDSDeployment module (loaded with AD DS feature)
Import-Module ADDSDeployment

# Create a secure string for the Directory Services Restore Mode (DSRM) password
# DSRM is used for recovery when AD is broken
# IMPORTANT: Remember this password! Store it securely.
$DSRMPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# Promote to domain controller, creating a new forest
# This is a significant operation - the server will reboot!
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetBIOSName "LAB" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDNS:$true `
    -SafeModeAdministratorPassword $DSRMPassword `
    -Force:$true `
    -NoRebootOnCompletion:$false

# The server will automatically reboot
# Wait 5-10 minutes for services to start after reboot
```

**Understanding the parameters**:

| Parameter | Value | Explanation |
|-----------|-------|-------------|
| `-DomainName` | "lab.local" | The FQDN of the new domain |
| `-DomainNetBIOSName` | "LAB" | Pre-Windows 2000 compatible name |
| `-ForestMode` | "WinThreshold" | Windows Server 2016+ functional level |
| `-DomainMode` | "WinThreshold" | Same as forest (can't be higher) |
| `-InstallDNS` | $true | Install DNS and integrate with AD |
| `-SafeModeAdministratorPassword` | SecureString | DSRM recovery password |
| `-Force` | $true | Skip confirmation prompts |
| `-NoRebootOnCompletion` | $false | Reboot automatically when done |

**Using Server Manager (GUI)**:
1. Click notification flag → "Promote this server to a domain controller"
2. Select "Add a new forest"
3. Enter Root domain name: `lab.local`
4. Set Forest/Domain functional level to "Windows Server 2016"
5. Keep DNS server checked
6. Enter DSRM password
7. Accept defaults for remaining screens
8. Click "Install"

### Step 3: Verify AD DS Installation

**What we're doing**: Confirming that Active Directory is functioning correctly.

**After reboot, connect to DC01**:

```bash
# Wait for DC01 to finish rebooting (3-5 minutes)
# Then connect - note: login will change!
# Old: vagrant/vagrant
# New: LAB\Administrator or lab.local\Administrator (same password: vagrant)
vagrant rdp dc01
```

**Verification commands**:

```powershell
# Verify domain exists
# This should return domain information
Get-ADDomain

# Expected output includes:
# DNSRoot: lab.local
# NetBIOSName: LAB
# DomainMode: Windows2016Domain (or higher)

# Verify this server is a domain controller
Get-ADDomainController -Filter *

# Expected output includes:
# Name: DC01
# Domain: lab.local
# IsGlobalCatalog: True

# Verify DNS zone was created
Get-DnsServerZone

# Expected output includes:
# ZoneName: lab.local (Primary, AD-Integrated)
# ZoneName: _msdcs.lab.local (Primary, AD-Integrated)

# Test DNS resolution
Resolve-DnsName -Name dc01.lab.local -Type A

# Should return:
# Name: dc01.lab.local
# Type: A
# IPAddress: 192.168.56.10

# Verify AD services are running
Get-Service NTDS, DNS, Kdc, Netlogon | Format-Table Name, Status, StartType

# All should show: Running, Automatic
```

### Step 4: Configure DNS

**What we're doing**: Adding DNS records and configuring forwarders so the lab can resolve both internal names and internet addresses.

```powershell
# 1. Create reverse lookup zone for 192.168.56.x network
# Reverse DNS maps IP addresses back to hostnames (PTR records)
# This is needed for many Windows features
Add-DnsServerPrimaryZone `
    -NetworkId "192.168.56.0/24" `
    -ReplicationScope "Forest" `
    -DynamicUpdate "Secure"

# Verify reverse zone was created
Get-DnsServerZone 

# Expected: 56.168.192.in-addr.arpa

# 2. Create static A record for SCCM01
# Even though SCCM01 will register dynamically when it joins the domain,
# creating static records ensures DNS works before domain join
Add-DnsServerResourceRecordA `
    -ZoneName "lab.local" `
    -Name "sccm01" `
    -IPv4Address "192.168.56.11" `
    -CreatePtr  # Also creates reverse PTR record

# Verify the record
Resolve-DnsName -Name sccm01.lab.local

# 3. Configure DNS forwarders for internet resolution
# Forwarders are external DNS servers that handle queries we can't resolve
# 8.8.8.8 = Google DNS, 1.1.1.1 = Cloudflare DNS
Set-DnsServerForwarder -IPAddress "8.8.8.8", "1.1.1.1"

# Verify forwarders
Get-DnsServerForwarder

# 4. Test external DNS resolution
Resolve-DnsName -Name www.google.com

# Should return IP addresses for Google

# 5. Verify DC01's PTR record exists
Resolve-DnsName -Name 192.168.56.10 -Type PTR

# Should return: dc01.lab.local
```

**Understanding DNS zones**:

| Zone Type | Purpose |
|-----------|---------|
| **Forward Lookup** | Name → IP (lab.local) |
| **Reverse Lookup** | IP → Name (56.168.192.in-addr.arpa) |
| **AD-Integrated** | Stored in AD, replicated between DCs |

### Step 5: Install and Configure DHCP

**What we're doing**: Setting up DHCP so client machines automatically receive IP addresses and network configuration.

```powershell
# 1. Install DHCP Server role
Install-WindowsFeature -Name DHCP -IncludeManagementTools

# 2. Authorize DHCP server in Active Directory
# This prevents rogue DHCP servers from operating on your network
# Only authorized servers can respond to DHCP requests
# NOTE: You may need to add your user, vagrant, to AD enterprise admins to add a dhcp server and log out/log back in to make the groups take effect. whoami /groups can verify active group membership for the login. 
Add-DhcpServerInDC -DnsName "dc01.lab.local" -IPAddress 192.168.56.10

# Verify authorization
Get-DhcpServerInDC

# 3. Configure DHCP server security groups
# This suppresses the "configuration required" notification in Server Manager
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2

# 4. Create DHCP scope for lab network
# A scope defines the range of IP addresses to distribute
Add-DhcpServerv4Scope `
    -Name "Lab Network" `
    -StartRange 192.168.56.100 `
    -EndRange 192.168.56.200 `
    -SubnetMask 255.255.255.0 `
    -State Active `
    -LeaseDuration (New-TimeSpan -Hours 8)

# Understanding the parameters:
# - StartRange/EndRange: IPs to distribute (100-200 = 101 addresses)
# - SubnetMask: Defines network boundary
# - LeaseDuration: How long a client keeps an IP (8 hours is good for lab)

# 5. Set scope options (additional network configuration)
# These options are sent to clients along with their IP address
Set-DhcpServerv4OptionValue `
    -ScopeId 192.168.56.0 `
    -Router 192.168.56.1 `
    -DnsServer 192.168.56.10 `
    -DnsDomain "lab.local"

# Understanding DHCP options:
# - Router (Option 003): Default gateway for clients
# - DnsServer (Option 006): DNS server addresses
# - DnsDomain (Option 015): DNS suffix for name resolution

# 6. (Optional) Create reservations for servers
# Reservations assign specific IPs to specific MAC addresses
# This ensures servers always get the same IP
# Note: Our servers use static IPs, so this is optional

# First, get the MAC address of SCCM01's host-only adapter
# (Run this on SCCM01, or check VirtualBox settings)
# Add-DhcpServerv4Reservation -ScopeId 192.168.56.0 -IPAddress 192.168.56.11 -ClientId "08-00-27-XX-XX-XX"

# 7. Verify DHCP configuration
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 192.168.56.0

# 8. Check DHCP service status
Get-Service DHCPServer | Format-List Name, Status, StartType
```

**Testing DHCP**:

After configuring DHCP, client VMs should receive addresses from DC01 instead of VirtualBox's DHCP:

```bash
# From your Linux host, restart client to get new DHCP lease
vagrant reload client01

# After boot, check the IP
vagrant winrm client01 -c "Get-NetIPAddress -InterfaceAlias 'Ethernet 2' -AddressFamily IPv4"

# Should show an IP in the 192.168.56.100-200 range
```

### Step 6: Create Organizational Units

**What we're doing**: Creating a logical structure in Active Directory to organize users, computers, and service accounts.

**Why use OUs**:
- Group similar objects together
- Apply Group Policy to specific OUs
- Delegate administration
- Makes the directory easier to navigate

```powershell
# Create top-level OUs
# The -Path parameter specifies where to create the OU
# "DC=lab,DC=local" is the root of the domain

# Servers OU - for domain-joined servers
New-ADOrganizationalUnit -Name "Servers" -Path "DC=lab,DC=local" -Description "Domain member servers"

# Workstations OU - for client computers
New-ADOrganizationalUnit -Name "Workstations" -Path "DC=lab,DC=local" -Description "Domain workstations"

# Users OU with sub-OUs for different user types
New-ADOrganizationalUnit -Name "Lab Users" -Path "DC=lab,DC=local" -Description "Lab user accounts"
New-ADOrganizationalUnit -Name "Administrators" -Path "OU=Lab Users,DC=lab,DC=local" -Description "Admin accounts"
New-ADOrganizationalUnit -Name "Standard Users" -Path "OU=Lab Users,DC=lab,DC=local" -Description "Standard user accounts"

# Service Accounts OU - for automated/service accounts
New-ADOrganizationalUnit -Name "Service Accounts" -Path "DC=lab,DC=local" -Description "Service and automation accounts"

# Verify OUs were created
Get-ADOrganizationalUnit -Filter * | Format-Table Name, DistinguishedName
```

**Understanding Distinguished Names (DN)**:
- `DC=lab,DC=local` = Domain Component (the domain name)
- `OU=Servers,DC=lab,DC=local` = Organizational Unit within the domain
- `CN=DC01,OU=Domain Controllers,DC=lab,DC=local` = Common Name (specific object)

### Step 7: Create Service Accounts

**What we're doing**: Creating dedicated Active Directory accounts for services like SQL Server and SCCM.

**Why use service accounts**:
- Principle of least privilege (don't use admin accounts)
- Audit trail (know which service did what)
- Password management (can rotate without affecting users)
- Required by many enterprise applications

```powershell
# Create a secure password for service accounts
# In production, use unique passwords for each account!
$ServicePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

# 1. SQL_Service - Runs SQL Server services
# SQL Server needs a domain account to access network resources
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

# 2. SCCM_NAA - Network Access Account
# SCCM clients use this to access content on distribution points
# when the computer account doesn't have access
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

# 3. SCCM_ClientPush - Client Push Installation Account
# SCCM uses this to install the client on remote machines
# Needs local admin rights on target computers
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

# 4. SCCM_JoinDomain - OSD Domain Join Account
# Used during OS deployment to join computers to the domain
# Needs permission to create computer objects in AD
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

# Grant SCCM_JoinDomain permission to join computers to the Workstations OU
# This uses the dsacls command-line tool
$WorkstationsOU = "OU=Workstations,DC=lab,DC=local"
# Create/Delete Computer Objects
dsacls $WorkstationsOU /G "LAB\SCCM_JoinDomain:CCDC;computer"
# Reset Password and Write Properties (Essential for the join handshake)
dsacls $WorkstationsOU /G "LAB\SCCM_JoinDomain:RPWPCA;;computer"

# Verify accounts were created
Get-ADUser -Filter * -SearchBase "OU=Service Accounts,DC=lab,DC=local" | 
    Format-Table Name, SamAccountName, Enabled
```

**Understanding service account best practices**:

| Setting | Reason |
|---------|--------|
| `PasswordNeverExpires` | Prevents service outages when password expires |
| `CannotChangePassword` | Prevents accidental password changes |
| Dedicated OU | Easy to find and audit service accounts |
| Descriptive names | Clear purpose (SQL_Service vs. svc1) |

### Step 8: Prepare AD for SCCM

**What we're doing**: Extending the AD schema and creating the System Management container that SCCM requires.

**Why SCCM needs this**:
- Schema extension adds SCCM-specific attributes to AD objects
- System Management container stores site information
- Site servers need permission to publish to this container

**8a. Extend the AD Schema** (Run on DC01 as Enterprise Admin):

```powershell
# The SCCM installation media contains extadsch.exe
# You need to mount/extract the SCCM ISO first

# Assuming SCCM media is extracted to C:\SCCM_Install:
Set-Location "C:\SCCM_Install\SMSSETUP\BIN\X64"

# Run the schema extension
# This adds new object classes and attributes to AD
.\extadsch.exe

# The tool creates a log file - check for success
Get-Content "C:\ExtADSch.log" | Select-Object -Last 20

# You should see:
# "Successfully extended the Active Directory schema."
```

**Understanding schema extension**:
- One-time operation (only needs to run once per forest)
- Adds ~1500 attributes and classes to AD
- Cannot be undone (but doesn't affect existing objects)
- Requires Enterprise Admin privileges

**8b. Create System Management Container**:

```powershell
# Load the Active Directory module
Import-Module ActiveDirectory

# Get the domain's distinguished name
$DomainDN = (Get-ADDomain).DistinguishedName

# Check if System Management container already exists
$SystemContainer = "CN=System,$DomainDN"
$ExistingContainer = Get-ADObject -Filter {Name -eq "System Management"} -SearchBase $SystemContainer -ErrorAction SilentlyContinue

if (-not $ExistingContainer) {
    # Create the System Management container
    # This is where SCCM publishes site information
    New-ADObject -Type Container -Name "System Management" -Path $SystemContainer
    Write-Host "System Management container created successfully"
} else {
    Write-Host "System Management container already exists"
}

# Verify creation
Get-ADObject -Filter {Name -eq "System Management"} -SearchBase $SystemContainer
```

**8c. Delegate Permissions to SCCM Computer Account**:

```powershell
# SCCM01's computer account needs Full Control on the System Management container
# This allows the site server to publish and manage AD data

# First, ensure SCCM01 exists in AD (it will after domain join)
# For now, we'll grant permissions to the computer account

# Get the System Management container
$SystemManagementDN = "CN=System Management,CN=System,$((Get-ADDomain).DistinguishedName)"

# Import the AD module for ACL manipulation
Import-Module ActiveDirectory

# Get the current ACL
$acl = Get-Acl "AD:\$SystemManagementDN"

# Create the access rule for SCCM01
# Note: SCCM01 must be domain-joined first! Run this after Step 9.
# $computerAccount = Get-ADComputer -Identity "SCCM01"
# $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
#     $computerAccount.SID,
#     "GenericAll",
#     "Allow",
#     "All"
# )
# $acl.AddAccessRule($ace)
# Set-Acl "AD:\$SystemManagementDN" $acl

Write-Host "Note: Run the permission delegation after SCCM01 joins the domain"
```

We'll complete the delegation after SCCM01 joins the domain in Step 9.

---

## Detailed Steps: SCCM Server (SCCM01)

### Step 9: Join SCCM01 to Domain

**What we're doing**: Adding SCCM01 to the lab.local Active Directory domain.

**Why**: SCCM requires domain membership for:
- Kerberos authentication
- SQL Server service accounts
- Client authentication
- Group Policy

**From your Linux host**:

```bash
# First, verify DC01's DNS is working
vagrant winrm dc01 -c "Resolve-DnsName sccm01.lab.local"
```

**On SCCM01** (via RDP or vagrant winrm):

```powershell
# 1. Configure SCCM01 to use DC01 as DNS server
# This is critical - domain join uses DNS to find domain controllers
$HostOnlyAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*Ethernet 2*" -or $_.InterfaceDescription -like "*Host-Only*" }
Set-DnsClientServerAddress -InterfaceIndex $HostOnlyAdapter.InterfaceIndex -ServerAddresses "192.168.56.10"

# Verify DNS is working
Resolve-DnsName -Name dc01.lab.local
Resolve-DnsName -Name lab.local

# 2. Join the domain
# This requires credentials with permission to join computers
$DomainCredential = Get-Credential -Message "Enter domain admin credentials (LAB\Administrator)"

# Add the computer to the domain
# -OUPath specifies where to create the computer object
Add-Computer `
    -DomainName "lab.local" `
    -Credential $DomainCredential `
    -OUPath "OU=Servers,DC=lab,DC=local" `
    -Restart

# The server will automatically reboot
# Wait 2-3 minutes, then reconnect
```

**Alternative method using vagrant winrm** (non-interactive):

```bash
# Create the credential and join in one command
vagrant winrm sccm01 -c "
    # Set DNS to point to DC01
    \$adapter = Get-NetAdapter | Where-Object { \$_.Name -like '*Ethernet 2*' }
    Set-DnsClientServerAddress -InterfaceIndex \$adapter.InterfaceIndex -ServerAddresses '192.168.56.10'
    
    # Create credential object
    \$password = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
    \$cred = New-Object PSCredential('LAB\Administrator', \$password)
    
    # Join domain
    Add-Computer -DomainName 'lab.local' -Credential \$cred -OUPath 'OU=Servers,DC=lab,DC=local' -Force
"

# Reboot SCCM01
vagrant reload sccm01

# After reboot, verify domain join
vagrant winrm sccm01 -c "(Get-WmiObject Win32_ComputerSystem).Domain"
# Expected: lab.local
```

**After domain join, complete AD delegation** (on DC01):

```powershell
# Now that SCCM01 is in AD, grant it permissions on System Management
$SystemManagementDN = "CN=System Management,CN=System,$((Get-ADDomain).DistinguishedName)"

# Get SCCM01's computer account SID
$SCCM01 = Get-ADComputer -Identity "SCCM01"

# Grant Full Control using dsacls (simpler than ACL manipulation)
dsacls $SystemManagementDN /G "LAB\SCCM01$:GA" /I:T

# Verify permissions
dsacls $SystemManagementDN | Select-String "SCCM01"
```
# OR Apply full Control with This Object and All Descendant objects in security settings in ADUC. 

### Step 10: Install SQL Server Prerequisites

**What we're doing**: Installing components required by SQL Server.

```powershell
# On SCCM01 (now domain-joined, login as LAB\Administrator)

# 1. Install .NET Framework 3.5
# SQL Server 2019+ requires .NET Framework 3.5 and 4.7.2+
# Windows Server 2022 includes 4.8, but 3.5 must be installed
Install-WindowsFeature -Name NET-Framework-Core -Source D:\sources\sxs

# Note: The -Source parameter points to the Windows installation media
# If you don't have it mounted, use Windows Update:
# Install-WindowsFeature -Name NET-Framework-Core

# Verify installation
Get-WindowsFeature -Name NET-Framework-Core

# 2. Verify .NET 4.8 is present
(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
# Should be 528040 or higher (4.8)

# 3. Open firewall for SQL Server (if firewall is enabled)
# SQL Server uses port 1433 for TCP and 1434 for UDP (browser)
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow
New-NetFirewallRule -DisplayName "SQL Server Browser" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow
```

### Step 11: Install SQL Server

**What we're doing**: Installing SQL Server 2022 Developer Edition with the correct configuration for SCCM.

**Critical settings for SCCM**:
- **Collation**: `SQL_Latin1_General_CP1_CI_AS` (REQUIRED - cannot be changed after install!)
- **Authentication**: Windows Authentication Mode
- **Service Account**: Domain account (LAB\SQL_Service)

**GUI Installation**:

1. Mount SQL Server ISO on SCCM01
2. Run `setup.exe`
3. Select "New SQL Server stand-alone installation"
4. Enter product key or select Developer edition
5. Accept license terms
6. **Feature Selection**:
   - Database Engine Services (required)
   - SQL Server Replication (optional but useful)
   - Full-Text Search (optional)
7. **Instance Configuration**:
   - Default instance (MSSQLSERVER)
8. **Server Configuration**:
   - SQL Server Agent: LAB\SQL_Service, Automatic
   - SQL Server Database Engine: LAB\SQL_Service, Automatic
   - SQL Server Browser: Automatic
9. **Database Engine Configuration**:
   - Windows authentication mode
   - Add Current User (LAB\Administrator)
   - Add: SCCM01\Administrator
   - **Collation**: Click "Customize" → SQL_Latin1_General_CP1_CI_AS
   - Data directories: Accept defaults or customize
10. Complete installation

**Unattended Installation** (create ConfigurationFile.ini):

```powershell
# First, mount SQL Server ISO (assuming D: drive)
# Extract or create configuration file:

$ConfigContent = @"
[OPTIONS]
ACTION="Install"
FEATURES=SQLENGINE,REPLICATION
INSTANCENAME="MSSQLSERVER"
INSTANCEID="MSSQLSERVER"

; Collation - CRITICAL for SCCM!
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"

; Service accounts
SQLSVCACCOUNT="LAB\SQL_Service"
SQLSVCPASSWORD="P@ssw0rd123!"
SQLSVCSTARTUPTYPE="Automatic"
AGTSVCACCOUNT="LAB\SQL_Service"
AGTSVCPASSWORD="P@ssw0rd123!"
AGTSVCSTARTUPTYPE="Automatic"
BROWSERSVCSTARTUPTYPE="Automatic"

; Security
SECURITYMODE="SQL"
SAPWD=""
SQLSYSADMINACCOUNTS="LAB\Administrator" "SCCM01\Administrator"
ADDCURRENTUSERASSQLADMIN="True"

; Paths
INSTALLSQLDATADIR="C:\Program Files\Microsoft SQL Server"
SQLUSERDBDIR="C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Data"
SQLUSERDBLOGDIR="C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Data"
SQLTEMPDBDIR="C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Data"

; Quiet install
QUIET="True"
QUIETSIMPLE="True"
IACCEPTSQLSERVERLICENSETERMS="True"
UpdateEnabled="False"
"@

$ConfigContent | Out-File -FilePath "C:\SQLConfig.ini" -Encoding ASCII

# Run installation
Start-Process -FilePath "D:\setup.exe" -ArgumentList "/ConfigurationFile=C:\SQLConfig.ini" -Wait

# Check installation log
Get-Content "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt" | Select-Object -Last 30
```

### Step 12: Configure SQL Server

**What we're doing**: Post-installation configuration to optimize SQL Server for SCCM.

```powershell
# 1. Verify collation is correct (CRITICAL!)
Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation') AS Collation"

# MUST return: SQL_Latin1_General_CP1_CI_AS
# If wrong, you must reinstall SQL Server!

# 2. Configure maximum memory
# Leave at least 2GB for the OS, give the rest to SQL
$TotalMemoryMB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB
$SQLMemoryMB = [math]::Floor($TotalMemoryMB - 2048)

Invoke-Sqlcmd -Query "
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory', $SQLMemoryMB;
RECONFIGURE;
"

Write-Host "SQL Server max memory set to $SQLMemoryMB MB"

# 3. Enable TCP/IP Protocol
# Load SQL Server Configuration management
Import-Module "SqlServer" -ErrorAction SilentlyContinue

# Alternative: Use WMI
$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$tcp = $wmi.ServerInstances['MSSQLSERVER'].ServerProtocols['Tcp']
$tcp.IsEnabled = $true
$tcp.Alter()

Write-Host "TCP/IP protocol enabled"

# 4. Restart SQL Server to apply changes
Restart-Service -Name MSSQLSERVER -Force
Start-Sleep -Seconds 10

# 5. Verify SQL Server is running
Get-Service MSSQLSERVER, SQLSERVERAGENT | Format-Table Name, Status

# 6. Test SQL connection
Invoke-Sqlcmd -Query "SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version"
```

**Install SQL Server Management Studio (SSMS)**:

```powershell
# Download SSMS (or copy from shared folder)
$SSMSUrl = "https://aka.ms/ssmsfullsetup"
$SSMSPath = "C:\Temp\SSMS-Setup.exe"

# Download
Invoke-WebRequest -Uri $SSMSUrl -OutFile $SSMSPath

# Install silently
Start-Process -FilePath $SSMSPath -ArgumentList "/install /quiet /norestart" -Wait

# SSMS will be available after installation
# Launch from Start Menu: SQL Server Management Studio
```

### Step 13: Install SCCM Prerequisites

**What we're doing**: Installing Windows features and tools required by SCCM.

```powershell
# 1. Install required Windows features for SCCM
$Features = @(
    "NET-Framework-Core",           # .NET 3.5
    "NET-Framework-45-Features",    # .NET 4.5+
    "BITS",                         # Background Intelligent Transfer Service
    "BITS-IIS-Ext",                 # BITS IIS Extension
    "RDC",                          # Remote Differential Compression
    "WAS",                          # Windows Process Activation Service
    "WAS-Config-APIs",
    "WAS-Process-Model",
    "Web-Server",                   # IIS
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Net-Ext",
    "Web-Net-Ext45",
    "Web-ASP-Net",
    "Web-ASP-Net45",
    "Web-ASP",
    "Web-Windows-Auth",
    "Web-Basic-Auth",
    "Web-URL-Auth",
    "Web-IP-Security",
    "Web-Scripting-Tools",
    "Web-Mgmt-Console",
    "Web-Mgmt-Compat",
    "Web-Metabase",
    "Web-WMI",
    "Web-DAV-Publishing"
)

Install-WindowsFeature -Name $Features -IncludeManagementTools

# Verify installation
Get-WindowsFeature | Where-Object { $_.Installed -and $_.Name -like "Web-*" } | Format-Table Name

# 2. Download and Install Windows ADK
# ADK is required for OS deployment features

# Download ADK online installer
$ADKUrl = "https://go.microsoft.com/fwlink/?linkid=2243390"  # Windows 11 ADK
$ADKPath = "C:\Temp\adksetup.exe"

Invoke-WebRequest -Uri $ADKUrl -OutFile $ADKPath

# Install ADK with required features
# Features needed for SCCM:
# - Deployment Tools
# - User State Migration Tool (USMT)
Start-Process -FilePath $ADKPath -ArgumentList "/features OptionId.DeploymentTools OptionId.UserStateMigrationTool /quiet /norestart" -Wait

# 3. Download and Install Windows PE Addon
$WinPEUrl = "https://go.microsoft.com/fwlink/?linkid=2243391"  # Windows 11 WinPE Addon
$WinPEPath = "C:\Temp\adkwinpesetup.exe"

Invoke-WebRequest -Uri $WinPEUrl -OutFile $WinPEPath

# Install WinPE Addon
Start-Process -FilePath $WinPEPath -ArgumentList "/features + /quiet /norestart" -Wait

# 4. Verify ADK installation
$ADKRegPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
Get-ItemProperty -Path $ADKRegPath -ErrorAction SilentlyContinue

Write-Host "ADK and WinPE addon installation complete"
```

### Step 14: Install SCCM

**What we're doing**: Installing the SCCM Primary Site Server.

**Pre-installation checks**:

```powershell
# Extract SCCM installation media to C:\SCCM_Install

# 1. Run prerequisite checker first
Set-Location "C:\SCCM_Install\SMSSETUP\BIN\X64"
.\prereqchk.exe /LOCAL

# Review output - all checks should pass
# Common failures:
# - Missing Windows features (install them)
# - Wrong SQL collation (must reinstall SQL)
# - Pending reboot (reboot and re-run)
```

**Create installation configuration file**:

```ini
; Save as C:\SCCM_Install\ConfigMgrSetup.ini

[Identification]
Action=InstallPrimarySite

[Options]
ProductID=EVAL                          ; Use EVAL for evaluation, or enter your key
SiteCode=PS1                            ; 3-character site code
SiteName=SCCM Primary Site 1
SMSInstallDir=C:\Program Files\Microsoft Configuration Manager
SDKServer=SCCM01.lab.local
PrerequisiteComp=1                      ; Download prerequisites if needed
PrerequisitePath=C:\SCCM_Install\Prereqs
AdminConsole=1                          ; Install admin console
JoinCEIP=0                              ; Don't join CEIP

[SQLConfigOptions]
SQLServerName=SCCM01                    ; SQL Server name
DatabaseName=CM_PS1                     ; SCCM database name
SQLServerPort=1433                      ; Default SQL port
SQLSSBPort=4022                         ; SQL Server Broker port

[CloudConnectorOptions]
CloudConnector=0                        ; Don't configure cloud connector initially

[HierarchyExpansionOption]
; Leave empty for standalone primary

[SABranchOptions]
SAActive=0                              ; Not a Software Assurance customer
CurrentBranch=1                         ; Install Current Branch
```

**Run SCCM installation**:

```powershell
# Start the installation (takes 30-60 minutes!)
Set-Location "C:\SCCM_Install\SMSSETUP\BIN\X64"
.\setup.exe /script "C:\SCCM_Install\ConfigMgrSetup.ini"

# Monitor installation progress
# Logs are in: C:\ConfigMgrSetup.log
Get-Content "C:\ConfigMgrSetup.log" -Tail 50 -Wait

# Wait for installation to complete
# Look for "Setup has successfully installed Configuration Manager"
```

**Verify installation**:

```powershell
# Check SCCM services
Get-Service SMS_EXECUTIVE, SMS_SITE_COMPONENT_MANAGER | Format-Table Name, Status

# Both should show: Running

# Open SCCM Console
# Start Menu → Microsoft Endpoint Manager → Configuration Manager Console

# Or from command line:
& "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
```

### Step 15: Configure SCCM

**What we're doing**: Initial SCCM configuration for the lab environment.

```powershell
# Import SCCM PowerShell module
# The module is in the SCCM console installation directory
Import-Module "$($env:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"

# Connect to the site
Set-Location "PS1:"  # PS1 is our site code

# 1. Create IP Subnet Boundary
# Boundaries define network locations for site assignment and content
New-CMBoundary `
    -Type IPSubnet `
    -Name "Lab Network - 192.168.56.0/24" `
    -Value "192.168.56.0/24"

# 2. Create Boundary Group
# Boundary groups associate boundaries with site systems
New-CMBoundaryGroup -Name "Lab Network"

# 3. Add boundary to boundary group
$Boundary = Get-CMBoundary -BoundaryName "Lab Network - 192.168.56.0/24"
$BoundaryGroup = Get-CMBoundaryGroup -Name "Lab Network"
Add-CMBoundaryToGroup -BoundaryId $Boundary.BoundaryID -BoundaryGroupId $BoundaryGroup.GroupID

# 4. Configure boundary group for site assignment
# 
$Server = Get-CMSiteSystemServer -Name
Set-CMBoundaryGroup `
    -Name "Lab Network" `
    -AddSiteSystemServer $Server `
    -DefaultSiteCode "PS1"

# 5. Enable Active Directory System Discovery
# This finds computers in AD automatically
Set-CMDiscoveryMethod `
    -ActiveDirectorySystemDiscovery `
    -SiteCode "PS1" `
    -Enabled $true `
    -ActiveDirectoryContainer "LDAP://OU=Workstations,DC=lab,DC=local" `
    -Recursive

# 6. Enable Active Directory User Discovery
Set-CMDiscoveryMethod `
    -ActiveDirectoryUserDiscovery `
    -SiteCode "PS1" `
    -Enabled $true `
    -ActiveDirectoryContainer "LDAP://OU=Lab Users,DC=lab,DC=local" `
    -Recursive


# 7. Enable Heartbeat Discovery (already enabled by default)
Set-CMDiscoveryMethod -Heartbeat -SiteCode "PS1" -Enabled $true


# New Method
$SiteCode = "PS1"
$Methods = @(
    "ActiveDirectorySystemDiscovery",
    "ActiveDirectoryUserDiscovery",
    "ActiveDirectoryGroupDiscovery",
    "HeartbeatDiscovery"
)

foreach ($Method in $Methods) {
    Set-CMDiscoveryMethod -SiteCode $SiteCode -Enabled $true -$Method
}

#add AD scopes
$DiscoveryScopes = @(
    @{
        Name          = "Lab Users"
        LdapLocation  = "LDAP://OU=Lab Users,DC=lab,DC=local"
        Recursive     = $true
    },
    @{
        Name          = "Lab Computers"
        LdapLocation  = "LDAP://OU=Workstations,DC=lab,DC=local"
        Recursive     = $true
    }
)

foreach ($Scope in $DiscoveryScopes) {
    New-CMActiveDirectoryDiscoveryScope `
        -Name $Scope.Name `
        -LdapLocation $Scope.LdapLocation `
        -Recursive $Scope.Recursive
}

# 8. Configure Network Access Account
# This account is used when computer accounts can't access content
$NAAPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force
Set-CMClientSettingSoftwareDeployment `
    -DefaultSetting `
    -NetworkAccessAccountName "LAB\SCCM_NAA" `
    -NetworkAccessAccountPassword $NAAPassword

# 9. Configure Client Push Installation
Set-CMClientPushInstallation `
    -SiteCode "PS1" `
    -EnableAutomaticClientPushInstallation $true `
    -InstallClientToDomainController $false `
    -InstallationProperty "SMSSITECODE=PS1"

# Add Client Push account
Set-CMClientPushInstallation `
    -SiteCode "PS1" `
    -AddAccount "LAB\SCCM_ClientPush"

# 10. Run a discovery cycle
Invoke-CMSystemDiscovery -SiteCode "PS1"

Write-Host "SCCM initial configuration complete"
```

---

## Detailed Steps: Client Machines

### Step 16: Join Clients to Domain

**What we're doing**: Adding CLIENT01 (and additional clients) to the lab.local domain.

```bash
# From your Linux host
vagrant winrm client01 -c "
    # Set DNS to DC01
    \$adapter = Get-NetAdapter | Where-Object { \$_.Name -like '*Ethernet 2*' }
    Set-DnsClientServerAddress -InterfaceIndex \$adapter.InterfaceIndex -ServerAddresses '192.168.56.10'
    
    # Test DNS
    Resolve-DnsName -Name dc01.lab.local
    
    # Join domain
    \$password = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
    \$cred = New-Object PSCredential('LAB\Administrator', \$password)
    Add-Computer -DomainName 'lab.local' -Credential \$cred -OUPath 'OU=Workstations,DC=lab,DC=local' -Force
"

# Reboot client
vagrant reload client01

# Verify domain join
vagrant winrm client01 -c "(Get-WmiObject Win32_ComputerSystem).Domain"
# Expected: lab.local
```

**Verify in Active Directory** (on DC01):

```powershell
# Check that CLIENT01 appears in AD
Get-ADComputer -Filter { Name -like "CLIENT*" } | Format-Table Name, DistinguishedName
```

### Step 17: Install SCCM Client

**Option 1: Wait for Client Push** (automatic)

If client push is configured and working, the SCCM client should install automatically within 30 minutes of domain join.

**Option 2: Manual Installation**:

```bash
# On CLIENT01
vagrant winrm client01 -c "
    # Copy client files from SCCM01
    \$Source = '\\\\SCCM01\\SMS_PS1\\Client'
    \$Dest = 'C:\\Temp\\CCMSetup'
    
    New-Item -ItemType Directory -Path \$Dest -Force
    Copy-Item -Path \"\$Source\\*\" -Destination \$Dest -Recurse
    
    # Install SCCM client
    Start-Process -FilePath 'C:\\Temp\\CCMSetup\\ccmsetup.exe' -ArgumentList '/mp:SCCM01.lab.local SMSSITECODE=PS1' -Wait
    
    # Check installation log
    # C:\\Windows\\ccmsetup\\Logs\\ccmsetup.log
"
```

**Verify client installation**:

```bash
# Check SCCM client service
vagrant winrm client01 -c "Get-Service CcmExec | Format-List Name, Status, StartType"

# Check client version
vagrant winrm client01 -c "
    \$client = New-Object -ComObject Microsoft.SMS.Client
    \$client.GetAssignedSite()
"
# Should return: PS1
```

**Verify in SCCM Console**:
1. Open Configuration Manager Console on SCCM01
2. Navigate to: Assets and Compliance → Devices
3. CLIENT01 should appear with a green checkmark

---

## Verification Procedures

### Complete Lab Verification Checklist

Run these commands to verify the entire lab is functioning:

```bash
# From your Linux host

# 1. Test AD Domain
vagrant winrm dc01 -c "Get-ADDomain | Select-Object Name, DomainMode, Forest"
# Expected: Name=lab, DomainMode=Windows2016Domain

# 2. Test DNS
vagrant winrm dc01 -c "Resolve-DnsName sccm01.lab.local"
# Expected: IP 192.168.56.11

# 3. Test Reverse DNS
vagrant winrm dc01 -c "Resolve-DnsName 192.168.56.10"
# Expected: dc01.lab.local

# 4. Test DHCP
vagrant winrm dc01 -c "Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State"
# Expected: ScopeId=192.168.56.0, State=Active

# 5. Test SQL Server
vagrant winrm sccm01 -c "Invoke-Sqlcmd -Query 'SELECT SERVERPROPERTY(''Collation'') AS Collation'"
# Expected: SQL_Latin1_General_CP1_CI_AS

# 6. Test SCCM Site
vagrant winrm sccm01 -c "Get-Service SMS_EXECUTIVE, SMS_SITE_COMPONENT_MANAGER | Select-Object Name, Status"
# Expected: Both Running

# 7. Test Client Domain Join
vagrant winrm client01 -c "(Get-WmiObject Win32_ComputerSystem).Domain"
# Expected: lab.local

# 8. Test SCCM Client
vagrant winrm client01 -c "Get-Service CcmExec | Select-Object Status"
# Expected: Running

# 9. Test Inter-VM Connectivity
vagrant winrm dc01 -c "Test-NetConnection -ComputerName sccm01.lab.local -Port 1433"
# Expected: TcpTestSucceeded: True
```

---

## Troubleshooting

### Common Issues and Solutions

#### Domain Controller Issues

**AD DS installation fails**:
```powershell
# Check event logs
Get-WinEvent -LogName "Directory Service" -MaxEvents 20 | Format-Table TimeCreated, Message
```

**DNS not resolving**:
```powershell
# Verify DNS service
Get-Service DNS | Start-Service

# Check zones
Get-DnsServerZone

# Clear DNS cache
Clear-DnsClientCache
```

#### SQL Server Issues

**Wrong collation**:
```powershell
# Check collation
Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('Collation')"

# If wrong, you MUST reinstall SQL Server
# Collation cannot be changed after installation
```

**Cannot connect to SQL**:
```powershell
# Check service
Get-Service MSSQLSERVER | Start-Service

# Check TCP/IP is enabled
# Open SQL Server Configuration Manager
# SQL Server Network Configuration → Protocols for MSSQLSERVER → TCP/IP = Enabled

# Check firewall
Get-NetFirewallRule -DisplayName "*SQL*"
```

#### SCCM Issues

**Prerequisite check fails**:
- Review `C:\ConfigMgrPrereq.log`
- Install missing Windows features
- Ensure correct SQL collation

**Site installation fails**:
- Review `C:\ConfigMgrSetup.log`
- Check SQL connectivity
- Verify AD schema extension completed

**Clients not appearing**:
- Verify boundary and boundary group configuration
- Check client push account has local admin rights
- Review `C:\Windows\ccmsetup\Logs\ccmsetup.log` on client

---

## Next Steps

After completing manual setup, you can:

1. **Create snapshots** for easy recovery:
   ```bash
   vagrant snapshot save dc01 "phase3-complete"
   vagrant snapshot save sccm01 "phase3-complete"
   vagrant snapshot save client01 "phase3-complete"
   ```

2. **Proceed to Phase 3.5** for Azure integration (optional)

3. **Proceed to Phase 4** for PXE boot and OS deployment

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-27  
**Author**: SCCM Homelab Project
