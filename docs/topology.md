# Network and VM Topology

## Overview

This document describes the network architecture and VM topology for the SCCM homelab environment.

**Two Operating Modes:**
1. **Traditional Mode** (Phase 1-3): Isolated on-premises SCCM lab
2. **Cloud-Integrated Mode** (Phase 3.5+): Hybrid environment with Azure AD, Intune, and CMG

## Network Architecture

### Network Segments

#### 1. Host-Only Network (192.168.56.0/24)
- **Purpose**: Isolated lab network for all VM communication
- **Gateway**: 192.168.56.1 (VirtualBox host)
- **DHCP Range**: 192.168.56.100-192.168.56.200 (managed by DC01)
- **Static Assignments**:
  - DC01: 192.168.56.10
  - SCCM01: 192.168.56.11

#### 2. NAT Network
- **Purpose**: Provides internet access for all VMs
- **Usage**: Windows updates, software downloads, activation
- **Configuration**: Automatic via VirtualBox NAT

### Network Diagram - Traditional Mode (Phase 1-3)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Host System (NixOS)                       │
│                                                                   │
│  ┌─────────────────┐                                            │
│  │  192.168.56.1   │  VirtualBox Host-Only Adapter              │
│  │  (vboxnet0)     │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────┴──────────────────────────────────────────────────┐ │
│  │           Host-Only Network (192.168.56.0/24)             │ │
│  │                                                            │ │
│  │  ┌──────────────┐         ┌──────────────┐               │ │
│  │  │    DC01      │         │   SCCM01     │               │ │
│  │  │ .56.10       │◄───────►│  .56.11      │               │ │
│  │  │              │         │              │               │ │
│  │  │ • AD DS      │         │ • SQL Server │               │ │
│  │  │ • DNS        │         │ • SCCM Site  │               │ │
│  │  │ • DHCP       │         │ • DP/PXE     │               │ │
│  │  └──────┬───────┘         └──────┬───────┘               │ │
│  │         │                        │                        │ │
│  │         │    ┌───────────────────┘                        │ │
│  │         │    │                                            │ │
│  │  ┌──────┴────┴──┐    ┌──────────────┐    ┌────────────┐ │ │
│  │  │  CLIENT01    │    │  CLIENT02    │    │  CLIENTn   │ │ │
│  │  │  .56.100+    │    │  .56.100+    │    │  .56.100+  │ │ │
│  │  │              │    │              │    │            │ │ │
│  │  │ • Win 10/11  │    │ • Win 10/11  │    │ • Win10/11 │ │ │
│  │  │ • Domain     │    │ • Domain     │    │ • Domain   │ │ │
│  │  │ • SCCM Client│    │ • SCCM Client│    │ • SCCM Cli │ │ │
│  │  └──────────────┘    └──────────────┘    └────────────┘ │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  NAT Network (Internet)                     │ │
│  │                  (all VMs via adapter 2)                    │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Network Diagram - Cloud-Integrated Mode (Phase 3.5+)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Host System (NixOS)                       │
│                                                                   │
│  ┌─────────────────┐                                            │
│  │  192.168.56.1   │  VirtualBox Host-Only Adapter              │
│  │  (vboxnet0)     │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────┴──────────────────────────────────────────────────┐ │
│  │           Host-Only Network (192.168.56.0/24)             │ │
│  │                                                            │ │
│  │  ┌──────────────┐         ┌──────────────┐               │ │
│  │  │    DC01      │         │   SCCM01     │               │ │
│  │  │ .56.10       │◄───────►│  .56.11      │───────┐       │ │
│  │  │              │         │              │       │       │ │
│  │  │ • AD DS      │         │ • SQL Server │       │       │ │
│  │  │ • DNS        │         │ • SCCM Site  │       │       │ │
│  │  │ • DHCP       │         │ • DP/PXE     │       │       │ │
│  │  │ • AAD Connect│──┐      │ • Azure Conn │       │       │ │
│  │  └──────┬───────┘  │      └──────┬───────┘       │       │ │
│  │         │          │             │               │       │ │
│  │         │    ┌─────┴─────────────┘               │       │ │
│  │         │    │   Password Hash Sync              │       │ │
│  │  ┌──────┴────┴──┐    ┌──────────────┐    ┌──────┴─────┐ │ │
│  │  │  CLIENT01    │    │  CLIENT02    │    │  CLIENTn   │ │ │
│  │  │  .56.100+    │    │  .56.100+    │    │  .56.100+  │ │ │
│  │  │              │    │              │    │            │ │ │
│  │  │ • Win 10/11  │    │ • Win 10/11  │    │ • Win10/11 │ │ │
│  │  │ • Hybrid AAD │    │ • Hybrid AAD │    │ • Hyb AAD  │ │ │
│  │  │ • Co-managed │    │ • Co-managed │    │ • Co-mgmt  │ │ │
│  │  └──────────────┘    └──────────────┘    └────────────┘ │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  NAT Network (Internet)                     │ │
│  │              (all VMs via adapter 2) ───────────────┐      │ │
│  └────────────────────────────────────────────────────┼──────┘ │
└────────────────────────────────────────────────────────┼────────┘
                                                         │
                                                         ▼
                          ┌──────────────────────────────────────┐
                          │       Microsoft Azure Cloud          │
                          │                                      │
                          │  ┌────────────────────────────────┐ │
                          │  │  Microsoft Entra ID (Azure AD) │ │
                          │  │  • Synced Users & Groups       │ │
                          │  │  • Hybrid AAD Joined Devices   │ │
                          │  │  • Device Registration SCP     │ │
                          │  └────────────────────────────────┘ │
                          │                                      │
                          │  ┌────────────────────────────────┐ │
                          │  │  Microsoft Intune              │ │
                          │  │  • Device Management           │ │
                          │  │  • Compliance Policies         │ │
                          │  │  • App Deployment              │ │
                          │  │  • Endpoint Analytics          │ │
                          │  │  • Conditional Access          │ │
                          │  └────────────────────────────────┘ │
                          │                                      │
                          │  ┌────────────────────────────────┐ │
                          │  │  Cloud Management Gateway      │ │
                          │  │  • Internet-based Clients      │ │
                          │  │  • Azure VM Scale Set (B2s)    │ │
                          │  │  • Cloud DP (optional)         │ │
                          │  └────────────────────────────────┘ │
                          │                                      │
                          │  ┌────────────────────────────────┐ │
                          │  │  Tenant Attach Services        │ │
                          │  │  • Device Sync to Endpoint Mgr │ │
                          │  │  • Remote Actions from Cloud   │ │
                          │  │  • Advanced Analytics          │ │
                          │  └────────────────────────────────┘ │
                          └──────────────────────────────────────┘
