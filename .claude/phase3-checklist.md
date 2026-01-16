# Phase 3: WinRM Automation Layer

**Status**: ⚪ Planned  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Fully automate Windows Server configuration using PowerShell remoting and WinRM. This is the core automation phase that builds AD, DNS, DHCP, SQL Server, and SCCM.

## Goals

- [ ] Fully automate Windows Server configuration
- [ ] Implement infrastructure as code for AD, DNS, DHCP, SQL, SCCM
- [ ] Create reusable PowerShell modules
- [ ] Enable one-command deployment

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

- [ ] Create `scripts/modules/Logger.psm1`
  - [ ] Write-Log function with timestamps
  - [ ] Log levels (INFO, WARN, ERROR, SUCCESS)
  - [ ] File and console output
  - [ ] Color-coded console output
- [ ] Create `scripts/modules/WinRMHelper.psm1`
  - [ ] New-RemoteSession function
  - [ ] Test-RemoteConnection function
  - [ ] Invoke-RemoteScript function
  - [ ] Get-RemoteSessionStatus function
  - [ ] Connection retry logic with exponential backoff
- [ ] Create `scripts/modules/Validator.psm1`
  - [ ] Test-ADDSInstalled function
  - [ ] Test-DNSConfiguration function
  - [ ] Test-DHCPConfiguration function
  - [ ] Test-SQLServerInstalled function
  - [ ] Test-SCCMInstalled function
  - [ ] Test-DomainJoined function

### 2. Active Directory Domain Services (DC01)

- [ ] Create `scripts/dc-setup.ps1`
- [ ] Install AD DS role and management tools
  - [ ] `Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools`
- [ ] Promote server to domain controller
  - [ ] Domain name: lab.local
  - [ ] NetBIOS name: LAB
  - [ ] Forest functional level: Windows Server 2016 or higher
  - [ ] Safe mode password configuration
  - [ ] Handle automatic reboot
- [ ] Wait for AD DS to be fully operational
- [ ] Configure DNS forwarders (8.8.8.8, 1.1.1.1)
- [ ] Create reverse lookup zone (56.168.192.in-addr.arpa)
- [ ] Create organizational units
  - [ ] Servers
  - [ ] Workstations
  - [ ] Users/Administrators
  - [ ] Users/Standard Users
  - [ ] Service Accounts
- [ ] Create service accounts
  - [ ] SQL_Service (SQL Server service account)
  - [ ] SCCM_NAA (Network Access Account)
  - [ ] SCCM_ClientPush (Client push installation)
  - [ ] SCCM_JoinDomain (Domain join for OSD)
- [ ] Set appropriate permissions on service accounts
- [ ] Create test user accounts (optional)
- [ ] Extend AD schema for SCCM
  - [ ] Run: `extadsch.exe` from SCCM media
  - [ ] Create System Management container
  - [ ] Grant permissions to SCCM computer account
- [ ] Validate AD DS configuration

### 3. DNS Server Configuration (DC01)

- [ ] Create forward lookup zone for lab.local
- [ ] Add DNS records for servers
  - [ ] dc01.lab.local → 192.168.56.10
  - [ ] sccm01.lab.local → 192.168.56.11
- [ ] Configure DNS forwarders
- [ ] Create reverse lookup zone
- [ ] Configure dynamic updates (secure updates only)
- [ ] Test DNS resolution
  - [ ] From DC01: `nslookup sccm01.lab.local`
  - [ ] From SCCM01: `nslookup dc01.lab.local`

### 4. DHCP Server Configuration (DC01)

- [ ] Install DHCP role and management tools
  - [ ] `Install-WindowsFeature -Name DHCP -IncludeManagementTools`
- [ ] Authorize DHCP server in Active Directory
- [ ] Create DHCP scope
  - [ ] Scope name: Lab Network
  - [ ] Network: 192.168.56.0/24
  - [ ] Range: 192.168.56.100 - 192.168.56.200
  - [ ] Subnet mask: 255.255.255.0
  - [ ] Lease duration: 8 hours
- [ ] Configure DHCP options
  - [ ] Option 003 (Router): 192.168.56.1
  - [ ] Option 006 (DNS): 192.168.56.10
  - [ ] Option 015 (DNS Domain): lab.local
- [ ] Create DHCP reservations (if needed)
- [ ] Activate scope
- [ ] Test DHCP from CLIENT01

### 5. SQL Server Installation (SCCM01)

- [ ] Create `scripts/sql-setup.ps1`
- [ ] Join SCCM01 to domain first
  - [ ] Use `Add-Computer` cmdlet
  - [ ] Reboot and wait for system to come back
- [ ] Install .NET Framework 3.5 (required for SQL Server)
- [ ] Mount SQL Server ISO or extract files
- [ ] Create SQL Server installation configuration file
  - [ ] Instance: MSSQLSERVER (default instance)
  - [ ] Service account: LAB\SQL_Service
  - [ ] Collation: SQL_Latin1_General_CP1_CI_AS (REQUIRED for SCCM)
  - [ ] Features: Database Engine, Management Tools, Reporting Services
  - [ ] SA account disabled (use Windows authentication)
  - [ ] Add SCCM01\Administrator and LAB\Administrator as SQL admins
- [ ] Execute SQL Server silent installation
  - [ ] Monitor setup logs
  - [ ] Handle errors and retries
- [ ] Configure SQL Server post-installation
  - [ ] Set max server memory (leave 2GB for OS)
  - [ ] Enable TCP/IP protocol
  - [ ] Configure SQL Server firewall rules
  - [ ] Set SQL Server service to automatic
  - [ ] Restart SQL Server service
