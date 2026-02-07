# Phase 3: WinRM Automation Layer

**Status**: 🟡 In Progress  
**Start Date**: 2026-01-27  
**Completion Date**: _____

## Overview

Fully automate Windows Server configuration using PowerShell remoting and WinRM. This is the core automation phase that builds AD, DNS, DHCP, SQL Server, and SCCM.

## Goals

- [ ] Fully automate Windows Server configuration
- [ ] Implement infrastructure as code for AD, DNS, DHCP, SQL, SCCM
- [ ] Create reusable PowerShell modules
- [ ] Enable one-command deployment

---

## Documentation Created

Before implementing automation, comprehensive documentation was created:

- ✅ **`docs/phase3-manual-setup.md`** - Manual setup guide with:
  - Detailed explanation of each technology (AD DS, DNS, DHCP, SQL, SCCM, WinRM)
  - Step-by-step manual configuration procedures
  - PowerShell commands with explanations
  - Troubleshooting guide
  - Verification procedures

- ✅ **`docs/phase3-automation-plan.md`** - Automation strategy with:
  - Architecture overview (Linux host → Vagrant WinRM → Windows VMs)
  - Cross-platform challenges and solutions
  - Implementation approach (scripts run locally on VMs)
  - Error handling and idempotency patterns
  - Known caveats and workarounds

---

## Prerequisites

- ✅ Phase 1 completed (Nix environment ready)
- ✅ Phase 2 completed (VMs running and accessible via WinRM)
- [ ] SQL Server 2019/2022 ISO downloaded or installation media accessible
- [ ] SCCM Current Branch installation media downloaded
- [ ] Windows ADK and WinPE addon downloaded

---

## Main Tasks

### 1. PowerShell Automation Framework

- [x] Create `scripts/modules/Logger.psm1`
  - [x] Write-Log function with timestamps
  - [x] Log levels (INFO, WARN, ERROR, SUCCESS, DEBUG)
  - [x] File and console output
  - [x] Color-coded console output
  - [x] Initialize-Logging, Write-LogSection, Write-LogError, Complete-Logging functions
- [ ] Create `scripts/modules/WinRMHelper.psm1` (deferred - using Vagrant WinRM instead)
  - Note: Vagrant's WinRM communicator handles remote execution
- [x] Create `scripts/modules/Validator.psm1`
  - [x] Test-ADDSInstalled function
  - [x] Test-DNSZoneExists, Test-DNSResolution functions
  - [x] Test-DHCPScopeExists, Test-DHCPScopeActive functions
  - [x] Test-SQLServerInstalled, Test-SQLServerCollation functions
  - [x] Test-SCCMInstalled, Test-SCCMClientInstalled functions
  - [x] Test-DomainJoined, Test-IsDomainController functions
  - [x] Get-LabStatus comprehensive status function

### 2. Active Directory Domain Services (DC01)

- [x] Create `scripts/dc/Install-ADDS.ps1`
  - [x] Install AD DS role and management tools
  - [x] Idempotent (skips if already installed)
  - [x] Comprehensive logging and explanations
- [x] Create `scripts/dc/Promote-DC.ps1`
  - [x] Promote server to domain controller
  - [x] Domain name: lab.local
  - [x] NetBIOS name: LAB
  - [x] Forest functional level: WinThreshold (Server 2016+)
  - [x] Safe mode password configuration
  - [x] Handle automatic reboot
- [x] Create `scripts/dc/Configure-DNS.ps1`
  - [x] Configure DNS forwarders (8.8.8.8, 1.1.1.1)
  - [x] Create reverse lookup zone (56.168.192.in-addr.arpa)
  - [x] Create static A records for SCCM01
  - [x] Test DNS resolution
- [x] Create `scripts/dc/Configure-DHCP.ps1`
  - [x] Install DHCP role
  - [x] Authorize DHCP in Active Directory
  - [x] Create scope (192.168.56.100-200)
  - [x] Configure DHCP options (Router, DNS, Domain)
