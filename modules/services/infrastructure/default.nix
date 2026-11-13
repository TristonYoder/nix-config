{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./cortendesk.nix
    ./headscale.nix
    ./nix-cache-server.nix
    ./postgresql.nix
    ./scrutiny.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
