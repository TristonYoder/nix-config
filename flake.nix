{
  description = "Multi-Host NixOS & Darwin Configuration - Servers, Desktops, and macOS";

  inputs = {
    # Core NixOS
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Home Manager for user configurations
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Home Manager for Darwin (matches unstable)
    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    
    # nix-darwin for macOS (use nixpkgs-unstable for darwin)
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    
    # nix-homebrew for managing Homebrew on macOS
    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };
    
    # NixOS hardware support modules (T2, Raspberry Pi, etc.)
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # External modules
    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.117";
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    agenix.url = "github:ryantm/agenix";
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";

    # External app flakes
    iopenpod-flake.url = "github:TristonYoder/iopenpod-flake";
    iopodcli.url = "github:TristonYoder/iOpenPodCLI";

    # Hermes Agent (NousResearch) — official NixOS module
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, home-manager-unstable, nix-darwin, nix-homebrew, nix-bitcoin, nixos-vscode-server, agenix, nixos-hardware, flake-utils, iopenpod-flake, iopodcli, hermes-agent, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      in
      {
        # Development shells
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            gh
            nix
            docker
            compose2nix
            agenix.packages.${system}.default
          ];
        };

        # Development shell for Bitcoin services
        devShells.bitcoin = pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            nix
            # Bitcoin development tools
          ];
        };
      }
    ) // {
      # =============================================================================
      # NIXOS CONFIGURATIONS
      # =============================================================================
      
      nixosConfigurations = {
        # -----------------------------------------------------------------------------
        # david - Main Server (x86_64-linux)
        # -----------------------------------------------------------------------------
        david = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          
          modules = [
            # Common configuration
            ./common/system.nix
            ./common/linux.nix
            
            # Server profile
            ./profiles/server.nix
            
            # Workstation profile (desktop apps)
            ./profiles/workstation.nix
            
            # Host-specific configuration
            ./hosts/david/configuration.nix
            ./hosts/david/hardware-configuration.nix
            
            # Custom modules (hardware, system, services)
            ./modules
            
            # Docker services (organized by category)
            ./docker/docker.nix
            ./docker/watchtower.nix
            ./docker/caddy-virtual-hosts.nix

            
            # Media services
            ./docker/media/audiobooks.nix
            ./docker/media/media-aq.nix
            ./docker/media/ersatztv.nix
            ./docker/media/threadfin.nix
            ./docker/media/tunarr.nix
            # ./docker/scrypted.nix
            
            # Website services
            ./docker/websites/com.carolineyoder.nix
            ./docker/websites/photography.carolineelizabeth.nix
            ./docker/websites/studio.7andco.nix
            
            # Productivity services
            ./docker/productivity/affine.nix
            ./docker/productivity/homarr.nix
            # ./docker/productivity/outline.nix
            ./docker/productivity/planning-poker.nix
            ./docker/productivity/pocket-id.nix
            ./docker/productivity/stageplotiphar.nix

            # External modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default
            # Hermes Agent — upstream module + our wrapper, david-only.
            # hermes-agent.nix is not in ./modules to avoid pulling the upstream
            # flake on hosts that can't reach github (pits) or don't use it.
            hermes-agent.nixosModules.default
            ./modules/services/ai/hermes-agent.nix
            # nix-bitcoin.nixosModules.default  # Only include when bitcoin.nix is enabled

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
            }
          ];
          
          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable nix-bitcoin iopenpod-flake iopodcli;
          };
        };

        # -----------------------------------------------------------------------------
        # tristons-workstation - Desktop Workstation (x86_64-linux)
        # -----------------------------------------------------------------------------
        tristons-workstation = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            # Common configuration
            ./common/system.nix
            ./common/linux.nix

            # Workstation profile (includes desktop profile)
            ./profiles/workstation.nix

            # Host-specific configuration
            ./hosts/tristons-workstation/configuration.nix
            ./hosts/tristons-workstation/hardware-configuration.nix

            # Custom modules (hardware, system, services)
            ./modules

            # External modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
              home-manager.users.carolineyoder = import ./home/carolineyoder.nix;
            }
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable iopenpod-flake iopodcli;
          };
        };

        # -----------------------------------------------------------------------------
        # tristons-nixbook - NixOS Laptop (x86_64-linux)
        # -----------------------------------------------------------------------------
        tristons-nixbook = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            # Common configuration
            ./common/system.nix
            ./common/linux.nix

            # Workstation profile (includes desktop profile)
            ./profiles/workstation.nix

            # Host-specific configuration
            ./hosts/tristons-nixbook/configuration.nix
            ./hosts/tristons-nixbook/hardware-configuration.nix

            # Custom modules (hardware, system, services)
            ./modules

            # External modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
              home-manager.users.carolineyoder = import ./home/carolineyoder.nix;
            }
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable iopenpod-flake;
          };
        };

        # -----------------------------------------------------------------------------
        # tristons-nixbook-pro - NixOS on T2 MacBook Pro 16,1 (dual boot, x86_64-linux)
        # -----------------------------------------------------------------------------
        tristons-nixbook-pro = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./common/system.nix
            ./common/linux.nix
            nixos-hardware.nixosModules.apple-t2
            ./profiles/workstation.nix
            ./hosts/tristons-nixbook-pro/configuration.nix
            ./hosts/tristons-nixbook-pro/hardware-configuration.nix
            ./modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
              home-manager.users.carolineyoder = import ./home/carolineyoder.nix;
            }
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable iopenpod-flake;
          };
        };

        # -----------------------------------------------------------------------------
        # tristons-nixbook-pro-installer - Bootable minimal ISO for T2 MacBook Pro
        # -----------------------------------------------------------------------------
        tristons-nixbook-pro-installer = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            nixos-hardware.nixosModules.apple-t2
            ./hosts/tristons-nixbook-pro/installer.nix
          ];

          specialArgs = {
            inherit nixpkgs nixpkgs-unstable;
          };
        };

        # -----------------------------------------------------------------------------
        # tristons-nixbook-pro-installer-plasma - Plasma 6 ISO for T2 MacBook Pro
        # -----------------------------------------------------------------------------
        tristons-nixbook-pro-installer-plasma = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            nixos-hardware.nixosModules.apple-t2
            ./hosts/tristons-nixbook-pro/installer-plasma.nix
          ];

          specialArgs = {
            inherit nixpkgs nixpkgs-unstable;
          };
        };

        # -----------------------------------------------------------------------------
        # installer - Barebones installer ISO (generic hardware, Tailscale + SSH)
        # -----------------------------------------------------------------------------
        installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./hosts/installer/configuration.nix
          ];

          specialArgs = {
            inherit nixpkgs;
          };
        };

        # -----------------------------------------------------------------------------
        # pits - Pi in the Sky - Edge Server (Cloud VPS)
        # -----------------------------------------------------------------------------
        pits = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";  # Cloud VPS (change to aarch64-linux for ARM)
          
          modules = [
            # Common configuration
            ./common/system.nix
            ./common/linux.nix
            
            # Edge profile
            ./profiles/edge.nix
            
            # Host-specific configuration
            ./hosts/pits/configuration.nix
            ./hosts/pits/hardware-configuration.nix
            
            # Custom modules (hardware, system, services)
            ./modules
            
            # External modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
            }
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable;
          };
        };
      };

      # =============================================================================
      # DARWIN CONFIGURATIONS (macOS)
      # =============================================================================
      
      darwinConfigurations = {
        # -----------------------------------------------------------------------------
        # tyoder-mbp - macOS MacBook Pro (Apple Silicon)
        # Friendly name: Triston's TPCC MacBook Pro (work)
        # -----------------------------------------------------------------------------
        tyoder-mbp = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";  # Change to x86_64-darwin if Intel Mac
          
          modules = [
            # Common configuration
            ./common/system.nix
            ./common/darwin.nix
            
            # Darwin profile
            ./profiles/darwin.nix
            
            # Host-specific configuration
            ./hosts/tyoder-mbp/configuration.nix
            
            # nix-homebrew - Homebrew installation management
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;  # Apple Silicon: install Homebrew for Rosetta 2
                user = "tyoder";
                autoMigrate = true;  # Migrate existing Homebrew installation if present
              };
            }
            
            # Home Manager for macOS (using unstable to match nix-darwin)
            home-manager-unstable.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.tyoder = import ./home/tyoder.nix;
            }
          ];
          
          specialArgs = {
            inherit nixpkgs nixpkgs-unstable;
          };
        };
        
        # -----------------------------------------------------------------------------
        # Tristons-MacBook-Pro - macOS MacBook Pro (Intel T2)
        # Friendly name: Triston's MacBook Pro
        # -----------------------------------------------------------------------------
        "Tristons-MacBook-Pro" = nix-darwin.lib.darwinSystem {
          system = "x86_64-darwin";  # Intel Mac
          
          modules = [
            # Common configuration
            ./common/system.nix
            ./common/darwin.nix
            
            # Darwin profile
            ./profiles/darwin.nix
            
            # Host-specific configuration
            ./hosts/tristons-mbp/configuration.nix
            
            # nix-homebrew - Homebrew installation management
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = false;  # Intel Mac: no Rosetta needed
                user = "tristonyoder";
                autoMigrate = true;  # Migrate existing Homebrew installation if present
              };
            }
            
            # Home Manager for macOS (using unstable to match nix-darwin)
            home-manager-unstable.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.tristonyoder = {
                imports = [
                  ./home/tristonyoder.nix
                  ./home/modules/homebrew.nix
                  ./home/modules/mas.nix
                  ./home/tristonyoder-darwin.nix
                ];
                home.homeDirectory = "/Users/tristonyoder";
              };
            }
          ];
          
          specialArgs = {
            inherit nixpkgs nixpkgs-unstable;
          };
        };
      };
    };
}
