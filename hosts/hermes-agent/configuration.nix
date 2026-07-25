{ config, lib, pkgs, ... }:

{
  networking.hostName = "hermes-agent";
  system.stateVersion = "25.05";

  modules.hardware.boot.enable = lib.mkForce false;

  # DHCP on ens3 only ever handed out the CGNAT address with no default
  # route — Vultr's own docs (instance networking tab) give a static
  # config with a real gateway instead. NetworkManager was also fighting
  # us on ens7 (VPC) activation, so go fully declarative/static and drop
  # NetworkManager for this host.
  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;

  networking.interfaces.ens3 = {
    ipv4.addresses = [{ address = "100.68.119.228"; prefixLength = 18; }];
    # Vultr's metadata service (169.254.169.254) lives behind this gateway,
    # not on the local /18 — needs its own route, per Vultr's docs.
    ipv4.routes = [{ address = "169.254.0.0"; prefixLength = 16; }];
  };
  networking.defaultGateway = { address = "100.68.64.1"; interface = "ens3"; };
  # IPv6 keeps working via SLAAC/RA (already confirmed reachable) — no
  # static v6 config needed.
  networking.nameservers = lib.mkForce [ "108.61.10.10" "2001:19f0:300:1704::6" ];

  # Private VPC 2.0 network to pits (10.151.100.4) — no DHCP server on
  # this network, Vultr's docs require a static assignment.
  networking.interfaces.ens7 = {
    useDHCP = false;
    mtu = 1450;
    ipv4.addresses = [{ address = "10.151.100.3"; prefixLength = 23; }];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # This is a 512MB/1vCPU/10GB Vultr VC2 — the smallest tier. ts.theyoder.family
  # (headscale control plane) and DNS already run on pits; running a second
  # headscale + technitium instance here would be redundant and neither has
  # agenix secrets provisioned for this host yet (headscale-api-key,
  # headscale-oidc-secret, cloudflare-api-token all exclude hermes-agent as a
  # recipient), so they'd just fail to decrypt at activation. Disable them
  # until there's an actual reason to run them here. Tailscale client stays on
  # so this host can reach the rest of the tailnet through pits' headscale.
  modules.services.infrastructure.headscale.enable = lib.mkForce false;
  # oidc.enable is checked independently of the parent enable in
  # modules/secrets.nix's secret declaration, so it has to be forced off too
  # or agenix still tries (and fails) to decrypt headscale-oidc-secret here.
  modules.services.infrastructure.headscale.oidc.enable = lib.mkForce false;
  modules.services.infrastructure.technitium.enable = lib.mkForce false;
  modules.services.providers.dns-technitium.enable = lib.mkForce false;
  modules.services.infrastructure.caddy.enable = lib.mkForce false;

  # Join the tailnet unattended on first boot — no IPv4 egress at all on this
  # VPS (Vultr gave it a CGNAT-only private v4 + real public v6, no default
  # v4 route), so it can't usefully advertise routes into the home LAN or
  # serve as an exit node the way pits/david do.
  modules.services.infrastructure.tailscale = {
    authKeyFile = config.age.secrets.tailscale-authkey-hermes-agent.path;
    advertiseExitNode = lib.mkForce false;
    advertiseRoutes = lib.mkForce "";
    advertiseTags = [ "tag:infra-theyoder-family" ];
    # net.ipv6.conf.all.forwarding=1 (the default here) silently disables
    # accept_ra, which would kill the SLAAC-derived IPv6 default route
    # this host actually depends on for internet access.
    enableIPForwarding = lib.mkForce false;
  };

  # profiles/edge.nix's min-free/max-free (5GB/10GB) assumes a bigger disk
  # than this host's 10GB total — on a disk this size that range would have
  # nix GC running almost continuously. Scale down to fit.
  nix.settings.min-free = lib.mkForce (1 * 1024 * 1024 * 1024);
  nix.settings.max-free = lib.mkForce (3 * 1024 * 1024 * 1024);

  services.journald.extraConfig = ''
    SystemMaxUse=50M
    RuntimeMaxUse=25M
  '';

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  environment.systemPackages = with pkgs; [
    htop
    tmux
    vim
  ];
}