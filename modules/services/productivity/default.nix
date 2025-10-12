{ ... }:
{
  # Import productivity service modules
  imports = [
    ./vaultwarden.nix
    ./n8n.nix
    ./actual.nix
  ];
}

