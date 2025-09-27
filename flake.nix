{
  description = "David's NixOS Configuration - Home Server & Development Environment";

  inputs = {
    # Core NixOS
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # External modules
    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/v0.0.117";
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    
    # Optional: Home Manager for user configurations
    # home-manager.url = "github:nix-community/home-manager";
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nix-bitcoin, nixos-vscode-server, flake-utils, ... }:
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
            
            # Service modules
            ./modules/services/apps.nix
            ./modules/services/nas.nix
            ./modules/services/caddy-hosts.nix
            ./modules/services/github-actions.nix
            ./modules/services/nextcloud.nix
            
            # Optional services (commented out by default)
            # ./modules/services/bitcoin.nix
            # ./modules/services/wordpress.nix
            # ./modules/services/tailscale-router.nix
            # ./modules/services/demos.nix
            
            # Docker services (unchanged)
            ./docker/affine.nix
            ./docker/com.carolineyoder.nix
            ./docker/photography.carolineelizabeth.nix
            ./docker/studio.7andco.nix
            ./docker/docker.nix
            ./docker/audiobooks.nix
            ./docker/media-aq.nix
            ./docker/homarr.nix
            ./docker/planning-poker.nix
            ./docker/tandoor.nix
            ./docker/watchtower.nix
            ./docker/ersatztv.nix
            
            # External modules
            nixos-vscode-server.nixosModules.default
            nix-bitcoin.nixosModules.default
          ];
          
          specialArgs = {
            inherit nixpkgs nixpkgs-unstable nix-bitcoin;
          };
        };
      };
    };
}
