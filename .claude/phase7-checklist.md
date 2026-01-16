# Phase 7: Optional - Containerized Tooling for Non-Nix Users

**Status**: ⚪ Optional  
**Start Date**: _____  
**Completion Date**: _____

## Overview

Provide a Docker/Podman alternative to Nix for users who cannot or prefer not to install Nix. This lowers the barrier to entry while maintaining reproducibility through containerization.

## Goals

- [ ] Provide Docker/Podman alternative to Nix
- [ ] Lower barrier to entry for users unfamiliar with Nix
- [ ] Maintain reproducibility through containerization
- [ ] Support Windows and macOS users who can't/won't install Nix

---

## Prerequisites

- ✅ Phase 1-4 completed and tested
- [ ] Understanding of Docker/Podman
- [ ] Docker or Podman installed for testing
- [ ] VirtualBox in container feasibility assessment

---

## Important Considerations

### VirtualBox in Containers - CRITICAL ASSESSMENT

⚠️ **WARNING**: Running VirtualBox inside containers is complex and often impractical.

#### Technical Challenges:
- [ ] VirtualBox requires kernel module access (`/dev/vboxdrv`)
- [ ] Nested virtualization has significant overhead
- [ ] Host VirtualBox drivers must match container VirtualBox version
- [ ] Privileged containers required (security concern)
- [ ] Volume mounts for VM storage are complex
- [ ] Network configuration becomes complicated

#### Alternative Approaches:
1. **Use KVM/QEMU instead of VirtualBox** (Linux hosts only)
2. **Use cloud-based infrastructure** (Terraform + AWS/Azure)
3. **Provide pre-built VM images** for manual import
4. **Document manual installation** for non-Nix users

**Recommendation**: Evaluate if this phase is truly needed before proceeding.

---

## Main Tasks

### 1. Feasibility Assessment

- [ ] Research VirtualBox in Docker/Podman
  - [ ] Check if technically possible
  - [ ] Evaluate performance implications
  - [ ] Research security concerns
- [ ] Test basic proof-of-concept
  - [ ] Create minimal container with VirtualBox
  - [ ] Attempt to load kernel modules
  - [ ] Test VM creation
- [ ] **Decision Point**: Continue or pivot to alternatives
  - [ ] If feasible: Continue with Docker/VirtualBox approach
  - [ ] If not feasible: Pivot to KVM/QEMU or cloud approach
  - [ ] If too complex: Document manual setup for non-Nix users

### 2. Dockerfile Development (if proceeding)

- [ ] Choose base image
  - [ ] Ubuntu 22.04 LTS (recommended for stability)
  - [ ] Fedora (if targeting newer packages)
  - [ ] Debian (minimal, stable)
- [ ] Create `container/Dockerfile`
  - [ ] Install base dependencies
  - [ ] Install Vagrant
  - [ ] Attempt VirtualBox installation
  - [ ] Install PowerShell Core
  - [ ] Install WinRM tools
  - [ ] Install Python
  - [ ] Copy project scripts
- [ ] Handle VirtualBox kernel module
  - [ ] Bind mount `/dev/vboxdrv` from host
  - [ ] Match VirtualBox versions (host and container)
  - [ ] Test privileged container mode
- [ ] Configure entrypoint
  - [ ] Start required services
  - [ ] Set up environment
  - [ ] Drop to shell or run command

### 3. Docker Compose Configuration

- [ ] Create `container/docker-compose.yml`
  - [ ] Define service
  - [ ] Configure volumes
    - [ ] Project directory
    - [ ] VM storage location
    - [ ] VirtualBox config directory
  - [ ] Configure devices
    - [ ] `/dev/vboxdrv`
    - [ ] `/dev/vboxnetctl`
  - [ ] Configure privileged mode
  - [ ] Configure network mode (host mode likely needed)
- [ ] Handle different host operating systems
  - [ ] Linux: Direct VirtualBox access
  - [ ] macOS: Docker Desktop limitations
  - [ ] Windows: Docker Desktop + WSL2 considerations

### 4. Alternative: KVM/QEMU Approach (if VirtualBox doesn't work)

- [ ] Research Vagrant with libvirt provider
  - [ ] Install libvirt in container
  - [ ] Configure QEMU
  - [ ] Test VM creation
- [ ] Adapt Vagrantfile for libvirt
  - [ ] Change provider to `libvirt`
  - [ ] Adjust network configuration
  - [ ] Test compatibility with Windows boxes
- [ ] Document differences from VirtualBox approach
  - [ ] Performance characteristics
  - [ ] Feature parity
  - [ ] Known limitations

### 5. Alternative: Cloud-Based Infrastructure

- [ ] Create Terraform configurations
  - [ ] AWS EC2 or Azure VMs
  - [ ] Nested virtualization capable instances
  - [ ] Network configuration (VPC, security groups)
