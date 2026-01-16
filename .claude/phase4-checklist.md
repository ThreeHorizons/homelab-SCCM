# Phase 4: PXE Booting & OSD Automation

**Status**: ⚪ Planned  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Enable network-based OS deployment through PXE boot and SCCM OSD task sequences. This phase adds bare-metal deployment capabilities to the lab.

## Goals

- [ ] Enable network-based OS deployment
- [ ] Create SCCM task sequences
- [ ] Test bare-metal deployment scenarios
- [ ] Implement automated OS deployment

---

## Prerequisites

- ✅ Phase 1 completed (Nix environment)
- ✅ Phase 2 completed (VMs running)
- ✅ Phase 3 completed (SCCM fully configured)
- [ ] Phase 3.5 completed (optional - enables cloud-integrated OSD scenarios)
- [ ] Windows 10/11 installation ISO available
- [ ] VirtualBox drivers for WinPE (if needed)

**Note on Cloud Integration**: If Phase 3.5 (Azure Integration) is completed, OSD task sequences can be enhanced to:
- Automatically hybrid Azure AD join deployed devices
- Automatically enroll devices in co-management during OSD
- Apply Intune policies immediately after deployment
- Register devices for Windows Autopilot post-deployment

---

## Main Tasks

### 1. Configure SCCM Distribution Point for PXE

- [ ] Enable PXE responder on Distribution Point (SCCM01)
  - [ ] Open SCCM Console
  - [ ] Navigate to Distribution Points
  - [ ] Properties → PXE tab
  - [ ] Enable "Enable PXE support for clients"
  - [ ] Enable "Allow this distribution point to respond to incoming PXE requests"
- [ ] Configure PXE settings
  - [ ] Respond to: "Known and unknown computers" (for testing)
  - [ ] PXE password (optional, set if desired)
  - [ ] Configure PXE response delay (0 seconds for lab)
  - [ ] Enable unknown computer support
- [ ] Configure boot image distribution
  - [ ] Enable boot images on the DP
  - [ ] Distribute to SCCM01 DP
- [ ] Verify PXE service is running
  - [ ] Check WDS service (if applicable)
  - [ ] Check SCCM PXE responder service
  - [ ] Verify firewall rules (UDP 4011, TCP 8005)

### 2. Alternative: Standalone PXE Server (Optional)

**Note**: Only pursue if SCCM PXE responder has issues

- [ ] Install dnsmasq on separate VM or SCCM01
  - [ ] Configure DHCP proxy mode
  - [ ] Point to TFTP server
- [ ] Configure TFTP server
  - [ ] Set up TFTP root directory
  - [ ] Copy boot files
- [ ] Create iPXE boot configuration
- [ ] Test with iPXE chainloading

### 3. Import and Configure Boot Images

- [ ] Import Windows ADK boot images to SCCM
  - [ ] Navigate to Software Library → Operating Systems → Boot Images
  - [ ] Default boot images should already exist
  - [ ] Boot image (x64): Default
  - [ ] Boot image (x86): Default (if needed)
- [ ] Customize boot images
  - [ ] Add VirtualBox network drivers (if needed)
    - [ ] Intel PRO/1000 MT Desktop (82540EM) driver
    - [ ] Usually included by default
  - [ ] Add PowerShell support to WinPE
    - [ ] Optional Components → Windows PowerShell
  - [ ] Add scripting support
    - [ ] Optional Components → Microsoft .NET (WinPE-NetFx)
  - [ ] Enable command prompt support (for debugging)
    - [ ] Customization tab → Enable command support
    - [ ] Press F8 during task sequence for debugging
- [ ] Configure boot image properties
  - [ ] Data Source tab: Deploy this boot image from PXE-enabled DP
  - [ ] Data Access tab: Copy to package share
  - [ ] Distribution Settings: Priority Normal
- [ ] Distribute boot images to DP
  - [ ] Right-click boot image → Distribute Content
  - [ ] Select SCCM01 DP
  - [ ] Monitor distribution status
- [ ] Update distribution points after changes
  - [ ] Right-click boot image → Update Distribution Points

### 4. Import OS Installation Media