```

## VM Specifications

### DC01 - Domain Controller

**Role**: Active Directory Domain Services, DNS, DHCP, Azure AD Connect (Phase 3.5)

**Specifications**:
- **OS**: Windows Server 2022 Standard (Desktop Experience)
- **vCPUs**: 2
- **RAM**: 2GB
- **Disk**: 60GB (dynamically allocated)
- **Network**:
  - Adapter 1: Host-Only (192.168.56.10/24)
  - Adapter 2: NAT (for internet)

**Installed Roles & Features (Traditional Mode)**:
- Active Directory Domain Services (AD DS)
- DNS Server
- DHCP Server
- Active Directory Management Tools
- PowerShell 5.1

**Additional Software (Cloud-Integrated Mode - Phase 3.5)**:
- Azure AD Connect (latest version)
- .NET Framework 4.6.2+
- TLS 1.2 enabled
- Azure AD Connect Health Agent (optional)

**Configuration**:
- **Domain**: lab.local
- **NetBIOS**: LAB
- **Forest Functional Level**: Windows Server 2016+
- **DNS Forwarders**: 8.8.8.8, 1.1.1.1
- **DHCP Scope**: 192.168.56.100-192.168.56.200
- **DHCP Reservations**:
  - SCCM01: 192.168.56.11 (if needed for stability)

**Azure AD Connect Configuration (Phase 3.5)**:
- **Sync Method**: Password Hash Synchronization
- **Sync Interval**: 30 minutes (default)
- **UPN Suffix**: @labtest.onmicrosoft.com (or custom domain)
- **Service Connection Point (SCP)**: Configured for hybrid Azure AD join

---

### SCCM01 - Configuration Manager Primary Site Server

**Role**: SQL Server, SCCM Primary Site, Distribution Point, PXE Server, Azure Services Connection (Phase 3.5)

**Specifications**:
- **OS**: Windows Server 2022 Standard (Desktop Experience)
- **vCPUs**: 2 (4 recommended for better performance)
- **RAM**: 4GB (8GB recommended)
- **Disk**: 100GB (dynamically allocated)
- **Network**:
  - Adapter 1: Host-Only (192.168.56.11/24)
  - Adapter 2: NAT (for internet - required for Azure connectivity)

**Installed Software (Traditional Mode)**:
- SQL Server 2019/2022 Developer or Standard Edition
  - Database Engine Services
  - Management Tools
  - Reporting Services (SSRS)
- Windows ADK (Windows Assessment and Deployment Kit)
- WinPE Addon for ADK
- .NET Framework 3.5 and 4.8+
- SCCM Current Branch (latest version)

**Additional Requirements (Cloud-Integrated Mode - Phase 3.5)**:
- TLS 1.2 enabled
- CMG server authentication certificate (.pfx)
- Azure subscription access
- Internet connectivity for Azure communication

**Installed Roles & Features**:
- IIS (Web Server)
- BITS Server Extensions
- Remote Differential Compression (RDC)
- .NET Framework 3.5 / 4.8+
- Windows Deployment Services (WDS) - optional if using SCCM PXE responder

**SCCM Site Configuration**:
- **Site Code**: PS1
- **Site Name**: SCCM Primary Site 1
- **Installation Mode**: Primary Site
- **Database**: SCCM01\MSSQLSERVER (or named instance)
- **SMS Provider**: SCCM01

**SCCM Roles (Traditional Mode)**:
- Management Point
- Distribution Point
  - PXE Responder enabled
  - Multicast enabled (optional)
- Software Update Point (WSUS)
- Reporting Services Point (SSRS)

**Additional SCCM Configuration (Cloud-Integrated Mode - Phase 3.5)**:
- **Azure Services Connection**: Configured for Cloud Management
- **Tenant Attach**: Enabled, syncing devices to Microsoft Endpoint Manager
- **Co-Management**: Enabled for pilot or all devices
- **Cloud Management Gateway (CMG)**: Deployed in Azure
  - VM Size: B2s (Lab)
  - Region: East US (or chosen region)
  - Certificate: Self-signed or purchased
- **Management Point**: CMG traffic enabled
- **Azure AD User Discovery**: Enabled
- **Azure AD User Group Discovery**: Enabled (optional)

---

### CLIENT01, CLIENT02, ... CLIENTn

**Role**: Windows client workstations, SCCM managed endpoints, Hybrid Azure AD Joined (Phase 3.5)

**Specifications** (per client):
- **OS**: Windows 10 22H2 or Windows 11 23H2
- **vCPUs**: 2
- **RAM**: 2GB (4GB recommended for Windows 11)
- **Disk**: 60GB (dynamically allocated)
- **Network**:
  - Adapter 1: Host-Only (DHCP - 192.168.56.100+)
  - Adapter 2: NAT (for internet - required for Azure AD communication)

**Configuration (Traditional Mode)**:
- **Domain**: lab.local
- **Computer Name**: CLIENT01, CLIENT02, etc.
- **OU**: Computers/Workstations (example)
- **SCCM Client**: Installed and reporting to PS1

**Additional Configuration (Cloud-Integrated Mode - Phase 3.5)**:
- **Hybrid Azure AD Joined**: Yes (via GPO)
- **Azure AD Tenant**: labtest.onmicrosoft.com
- **Intune Enrolled**: Yes (automatic via co-management)
- **Co-Management Status**: Co-managed (SCCM + Intune)
- **Workloads**: Mix of SCCM and Intune managed
  - Compliance Policies: Intune
  - Resource Access: Intune
  - Device Configuration: SCCM or Intune (configurable)
  - Endpoint Protection: SCCM or Intune (configurable)
  - Windows Update: SCCM or Intune (configurable)
- **Management Visibility**: 
  - ConfigMgr Console (SCCM01)
  - Microsoft Endpoint Manager admin center (https://endpoint.microsoft.com)

**Purpose**:
- Test SCCM client management
- Application deployments
- Software updates
- OS deployment (OSD)
- Inventory and compliance
- Remote control
- **Phase 3.5 Additional Testing**:
  - Intune policy deployment
  - Conditional access scenarios
  - Hybrid Azure AD join workflows
  - Co-management workload switching
  - Cloud-based remote actions
  - Endpoint analytics data collection

---

## DNS Configuration

### Forward Lookup Zones

**lab.local** (Primary Zone)
- dc01.lab.local → 192.168.56.10
- sccm01.lab.local → 192.168.56.11
- client01.lab.local → DHCP assigned
- client02.lab.local → DHCP assigned

### Reverse Lookup Zone

**56.168.192.in-addr.arpa**
- 10 → dc01.lab.local
- 11 → sccm01.lab.local

### DNS Forwarders

- 8.8.8.8 (Google DNS)
- 1.1.1.1 (Cloudflare DNS)

---

## DHCP Configuration

### Scope: Lab Network

- **Scope Name**: Lab Network
- **Network**: 192.168.56.0/24
- **Range**: 192.168.56.100 - 192.168.56.200
- **Subnet Mask**: 255.255.255.0
- **Lease Duration**: 8 hours
- **Gateway**: 192.168.56.1
- **DNS Servers**: 192.168.56.10 (DC01)
- **Domain**: lab.local

### DHCP Options

- **Option 003 (Router)**: 192.168.56.1
- **Option 006 (DNS Servers)**: 192.168.56.10
- **Option 015 (DNS Domain Name)**: lab.local

Note: Do NOT set DHCP options 066/067 when using SCCM PXE responder (conflicts).

---

## Active Directory Structure

### Domain

- **Domain Name**: lab.local
- **NetBIOS Name**: LAB
- **Forest Root**: lab.local

### Organizational Units (Suggested)

```
lab.local/
├── Domain Controllers/
│   └── DC01
├── Servers/
│   └── SCCM01
├── Workstations/
│   ├── CLIENT01
│   ├── CLIENT02
│   └── ...
├── Users/
│   ├── Administrators/
│   └── Standard Users/
└── Service Accounts/
    ├── SQL_Service
    ├── SCCM_NAA (Network Access Account)
    └── SCCM_ClientPush
