{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./dns-sync.nix
    ./headscale.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