- [ ] Automate cloud deployment
  - [ ] Provision Windows Server VMs
  - [ ] Configure networking
  - [ ] Run automation scripts
- [ ] Document cost implications
  - [ ] Hourly/monthly costs
  - [ ] Resource sizing
  - [ ] Shutdown/startup procedures
- [ ] Create cleanup scripts
  - [ ] Destroy infrastructure when done
  - [ ] Prevent accidental charges

### 6. VS Code Dev Container Integration

- [ ] Create `.devcontainer/devcontainer.json`
  - [ ] Base on created Dockerfile
  - [ ] Configure VS Code extensions
    - [ ] PowerShell
    - [ ] Vagrant
    - [ ] Remote SSH (for VM access)
  - [ ] Configure port forwarding
  - [ ] Configure volume mounts
- [ ] Test in VS Code
  - [ ] Open in container
  - [ ] Verify tools available
  - [ ] Test workflow

### 7. GitHub Codespaces Compatibility (optional)

- [ ] Evaluate GitHub Codespaces for this use case
  - [ ] Codespaces don't support nested virtualization
  - [ ] **Likely not feasible** for VirtualBox approach
  - [ ] Could work for cloud-based approach (Terraform)
- [ ] Document limitations
- [ ] Provide alternative setup for Codespaces users

### 8. Container Image Publishing

- [ ] Build container image
  - [ ] `docker build -t homelab-sccm:latest .`
  - [ ] Test locally
  - [ ] Optimize image size
- [ ] Choose registry
  - [ ] Docker Hub (public)
  - [ ] GitHub Container Registry (GHCR)
  - [ ] Private registry
- [ ] Set up automated builds
  - [ ] GitHub Actions workflow
  - [ ] Build on commit/tag
  - [ ] Push to registry
- [ ] Document pulling and running
  - [ ] `docker pull <user>/homelab-sccm:latest`
  - [ ] `docker run` with appropriate flags

### 9. Documentation for Container Approach

- [ ] Create `docs/container-support.md`
  - [ ] Prerequisites (Docker/Podman)
  - [ ] Container usage instructions
  - [ ] Volume mount explanations
  - [ ] Known limitations
  - [ ] Troubleshooting
- [ ] Create `docs/non-nix-setup.md`
  - [ ] Alternative methods to Nix
  - [ ] Manual installation steps
  - [ ] Container approach
  - [ ] Cloud approach (if implemented)
- [ ] Update main README with container option
  - [ ] Quick start with Docker
  - [ ] Link to detailed docs

### 10. Manual Installation Documentation (Alternative)

If containerization proves too complex:

- [ ] Create step-by-step manual installation guide
  - [ ] Install Vagrant on host system
  - [ ] Install VirtualBox on host system
  - [ ] Install PowerShell Core on host system
  - [ ] Clone repository
  - [ ] Run setup scripts
- [ ] Provide OS-specific guides
  - [ ] Windows 10/11
  - [ ] macOS (without Nix)
  - [ ] Ubuntu/Debian
  - [ ] Fedora
- [ ] Accept that Nix is recommended but not required

---

## Sub-tasks & Considerations

### Nested Virtualization Hardware Requirements

- [ ] CPU must support nested virtualization
  - [ ] Intel: VT-x with EPT
  - [ ] AMD: AMD-V with RVI
- [ ] Enable nested virtualization on host
  - [ ] Linux KVM: `modprobe -r kvm_intel && modprobe kvm_intel nested=1`
  - [ ] Check: `cat /sys/module/kvm_intel/parameters/nested`
- [ ] Performance overhead: 20-50% typical

### Docker Desktop Licensing

- [ ] Docker Desktop license changed in 2021
  - [ ] Free for personal use, education, small businesses
  - [ ] Requires license for larger companies
  - [ ] Podman is open-source alternative
- [ ] Document licensing considerations
- [ ] Recommend Podman for commercial users

### Rootless Containers

- [ ] Test with rootless Podman
  - [ ] Better security posture
  - [ ] More complex setup
  - [ ] Device access limitations
- [ ] Document rootless vs. rootful trade-offs

### Image Size Optimization

- [ ] Use multi-stage builds
- [ ] Remove unnecessary packages
- [ ] Clean up package manager cache
- [ ] Target <2GB final image (if possible)
- [ ] Consider slim base images

### Security Considerations

- [ ] Privileged containers are security risk
- [ ] Document security implications
- [ ] Recommend only for development/learning
- [ ] Never use in production environment
- [ ] Limit container capabilities where possible

---

## Deliverables

- [ ] `container/Dockerfile` - Container image definition
- [ ] `container/docker-compose.yml` - Orchestration configuration
- [ ] `container/entrypoint.sh` - Container entry point script
- [ ] `docs/container-support.md` - Container usage guide
- [ ] `docs/non-nix-setup.md` - Alternative setup methods
- [ ] `.devcontainer/devcontainer.json` - VS Code dev container config
- [ ] Published container image (Docker Hub or GHCR)
- [ ] GitHub Actions workflow for automated builds (optional)