```

### Service Accounts

| Account | Purpose | Permissions |
|---------|---------|-------------|
| LAB\SQL_Service | SQL Server service account | Local admin on SCCM01 |
| LAB\SCCM_NAA | SCCM Network Access Account | Domain user, no special rights |
| LAB\SCCM_ClientPush | Client push installation | Local admin on all clients |
| LAB\SCCM_JoinDomain | Domain join account (OSD) | Permission to join computers to domain |

---

## Port Requirements

### Domain Controller (DC01)

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 53 | TCP/UDP | DNS | Name resolution |
| 88 | TCP/UDP | Kerberos | Authentication |
| 135 | TCP | RPC | Remote management |
| 389 | TCP/UDP | LDAP | Directory services |
| 445 | TCP | SMB | File sharing |
| 636 | TCP | LDAPS | Secure LDAP |
| 3389 | TCP | RDP | Remote desktop |

### SCCM Server (SCCM01)

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 80 | TCP | HTTP | Client communication |
| 443 | TCP | HTTPS | Secure client communication |
| 445 | TCP | SMB | File sharing |
| 1433 | TCP | SQL | Database access |
| 4011 | UDP | PXE | DHCP proxy |
| 8005 | TCP | WDS | Windows Deployment Services |
| 10123 | TCP | SCCM | Client notification |
| 3389 | TCP | RDP | Remote desktop |

### Clients

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 135 | TCP | RPC | Client push |
| 445 | TCP | SMB | File sharing |
| 2701 | TCP | SCCM | Client data transfer |
| 2702 | TCP | SCCM | Management point |
| 3389 | TCP | RDP | Remote desktop |

---

## VirtualBox Network Configuration

### Host-Only Network Setup

```bash
# Create host-only network
VBoxManage hostonlyif create