- [x] Create `scripts/dc/Create-OUs.ps1`
  - [x] Servers OU
  - [x] Workstations OU
  - [x] Lab Users/Administrators OU
  - [x] Lab Users/Standard Users OU
  - [x] Service Accounts OU
- [x] Create `scripts/dc/Create-ServiceAccounts.ps1`
  - [x] SQL_Service (SQL Server service account)
  - [x] SCCM_NAA (Network Access Account)
  - [x] SCCM_ClientPush (Client push installation)
  - [x] SCCM_JoinDomain (Domain join for OSD)
  - [x] Set permissions for SCCM_JoinDomain on Workstations OU
- [ ] Extend AD schema for SCCM (requires SCCM media - Phase 3 SQL/SCCM)
  - [ ] Run: `extadsch.exe` from SCCM media
  - [ ] Create System Management container
  - [ ] Grant permissions to SCCM computer account
- [ ] Validate AD DS configuration

### 3. DNS Server Configuration (DC01)

- [x] Create forward lookup zone for lab.local (auto-created during AD DS promotion)
- [x] Add DNS records for servers
  - [x] dc01.lab.local → 192.168.56.10 (auto-registered)
  - [x] sccm01.lab.local → 192.168.56.11 (created in Configure-DNS.ps1)
- [x] Configure DNS forwarders (8.8.8.8, 1.1.1.1 in Configure-DNS.ps1)
- [x] Create reverse lookup zone (56.168.192.in-addr.arpa in Configure-DNS.ps1)
- [x] Configure dynamic updates (secure updates only - AD default)
- [ ] Test DNS resolution
  - [ ] From DC01: `nslookup sccm01.lab.local`
  - [ ] From SCCM01: `nslookup dc01.lab.local`

### 4. DHCP Server Configuration (DC01)

- [x] Install DHCP role and management tools (Configure-DHCP.ps1)
  - [x] `Install-WindowsFeature -Name DHCP -IncludeManagementTools`
- [x] Authorize DHCP server in Active Directory (Configure-DHCP.ps1)
- [x] Create DHCP scope (Configure-DHCP.ps1)
  - [x] Scope name: Lab Network
  - [x] Network: 192.168.56.0/24
  - [x] Range: 192.168.56.100 - 192.168.56.200
  - [x] Subnet mask: 255.255.255.0
  - [x] Lease duration: 8 hours
- [x] Configure DHCP options (Configure-DHCP.ps1)
  - [x] Option 003 (Router): 192.168.56.1
  - [x] Option 006 (DNS): 192.168.56.10
  - [x] Option 015 (DNS Domain): lab.local
- [ ] Create DHCP reservations (if needed)
- [x] Activate scope (Configure-DHCP.ps1)
- [ ] Test DHCP from CLIENT01

### 5. SQL Server Installation (SCCM01)

- [x] Create `scripts/sql/Install-SQLServer.ps1`
  - [x] Full technology explanation with learning content
  - [x] Configuration file generation for unattended install
  - [x] Collation configuration (SQL_Latin1_General_CP1_CI_AS)
  - [x] Service account configuration
  - [x] Memory limit configuration
  - [x] TCP/IP protocol enablement
  - [x] Firewall rule creation
  - [x] Idempotent operation
- [ ] Join SCCM01 to domain first
  - [x] Use `Add-Computer` cmdlet (script ready: Join-LabDomain.ps1)
  - [ ] Reboot and wait for system to come back
- [x] Install .NET Framework 3.5 (handled in Install-SQLServer.ps1)
- [ ] Mount SQL Server ISO or extract files (requires ISO)
- [x] Create SQL Server installation configuration file (in script)
  - [x] Instance: MSSQLSERVER (default instance)
  - [x] Service account: LAB\SQL_Service
  - [x] Collation: SQL_Latin1_General_CP1_CI_AS (REQUIRED for SCCM)
  - [x] Features: Database Engine, Replication, Full-Text, Reporting Services
  - [x] Windows authentication mode
  - [x] Add Administrators as SQL admins