---

## Potential Issues & Solutions

### Issue: VirtualBox in containers is not reliable

**Symptoms**: Kernel module conflicts, VM failures

**Solutions**:
- Pivot to KVM/QEMU with libvirt provider
- Use cloud-based infrastructure (Terraform)
- Document manual installation without containers
- Accept that Nix is the primary supported method

### Issue: Docker Desktop limitations on macOS/Windows

**Symptoms**: Can't access host VirtualBox, nested virtualization not supported

**Solutions**:
- Containers are primarily for Linux hosts
- macOS/Windows users should use Nix directly
- Document limitations clearly
- Don't over-promise container support

### Issue: Large container image size (multiple GB)

**Symptoms**: Slow pulls, storage concerns

**Solutions**:
- Optimize Dockerfile with multi-stage builds
- Remove unnecessary packages
- Use slim base images
- Accept that tooling has inherent size
- Provide image size in documentation (set expectations)

### Issue: USB passthrough and advanced features don't work

**Symptoms**: Can't use USB devices, limited functionality

**Solutions**:
- Document limitations
- USB passthrough unlikely to work in containers
- For advanced features, recommend native installation
- Container approach is for basic lab functionality only

### Issue: KVM/QEMU performance worse than VirtualBox

**Symptoms**: Slow VM performance

**Solutions**:
- Document expected performance
- KVM is actually often faster than VirtualBox
- Ensure KVM acceleration enabled
- Use virtio drivers in Windows guests for best performance

---

## Testing Checklist

If pursuing VirtualBox in container approach:

```bash
# Build container
cd container
docker build -t homelab-sccm:latest .

# Run container (privileged, with devices)
docker run -it --privileged \
  --device=/dev/vboxdrv \
  --device=/dev/vboxnetctl \
  -v $(pwd)/..:/workspace \
  -v ~/VirtualBox\ VMs:/vms \
  homelab-sccm:latest

# Inside container, verify tools
vagrant --version
VBoxManage --version
pwsh --version

# Test VirtualBox
VBoxManage list vms

# Exit container
exit
```

If pursuing KVM/QEMU approach:

```bash
# Build container with libvirt
docker build -f container/Dockerfile.libvirt -t homelab-sccm-kvm:latest .

# Run with KVM access
docker run -it --privileged \
  --device=/dev/kvm \
  -v $(pwd)/..:/workspace \
  homelab-sccm-kvm:latest

# Inside container, verify
vagrant --version
virsh version
```

---

## Success Criteria

Phase 7 is complete when:

**If VirtualBox approach successful**:
- ✅ Dockerfile builds successfully
- ✅ Container can access VirtualBox kernel modules
- ✅ VMs can be created from within container
- ✅ docker-compose.yml orchestrates properly
- ✅ Documentation covers container usage
- ✅ Image published to registry
- ✅ Known limitations documented

**If alternative approach chosen**:
- ✅ Alternative documented (KVM, cloud, manual)
- ✅ Working proof-of-concept demonstrated
- ✅ Documentation complete
- ✅ Limitations and trade-offs explained
- ✅ Cost implications documented (if cloud approach)

**If phase deemed not feasible**:
- ✅ Technical assessment documented
- ✅ Reasons for not proceeding explained
- ✅ Manual installation guide provided as alternative
- ✅ Nix remains recommended approach

---

## Recommendations

### Should You Pursue Phase 7?

**Consider NOT pursuing if**:
- Nix works well on your target platforms (Phases 1-6)
- Target users can install Nix (it's not that hard)
- Technical complexity of containers outweighs benefits
- Limited development resources

**Consider pursuing if**:
- Target audience strongly prefers Docker/containers
- Corporate environments restrict Nix installation
- Want to support truly diverse platforms
- Have resources to maintain container images
- Can accept KVM/QEMU as VirtualBox alternative

**Pragmatic Recommendation**:
Phase 7 is optional for good reason. If Phases 1-6 work well, the value of Phase 7 may not justify the complexity. Many successful projects choose a primary supported method (Nix) and provide manual installation docs as an alternative.

---

## Next Steps

Once Phase 7 is complete (or skipped):
- Project is feature-complete
- Focus shifts to maintenance and improvements
- Consider additional enhancements:
  - CI/CD for testing
  - Additional SCCM scenarios
  - Performance optimizations
  - Community contributions

---

## Notes

<!-- Add any phase-specific notes, issues, or learnings here -->

**Date**: _____  
**Notes**: _____

**Container Approach Decision**:
- ☐ Pursuing VirtualBox in container
- ☐ Pursuing KVM/QEMU alternative
- ☐ Pursuing cloud-based alternative
- ☐ Providing manual installation guide only
- ☐ Skipping Phase 7 entirely

---

**Phase 7 Completed**: ☐  
**Completed By**: _____  
**Sign-off Date**: _____
