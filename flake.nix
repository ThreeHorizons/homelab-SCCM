{
  # Flake description - shown when someone runs `nix flake metadata`
  description = "Homelab SCCM - NixOS-based Configuration Manager lab environment";

  # Inputs are dependencies this flake needs
  # Think of this like a package.json or requirements.txt
  inputs = {
    # nixpkgs is the main Nix package repository
    # Using nixos-unstable for latest stable versions of tools
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # Outputs are what this flake provides to users
  # The `{ self, nixpkgs }` parameter receives our inputs defined above
  outputs = { self, nixpkgs }:
    let
      # Define supported systems
      supportedSystems = [
        "x86_64-linux"   # 64-bit Linux (NixOS, Ubuntu, Fedora, etc.)
        "aarch64-linux"  # ARM64 Linux (Raspberry Pi, etc.)
        "x86_64-darwin"  # Intel macOS
        "aarch64-darwin" # Apple Silicon macOS
      ];

      # Helper function to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Import nixpkgs for a specific system
      pkgsFor = system: import nixpkgs {
        inherit system;
        # Allow unfree packages (some tools may require this)
        config.allowUnfree = true;
      };
    in
    {
      # devShells provides development environments
      # When you run `nix develop`, Nix looks for devShells.<system>.default
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            # `name` is just metadata - appears in shell prompts
            name = "homelab-sccm-devshell";

            # `buildInputs` lists all packages we want available in the shell
            #
            # NOTE: VirtualBox is NOT included here.
            # VirtualBox requires kernel modules and setuid wrappers that must
            # be installed at the system level. Each platform handles this
            # differently:
            #   - NixOS: virtualisation.virtualbox.host.enable = true
            #   - Ubuntu/Debian: apt install virtualbox
            #   - Fedora: dnf install VirtualBox
            #   - macOS: Download from virtualbox.org
            # See docs/nix-setup.md for detailed installation instructions.
            buildInputs = with pkgs; [
              # Version control
              git              # Git version control system

              # VM orchestration
              vagrant          # Automates VirtualBox VM creation and provisioning

              # Windows automation and management
              powershell       # PowerShell Core 7.x - cross-platform PowerShell

              # Scripting and automation
              python3          # Python 3.x for scripting and automation
              python3Packages.pip  # Python package installer

              # Networking tools (useful for debugging)
              curl             # Transfer data with URLs
              wget             # Download files
              netcat           # Network debugging
              freerdp          # GUI remote via xfreerdp

              # Text processing (useful for parsing logs)
              jq               # JSON processor
              yq-go            # YAML processor

              # Hardware virtualization
              swtpm            # TPM emulator
            ];

            # `shellHook` runs commands when entering the dev shell
            shellHook = ''
              # ============================================================
              # STORAGE CONFIGURATION
              # ============================================================
              # This lab requires ~300GB of disk space for VMs.
              # By default, files are stored in your home directory:
              #   - Vagrant boxes: ~/.vagrant.d/boxes/
              #   - VirtualBox VMs: ~/VirtualBox VMs/
              #
              # To use a custom location (e.g., /mnt/vms):
              #   1. Add to ~/.bashrc or ~/.zshrc:
              #      export VAGRANT_HOME=/mnt/vms/vagrant-boxes
              #   2. Configure VirtualBox (one-time):
              #      VBoxManage setproperty machinefolder /mnt/vms/virtualbox-vms
              #   3. Reload shell and re-run: nix develop
              #
              # Or use the automated script: ./scripts/configure-storage.sh /mnt/vms
              # See docs/storage-configuration.md for details.
              # ============================================================

              # Set Vagrant home directory (where boxes are cached)
              if [ -z "$VAGRANT_HOME" ]; then
                # Default: Use standard Vagrant location
                export VAGRANT_HOME="$HOME/.vagrant.d"
              fi

              # Ensure Vagrant home directory exists (idempotent)
              mkdir -p "$VAGRANT_HOME/boxes" 2>/dev/null || true

              # Check if custom storage is configured
              USING_CUSTOM_STORAGE=false
              if [[ "$VAGRANT_HOME" != "$HOME/.vagrant.d" ]]; then
                USING_CUSTOM_STORAGE=true
              fi

              # Check for VirtualBox installation
              if ! command -v VBoxManage &> /dev/null; then
                echo "=============================================="
                echo "  ERROR: VirtualBox is not installed!"
                echo "=============================================="
                echo ""
                echo "VirtualBox must be installed at the system level."
                echo "See docs/nix-setup.md for installation instructions."
                echo ""
                echo "Quick install:"
                echo "  NixOS:  Add 'virtualisation.virtualbox.host.enable = true;'"
                echo "          to your configuration.nix and run 'nixos-rebuild switch'"
                echo "  Ubuntu: sudo apt install virtualbox"
                echo "  Fedora: sudo dnf install VirtualBox"
                echo "  macOS:  Download from https://www.virtualbox.org/wiki/Downloads"
                echo ""
                echo "=============================================="
              else
                # Print welcome message with tool versions
                echo "=============================================="
                echo "  Homelab SCCM Development Environment"
                echo "=============================================="
                echo ""
                echo "Available tools:"
                echo "  - Vagrant: $(vagrant --version 2>/dev/null || echo 'not found')"
                echo "  - VirtualBox: $(VBoxManage --version 2>/dev/null | head -n1 || echo 'not found')"
                echo "  - PowerShell: $(pwsh --version 2>/dev/null || echo 'not found')"
                echo "  - Python: $(python --version 2>/dev/null || echo 'not found')"
                echo ""

                # Display storage configuration with helpful guidance
                echo "Storage configuration:"
                if [ "$USING_CUSTOM_STORAGE" = true ]; then
                  echo "  ✓ Custom storage configured"
                  echo "  - Vagrant boxes: $VAGRANT_HOME"
                  echo "  - VirtualBox VMs: $(VBoxManage list systemproperties | grep 'Default machine folder' | cut -d: -f2 | xargs)"
                else
                  echo "  ℹ Using default locations (home directory)"
                  echo "  - Vagrant boxes: $VAGRANT_HOME"
                  echo "  - VirtualBox VMs: $(VBoxManage list systemproperties | grep 'Default machine folder' | cut -d: -f2 | xargs)"
                  echo ""
                  echo "  ⚠ This lab requires ~300GB disk space!"
                  echo "  To use a different location (e.g., /mnt/vms):"
                  echo "    ./scripts/configure-storage.sh /mnt/vms"
                  echo "  See: docs/storage-configuration.md"
                fi
                echo ""

                echo "Quick commands:"
                echo "  - 'cd vagrant && vagrant up' - Start VMs"
                echo "  - 'vagrant status' - Check VM status"
                echo "  - 'pwsh' - Enter PowerShell"
                echo ""
                echo "Documentation: See docs/ directory"
                echo "=============================================="
                echo ""

                # Check if user is in vboxusers group (Linux only)
                if [[ "$(uname)" == "Linux" ]] && ! groups | grep -q vboxusers; then
                  echo "WARNING: You are not in the 'vboxusers' group!"
                  echo "  Run: sudo usermod -aG vboxusers $USER"
                  echo "  Then logout and login again."
                  echo ""
                fi

                # Check for conflicting hypervisor kernel modules (Linux only)
                if [[ "$(uname)" == "Linux" ]]; then
                  CONFLICTING_MODULES=""
                  if lsmod | grep -q "^kvm_amd"; then
                    CONFLICTING_MODULES="$CONFLICTING_MODULES kvm_amd"
                  fi
                  if lsmod | grep -q "^kvm_intel"; then
                    CONFLICTING_MODULES="$CONFLICTING_MODULES kvm_intel"
                  fi
                  if lsmod | grep -q "^kvm " || lsmod | grep -q "^kvm$"; then
                    CONFLICTING_MODULES="$CONFLICTING_MODULES kvm"
                  fi

                  if [ -n "$CONFLICTING_MODULES" ]; then
                    echo "⚠️  WARNING: Conflicting hypervisor modules detected!"
                    echo "=============================================="
                    echo "VirtualBox cannot run while KVM is active."
                    echo ""
                    echo "Loaded modules:$CONFLICTING_MODULES"
                    echo ""
                    echo "To use VirtualBox, unload KVM modules:"
                    echo "  sudo rmmod kvm_amd kvm_intel kvm"
                    echo ""
                    echo "To permanently disable KVM (if not needed):"
                    echo "  sudo bash -c 'cat > /etc/modprobe.d/blacklist-kvm.conf << EOF"
                    echo "  blacklist kvm"
                    echo "  blacklist kvm_amd"
                    echo "  blacklist kvm_intel"
                    echo "  EOF'"
                    echo ""
                    echo "=============================================="
                    echo ""
                  fi
                fi
              fi

              # Set environment variables for VirtualBox
              export VBOX_USER_HOME="$HOME/.config/VirtualBox"

              # Add current directory to PATH for easy script execution
              export PATH="$PWD/scripts:$PATH"
            '';
          };
        }
      );
    };
}
