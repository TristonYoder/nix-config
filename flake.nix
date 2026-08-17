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
    
    # Declarative KDE Plasma 6 config, as a Home Manager module.
    # Upstream tracks home-manager master; we point it at our pinned
    # release-26.05 instead. Bump this input deliberately rather than letting
    # `nix flake update` drag it, since it can drift ahead of stable HM.
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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

    # Raspberry Pi 5 firmware/bootloader/kernel support — used by the
    # stage-plotiphar kiosk host and the installer-rpi5 flake output.
    # Vanilla nixpkgs sdImage doesn't support the Pi 5's boot process.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

    # External modules
    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.117";
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    agenix.url = "github:ryantm/agenix";
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";

    # External app flakes
    iopenpod-flake.url = "github:TristonYoder/iopenpod-flake";
    iopodcli.url = "github:TristonYoder/iOpenPodCLI";
    blueprint.url = "github:TristonYoder/blueprint";

    # Hermes Agent (NousResearch) — official NixOS module
    hermes-agent.url = "github:NousResearch/hermes-agent";

    # B1 Church — self-hosted ChurchApps stack. The flake owns both the image
    # builds and the NixOS module, and its nightly build commits the published
    # image tag, so this input's revision *is* the deployed version: upgrading
    # is `nix flake update b1church`, which the weekly flake updater already
    # dry-runs and PRs. Takes no inputs of its own, so it adds no lock churn.
    b1church.url = "github:TristonYoder/b1church-flake";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, home-manager-unstable, plasma-manager, nix-darwin, nix-homebrew, nix-bitcoin, nixos-vscode-server, agenix, nixos-hardware, nixos-raspberrypi, flake-utils, iopenpod-flake, iopodcli, blueprint, hermes-agent, b1church, ... }:
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
            # B1 Church — external module + our wrapper (vHosts + agenix
            # paths), david-only, kept out of ./modules for the same reason.
            b1church.nixosModules.default
            ./modules/services/productivity/b1church.nix
            # nix-bitcoin.nixosModules.default  # Only include when bitcoin.nix is enabled

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              # Declarative Plasma. Loaded for every user on this host but inert
              # until modules.plasma.enable is set in the host config.
              home-manager.sharedModules = [
                plasma-manager.homeModules.plasma-manager
                ./home/modules/plasma
              ];
              home-manager.users.tristonyoder = import ./home/tristonyoder.nix;
            }
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable nix-bitcoin iopenpod-flake iopodcli blueprint;
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
              # Declarative Plasma. Loaded for every user on this host but inert
              # until modules.plasma.enable is set in the host config.
              home-manager.sharedModules = [
                plasma-manager.homeModules.plasma-manager
                ./home/modules/plasma
              ];
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
              # Declarative Plasma. Loaded for every user on this host but inert
              # until modules.plasma.enable is set in the host config.
              home-manager.sharedModules = [
                plasma-manager.homeModules.plasma-manager
                ./home/modules/plasma
              ];
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
              # Declarative Plasma. Loaded for every user on this host but inert
              # until modules.plasma.enable is set in the host config.
              home-manager.sharedModules = [
                plasma-manager.homeModules.plasma-manager
                ./home/modules/plasma
              ];
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

        # Same installer config, built for aarch64 (Raspberry Pi / ARM boards).
        # Building this requires an aarch64-linux builder — either a native ARM
        # machine or `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` on an
        # x86_64 builder host. Neither is currently set up on any host in this
        # fleet (david included) — building this output will fail with
        # "don't know how to build for system aarch64-linux" until one is.
        installer-aarch64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";

          modules = [
            ./hosts/installer/configuration.nix
          ];

          specialArgs = {
            inherit nixpkgs;
          };
        };

        # Barebones installer for Raspberry Pi 5 (CM5/Pi 5) specifically —
        # generic aarch64-linux UEFI ISOs don't boot on the Pi 5, it needs
        # its own firmware/bootloader/kernel handling. Uses the same
        # nixos-raspberrypi flake (and raspberry-pi-5.base module) as the
        # stage-plotiphar kiosk host on the host/plotiphar branch, so this
        # is a proven-working pattern, not a first attempt.
        installer-rpi5 = nixos-raspberrypi.lib.nixosInstaller {
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
              ];
            }
            ./hosts/installer/rpi5.nix
          ];
        };

        # PXE/iPXE netboot variant of the barebones installer — kernel +
        # initrd pair instead of an ISO, for modules/services/infrastructure/pxe-boot.nix
        # to serve. Pi 5 is intentionally not covered here — it network-boots
        # via its own EEPROM/TFTP mechanism, not iPXE chainloading, and needs
        # a materially different implementation.
        installer-netboot = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./hosts/installer/netboot.nix
          ];

          specialArgs = {
            inherit nixpkgs;
          };
        };

        # Same netboot config, built for aarch64. See installer-aarch64 above
        # for the emulated-builder caveat — same applies here.
        installer-netboot-aarch64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";

          modules = [
            ./hosts/installer/netboot.nix
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

        # -----------------------------------------------------------------------------
        # stage-plotiphar - Raspberry Pi 5 (CM5 Lite) signage kiosk (aarch64-linux)
        # -----------------------------------------------------------------------------
        stage-plotiphar = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";

          modules = [
            nixos-raspberrypi.lib.inject-overlays

            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.display-vc4
              ];
            }

            # Common configuration
            ./common/system.nix
            ./common/linux.nix

            # Kiosk profile
            ./profiles/kiosk.nix

            # Host-specific configuration
            ./hosts/stage-plotiphar/configuration.nix
            ./hosts/stage-plotiphar/hardware-configuration.nix

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
            inherit self nixpkgs nixpkgs-unstable nixos-raspberrypi;
          };
        };

        # -----------------------------------------------------------------------------
        # stage-plotiphar-vm - Parallels-bootable live ISO of the same kiosk config,
        # for testing before deploying to the real Pi 5. See hosts/stage-plotiphar-vm
        # for what this can/can't validate. Build with:
        # nix build .#nixosConfigurations.stage-plotiphar-vm.config.system.build.isoImage
        # -----------------------------------------------------------------------------
        stage-plotiphar-vm = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";

          modules = [
            # Common configuration
            ./common/system.nix
            ./common/linux.nix

            # Kiosk profile — same one the real Pi 5 host uses
            ./profiles/kiosk.nix

            # Host-specific configuration
            ./hosts/stage-plotiphar-vm/configuration.nix

            # Custom modules (hardware, system, services)
            ./modules

            # ./modules/secrets.nix declares `age.secrets.*` unconditionally,
            # so the agenix module needs to exist even though this throwaway
            # VM never actually decrypts anything.
            agenix.nixosModules.default
          ];

          specialArgs = {
            inherit self nixpkgs nixpkgs-unstable;
          };
        };

        # -----------------------------------------------------------------------------
        # stage-plotiphar-installer - one-shot Pi 5 SD/NVMe image used only to get
        # NixOS onto the box; not a host you rebuild day-to-day. Bakes in Triston's
        # SSH keys so it's reachable the instant it boots (no monitor/keyboard).
        # Build with: nix build .#nixosConfigurations.stage-plotiphar-installer.config.system.build.sdImage
        # -----------------------------------------------------------------------------
        stage-plotiphar-installer = nixos-raspberrypi.lib.nixosInstaller {
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
              ];

              users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz Triston Yoder"
              ];
              users.users.nixos.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz Triston Yoder"
              ];
            }
          ]
          # WiFi creds, if present on THIS machine outside the repo entirely — never
          # committed. See secrets/local-only/README.md. Deliberately an absolute path
          # outside the flake's own source tree (not e.g. ./secrets/local-only/...):
          # flakes only see git-tracked files in their own source, so a gitignored file
          # *inside* the repo directory would silently and invisibly not exist here.
          # Requires building with --impure (this reads outside the flake's source).
          ++ nixpkgs.lib.optional
            (builtins.pathExists "${builtins.getEnv "HOME"}/.config/nix-config-local-only/wifi-installer.nix")
            (import "${builtins.getEnv "HOME"}/.config/nix-config-local-only/wifi-installer.nix");
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
