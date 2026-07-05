{ ... }:
{
  imports = [
    ./dns-technitium.nix
    ./cloudflare-tunnel.nix
    ./monitoring.nix
    ./dashboard-homepage.nix
    ./dashboard-homarr.nix
    ./app-manifest.nix
  ];
}
