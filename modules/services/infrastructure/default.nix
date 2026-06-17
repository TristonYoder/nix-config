{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./headscale.nix
    ./netboot.nix
    ./nix-cache-server.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