- [ ] Create Operating System Images
  - [ ] Mount Windows 10/11 ISO
  - [ ] Navigate to Software Library → Operating Systems → Operating System Images
  - [ ] Add Operating System Image
  - [ ] Path: `\\SCCM01\Sources$\OSD\Windows10\` (or similar)
  - [ ] Import install.wim from ISO
- [ ] Alternatively: Create Operating System Installer
  - [ ] Add Operating System Installer
  - [ ] Point to mounted ISO or extracted files
  - [ ] Includes full Windows setup files
- [ ] Distribute OS image to DP
  - [ ] Right-click → Distribute Content
  - [ ] Select SCCM01 DP
  - [ ] Wait for distribution to complete

### 5. Create Driver Packages (Optional)

- [ ] Import VirtualBox drivers
  - [ ] Intel PRO/1000 network adapter
  - [ ] VirtualBox graphics adapter
  - [ ] VirtualBox storage controller
  - [ ] Usually Windows includes these by default
- [ ] Create driver package
  - [ ] Navigate to Software Library → Drivers
  - [ ] Import drivers
  - [ ] Create driver package
- [ ] Distribute driver package to DP
- [ ] Note: VirtualBox VMs typically don't need extra drivers

### 6. Create OS Deployment Task Sequence

- [ ] Create new task sequence
  - [ ] Navigate to Software Library → Operating Systems → Task Sequences
  - [ ] Right-click → Create Task Sequence
  - [ ] Select "Install an existing image package"
- [ ] Configure task sequence wizard
  - [ ] Task sequence name: "Deploy Windows 10 x64"
  - [ ] Boot image: Select x64 boot image
  - [ ] OS image: Select imported Windows 10/11 image
  - [ ] Product key: Leave blank for evaluation
  - [ ] Administrator password: Set lab password
- [ ] Customize task sequence steps
  - [ ] Partition Disk: UEFI or BIOS (set based on VirtualBox config)
  - [ ] Apply Operating System
  - [ ] Apply Windows Settings
    - [ ] Computer name: Use variable or prompt
    - [ ] Administrator password
    - [ ] Time zone
  - [ ] Apply Network Settings
    - [ ] Join domain: lab.local
    - [ ] Domain credentials: LAB\SCCM_JoinDomain
    - [ ] Target OU: Computers/Workstations
  - [ ] Setup Windows and ConfigMgr
    - [ ] Install SCCM client
    - [ ] Site code: PS1

**Cloud-Enhanced OSD (if Phase 3.5 completed)**:
- [ ] Add hybrid Azure AD join to task sequence
  - [ ] After domain join, add "Run PowerShell Script" step
  - [ ] Script verifies hybrid Azure AD join configured
  - [ ] Or simply wait for GPO to trigger automatic join
- [ ] Enable automatic co-management enrollment
  - [ ] SCCM client installation automatically triggers Intune enrollment
  - [ ] Verify co-management settings allow auto-enrollment
- [ ] Optional: Add Autopilot registration step
  - [ ] After Windows setup, register hardware hash with Intune
  - [ ] Use Get-WindowsAutopilotInfo.ps1 script

- [ ] Add additional task sequence steps (optional)
  - [ ] Install Applications
  - [ ] Install Software Updates
  - [ ] Run PowerShell scripts
  - [ ] Custom configuration steps
- [ ] Configure task sequence options
  - [ ] Maximum runtime: 120 minutes
  - [ ] Enable notifications
  - [ ] Continue on error (for specific steps if desired)

### 7. Create SCCM Collections for OSD

- [ ] Create "All Unknown Computers" collection (built-in)
  - [ ] Verify it exists in Device Collections
- [ ] Create "OSD Deployment" collection
  - [ ] Navigate to Assets and Compliance → Device Collections
  - [ ] Right-click → Create Device Collection
  - [ ] Name: "OSD Deployment"
  - [ ] Limiting collection: All Systems
  - [ ] Add query rule or direct membership
- [ ] Create "New Computers" collection (optional)
  - [ ] For tracking recently deployed systems

### 8. Deploy Task Sequence

- [ ] Deploy task sequence to collection
  - [ ] Right-click task sequence → Deploy
  - [ ] Collection: "All Unknown Computers"
  - [ ] Purpose: Available (for testing) or Required
  - [ ] Make available to: Only media and PXE
- [ ] Configure deployment settings
  - [ ] Schedule: Available ASAP
  - [ ] Deployment options: Download content locally when needed
  - [ ] Allow task sequence to run for clients on Internet: No
- [ ] Configure user experience
  - [ ] Show progress
  - [ ] Allow users to run independently of assignments: Yes (for available)
- [ ] Monitor deployment status
  - [ ] Monitoring → Deployments
  - [ ] Check for errors

### 9. Test PXE Boot Workflow

- [ ] Create new VirtualBox VM for testing
  - [ ] Name: TESTPXE01
  - [ ] Type: Windows 10/11
  - [ ] Memory: 4GB (for testing)
  - [ ] Create new virtual hard disk: 60GB
  - [ ] Network: Host-Only Adapter (vboxnet0)
  - [ ] Boot order: Network first, then hard disk
- [ ] Configure VM for PXE boot
  - [ ] Settings → System → Boot Order
  - [ ] Enable Network, move to top
  - [ ] Enable EFI (optional, test both BIOS and UEFI)
- [ ] Start VM and test PXE boot
  - [ ] Press F12 for network boot (if needed)
  - [ ] Should receive DHCP address from DC01
  - [ ] Should download boot image from SCCM01
  - [ ] WinPE should load
- [ ] Navigate task sequence wizard
  - [ ] Press Enter or wait for automatic PXE boot
  - [ ] Boot into WinPE environment
  - [ ] Task Sequence Wizard should appear
  - [ ] Select "Deploy Windows 10 x64" task sequence
  - [ ] Provide computer name if prompted
  - [ ] Monitor deployment progress
- [ ] Verify OS deployment
  - [ ] Wait for task sequence to complete (15-30 minutes)
  - [ ] System should reboot into Windows
  - [ ] Verify domain join: `(Get-WmiObject Win32_ComputerSystem).Domain`
  - [ ] Verify SCCM client installed: `Get-Service CcmExec`
  - [ ] Check computer appears in SCCM console

### 10. Create Multiple Test Scenarios

- [ ] Test BIOS boot mode
  - [ ] Create VM without EFI
  - [ ] Verify task sequence handles BIOS partitioning
- [ ] Test UEFI boot mode
  - [ ] Create VM with EFI enabled
  - [ ] Verify task sequence handles UEFI partitioning
- [ ] Test multiple simultaneous deployments
  - [ ] Create 2-3 VMs
  - [ ] PXE boot all simultaneously
  - [ ] Monitor SCCM DP performance
- [ ] Test deployment failures and recovery
  - [ ] Intentionally fail a step
  - [ ] Verify error handling
  - [ ] Test redeployment

---

## Sub-tasks & Considerations

### VirtualBox PXE Boot

- [ ] Research VirtualBox PXE boot capabilities and limitations
- [ ] VirtualBox PXE may be slow with NAT networks
- [ ] Use host-only network for reliable PXE
- [ ] Test with different network adapter types
- [ ] Document any VirtualBox-specific quirks

### BIOS vs. UEFI

- [ ] Test with both BIOS and UEFI boot modes
- [ ] UEFI requires different boot files than BIOS
- [ ] Task sequence partitioning differs (GPT vs MBR)
- [ ] Ensure boot images support both modes

### WinPE Driver Requirements

- [ ] Verify WinPE includes VirtualBox virtual NIC driver
- [ ] Intel PRO/1000 MT Desktop (82540EM) usually included
- [ ] Test network connectivity in WinPE (press F8, run ipconfig)
- [ ] Add drivers to boot image if network fails

### Task Sequence Debugging

- [ ] Enable command prompt support in boot image
- [ ] Press F8 during task sequence execution
- [ ] Review smsts.log in X:\Windows\Temp\SMSTSLog
- [ ] Common log locations:
  - WinPE: `X:\Windows\Temp\SMSTSLog\smsts.log`
  - Full OS: `C:\Windows\CCM\Logs\SMSTSLog\smsts.log`

### DHCP Configuration

- [ ] Verify DHCP options NOT set for 066/067 (conflicts with PXE responder)
- [ ] SCCM PXE responder handles boot file delivery
- [ ] WDS and SCCM PXE responder can conflict (use one or the other)

### PXE Response Settings

- [ ] "Known computers only" vs "All computers"
- [ ] For lab: Allow all computers (easier testing)
- [ ] For production: Known computers only (security)
- [ ] Test unknown computer approval workflow

---

## Deliverables

- [ ] `pxe/README.md` - PXE boot overview and architecture
- [ ] `pxe/dnsmasq.conf` - dnsmasq configuration (if using alternative)
- [ ] `pxe/tftp/` - TFTP root structure (if using alternative)
- [ ] `scripts/pxe-setup.ps1` - PXE/DP configuration automation script
- [ ] `scripts/import-os.ps1` - OS image import automation
- [ ] `scripts/create-tasksequence.ps1` - Task sequence creation automation
- [ ] `docs/pxe-plan.md` - PXE implementation strategy
- [ ] `docs/osd-troubleshooting.md` - Common OSD issues and solutions
- [ ] `docs/task-sequences.md` - Task sequence design and best practices

---

## Potential Issues & Solutions

### Issue: VirtualBox PXE boot slow or unreliable

**Symptoms**: PXE boot times out, no DHCP response

**Solutions**:
- Use host-only network instead of NAT for PXE
- Increase PXE timeout in BIOS settings (VirtualBox)
- Verify DHCP server is responding
- Check network adapter type (Intel PRO/1000 recommended)

### Issue: "No task sequences available" error

**Symptoms**: WinPE loads but no task sequences shown

**Solutions**:
- Check task sequence deployment to correct collection
- Verify "All Unknown Computers" collection includes new MAC
- Check for duplicate MAC addresses in SCCM database
- Ensure deployment is available to "media and PXE"
- Verify task sequence deployment time (must be active)

### Issue: UEFI PXE boot requires different boot files

**Symptoms**: BIOS works but UEFI fails (or vice versa)

**Solutions**:
- Ensure boot image supports target architecture (x64)
- SCCM PXE responder automatically serves correct files
- Verify EFI boot files distributed to DP
- Check UEFI network stack is enabled in VirtualBox

### Issue: WinPE network driver missing

**Symptoms**: IP address not assigned in WinPE

**Solutions**:
- Press F8 in WinPE, run `ipconfig`
- Check Device Manager for network adapter
- Add VirtualBox driver to boot image
- Verify Intel PRO/1000 driver included in boot image

### Issue: Boot image distribution slow

**Symptoms**: Long wait times for content distribution

**Solutions**:
- Boot images can be 300-500MB
- Monitor distribution status in SCCM console
- Check network bandwidth between site server and DP
- Verify DP has adequate disk space

### Issue: Task sequence fails during domain join

**Symptoms**: OS deploys but domain join fails

**Solutions**:
- Verify domain join account credentials (LAB\SCCM_JoinDomain)
- Check account has permission to join computers to domain
- Verify DNS resolution in task sequence
- Check target OU exists and is accessible
- Review smsts.log for detailed error

### Issue: PXE response timeout

**Symptoms**: "PXE-E51: No DHCP or proxyDHCP offers were received"

**Solutions**:
- Verify DHCP server is running on DC01
- Check PXE responder service is running on SCCM01
- Ensure no DHCP options 066/067 configured
- Verify firewall allows UDP 4011 and TCP 8005
- Check VirtualBox promiscuous mode on adapter

---

## Testing Checklist

```bash
# Verify PXE responder running
pwsh -c "Invoke-Command -ComputerName 192.168.56.11 -Credential LAB\Administrator -ScriptBlock { Get-Service SccmPxe }"
# Expected: Running

