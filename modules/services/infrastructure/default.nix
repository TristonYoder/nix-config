{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./headscale.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