- [x] Execute SQL Server silent installation (in script)
  - [x] Monitor setup logs
  - [x] Handle errors and retries
- [x] Configure SQL Server post-installation (in script)
  - [x] Set max server memory (leave 2GB for OS)
  - [x] Enable TCP/IP protocol
  - [x] Configure SQL Server firewall rules
  - [x] Set SQL Server service to automatic
- [ ] Install SQL Server Management Studio (SSMS) - manual download required
- [x] Validate SQL Server installation (in script)
  - [x] Test connection from SCCM01
  - [x] Verify collation: `SELECT SERVERPROPERTY('Collation')`
  - [x] Check SQL Server version

### 6. SCCM Prerequisites (SCCM01)

- [x] Create `scripts/sccm/Install-Prerequisites.ps1`
  - [x] Full technology explanation with learning content
  - [x] Comprehensive Windows feature installation
- [x] Install required Windows features (in script)
  - [x] .NET Framework 3.5 and 4.8+
  - [x] IIS (Web Server) with all required role services for MP/DP
  - [x] BITS Server Extensions
  - [x] Remote Differential Compression (RDC)
  - [x] All IIS security, compression, authentication features
- [x] Download and install Windows ADK (script supports path parameter)
  - [x] Required features: Deployment Tools, Windows PE
  - [x] Silent installation parameters documented
- [x] Download and install WinPE addon for ADK (script supports path parameter)
- [x] Install ODBC Driver for SQL Server (verification in script)
- [x] Configure IIS (installed via Windows features)
- [x] Verify all prerequisites met
  - [x] AD schema extension check
  - [x] System Management container check
  - [x] SQL Server verification
  - [x] Prerequisites summary report

### 7. SCCM Installation (SCCM01)

- [x] Create `scripts/sccm/Install-SCCM.ps1`
  - [x] Full technology explanation (site types, roles, installation process)
  - [x] Configuration file generation for unattended install
  - [x] Comprehensive pre-installation verification
  - [x] Prerequisite check before installation
  - [x] Post-installation verification
- [ ] Mount or extract SCCM installation media (requires ISO)
- [x] Create SCCM installation configuration file (in script)
  - [x] Site code: PS1
  - [x] Site name: Primary Site 1
  - [x] Installation mode: Install new primary site
  - [x] SQL Server: SCCM01
  - [x] Database name: CM_PS1
  - [x] SMS Provider: SCCM01
  - [x] Management Point: SCCM01
- [x] Run SCCM prerequisite checker (in script)
  - [x] `Setup.exe /PREREQ` command
  - [x] Review prerequisite warnings/errors
- [x] Execute SCCM installation (in script)
  - [x] Silent installation: `Setup.exe /SCRIPT ConfigMgrSetup.ini`
  - [x] Monitor installation logs: ConfigMgrSetup.log
  - [x] Installation takes 30-60 minutes (documented)
- [x] Wait for SCCM installation to complete (in script)
  - [x] Check SCCM services
  - [x] Check WMI namespace
  - [x] Check site status

### 8. SCCM Post-Installation Configuration (SCCM01)

- [x] Create `scripts/sccm/Configure-SCCM.ps1`
  - [x] Full technology explanation (boundaries, discovery, client settings)
  - [x] Uses Configuration Manager PowerShell module
  - [x] Verification and status reporting
- [x] Configure site boundaries (in script)
  - [x] Create IP subnet boundary: 192.168.56.0/24
  - [x] Create boundary group: Lab Network Boundary Group
  - [x] Add boundary to boundary group
- [x] Configure boundary group settings (in script)
  - [x] Enable for site assignment
  - [x] Enable for content location
  - [x] Add site system servers (SCCM01 as DP/MP)
