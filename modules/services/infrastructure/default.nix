{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}