- [ ] Install SQL Server Management Studio (SSMS)
- [ ] Validate SQL Server installation
  - [ ] Test connection from SCCM01
  - [ ] Verify collation: `SELECT SERVERPROPERTY('Collation')`
  - [ ] Check SQL Server version

### 6. SCCM Prerequisites (SCCM01)

- [ ] Create `scripts/sccm-prereq.ps1`
- [ ] Install required Windows features
  - [ ] .NET Framework 3.5 and 4.8+
  - [ ] IIS (Web Server) with required role services
  - [ ] BITS Server Extensions
  - [ ] Remote Differential Compression (RDC)
- [ ] Download and install Windows ADK
  - [ ] Required features: Deployment Tools, Windows PE
  - [ ] Silent installation parameters
- [ ] Download and install WinPE addon for ADK
- [ ] Install ODBC Driver for SQL Server (18.4.1.1+)
- [ ] Configure IIS
  - [ ] Set up application pools
  - [ ] Configure HTTPS bindings (optional)
- [ ] Verify all prerequisites met
  - [ ] Run SCCM prerequisite checker (will be available in Phase 3)

### 7. SCCM Installation (SCCM01)

- [ ] Create `scripts/sccm-install.ps1`
- [ ] Mount or extract SCCM installation media
- [ ] Create SCCM installation configuration file (ConfigMgrSetup.ini)
  - [ ] Site code: PS1
  - [ ] Site name: SCCM Primary Site 1
  - [ ] Installation mode: Install new primary site
  - [ ] SQL Server: SCCM01
  - [ ] Database name: CM_PS1
  - [ ] SMS Provider: SCCM01
  - [ ] Management Point: SCCM01
- [ ] Run SCCM prerequisite checker
  - [ ] `Setup.exe /TESTDBUPGRADE` (if upgrading)
  - [ ] Review prerequisite warnings/errors
- [ ] Execute SCCM installation
  - [ ] Silent installation: `Setup.exe /SCRIPT ConfigMgrSetup.ini`
  - [ ] Monitor installation logs: ConfigMgrSetup.log
  - [ ] Installation takes 30-60 minutes
- [ ] Wait for SCCM installation to complete
  - [ ] Monitor SMS_SITE_COMPONENT_MANAGER
  - [ ] Check site status

### 8. SCCM Post-Installation Configuration (SCCM01)

- [ ] Create `scripts/sccm-config.ps1`
- [ ] Configure site boundaries
  - [ ] Create IP subnet boundary: 192.168.56.0/24
  - [ ] Create boundary group: Lab Network
  - [ ] Add boundary to boundary group
- [ ] Configure boundary group settings
  - [ ] Enable for site assignment
  - [ ] Enable for content location
  - [ ] Add site system servers (SCCM01 as DP/MP)
- [ ] Configure Discovery Methods
  - [ ] Enable Active Directory System Discovery
  - [ ] Enable Active Directory User Discovery
  - [ ] Enable Network Discovery (optional)
  - [ ] Enable Heartbeat Discovery
- [ ] Configure Client Settings
  - [ ] Set client installation properties
  - [ ] Configure hardware inventory schedule
  - [ ] Configure software inventory (optional)
  - [ ] Enable remote control
- [ ] Enable Distribution Point role (already installed with site)
  - [ ] Verify DP configuration
  - [ ] Test content distribution
- [ ] Configure Network Access Account
  - [ ] Account: LAB\SCCM_NAA
  - [ ] Set in Client Settings
- [ ] Install SCCM console on SCCM01 (if not already)
- [ ] Verify SCCM site health
  - [ ] Check component status
  - [ ] Review logs in `C:\Program Files\Microsoft Configuration Manager\Logs\`

### 9. Client Domain Join (CLIENT01+)

- [ ] Create `scripts/client-join.ps1`
- [ ] Join each client to lab.local domain
  - [ ] Use `Add-Computer` cmdlet
  - [ ] Credentials: LAB\Administrator
  - [ ] Target OU: Computers/Workstations
- [ ] Reboot clients
- [ ] Wait for clients to reconnect
- [ ] Verify domain join
  - [ ] Check computer appears in AD Users and Computers
  - [ ] Verify DNS registration

### 10. SCCM Client Installation (CLIENT01+)

- [ ] Create `scripts/client-sccm.ps1`
- [ ] Configure Client Push Installation
  - [ ] Account: LAB\SCCM_ClientPush (with local admin rights)
  - [ ] Enable automatic site-wide client push
  - [ ] Configure installation properties
- [ ] Manual client installation (alternative)
  - [ ] Copy ccmsetup.exe from SCCM01
  - [ ] Run: `ccmsetup.exe /mp:SCCM01 SMSSITECODE=PS1`
- [ ] Verify client installation
  - [ ] Check ConfigMgr Control Panel applet
  - [ ] Verify client appears in SCCM console
  - [ ] Check client logs: `C:\Windows\CCM\Logs\`
- [ ] Trigger client actions
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

- [ ] `scripts/modules/Logger.psm1`
- [ ] `scripts/modules/WinRMHelper.psm1`
- [ ] `scripts/modules/Validator.psm1`
- [ ] `scripts/dc-setup.ps1`
- [ ] `scripts/sql-setup.ps1`
- [ ] `scripts/sccm-prereq.ps1`
- [ ] `scripts/sccm-install.ps1`
- [ ] `scripts/sccm-config.ps1`
- [ ] `scripts/client-join.ps1`
- [ ] `scripts/client-sccm.ps1`
- [ ] `docs/winrm-automation.md`
- [ ] `docs/passwords.md`
- [ ] `docs/service-accounts.md`

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

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

---

**Phase 3 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
