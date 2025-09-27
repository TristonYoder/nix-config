{
  description = "Triston Yoder's NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-vscode-server.url = "github:nix-community/nixos-vscode-server";
    
    # Optional: Add other flake inputs as needed
    # home-manager.url = "github:nix-community/home-manager";
    # nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-vscode-server, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        david = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./configuration.nix
            ./server-deployment.nix
          ];
          specialArgs = { inherit inputs; inherit nixos-vscode-server; };
        };
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixos-rebuild
          git
          jq
          rsync
        ];
      };

      # Formatter
      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