# Check boot image distribution status
# From SCCM Console → Monitoring → Distribution Status → Content Status
# Expected: Success for boot images

# Check task sequence deployment
# From SCCM Console → Monitoring → Deployments
# Expected: Task sequence deployed to "All Unknown Computers"

# Create test VM
VBoxManage createvm --name TESTPXE01 --ostype Windows10_64 --register
VBoxManage modifyvm TESTPXE01 --memory 4096 --cpus 2
VBoxManage createhd --filename ~/VirtualBox\ VMs/TESTPXE01/TESTPXE01.vdi --size 61440
VBoxManage storagectl TESTPXE01 --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach TESTPXE01 --storagectl "SATA" --port 0 --device 0 --type hdd --medium ~/VirtualBox\ VMs/TESTPXE01/TESTPXE01.vdi
VBoxManage modifyvm TESTPXE01 --nic1 hostonly --hostonlyadapter1 vboxnet0
VBoxManage modifyvm TESTPXE01 --boot1 net --boot2 disk --boot3 none --boot4 none

# Start VM and test PXE boot
VBoxManage startvm TESTPXE01

# Monitor from SCCM logs
pwsh -c "Invoke-Command -ComputerName 192.168.56.11 -Credential LAB\Administrator -ScriptBlock { Get-Content 'C:\Program Files\Microsoft Configuration Manager\Logs\SMSPXE.log' -Tail 50 }"
```

---

## Success Criteria

Phase 4 is complete when:

- ✅ SCCM Distribution Point PXE enabled and functional
- ✅ Boot images distributed and accessible via PXE
- ✅ OS installation media imported to SCCM
- ✅ Task sequence created and deployed
- ✅ Test VM successfully PXE boots
- ✅ WinPE loads and displays task sequence wizard
- ✅ Full OS deployment completes successfully
- ✅ Deployed system domain-joins automatically
- ✅ SCCM client installs and reports to site
- ✅ Can deploy multiple systems simultaneously
- ✅ Both BIOS and UEFI boot modes tested (optional but recommended)

---

## Next Steps

Once Phase 4 is complete, proceed to:
- **Phase 5**: Cross-Platform Support (Linux Distros)
- See `.claude/phase5-checklist.md`

Or continue using the lab for:
- Application deployment testing
- Software update management
- Compliance settings
- Endpoint protection
- Further SCCM feature exploration

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

---

**Phase 4 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