- [x] Configure Discovery Methods (in script)
  - [x] Enable Active Directory System Discovery
  - [x] Enable Active Directory User Discovery
  - [x] Verify Heartbeat Discovery
- [x] Configure Client Settings (documented for manual setup)
  - [ ] Set client installation properties (Console)
  - [ ] Configure hardware inventory schedule (Console)
  - [ ] Configure software inventory (optional, Console)
  - [ ] Enable remote control (Console)
- [x] Distribution Point role (installed with site)
  - [x] Verify DP configuration
- [x] Configure Network Access Account (in script)
  - [x] Account: LAB\SCCM_NAA
  - [x] Configured via Set-CMAccount
- [x] Install SCCM console on SCCM01 (installed with site)
- [x] Verify SCCM site health (in script)
  - [x] Check component status
  - [x] Verification report

### 9. Client Domain Join (CLIENT01+)

- [x] Create `scripts/common/Join-LabDomain.ps1`
- [ ] Join each client to lab.local domain
  - [x] Use `Add-Computer` cmdlet (script ready)
  - [x] Credentials: LAB\Administrator (script uses credential parameter)
  - [x] Target OU: Workstations (auto-detected in script)
- [ ] Reboot clients
- [ ] Wait for clients to reconnect
- [ ] Verify domain join
  - [ ] Check computer appears in AD Users and Computers
  - [ ] Verify DNS registration

**Additional Common Scripts Created:**
- [x] `scripts/common/Set-LabDNS.ps1` - Configure DNS client to point to DC01

### 10. SCCM Client Installation (CLIENT01+)

- [x] Create `scripts/client/Install-SCCMClient.ps1`
  - [x] Full technology explanation (installation methods, parameters, logs)
  - [x] Pre-installation checks (domain, connectivity, DNS)
  - [x] Client file location and download
  - [x] Installation monitoring
  - [x] Post-installation verification
- [ ] Configure Client Push Installation (Console)
  - [ ] Account: LAB\SCCM_ClientPush (with local admin rights)
  - [ ] Enable automatic site-wide client push
  - [ ] Configure installation properties
- [x] Manual client installation (script supports this)
  - [x] Copy ccmsetup.exe from SCCM01
  - [x] Run: `ccmsetup.exe /mp:SCCM01 SMSSITECODE=PS1`