# Configure IP (usually vboxnet0)
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0

# Disable VirtualBox DHCP (DC01 will handle DHCP)
VBoxManage dhcpserver modify --ifname vboxnet0 --disable
```

### VM Network Adapter Configuration

Each VM has two adapters:

**Adapter 1** (Host-Only):
- Type: Host-Only Adapter
- Name: vboxnet0
- Adapter Type: Intel PRO/1000 MT Desktop (82540EM)
- Promiscuous Mode: Allow All (for PXE)

**Adapter 2** (NAT):
- Type: NAT
- Adapter Type: Intel PRO/1000 MT Desktop (82540EM)

---

## Scalability

### Adding More Clients

To add additional clients, increment the client number:

- VM Name: CLIENT03, CLIENT04, etc.
- Computer Name: CLIENT03, CLIENT04, etc.
- DHCP assignment: Automatic (192.168.56.100+)

### Adding Secondary Site (Future)

For more advanced scenarios:

- Add SCCM02 (Secondary Site)
- Subnet: 192.168.57.0/24
- Connects to PS1 as parent site

---

## Backup and Snapshots

### Recommended Snapshots

1. **Initial State**: After Vagrant provisioning, before automation
2. **AD Configured**: After DC01 setup complete
3. **SCCM Installed**: After SCCM installation complete
4. **Clients Joined**: After all clients domain-joined and SCCM client installed
5. **OSD Ready**: After PXE/OSD configuration complete

```bash
# Create snapshots
vagrant snapshot save <vm-name> <snapshot-name>

