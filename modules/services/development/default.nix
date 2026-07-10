{ ... }:
{
  # Import development service modules
  imports = [
    ./vscode-server.nix
    ./github-actions.nix
    ./github-runner.nix
    ./kasm.nix
    ./openvscode-server.nix
    ./code-server.nix
  ];
}