- [x] Verify client installation (in script)
  - [x] Check ConfigMgr Control Panel applet
  - [x] Verify CcmExec service
  - [x] Check client logs: `C:\Windows\CCM\Logs\`
- [ ] Trigger client actions (manual via Console/Control Panel)
  - [ ] Machine Policy Retrieval
  - [ ] Hardware Inventory
  - [ ] Discovery Data Collection

---

## Sub-tasks & Considerations

### PowerShell DSC Alternative

- [ ] Consider using PowerShell DSC configurations instead of scripts
- [ ] Evaluate trade-offs: complexity vs. idempotency
- [ ] Document DSC approach for future consideration

### Idempotency

- [ ] Implement checks before each major step
  - [ ] Skip if already configured
  - [ ] Handle partial completions
- [ ] Make scripts safe to re-run
- [ ] Add validation checkpoints

### Error Handling

- [ ] Wrap critical sections in try-catch blocks
- [ ] Log all errors with context
- [ ] Implement rollback where possible
- [ ] Create cleanup scripts for failed deployments

### Credential Management

- [ ] Handle passwords securely (PSCredential objects)
- [ ] Avoid plaintext passwords in scripts
- [ ] Use environment variables or secure input
- [ ] Document password requirements

### Progress Tracking

- [ ] Implement progress bars for long operations
- [ ] Provide estimated time remaining
- [ ] Send notifications on completion/failure
- [ ] Create summary reports

### Cross-Platform Considerations

- [ ] Test scripts from Linux host via PowerShell Core
- [ ] Use `Invoke-Command` for remote execution
- [ ] Handle authentication from non-domain host
- [ ] Test with both PowerShell 5.1 and 7.x

### Service Accounts Documentation

- [ ] Document required service accounts and purposes
- [ ] Document minimum permissions for each account
- [ ] Create password policy for lab accounts
- [ ] Store credentials securely

### SQL Server Considerations

- [ ] Test with both SQL Server 2019 and 2022
- [ ] Verify collation is correct (SCCM requirement)
- [ ] Configure SQL memory limits appropriately
- [ ] Enable SQL Server Browser service if using named instances

### SCCM Schema Extension

- [ ] Validate schema extension in AD
  - [ ] Check for System Management container
  - [ ] Verify permissions
- [ ] Handle Enterprise Admin privilege requirement
- [ ] Test in separate forest if needed

---

## Deliverables

### Modules
- [x] `scripts/modules/Logger.psm1` - Logging with timestamps, levels, colors
- [ ] `scripts/modules/WinRMHelper.psm1` - Deferred (using Vagrant WinRM instead)
- [x] `scripts/modules/Validator.psm1` - Validation functions for all components

### DC01 Scripts
- [x] `scripts/dc/Install-ADDS.ps1` - Install AD DS role
- [x] `scripts/dc/Promote-DC.ps1` - Promote to domain controller
- [x] `scripts/dc/Configure-DNS.ps1` - Configure DNS zones and records
- [x] `scripts/dc/Configure-DHCP.ps1` - Configure DHCP scope and options
- [x] `scripts/dc/Create-OUs.ps1` - Create organizational units
- [x] `scripts/dc/Create-ServiceAccounts.ps1` - Create service accounts

### Common Scripts
- [x] `scripts/common/Set-LabDNS.ps1` - Configure DNS client to point to DC01
- [x] `scripts/common/Join-LabDomain.ps1` - Join computer to domain

### Orchestration
- [x] `scripts/orchestration/deploy-dc.sh` - DC01 deployment orchestration (Bash)
- [x] `scripts/orchestration/deploy-sccm.sh` - SCCM01 deployment orchestration (Bash)
- [x] `scripts/orchestration/deploy-client.sh` - Client deployment orchestration (Bash)

### SQL Scripts
- [x] `scripts/sql/Install-SQLServer.ps1` - SQL Server installation with full documentation

### SCCM Scripts
- [x] `scripts/sccm/Install-Prerequisites.ps1` - Windows features and SCCM prerequisites
- [x] `scripts/sccm/Install-SCCM.ps1` - SCCM primary site installation
- [x] `scripts/sccm/Configure-SCCM.ps1` - Post-installation configuration

### Client Scripts
- [x] `scripts/client/Install-SCCMClient.ps1` - SCCM client installation

### DC Scripts (Additional)
- [x] `scripts/dc/Extend-ADSchema.ps1` - AD schema extension for SCCM

### Documentation
- [x] `docs/phase3-manual-setup.md` - Manual setup guide
- [x] `docs/phase3-automation-plan.md` - Automation strategy
- [ ] `docs/winrm-automation.md` - WinRM setup and troubleshooting
- [ ] `docs/passwords.md` - Password management
- [ ] `docs/service-accounts.md` - Required accounts and permissions

---

## Potential Issues & Solutions

### Issue: WinRM authentication fails

**Symptoms**: "Access is denied" or authentication errors

**Solutions**:
- Configure TrustedHosts on NixOS host
- Use CredSSP for double-hop scenarios
- Verify domain join completed successfully
- Check Windows Firewall rules

### Issue: PowerShell Core module compatibility

**Symptoms**: Windows management modules don't load

**Solutions**:
- Use `Invoke-Command` to run inside Windows PowerShell 5.1
- Don't run Windows-specific modules directly in PowerShell Core
- Test module compatibility before use

### Issue: AD schema extension requires Enterprise Admin

**Symptoms**: Schema extension fails with permission error

**Solutions**:
- Run as Administrator on DC01
- Verify account has Enterprise Admin privileges
- In lab environment, use domain admin account

### Issue: SQL Server collation incorrect

**Symptoms**: SCCM installation fails with collation error

**Solutions**:
- Uninstall SQL Server completely
- Reinstall with `SQL_Latin1_General_CP1_CI_AS` collation
- Verify collation before SCCM installation

### Issue: SCCM installation takes 30-60 minutes

**Symptoms**: Long wait times, uncertainty about progress

**Solutions**:
- Monitor ConfigMgrSetup.log in real-time
- Implement progress tracking in script
- Set expectations in documentation
- Use VM snapshots to avoid repeated installations

### Issue: Client push fails

**Symptoms**: Clients don't appear in SCCM console

**Solutions**:
- Verify Windows Firewall rules (ports 135, 139, 445)
- Check admin$ share accessibility: `\\CLIENT01\admin$`
- Verify Client Push Account has local admin rights
- Review ccm.log on SCCM01 for errors
- Try manual client installation as fallback

### Issue: Network discovery doesn't work properly

**Symptoms**: Clients not discovered automatically

**Solutions**:
- VirtualBox NAT networks may not support broadcast
- Use Active Directory System Discovery instead
- Manually add computers if needed
- Adjust discovery settings

---

## Testing Checklist

```bash
# Test DC setup
pwsh -c "Invoke-Command -ComputerName 192.168.56.10 -Credential LAB\Administrator -ScriptBlock { Get-ADDomain }"
# Expected: Domain information for lab.local

