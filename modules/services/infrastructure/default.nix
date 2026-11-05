{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./headscale.nix
    ./nix-cache-server.nix
    ./postgresql.nix
    ./pxe-boot.nix
    ./scrutiny.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
