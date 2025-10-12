{
  description = "David's NixOS Configuration - Home Server & Development Environment";

  inputs = {
    # Core NixOS
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # External modules
    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.117";
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    agenix.url = "github:ryantm/agenix";
    
    # Optional: Home Manager for user configurations
    # home-manager.url = "github:nix-community/home-manager";
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nix-bitcoin, nixos-vscode-server, agenix, flake-utils, ... }:
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
      # NixOS configurations
      nixosConfigurations = {
        david = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          
          modules = [
            # Core configuration
            ./configuration.nix
            ./hardware-configuration.nix
            
            # Custom modules (hardware, system, services)
            ./modules
            
            # Docker services (organized by category)
            ./docker/docker.nix
            ./docker/watchtower.nix
            
            # Media services
            ./docker/media/audiobooks.nix
            ./docker/media/media-aq.nix
            ./docker/media/ersatztv.nix
            
            # Website services
            ./docker/websites/com.carolineyoder.nix
            ./docker/websites/photography.carolineelizabeth.nix
            ./docker/websites/studio.7andco.nix
            
            # Productivity services
            ./docker/productivity/affine.nix
            ./docker/productivity/homarr.nix
            ./docker/productivity/outline.nix
            ./docker/productivity/planning-poker.nix
            ./docker/productivity/tandoor.nix
            
            # External modules
            nixos-vscode-server.nixosModules.default
            agenix.nixosModules.default
            # nix-bitcoin.nixosModules.default  # Only include when bitcoin.nix is enabled
          ];
          
          specialArgs = {
            inherit nixpkgs nixpkgs-unstable nix-bitcoin;
          };
        };
      };
    };
}
