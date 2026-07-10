{ ... }:
{
  # Import development service modules
  imports = [
    ./vscode-server.nix
    ./github-actions.nix
    ./gitlab.nix
    ./gitlab-runner.nix
    ./kasm.nix
    ./openvscode-server.nix
    ./code-server.nix
  ];
}

