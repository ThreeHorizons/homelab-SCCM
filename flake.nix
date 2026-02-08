{
  # ===========================================================================
  # Homelab SCCM - NixVirt-based Configuration Manager Lab Environment
  # ===========================================================================
  #
  # This flake provides:
  # 1. NixOS module for declarative VM infrastructure (networks, storage, VMs)
  # 2. Development shell with libvirt tools and PowerShell automation
  # 3. Cross-platform support (devShell works on Linux/macOS for script editing)
  #
  # Architecture: NixVirt + libvirt/QEMU (migrated from Vagrant + VirtualBox)
  # See: docs/phase1-revision-nixvirt-architecture.md
  # ===========================================================================

  description = "Homelab SCCM - NixOS-based Configuration Manager lab environment (NixVirt + libvirt)";

  # ===========================================================================
  # INPUTS (Dependencies)
  # ===========================================================================
  inputs = {
    # nixpkgs: Main Nix package repository
    # Using nixos-unstable for latest stable versions of tools
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # NixVirt: Declarative libvirt configuration
    # FlakeHub provides stable releases with proper versioning
    # URL format: https://flakehub.com/f/<org>/<repo>/*.tar.gz
    # The * wildcard resolves to the latest release
    #
    # Why FlakeHub instead of GitHub?
    # - Stable releases (GitHub master branch can be broken)
    # - Proper semantic versioning
    # - Maintained by NixVirt project as recommended approach
    NixVirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";

      # inputs.nixpkgs.follows: Use our nixpkgs instead of NixVirt's
      # This ensures all packages come from the same nixpkgs version
      # Prevents duplicate package builds and version conflicts
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ===========================================================================
  # OUTPUTS (What this flake provides)
  # ===========================================================================
  outputs = { self, nixpkgs, NixVirt }:
    let
      # Supported systems for the devShell
      # NixOS module only works on Linux, but devShell can work elsewhere
      supportedSystems = [
        "x86_64-linux"   # 64-bit Linux (NixOS, Ubuntu, Fedora, etc.)
        "aarch64-linux"  # ARM64 Linux (Raspberry Pi, etc.)
        "x86_64-darwin"  # Intel macOS (for script editing only)
        "aarch64-darwin" # Apple Silicon macOS (for script editing only)
      ];

      # Helper: Generate attributes for each supported system
      # Like map() but for attrsets
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Helper: Import nixpkgs for a specific system
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;  # Allow unfree packages (may be needed for some tools)
      };
    in
    {
      # =======================================================================
      # NIXOS MODULE (Linux only)
      # =======================================================================
      # Provides declarative configuration for libvirt VMs
      # Import this module into your NixOS configuration to deploy the lab
      #
      # Usage in /etc/nixos/configuration.nix (or flake.nix):
      #   imports = [ homelab-sccm.nixosModules.default ];
      #
      # Then run: sudo nixos-rebuild switch
      # This will create networks, storage pools, volumes, and VM definitions
      # =======================================================================
      nixosModules.default = { config, lib, pkgs, ... }: {
        # Import NixVirt's NixOS module
        # This provides virtualisation.libvirt.* options
        imports = [ NixVirt.nixosModules.default ];

        # Enable NixVirt declarative management
        # This creates a nixvirt.service systemd unit that runs after libvirtd
        # and idempotently applies all network/pool/domain definitions below.
        # Note: This is separate from virtualisation.libvirtd.enable (the daemon).
        # libvirtd must also be enabled (done in your system config's devops module).
        virtualisation.libvirt.enable = true;

        # Enable swtpm (Software TPM emulator)
        # Required for Windows 11 (TPM 2.0 requirement)
        virtualisation.libvirt.swtpm.enable = true;

        # Configure libvirt connection and resources
        # qemu:///system: System-level libvirt (shared across users)
        # Alternative: qemu:///session (user-level, less common)
        virtualisation.libvirt.connections."qemu:///system" = {
          # Networks: Import our network definitions
          # Returns an attrset: { lab-net = {...}; default = {...}; }
          networks = import ./nixvirt/networks.nix { inherit NixVirt; };

          # Storage pools: Import our pool and volume definitions
          # Returns an attrset: { homelab = {...}; }
          pools = import ./nixvirt/pools.nix { inherit NixVirt; };

          # Domains (VMs): Import our VM definitions
          # Returns an attrset: { dc01 = {...}; sccm01 = {...}; ... }
          domains = import ./nixvirt/domains.nix { inherit NixVirt; };
        };
      };

      # =======================================================================
      # DEVELOPMENT SHELLS (Cross-platform)
      # =======================================================================
      # Provides tools for managing VMs and running PowerShell automation
      # Run: nix develop
      # =======================================================================
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          # Detect if we're on Linux (where libvirt actually works)
          # On macOS/others, we only provide script editing tools
          isLinux = pkgs.stdenv.isLinux;
        in
        {
          default = pkgs.mkShell {
            name = "homelab-sccm-devshell";

            # =================================================================
            # BUILD INPUTS (Available packages)
            # =================================================================
            buildInputs = with pkgs; [
              # Version control
              git

              # Windows automation and management
              powershell       # PowerShell Core 7.x - cross-platform

              # Scripting and automation
              python3
              python3Packages.pip

              # Networking and debugging tools
              curl
              wget
              netcat
              freerdp          # Remote desktop client (xfreerdp)

              # Text processing (useful for log analysis)
              jq               # JSON processor
              yq-go            # YAML processor
            ] ++ (if isLinux then [
              # Linux-only: libvirt and virtualization tools
              # These don't work on macOS/Windows
              libvirt          # Provides virsh command-line tool
              virt-manager     # GUI for managing VMs
              qemu             # QEMU emulator (provides qemu-img)
              swtpm            # Software TPM emulator (for Windows 11)
            ] else [
              # Non-Linux: Just provide script editing tools
              # VM management won't work, but you can edit PowerShell scripts
            ]);

            # =================================================================
            # SHELL HOOK (Runs when entering devShell)
            # =================================================================
            shellHook = if isLinux then ''
              # ===============================================================
              # LINUX: Full libvirt environment
              # ===============================================================
              echo "=============================================================="
              echo "  Homelab SCCM Development Environment (NixVirt + libvirt)"
              echo "=============================================================="
              echo ""
              echo "Available tools:"
              echo "  - libvirt: $(virsh --version 2>/dev/null || echo 'not found')"
              echo "  - virt-manager: $(virt-manager --version 2>/dev/null || echo 'not found')"
              echo "  - PowerShell: $(pwsh --version 2>/dev/null || echo 'not found')"
              echo "  - Python: $(python --version 2>/dev/null || echo 'not found')"
              echo ""

              # Check libvirt daemon status
              if systemctl is-active --quiet libvirtd 2>/dev/null; then
                echo "✅ libvirtd is running"
              else
                echo "❌ libvirtd is not running!"
                echo "   Start it: sudo systemctl start libvirtd"
                echo ""
              fi

              # Check if user is in libvirt group
              if groups | grep -q libvirt; then
                echo "✅ User is in libvirt group"
              else
                echo "⚠️  WARNING: You are not in the 'libvirt' group!"
                echo "   Run: sudo usermod -aG libvirt $USER"
                echo "   Then logout and login again."
                echo ""
              fi

              # Check for VMs (if libvirt is accessible)
              if command -v virsh &> /dev/null && virsh -c qemu:///system list --all &> /dev/null; then
                VM_COUNT=$(virsh -c qemu:///system list --all --name | grep -v '^$' | wc -l)
                if [ "$VM_COUNT" -gt 0 ]; then
                  echo ""
                  echo "Virtual machines ($VM_COUNT):"
                  virsh -c qemu:///system list --all
                else
                  echo ""
                  echo "ℹ️  No VMs defined yet."
                  echo "   Import the NixOS module to create VMs."
                  echo "   See: docs/phase1-revision-implementation-steps.md"
                fi
              fi

              echo ""
              echo "Quick commands:"
              echo "  - 'virsh -c qemu:///system list --all' - List all VMs"
              echo "  - 'virsh start DC01' - Start a VM"
              echo "  - 'virt-manager' - Open GUI manager"
              echo "  - 'virsh net-list --all' - List networks"
              echo "  - 'virsh pool-list --all' - List storage pools"
              echo "  - 'pwsh' - Enter PowerShell for automation scripts"
              echo ""
              echo "Next steps:"
              echo "  1. Ensure prerequisites are met (see checklist)"
              echo "  2. Import NixOS module into your configuration"
              echo "  3. Run: sudo nixos-rebuild switch"
              echo "  4. Download Windows ISOs to /var/lib/libvirt/iso/"
              echo "  5. Start VMs and install Windows via virt-manager"
              echo ""
              echo "Documentation: docs/phase1-revision-nixvirt-architecture.md"
              echo "=============================================================="
              echo ""

              # Add scripts directory to PATH for easy execution
              export PATH="$PWD/scripts:$PATH"
            '' else ''
              # ===============================================================
              # NON-LINUX: Script editing only
              # ===============================================================
              echo "=============================================================="
              echo "  Homelab SCCM Development Environment (Script Editing Mode)"
              echo "=============================================================="
              echo ""
              echo "⚠️  Note: You are on $(uname -s)"
              echo "   libvirt VM management is only available on Linux."
              echo "   This devShell provides PowerShell and scripting tools only."
              echo ""
              echo "Available tools:"
              echo "  - PowerShell: $(pwsh --version 2>/dev/null || echo 'not found')"
              echo "  - Python: $(python --version 2>/dev/null || echo 'not found')"
              echo "  - Git: $(git --version 2>/dev/null || echo 'not found')"
              echo ""
              echo "You can:"
              echo "  - Edit PowerShell automation scripts"
              echo "  - Review and update documentation"
              echo "  - Test PowerShell modules locally"
              echo ""
              echo "For full VM management, use this flake on NixOS or Linux."
              echo "=============================================================="
              echo ""

              export PATH="$PWD/scripts:$PATH"
            '';
          };
        }
      );

      # =======================================================================
      # METADATA (Optional, but helpful)
      # =======================================================================
      # Provides information about this flake
      # Visible via: nix flake show
      # =======================================================================

      # Formatter for 'nix fmt' command (optional)
      # formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}

# =============================================================================
# TECHNICAL NOTES
# =============================================================================
#
# 1. FLAKE INPUTS:
#    - inputs.*.url: Where to fetch the dependency
#    - inputs.*.follows: Use another input's version (avoid duplicates)
#    - FlakeHub URLs: https://flakehub.com/f/<org>/<repo>/<version>.tar.gz
#    - GitHub URLs: github:<org>/<repo>/<branch>
#
# 2. NIXOS MODULE SYSTEM:
#    - Modules are functions: { config, lib, pkgs, ... }: { ... }
#    - config: The full system configuration (read/write)
#    - lib: NixOS library functions (attrsets, strings, etc.)
#    - pkgs: Available packages for this system
#    - imports: Other modules to include
#    - Modules are merged recursively (can override each other)
#
# 3. LIBVIRT CONNECTIONS:
#    - qemu:///system: System-level (needs libvirt group, persistent)
#    - qemu:///session: User-level (no special permissions, non-persistent)
#    - For this lab: qemu:///system is better (proper networking, shared)
#
# 4. DEVSHELL CROSS-PLATFORM:
#    - isLinux: Only provide libvirt tools on Linux
#    - macOS/Windows: Just provide PowerShell for script editing
#    - This allows developers on any platform to work on scripts
#    - Actual VM management requires NixOS or Linux
#
# 5. FLAKE OUTPUTS:
#    - nixosModules.default: NixOS module (import into configuration.nix)
#    - devShells.<system>.default: Development environment (nix develop)
#    - packages.<system>.*: Installable packages (not used here)
#    - apps.<system>.*: Runnable applications (not used here)
#
# 6. IMPORTING NIXVIRT CONFIG:
#    - import ./nixvirt/networks.nix { inherit NixVirt; }
#    - Passes NixVirt input to networks.nix as a parameter
#    - networks.nix returns an attrset of network definitions
#    - Same pattern for pools.nix and domains.nix
#
# 7. VALIDATION:
#    - Syntax check: nix flake check
#    - Show structure: nix flake show
#    - Evaluate module: nix eval .#nixosModules.default
#    - Enter devShell: nix develop
#    - Lock inputs: nix flake lock (creates flake.lock)
#
# 8. FLAKE LOCK FILE:
#    - flake.lock: Records exact versions of all inputs
#    - Generated by: nix flake lock or first nix flake command
#    - Ensures reproducibility (same flake.lock = same versions)
#    - Update inputs: nix flake update
#    - Update one input: nix flake lock --update-input NixVirt
#
# 9. NIXOS INTEGRATION:
#    To use this flake in your NixOS configuration:
#
#    Option A: In /etc/nixos/flake.nix:
#      {
#        inputs.homelab-sccm.url = "path:/home/user/projects/homelab-SCCM";
#        outputs = { nixpkgs, homelab-sccm, ... }: {
#          nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
#            modules = [ homelab-sccm.nixosModules.default ./configuration.nix ];
#          };
#        };
#      }
#
#    Option B: In /etc/nixos/configuration.nix (if not using flakes):
#      { config, pkgs, ... }:
#      let
#        homelab-sccm = import /home/user/projects/homelab-SCCM;
#      in {
#        imports = [ homelab-sccm.nixosModules.default ];
#      }
#
# 10. TROUBLESHOOTING:
#     - "input ... does not exist": Run 'nix flake lock' to fetch inputs
#     - "attribute ... missing": Check nixvirt/*.nix files are exporting correctly
#     - "infinite recursion": Check for circular imports in modules
#     - "file ... does not exist": Use string paths, not Nix path literals for runtime files
#
# =============================================================================
