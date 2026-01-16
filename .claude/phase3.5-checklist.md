# Phase 3.5: Azure Integration Foundation (Optional but Recommended)

**Status**: ⚪ Optional  
**Start Date**: _____  
**Completion Date**: _____

## Overview

This **optional phase** bridges traditional on-premises SCCM with modern cloud-integrated endpoint management. It enables co-management, tenant attach, Cloud Management Gateway (CMG), and hybrid Azure AD scenarios that are increasingly common in 2026 enterprise environments.

**Important**: This phase requires an Azure subscription and will incur cloud costs (~$0-50/month depending on usage). You can complete Phases 1-3 without this phase for traditional SCCM-only learning.

## Goals

- [ ] Integrate on-premises Active Directory with Azure AD (Microsoft Entra ID)
- [ ] Enable hybrid Azure AD join for domain-joined devices
- [ ] Deploy Cloud Management Gateway (CMG) for internet-based client management
- [ ] Configure tenant attach to upload devices to Microsoft Endpoint Manager
- [ ] Enable co-management between SCCM and Intune
- [ ] Test modern management scenarios (Intune policies, conditional access, Endpoint Analytics)

---

## Prerequisites

### Azure Requirements
- [ ] Azure subscription (free trial acceptable for initial testing)
  - Option 1: [Azure Free Trial](https://azure.microsoft.com/free/) - $200 credit for 30 days
  - Option 2: [Microsoft 365 Developer Program](https://developer.microsoft.com/microsoft-365/dev-program) - Free renewable 90-day E5 tenant
  - Option 3: Visual Studio subscription with Azure credits
- [ ] Microsoft Intune license (trial or paid)
  - Can activate 30-day Intune trial from Azure portal
  - Or included in Microsoft 365 E3/E5, EMS E3/E5
- [ ] Global Administrator account for Azure AD tenant
- [ ] Public DNS domain name (optional, can use `*.onmicrosoft.com` domain)

### Lab Environment Prerequisites
- ✅ Phase 1 completed (Nix environment ready)
- ✅ Phase 2 completed (VMs running)
- ✅ Phase 3 completed (AD, DNS, DHCP, SQL, SCCM operational)
- [ ] Internet connectivity from DC01 and SCCM01 (verify NAT network working)
- [ ] TLS 1.2 enabled on all Windows servers
- [ ] .NET Framework 4.6.2 or later installed on DC01 and SCCM01

### Downloaded Software
- [ ] Azure AD Connect (latest version)
  - Download: https://www.microsoft.com/en-us/download/details.aspx?id=47594
- [ ] Optional: Azure AD Connect Health Agent
- [ ] SSL certificate for CMG (can use self-signed for lab)

---

## Main Tasks

### 1. Azure Tenant Setup and Preparation

#### 1.1 Create Azure AD Tenant (if needed)
- [ ] Sign up for Azure subscription at https://azure.microsoft.com/free/
- [ ] Verify Azure AD tenant created (e.g., `labtest.onmicrosoft.com`)
- [ ] Note tenant ID from Azure Portal → Azure Active Directory → Overview
- [ ] Create at least 2 test users in Azure AD for testing
- [ ] Verify Global Administrator role assigned to your account

#### 1.2 Activate Intune Trial
- [ ] Navigate to Azure Portal → Microsoft Intune
- [ ] Start 30-day trial if no license exists
- [ ] Verify Intune license shows in Azure AD → Licenses
- [ ] Assign Intune licenses to test users
- [ ] Access Microsoft Endpoint Manager admin center: https://endpoint.microsoft.com/

#### 1.3 Configure Azure AD Domain (Optional)
- [ ] If using custom domain, add to Azure AD → Custom domain names
- [ ] Add DNS TXT record to verify domain ownership
- [ ] Set as primary domain if desired
- [ ] **Alternative**: Use default `*.onmicrosoft.com` domain for lab

#### 1.4 Azure Resource Preparation for CMG
- [ ] Create Azure resource group: `RG-SCCM-Lab-CMG`
- [ ] Verify subscription has Microsoft.Compute resource provider registered
- [ ] Create Azure Storage account for CMG (or let SCCM create it)
- [ ] Note Azure subscription ID for SCCM configuration

---

### 2. Azure AD Connect Installation and Configuration

#### 2.1 Pre-Installation Checks on DC01
```powershell
# Verify internet connectivity
Test-NetConnection -ComputerName login.microsoftonline.com -Port 443

# Check PowerShell version (should be 5.1+)
$PSVersionTable.PSVersion

# Verify .NET Framework version (4.6.2+)
(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -ge 394802

# Check TLS 1.2 enabled
[Net.ServicePointManager]::SecurityProtocol
```

- [ ] All pre-checks pass on DC01
- [ ] Verify DC01 has internet access via NAT network
- [ ] Ensure DC01 can resolve public DNS names

#### 2.2 Install Azure AD Connect
- [ ] Copy Azure AD Connect installer to DC01
- [ ] Run installer: `AzureADConnect.msi`
- [ ] Select "Express Settings" for simplicity (or "Customize" for advanced)
- [ ] Sign in with Azure AD Global Administrator account
- [ ] Sign in with on-premises Enterprise Admin account (LAB\Administrator)

#### 2.3 Configure Synchronization Settings
- [ ] Select "Password Hash Synchronization" (recommended for lab)
  - Alternative: "Pass-through Authentication" or "Federation with AD FS"
- [ ] Choose organizational units to sync (sync all or select specific OUs)
- [ ] Configure UPN suffixes if using custom domain
- [ ] Review and confirm configuration
- [ ] Start synchronization process

#### 2.4 Verify Azure AD Sync
```powershell
# On DC01, check sync status
Import-Module ADSync
Get-ADSyncScheduler

# Verify sync connector status
Get-ADSyncConnectorRunStatus

# Force initial sync if needed
Start-ADSyncSyncCycle -PolicyType Initial
```

- [ ] Initial synchronization completes without errors
- [ ] Verify users appear in Azure Portal → Azure Active Directory → Users
- [ ] Confirm synced users show "Windows Server AD" as source
- [ ] Test sign-in to https://portal.azure.com with synced user account
- [ ] Verify password hash sync working (user can authenticate with on-prem password)

#### 2.5 Configure Sync Scheduler
- [ ] Configure sync interval (default 30 minutes)
- [ ] Enable automatic sync scheduler
- [ ] Document sync schedule in lab notes

---

### 3. Hybrid Azure AD Join Configuration

#### 3.1 Configure Service Connection Point (SCP) in AD
- [ ] Open Azure AD Connect configuration wizard
- [ ] Navigate to "Configure device options" → "Configure Hybrid Azure AD join"
- [ ] Select target OS: Windows 10/11
- [ ] Choose authentication method: Managed (if using password hash sync) or Federated
- [ ] Configure SCP in on-premises AD forest
- [ ] Verify SCP created:

```powershell
# Check SCP in AD
$scp = New-Object System.DirectoryServices.DirectoryEntry
$scp.Path = "LDAP://CN=62a0ff2e-97b9-4513-943f-0d221bd30080,CN=Device Registration Configuration,CN=Services,CN=Configuration,DC=lab,DC=local"
$scp.keywords
```

- [ ] SCP keywords show Azure AD tenant information

#### 3.2 Configure Group Policy for Device Registration
- [ ] On DC01, open Group Policy Management
- [ ] Create new GPO: "Azure AD Device Registration"
- [ ] Navigate to: Computer Configuration → Policies → Administrative Templates → Windows Components → Device Registration
- [ ] Enable: "Register domain-joined computers as devices"
- [ ] Link GPO to domain or OU containing client computers
- [ ] Run `gpupdate /force` on DC01

#### 3.3 Test Hybrid Azure AD Join on CLIENT01
- [ ] On CLIENT01, run `gpupdate /force`
- [ ] Reboot CLIENT01
- [ ] After reboot, check device registration status:

```cmd
dsregcmd /status
```

- [ ] Verify output shows:
  - `AzureAdJoined : YES`
  - `DomainJoined : YES`
  - `DomainName : lab.local`
  - `TenantId : <your-tenant-id>`

- [ ] In Azure Portal → Azure Active Directory → Devices
  - [ ] CLIENT01 appears in device list
  - [ ] Join Type shows "Hybrid Azure AD joined"
  - [ ] Management Type shows "Unmanaged" (will change after co-management)

#### 3.4 Troubleshooting Hybrid Join (if needed)
- [ ] Check Task Scheduler → Microsoft → Windows → Workplace Join → Automatic-Device-Join
- [ ] Review event logs: Event Viewer → Applications and Services Logs → Microsoft → Windows → User Device Registration
- [ ] Common issues:
  - SCP not configured correctly
  - Firewall blocking https://enterpriseregistration.windows.net
  - Time sync issues between on-prem and Azure
  - Certificate issues

---

### 4. Cloud Management Gateway (CMG) Deployment

#### 4.1 Generate CMG Server Authentication Certificate

**Option A: Self-Signed Certificate (Lab Only)**
```powershell
# On SCCM01, generate self-signed cert
$cert = New-SelfSignedCertificate `
    -DnsName "cmg.labtest.cloudapp.net" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyExportPolicy Exportable `
    -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(2)

# Export certificate with private key
$certPassword = ConvertTo-SecureString -String "P@ssw0rd!" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\Temp\CMG-Cert.pfx" -Password $certPassword
```

- [ ] CMG certificate created and exported
- [ ] Certificate password documented securely

**Option B: Purchase Certificate from Public CA** (for production-like testing)
- [ ] Purchase wildcard certificate from DigiCert, Let's Encrypt, etc.
- [ ] Certificate subject name must match Azure cloud service name
- [ ] Export certificate with private key as .pfx

#### 4.2 Configure Azure Services Connection in SCCM
- [ ] On SCCM01, open Configuration Manager console
- [ ] Navigate to: Administration → Cloud Services → Azure Services
- [ ] Click "Configure Azure Services"
- [ ] Select "Cloud Management" service type
- [ ] Sign in with Azure AD Global Administrator account
- [ ] Create server app and client app in Azure AD (wizard automates this)
- [ ] Verify apps created in Azure Portal → Azure AD → App registrations:
  - ConfigMgr Server App
  - ConfigMgr Client App
- [ ] Enable Azure AD User Discovery
- [ ] Enable Azure AD User Group Discovery (optional)
- [ ] Complete wizard and verify connection successful

#### 4.3 Deploy Cloud Management Gateway
- [ ] In ConfigMgr console → Administration → Cloud Services → Cloud Management Gateway
- [ ] Click "Create Cloud Management Gateway"
- [ ] Sign in to Azure with subscription owner/contributor account
- [ ] Select Azure subscription and resource group
- [ ] Select region (choose closest or cheapest, e.g., East US)
- [ ] Select certificate: Import the CMG-Cert.pfx created earlier
- [ ] Enter certificate password
- [ ] Configure settings:
  - Service name: `cmg-labtest` (will become `cmg-labtest.cloudapp.net`)
  - VM size: **B2s (Lab)** - small/cheap for testing
  - Instances: 1 (minimum for lab)
  - Verify client certificate revocation: Optional (disable for self-signed certs)
  - Enforce TLS 1.2: Yes (recommended)
  - Enable CMG to function as cloud distribution point: Yes (optional)
- [ ] Review and create CMG
- [ ] Wait 15-30 minutes for Azure deployment to complete

#### 4.4 Verify CMG Deployment
```powershell
# Check CMG status in ConfigMgr
Get-CMCloudManagementGateway

# In Azure Portal, verify resources created:
# - Cloud Service (classic) or Virtual Machine Scale Set
# - Storage account for CMG
# - Network resources
```

- [ ] CMG status shows "Ready" in ConfigMgr console
- [ ] Azure resources visible in Azure Portal → Resource Group
- [ ] CloudMgr.log on SCCM01 shows successful deployment (C:\Program Files\Microsoft Configuration Manager\Logs\)

#### 4.5 Configure Management Point for CMG
- [ ] In ConfigMgr console → Administration → Site Configuration → Servers and Site System Roles
- [ ] Select SCCM01 → Management Point role properties
- [ ] Enable: "Allow Configuration Manager cloud management gateway traffic"
- [ ] Select the CMG connection you created
- [ ] Apply and verify settings

#### 4.6 Configure Boundary Group for CMG
- [ ] Navigate to Administration → Hierarchy Configuration → Boundary Groups
- [ ] Edit existing boundary group or create new one
- [ ] In "References" tab → Add CMG as a site system server
- [ ] This allows clients to find CMG when they roam outside corporate network

#### 4.7 Test CMG Connectivity (Optional - Advanced)
- [ ] On CLIENT01, simulate internet-only scenario:
  - Disconnect from host-only network
  - Connect only to NAT network (simulates internet)
  - Or use firewall rules to block on-prem MP, allow only CMG
- [ ] Verify client connects to CMG:

```powershell
# Check client connection status
Get-WmiObject -Namespace root\ccm -Class ClientInfo

# Review CMG logs
Get-Content C:\Windows\CCM\Logs\ClientLocation.log -Tail 50
Get-Content C:\Windows\CCM\Logs\LocationServices.log -Tail 50
```

- [ ] Client successfully communicates via CMG
- [ ] Policies received through cloud gateway

---

### 5. Tenant Attach Configuration

#### 5.1 Prerequisites Verification
- [ ] Azure Services connection already configured in Step 4.2
- [ ] SCCM version is 2002 or later (Current Branch)
- [ ] Verify service connection point is in online mode
- [ ] Verify users are synced to Azure AD

#### 5.2 Enable Tenant Attach
- [ ] In ConfigMgr console → Administration → Cloud Services → Co-management
- [ ] If not already configured, click "Configure co-management"
- [ ] In wizard, select "Tenant attach" or "Enable uploading to Microsoft Endpoint Manager admin center"
- [ ] Choose which device collections to upload:
  - Option 1: All devices managed by SCCM
  - Option 2: Specific collection (create "Tenant Attach Pilot" collection)
- [ ] Complete wizard
- [ ] Wait 5-10 minutes for initial upload

#### 5.3 Verify Tenant Attach in Endpoint Manager
- [ ] Navigate to https://endpoint.microsoft.com/
- [ ] Sign in with Azure AD Global Administrator
- [ ] Go to Devices → All devices
- [ ] Verify SCCM-managed devices appear with:
  - Managed by: Configuration Manager
  - Co-managed: No (initially, will change in next section)
- [ ] Click on a device (e.g., CLIENT01)
- [ ] Test remote actions:
  - [ ] Sync Machine Policy
  - [ ] Restart device
  - [ ] Verify action completes successfully

#### 5.4 Troubleshooting Tenant Attach
- [ ] Check logs on SCCM01:
  - SMS_SERVICE_CONNECTOR.log
  - M365AHandler.log
  - CMGatewaySyncUploadWorker.log
- [ ] Verify Azure AD app permissions in Azure Portal
- [ ] Check service connection point status

---

### 6. Co-Management Configuration

#### 6.1 Co-Management Prerequisites Check
- [ ] Hybrid Azure AD join working (verified in Step 3)
- [ ] Tenant attach enabled (verified in Step 5)
- [ ] Clients are SCCM version 1710 or later
- [ ] Clients running Windows 10 version 1709 or later (or Windows 11)
- [ ] Intune licenses assigned to users

#### 6.2 Enable Co-Management
- [ ] In ConfigMgr console → Administration → Cloud Services → Co-management
- [ ] Click "Configure co-management" (or edit existing)
- [ ] Enable co-management: Yes
- [ ] Choose enrollment method:
  - **Automatic enrollment in Intune**: All clients or Pilot
  - Create pilot collection: "Co-Management Pilot Collection"
  - Add CLIENT01 to pilot collection
- [ ] Configure workload sliders (what Intune manages vs SCCM):
  
  **Recommended starting workloads for pilot**:
  - [ ] Compliance policies → **Intune** (good starting point)
  - [ ] Device Configuration → **Configuration Manager** (keep for now)
  - [ ] Endpoint Protection → **Configuration Manager** (keep for now)
  - [ ] Resource access policies → **Intune** (safe to move)
  - [ ] Client apps → **Configuration Manager** (keep for now)
  - [ ] Office Click-to-Run apps → **Configuration Manager** (keep for now)
  - [ ] Windows Update policies → **Configuration Manager** (keep initially)

- [ ] Complete wizard
- [ ] Wait 10-15 minutes for policies to apply

#### 6.3 Verify Co-Management on Clients
```powershell
# On CLIENT01, check co-management status
Get-WmiObject -Namespace root\ccm\CIModels -Class SMS_Client_ComanagementState

# Check Intune enrollment status
dsregcmd /status
# Look for "MDMUrl" and "MDM enrollment state"

# Verify in Registry
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP\Provider\MS DM Server"
```

- [ ] CLIENT01 shows as Intune-enrolled
- [ ] Device appears in Endpoint Manager with "Co-managed: Yes"
- [ ] Workload authority shows correctly (Intune vs ConfigMgr)

#### 6.4 Verify Co-Management in Endpoint Manager
- [ ] Navigate to https://endpoint.microsoft.com/ → Devices → All devices
- [ ] Find CLIENT01, verify:
  - Managed by: Co-managed
  - Compliance state: (may show "Not evaluated" initially)
  - Last check-in: Recent timestamp
- [ ] Click on device → Monitor → Device configuration
  - Verify both Intune and ConfigMgr policies visible

#### 6.5 Test Workload Management
- [ ] Create simple Intune compliance policy:
  - Navigate to Endpoint Manager → Devices → Compliance policies → Create policy
  - Platform: Windows 10 and later
  - Add simple requirement (e.g., require password)
  - Assign to "All devices" or test group
- [ ] On CLIENT01, force Intune sync:

```powershell
# Force Intune policy sync
Get-ScheduledTask | Where-Object {$_.TaskName -like "*PushLaunch*"} | Start-ScheduledTask

# Or reboot device
```

- [ ] Verify compliance policy evaluated on device
- [ ] Check compliance status in Endpoint Manager
- [ ] Confirm SCCM policies still applying correctly

#### 6.6 Gradually Shift Workloads (Optional)
- [ ] After verifying pilot successful, move additional workloads to Intune:
  - Endpoint Protection → Intune
  - Device Configuration → Intune (gradually)
  - Windows Update policies → Intune
- [ ] Test each workload shift thoroughly before moving next one
- [ ] Document which workloads are Intune vs SCCM for lab reference

---

### 7. Modern Management Scenarios Testing

#### 7.1 Test Intune Policy Deployment
- [ ] Create device configuration profile:
  - Endpoint Manager → Devices → Configuration profiles → Create profile
  - Platform: Windows 10 and later
  - Profile type: Templates → Device restrictions
  - Configure simple setting (e.g., block camera, require password)
  - Assign to test group containing CLIENT01
- [ ] Verify policy applies on CLIENT01
- [ ] Check Company Portal app shows compliance status

#### 7.2 Test Conditional Access (Optional)
- [ ] Create conditional access policy:
  - Azure Portal → Azure Active Directory → Security → Conditional Access
  - Create policy requiring compliant device for accessing Office 365
  - Assign to test user
- [ ] Test access from CLIENT01:
  - Sign in to https://portal.office.com with test user
  - Verify access granted only when device compliant
  - Mark device non-compliant (violate policy) and verify access blocked

#### 7.3 Explore Endpoint Analytics
- [ ] In Endpoint Manager → Reports → Endpoint analytics
- [ ] Enable Endpoint analytics if not already enabled
- [ ] Wait 24-48 hours for data collection
- [ ] Review scores for:
  - Startup performance
  - Application reliability
  - Battery health (if applicable)
  - Work from anywhere score

#### 7.4 Test Remote Actions from Cloud
- [ ] In Endpoint Manager, select CLIENT01
- [ ] Test remote actions:
  - [ ] Sync device
  - [ ] Restart device
  - [ ] Collect diagnostics
  - [ ] Run quick scan (Windows Defender)
- [ ] Verify actions complete and log in CMTrace on CLIENT01

#### 7.5 Test Windows Autopilot (Optional - Advanced)
- [ ] Register device in Autopilot:
  - Get hardware hash from CLIENT01
  - Upload to Endpoint Manager → Devices → Enroll devices → Windows enrollment → Devices
- [ ] Create Autopilot deployment profile
- [ ] Reset CLIENT01 and test Autopilot enrollment flow
- [ ] Verify SCCM client auto-installs after Autopilot

---

## Deliverables

- [ ] Azure AD Connect running on DC01 with active synchronization
- [ ] At least one hybrid Azure AD joined device (CLIENT01)
- [ ] Cloud Management Gateway deployed in Azure and operational
- [ ] Tenant attach configured with devices visible in Endpoint Manager
- [ ] Co-management enabled with at least one workload shifted to Intune
- [ ] Documentation of Azure tenant details (tenant ID, subscription ID, app registrations)
- [ ] Test results demonstrating:
  - User sign-in with synced credentials
  - Device hybrid join successful
  - CMG client communication working
  - Intune policy deployment successful
  - Remote actions from Endpoint Manager working

---

## Potential Issues & Solutions

### Issue: Azure AD Connect Installation Fails
**Symptoms**: "Unable to connect to Azure AD" or "Invalid credentials"
**Solutions**:
- Verify internet connectivity from DC01
- Check TLS 1.2 enabled
- Ensure Global Administrator credentials correct
- Check firewall/proxy not blocking Microsoft endpoints
- Review https://learn.microsoft.com/en-us/azure/active-directory/hybrid/reference-connect-ports

### Issue: Hybrid Azure AD Join Fails
**Symptoms**: `dsregcmd /status` shows "AzureAdJoined : NO"
**Solutions**:
- Verify SCP configured correctly in AD
- Check GPO applied: `gpresult /h gpresult.html` and review
- Check connectivity to https://enterpriseregistration.windows.net
- Ensure time sync between on-prem and Azure (within 5 minutes)
- Review Event Viewer → User Device Registration logs
- Check Azure AD Connect sync is working

### Issue: CMG Deployment Fails
**Symptoms**: CMG status shows "Failed" or stuck in "Provisioning"
**Solutions**:
- Verify Azure subscription has sufficient permissions
- Check certificate is valid and password correct
- Ensure Microsoft.Compute resource provider registered
- Review CloudMgr.log and SMS_CLOUD_SERVICES_MANAGER.log on SCCM01
- Verify no Azure quota limits hit (VM cores, storage)
- Try different Azure region if current region has capacity issues

### Issue: Clients Not Enrolling in Intune
**Symptoms**: Device shows in Endpoint Manager but "MDM Enrollment" shows No
**Solutions**:
- Verify Intune licenses assigned to users
- Check MDM authority set correctly (should be Intune)
- Verify MDM enrollment GPO applied: `gpupdate /force`
- Check Intune service connection point online
- Review Event Viewer → Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider
- Manually test enrollment: Settings → Accounts → Access work or school → Connect

### Issue: Co-Management Not Working
**Symptoms**: Device doesn't show as co-managed in Endpoint Manager
**Solutions**:
- Verify device is hybrid Azure AD joined first
- Check client is in co-management enabled collection
- Ensure SCCM client version 1710+
- Verify Windows 10 version 1709+ or Windows 11
- Check CoManagementHandler.log on client
- Force SCCM machine policy update: `Invoke-WmiMethod -Namespace root\ccm -Class sms_client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}"`

### Issue: Azure Costs Higher Than Expected
**Symptoms**: Unexpected Azure charges
**Solutions**:
- Stop/deallocate CMG when not actively testing
- Use B2s VM size (cheapest) for CMG in lab
- Delete CMG storage account contents periodically
- Use Azure Cost Management to monitor spending
- Set up Azure budget alerts
- Consider using Azure credits from Visual Studio subscription

---

## Testing Procedures

### Test 1: Hybrid Identity Verification
```powershell
# On DC01
Get-ADSyncScheduler
Start-ADSyncSyncCycle -PolicyType Delta

# Verify in Azure Portal
# Azure AD → Users → Find synced user → Check "Source" = "Windows Server AD"

# Test user sign-in
# Open incognito browser → https://portal.azure.com
# Sign in with user@labtest.onmicrosoft.com and on-prem password
```

**Expected Result**: Synced users can authenticate to Azure services with on-premises credentials.

### Test 2: Hybrid Azure AD Join Verification
```cmd
# On CLIENT01
dsregcmd /status

# Expected output:
# +----------------------------------------------------------------------+
# | Device State                                                         |
# +----------------------------------------------------------------------+
#
#              AzureAdJoined : YES
#           EnterpriseJoined : NO
#               DomainJoined : YES
#                 DomainName : lab.local
```

**Expected Result**: Device joined to both on-prem AD and Azure AD.

### Test 3: CMG Communication Test
```powershell
# On CLIENT01
# Simulate internet-only (block on-prem MP with firewall rule)
New-NetFirewallRule -DisplayName "Block SCCM MP" -Direction Outbound -RemoteAddress 192.168.56.11 -Action Block

# Force policy refresh
Invoke-WmiMethod -Namespace root\ccm -Class sms_client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}"

# Check logs
Get-Content C:\Windows\CCM\Logs\ClientLocation.log -Tail 20
# Should show CMG URL

# Cleanup
Remove-NetFirewallRule -DisplayName "Block SCCM MP"
```

**Expected Result**: Client retrieves policies through CMG when on-prem MP blocked.

### Test 4: Co-Management Workload Test
```powershell
# In Endpoint Manager, create compliance policy
# Set requirement: Password required

# On CLIENT01, force Intune sync
Get-ScheduledTask | Where-Object {$_.TaskName -like "*PushLaunch*"} | Start-ScheduledTask

# Wait 10 minutes, then check
Get-WmiObject -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration

# Check Endpoint Manager for compliance status
```

**Expected Result**: Intune compliance policy applies, device reports compliance status to cloud.

---

## Success Criteria

- [ ] Azure AD Connect synchronizes users every 30 minutes automatically
- [ ] All lab users from on-prem AD appear in Azure AD portal
- [ ] CLIENT01 shows as "Hybrid Azure AD joined" in both `dsregcmd /status` and Azure portal
- [ ] Cloud Management Gateway status is "Ready" in ConfigMgr console
- [ ] CMG resources deployed in Azure resource group and visible in portal
- [ ] At least one device (CLIENT01) visible in Microsoft Endpoint Manager admin center
- [ ] Tenant attach remote actions work (sync, restart) from Endpoint Manager portal
- [ ] Co-management enabled with CLIENT01 showing "Co-managed: Yes" in Endpoint Manager
- [ ] At least one Intune workload (e.g., Compliance Policies) successfully managed
- [ ] Intune policy successfully deploys to co-managed device and evaluates correctly
- [ ] Can perform all testing scenarios without errors

---

## Cost Management & Optimization

### Monthly Cost Estimate
- **Azure AD Free Tier**: $0 (up to 50,000 objects)
- **Intune Trial**: $0 for 30 days, then ~$6-8/user/month
- **CMG (B2s VM)**: ~$15-20/month (VM + storage + minimal data transfer)
- **Azure AD Connect**: $0 (free tool)
- **Total Estimated**: $0 first month (trials), then $20-50/month

### Cost Optimization Tips
1. **Use Microsoft 365 Developer Program**: Free renewable E5 tenant includes Intune
2. **Stop CMG when not testing**: Deallocate VM to save ~70% of CMG costs
3. **Use Azure credits**: Visual Studio subscription includes $50-150/month credits
4. **Clean up CMG logs**: Delete old storage blobs to reduce storage costs
5. **Set Azure budget alerts**: Get notified before costs exceed expectations
6. **Tear down and recreate**: Every 30 days to reset trials if learning only

### Stopping CMG to Save Costs
```powershell
# In ConfigMgr console
# Administration → Cloud Services → Cloud Management Gateway
# Right-click CMG → Stop

# Or in Azure Portal
# Find Cloud Service or VM Scale Set → Stop/Deallocate
```

---

## Next Steps

After completing this phase:

1. **Proceed to Phase 4 (PXE & OSD)** with enhanced understanding:
   - Task sequences can now provision co-managed devices
   - Autopilot can be integrated into deployment workflows
   - CMG allows deployments to internet-based devices

2. **Experiment with advanced scenarios**:
   - Conditional access policies
   - Endpoint analytics insights
   - Intune app deployment
   - Windows Update for Business policies
   - Attack surface reduction rules via Intune

3. **Document your cloud integration**:
   - Azure tenant details
   - App registration IDs
   - Co-management workload decisions
   - Troubleshooting steps specific to your lab

---

## Notes & Observations

**Date**: _____  
**Completed By**: _____

### Azure Tenant Information
- Tenant ID: _____________________________
- Tenant Name: _____________________________
- Subscription ID: _____________________________
- ConfigMgr Server App ID: _____________________________
- ConfigMgr Client App ID: _____________________________

### Observations
- _____________________________________________________________________
- _____________________________________________________________________
- _____________________________________________________________________

### Issues Encountered
- _____________________________________________________________________
- _____________________________________________________________________
- _____________________________________________________________________

### Lessons Learned
- _____________________________________________________________________
- _____________________________________________________________________
- _____________________________________________________________________

---

## Sign-Off

- [ ] All main tasks completed successfully
- [ ] Testing procedures completed and documented
- [ ] Success criteria met
- [ ] Ready to proceed to Phase 4 or continue cloud exploration

**Completed By**: ___________________  
**Date**: ___________________  
**Signature**: ___________________

---

## References & Resources

### Official Microsoft Documentation
- [Azure AD Connect Installation](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-install-roadmap)
- [Plan Your Hybrid Azure AD Join](https://learn.microsoft.com/en-us/entra/identity/devices/hybrid-join-plan)
- [Plan for Cloud Management Gateway](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/manage/cmg/plan-cloud-management-gateway)
- [Enable Tenant Attach](https://learn.microsoft.com/en-us/intune/configmgr/tenant-attach/device-sync-actions)
- [Co-Management for Windows Devices](https://learn.microsoft.com/en-us/intune/configmgr/comanage/overview)
- [Tutorial: Enable Co-Management](https://learn.microsoft.com/en-us/intune/configmgr/comanage/tutorial-co-manage-clients)

### Community Guides
- [Prajwal Desai - Tenant Attach Guide](https://www.prajwaldesai.com/enable-tenant-attach-in-configmgr-sccm/)
- [Anoop Nair - SCCM CMG Setup](https://www.anoopcnair.com/sccm-cmg-guide-step-step-azure-cloud-services/)
- [Petri - Hybrid Azure AD Join Guide](https://petri.com/how-to-automatically-hybrid-azure-ad-join-and-intune-enroll-pcs/)

### Troubleshooting Resources
- [Azure AD Connect Troubleshooting](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/tshoot-connect-connectivity)
- [Hybrid Join Troubleshooting](https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-hybrid-join-windows-current)
- [CMG Troubleshooting](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/manage/cmg/monitor-clients-cloud-management-gateway)
- [Co-Management Troubleshooting](https://learn.microsoft.com/en-us/intune/configmgr/comanage/how-to-monitor)