# Test DNS
pwsh -c "Invoke-Command -ComputerName 192.168.56.10 -Credential LAB\Administrator -ScriptBlock { Resolve-DnsName sccm01.lab.local }"
# Expected: IP address 192.168.56.11

# Test DHCP
pwsh -c "Invoke-Command -ComputerName 192.168.56.10 -Credential LAB\Administrator -ScriptBlock { Get-DhcpServerv4Scope }"
# Expected: Scope 192.168.56.0

# Test SQL Server
pwsh -c "Invoke-Command -ComputerName 192.168.56.11 -Credential LAB\Administrator -ScriptBlock { Get-Service MSSQLSERVER }"
# Expected: Running

# Test SCCM Site Status
pwsh -c "Invoke-Command -ComputerName 192.168.56.11 -Credential LAB\Administrator -ScriptBlock { Get-Service SMS_EXECUTIVE }"
# Expected: Running

# Test Client Domain Join
pwsh -c "Invoke-Command -ComputerName CLIENT01 -Credential LAB\Administrator -ScriptBlock { (Get-WmiObject Win32_ComputerSystem).Domain }"
# Expected: lab.local

# Test SCCM Client
pwsh -c "Invoke-Command -ComputerName CLIENT01 -Credential LAB\Administrator -ScriptBlock { Get-Service CcmExec }"
# Expected: Running
```

---

## Success Criteria

Phase 3 is complete when:

- ✅ Active Directory domain (lab.local) is operational
- ✅ DNS resolves all lab systems correctly
- ✅ DHCP assigns IPs to clients
- ✅ SQL Server installed with correct collation
- ✅ SCCM primary site installed and operational
- ✅ SCCM site boundaries and boundary groups configured
- ✅ All clients domain-joined
- ✅ SCCM clients installed and reporting to site
- ✅ All automation scripts execute successfully
- ✅ Can redeploy entire lab with one command sequence

---

## Next Steps

Once Phase 3 is complete, proceed to:
- **Phase 4**: PXE Booting & OSD Automation
- See `.claude/phase4-checklist.md`

---

## Notes

### 2026-01-27 - Phase 3 Planning & Documentation

**Completed:**
1. Created comprehensive manual setup guide (`docs/phase3-manual-setup.md`)
   - Detailed explanations of AD DS, DNS, DHCP, SQL Server, SCCM, and WinRM
   - Step-by-step manual procedures with PowerShell commands
   - Manual setup checklist for tracking progress
   - Verification procedures for each component
   - Troubleshooting guide

2. Created automation planning document (`docs/phase3-automation-plan.md`)
   - Architecture diagram showing Linux → Vagrant → Windows flow
   - Cross-platform challenges documented
   - Implementation strategy using Vagrant WinRM
   - Error handling patterns documented

**Key Decisions:**
- Use Vagrant WinRM (not direct PowerShell remoting) from Linux host
- Scripts execute locally on Windows VMs for full module access
- Bash orchestration scripts coordinate deployment phases
- PowerShell modules for reusable logging, validation, helpers

---

### 2026-01-27 - Phase 3 Implementation (Continued)

**Scripts Created:**

**PowerShell Modules:**
- `scripts/modules/Logger.psm1` - Comprehensive logging with timestamps, levels, colors
- `scripts/modules/Validator.psm1` - Validation functions for all lab components

**DC01 Scripts (Active Directory, DNS, DHCP):**
- `scripts/dc/Install-ADDS.ps1` - Install AD DS role with idempotency
- `scripts/dc/Promote-DC.ps1` - Promote to domain controller, create lab.local forest
- `scripts/dc/Configure-DNS.ps1` - Reverse lookup zone, A records, forwarders
- `scripts/dc/Configure-DHCP.ps1` - DHCP scope 192.168.56.100-200 with options
- `scripts/dc/Create-OUs.ps1` - Organizational units structure
- `scripts/dc/Create-ServiceAccounts.ps1` - SQL_Service, SCCM_NAA, SCCM_ClientPush, SCCM_JoinDomain
- `scripts/dc/Extend-ADSchema.ps1` - AD schema extension and System Management container

**Common Scripts:**
- `scripts/common/Set-LabDNS.ps1` - Configure DNS client to point to DC01
- `scripts/common/Join-LabDomain.ps1` - Join computer to lab.local domain

**SQL Server Scripts:**
- `scripts/sql/Install-SQLServer.ps1` - Complete SQL Server installation
  - Configuration file generation for unattended install
  - Correct collation (SQL_Latin1_General_CP1_CI_AS)
  - Service account configuration
  - Memory limits, TCP/IP, firewall rules
  - Comprehensive verification

**SCCM Scripts:**
- `scripts/sccm/Install-Prerequisites.ps1` - Windows features and SCCM prerequisites
  - All required IIS features for MP/DP
  - .NET Framework, BITS, RDC
  - ADK and WinPE support
  - Prerequisites verification
- `scripts/sccm/Install-SCCM.ps1` - SCCM primary site installation
  - Configuration file generation
  - Prerequisite checker
  - Unattended installation
  - Post-installation verification
- `scripts/sccm/Configure-SCCM.ps1` - Post-installation configuration
  - Boundaries and boundary groups
  - Discovery methods
  - Network Access Account

**Client Scripts:**
- `scripts/client/Install-SCCMClient.ps1` - SCCM client installation
  - Pre-installation checks
  - Client file download and installation
  - Installation monitoring
  - Verification

**Orchestration Scripts (Bash):**
- `scripts/orchestration/deploy-dc.sh` - Complete DC01 deployment
- `scripts/orchestration/deploy-sccm.sh` - Complete SCCM01 deployment
- `scripts/orchestration/deploy-client.sh` - Client deployment

**All scripts include:**
- Comprehensive technology explanations for learning
- Idempotent operations (safe to re-run)
- Detailed logging with timestamps
- Error handling and verification
- Cross-platform considerations (Linux host via Vagrant WinRM)

**Remaining Manual Steps:**
- Download SQL Server ISO
- Download SCCM installation media
- Download Windows ADK and WinPE addon
- Configure Client Push Installation in SCCM Console
- Some client settings require Console configuration

---

**Phase 3 Automation Scripts**: ✅ Complete  
**Phase 3 Testing**: ☐ Pending (requires installation media)  
**Completed By**: _____  
**Sign-off Date**: _____
