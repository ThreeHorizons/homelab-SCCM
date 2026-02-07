# Integration Guide: Adding homelab-SCCM to Your Main Flake

This guide shows how to integrate the homelab-SCCM lab environment into your existing multi-system NixOS flake.

## Option 1: As a Flake Input (Recommended)

Add homelab-SCCM as an input to your main flake.nix:

```nix
{
  description = "Multi-System NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix.url = "github:danth/stylix";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zed-editor.url = "github:zed-industries/zed";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # ADD THIS: homelab-SCCM lab environment
    homelab-sccm = {
      url = "path:/home/myodhes-nix/projects/homelab-SCCM";
      # Let it use its own nixpkgs (has NixVirt pinned to compatible version)
      # Or use: inputs.nixpkgs.follows = "nixpkgs"; if you want consistency
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, nixos-hardware, home-manager, darwin, homelab-sccm, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      mkNixosSystem = system: hostname: pkgsInput: modules:
        let
          pkgs = import pkgsInput {
            inherit system;
            config.allowUnfree = true;
          };
        in pkgsInput.lib.nixosSystem {
          inherit system pkgs;
          specialArgs = { inherit inputs hostname; };
          modules = [
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = false;
              home-manager.useUserPackages = true;
            }
          ] ++ modules;
        };

      mkDarwinSystem = system: hostname: pkgsInput: modules: darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs hostname; };
        modules = [
          home-manager.darwinModules.home-manager
          { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true; }
        ] ++ modules;
      };
    in
    {
      nixosConfigurations = {
        frameworking = mkNixosSystem "x86_64-linux" "frameworking" nixpkgs [
          ./hosts/frameworking/default.nix
        ];
      };

      # ... rest of your outputs ...
    };
}
```

## Option 2: Enable in Host Configuration

Then in your host configuration (`hosts/frameworking/default.nix`), conditionally enable it:

```nix
# hosts/frameworking/default.nix
{ config, pkgs, inputs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # ... your other imports ...
    
    # OPTIONAL: Enable homelab-SCCM if you want it on this host
    # Comment out or remove when not using the lab
    inputs.homelab-sccm.nixosModules.default
  ];
  
  # Your existing configuration...
}
```

## Option 3: Create a Dedicated Lab Host Configuration

Better yet, create a separate host configuration specifically for the lab:

```nix
# In your main flake.nix outputs:
nixosConfigurations = {
  frameworking = mkNixosSystem "x86_64-linux" "frameworking" nixpkgs [
    ./hosts/frameworking/default.nix
  ];
  
  # NEW: Dedicated lab configuration
  sccm-lab = mkNixosSystem "x86_64-linux" "sccm-lab" nixpkgs [
    ./hosts/sccm-lab/default.nix
  ];
};
```

Then create `hosts/sccm-lab/default.nix`:

```nix
# hosts/sccm-lab/default.nix
{ config, pkgs, inputs, hostname, ... }:

{
  imports = [
    # Import the homelab-SCCM module
    inputs.homelab-sccm.nixosModules.default
    
    # You might want to symlink or reuse hardware-configuration.nix
    ../frameworking/hardware-configuration.nix
    
    # Common base configuration
    ../../modules/base.nix  # if you have one
  ];

  # Lab-specific configuration
  networking.hostName = "sccm-lab";

  # Enable libvirtd
  virtualisation.libvirtd.enable = true;
  
  # Add your user to libvirt group
  users.users.myodhes-nix.extraGroups = [ "libvirt" ];
  
  # Enable virt-manager
  programs.virt-manager.enable = true;
  
  # Optionally disable some services to save resources when running VMs
  services.xserver.enable = true;  # Keep if you want to use virt-manager GUI
  
  # Your other configuration...
  system.stateVersion = "24.11";
}
```

## Option 4: Use NixOS Specialisations (Most Flexible!)

This is the cleanest approach - it lets you have **both** your normal system **and** the lab environment, switchable at boot:

```nix
# hosts/frameworking/default.nix
{ config, pkgs, inputs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Your normal imports...
  ];

  # Your normal configuration...
  
  # ADD THIS: Specialisation for the SCCM lab
  specialisation = {
    sccm-lab = {
      configuration = {
        imports = [
          inputs.homelab-sccm.nixosModules.default
        ];
        
        # Lab-specific overrides
        system.nixos.tags = [ "sccm-lab" ];
        
        # Ensure libvirt is enabled
        virtualisation.libvirtd.enable = true;
        users.users.myodhes-nix.extraGroups = [ "libvirt" ];
        programs.virt-manager.enable = true;
      };
    };
  };
}
```

Then at boot, you can choose "NixOS - sccm-lab" from the bootloader menu!

Or switch to it live:
```bash
sudo /nix/var/nix/profiles/system/specialisation/sccm-lab/bin/switch-to-configuration switch
```

Switch back to normal:
```bash
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

## My Recommendation

I recommend **Option 4 (Specialisation)** because:

✅ **No separate host configuration needed** - keeps your flake simple
✅ **Easy to enable/disable** - switch between configurations without rebuilding
✅ **Isolated** - Lab resources only created when you boot into the specialisation
✅ **Doesn't affect your normal workflow** - normal boot works exactly as before

## Quick Implementation Steps

1. **Add homelab-sccm to your inputs** (shown in Option 1)

2. **Add the specialisation block** to `hosts/frameworking/default.nix`:

```nix
# Near the end of your frameworking config
specialisation.sccm-lab = {
  configuration = {
    imports = [ inputs.homelab-sccm.nixosModules.default ];
    system.nixos.tags = [ "sccm-lab" ];
    virtualisation.libvirtd.enable = true;
    users.users.myodhes-nix.extraGroups = [ "libvirt" ];
    programs.virt-manager.enable = true;
  };
};
```

3. **Rebuild your system**:
```bash
sudo nixos-rebuild switch --flake /path/to/your/main/flake#frameworking
```

4. **Reboot and select the specialisation** from the boot menu, or switch to it live.

## Accessing the Lab DevShell

Even without the NixOS module active, you can still use the lab's devShell for PowerShell automation:

```bash
# From your homelab-SCCM directory
nix develop /home/myodhes-nix/projects/homelab-SCCM

# Or add it to your main flake's devShells:
devShells = nixpkgs.lib.genAttrs supportedSystems (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in {
    # Your existing shells...
    
    # ADD THIS:
    sccm-lab = homelab-sccm.devShells.${system}.default;
  }
);

# Then use it with:
nix develop .#sccm-lab
```

## Summary

**Quick Start (Specialisation Approach):**
1. Add `homelab-sccm` to inputs
2. Add specialisation block to frameworking config
3. `sudo nixos-rebuild switch`
4. Reboot and select "sccm-lab" from boot menu
5. VMs are now available via `virsh list --all`

**Cleanup:**
- Just boot back into your normal system
- The VMs persist until you explicitly delete them

Want me to generate the exact code snippets for your specific flake structure?
