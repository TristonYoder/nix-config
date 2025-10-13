{ ... }:
{
  # Import development service modules
  imports = [
    ./vscode-server.nix
    ./github-actions.nix
  ];
}