# Example
vagrant snapshot save dc01 ad-configured
vagrant snapshot save sccm01 sccm-installed
```

---

## Monitoring and Management

### Access URLs

- **SCCM Console**: RDP to SCCM01 → Start → Configuration Manager Console
- **SQL Management Studio**: RDP to SCCM01 → SSMS
- **Active Directory**: RDP to DC01 → Active Directory Users and Computers
- **DHCP**: RDP to DC01 → DHCP Management Console
- **DNS**: RDP to DC01 → DNS Manager

### Log Locations

**DC01**:
- AD DS Logs: Event Viewer → Applications and Services Logs → Directory Service
- DHCP Logs: `C:\Windows\System32\DHCP\`
- DNS Logs: Event Viewer → Applications and Services Logs → DNS Server

**SCCM01**:
- SCCM Install Logs: `C:\ConfigMgrSetup.log`
- SCCM Site Server Logs: `C:\Program Files\Microsoft Configuration Manager\Logs\`
- SQL Logs: `C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Log\`

**Clients**:
- SCCM Client Logs: `C:\Windows\CCM\Logs\`

---

## Azure Integration Costs (Phase 3.5 Optional)

If implementing cloud-integrated mode, be aware of the following costs:

### Monthly Cost Estimate

| Component | Cost | Notes |
|-----------|------|-------|
| Azure AD Free | $0 | Up to 50,000 objects |
| Azure AD Premium P1 | $6/user/month | Required for advanced conditional access |
| Microsoft Intune | $6-8/user/month | Or included in M365 E3/E5 |
| Cloud Management Gateway (CMG) | $15-25/month | B2s VM instance + storage + data transfer |
| Azure Storage for CMG | $1-5/month | Depends on log retention |
| Data Transfer (egress) | Variable | First 100GB/month free |
| **Total (Minimum with trials)** | **$0** | First 30 days with trials |
| **Total (After trials)** | **$20-50/month** | Depends on user count and CMG usage |

### Cost Optimization Strategies

1. **Use Free Trials**:
   - Azure 30-day free trial ($200 credit)
   - Intune 30-day trial
   - Microsoft 365 Developer Program (renewable 90-day E5 license)

2. **Stop CMG When Not Testing**:
   - Deallocate CMG VM when not actively testing internet-based management
   - Saves ~70% of CMG costs
   - Can be restarted when needed

3. **Use Azure Credits**:
   - Visual Studio subscription includes $50-150/month Azure credits
   - Azure for Students ($100 credit)

4. **Lab-Only Licensing**:
   - Use evaluation licenses where possible
   - SQL Server Developer Edition (free)
   - Windows Server evaluation (180 days)
   - Windows 10/11 evaluation (90 days)

5. **Destroy and Recreate for Long-Term Learning**:
   - Every 30 days, destroy Azure resources and recreate with new trial
   - Use infrastructure-as-code approach for quick rebuild

### Azure Resource Requirements

**Required Azure Resources for Phase 3.5:**
- Azure AD tenant (free tier sufficient)
- Azure subscription (free trial or paid)
- Resource Group for CMG resources
- Cloud Service (Classic) or Virtual Machine Scale Set for CMG
- Storage Account for CMG
- App Registrations (2): ConfigMgr Server App, ConfigMgr Client App

**Optional Azure Resources:**
- Application Insights for advanced monitoring
- Azure Log Analytics for CMG analytics
- Azure Monitor for alerting

---

## Next Steps

### Traditional Mode (Phase 1-3)

Once the topology is deployed:

1. Verify network connectivity between all VMs
2. Test DNS resolution from clients
3. Verify DHCP assignments
4. Test SCCM client communication
5. Configure SCCM boundaries and boundary groups
6. Begin application and update deployments
7. Test OSD task sequences

### Cloud-Integrated Mode (Phase 3.5+)

After completing traditional mode setup:

1. Sign up for Azure subscription and Intune trial
2. Install and configure Azure AD Connect on DC01
3. Verify user and device synchronization to Azure AD
4. Deploy Cloud Management Gateway (CMG)
5. Enable hybrid Azure AD join via GPO
6. Configure tenant attach to sync devices to Endpoint Manager
7. Enable co-management and shift pilot workloads
8. Test Intune policies and cloud-based remote actions

See [CLAUDE.md](../CLAUDE.md) for detailed phase implementation guides and [phase3.5-checklist.md](../.claude/phase3.5-checklist.md) for Azure integration steps.
