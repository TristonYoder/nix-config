{ ... }:
{
  imports = [
    ./dns-technitium.nix
    ./cloudflare-tunnel.nix
    ./monitoring.nix
    ./dashboard.nix
  ];
}
