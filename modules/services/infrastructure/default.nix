{ ... }:
{
  # Import infrastructure service modules
  imports = [
    ./caddy.nix
    ./cloudflared.nix
    ./headscale.nix
    ./netboot.nix
    ./postgresql.nix
    ./tailscale.nix
    ./technitium.nix
  ];
}
