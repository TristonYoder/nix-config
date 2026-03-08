{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./headscale.nix
    ./nix-cache.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
