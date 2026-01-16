{
  # Flake description - shown when someone runs `nix flake metadata`
  description = "Homelab SCCM - NixOS-based Configuration Manager lab environment";

  # Inputs are dependencies this flake needs
  # Think of this like a package.json or requirements.txt
  inputs = {
    # nixpkgs is the main Nix package repository
    # We're using the 24.05 stable release for reliability
    # "github:NixOS/nixpkgs/nixos-24.05" means:
    #   - Get it from GitHub
    #   - Organization: NixOS
    #   - Repository: nixpkgs
    #   - Branch: nixos-24.05 (stable release from May 2024)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  # Outputs are what this flake provides to users
  # The `{ self, nixpkgs }` parameter receives our inputs defined above
  outputs = { self, nixpkgs }:
    let
      # We're targeting x86_64 Linux (64-bit Linux systems)
      # This is the "system" architecture string
      system = "x86_64-linux";

      # Import nixpkgs for our specific system
      # We need to configure it to allow unfree packages (VirtualBox)
      pkgs = import nixpkgs {
        inherit system;

        # VirtualBox has a non-free license, so we must explicitly allow it
        # Without this, Nix will refuse to build VirtualBox
        config.allowUnfree = true;
      };
    in
    {
      # devShells provides development environments
      # When you run `nix develop`, Nix looks for devShells.<system>.default
      devShells.${system}.default = pkgs.mkShell {

        # `name` is just metadata - appears in shell prompts
        name = "homelab-sccm-devshell";

        # `buildInputs` lists all packages we want available in the shell
        # These are the tools we need for the project
        buildInputs = with pkgs; [
          # Version control
          git              # Git version control system (likely already installed)

          # Virtualization tools
          vagrant          # VM orchestration - automates VirtualBox VM creation
          virtualbox       # Oracle VirtualBox - the hypervisor we'll use

          # Windows automation and management
          powershell       # PowerShell Core 7.x - cross-platform PowerShell

          # Scripting and automation
          python3          # Python 3.x for scripting and automation
          python3Packages.pip  # Python package installer

          # Networking tools (useful for debugging)
          curl             # Transfer data with URLs
          wget             # Download files
          netcat           # Network debugging

          # Text processing (useful for parsing logs)
          jq               # JSON processor
          yq-go            # YAML processor
        ];

        # `shellHook` runs commands when entering the dev shell
        # This is like .bashrc but only for this development environment
        shellHook = ''
          # Print a nice welcome message
          echo "=============================================="
          echo "  Homelab SCCM Development Environment"
          echo "=============================================="
          echo ""
          echo "Available tools:"
          echo "  - Vagrant: $(vagrant --version)"
          echo "  - VirtualBox: $(VBoxManage --version | head -n1)"
          echo "  - PowerShell: $(pwsh --version)"
          echo "  - Python: $(python --version)"
          echo ""
          echo "Quick commands:"
          echo "  - 'cd vagrant && vagrant up' - Start VMs"
          echo "  - 'vagrant status' - Check VM status"
          echo "  - 'pwsh' - Enter PowerShell"
          echo ""
          echo "Documentation: See docs/ directory"
          echo "=============================================="
          echo ""

          # Check if user is in vboxusers group (required for VirtualBox)
          if ! groups | grep -q vboxusers; then
            echo "⚠️  WARNING: You are not in the 'vboxusers' group!"
            echo "   Run: sudo usermod -aG vboxusers $USER"
            echo "   Then logout and login again."
            echo ""
          fi

          # Set environment variables for VirtualBox
          # This ensures VirtualBox knows where to find its files
          export VBOX_USER_HOME="$HOME/.config/VirtualBox"

          # Add current directory to PATH for easy script execution
          export PATH="$PWD/scripts:$PATH"
        '';
      };
    };
}
