{ config, lib, pkgs, ... }:

{
  networking.hostName = "hermes-agent";
  system.stateVersion = "25.05";

  modules.hardware.boot.enable = lib.mkForce false;

  networking.useDHCP = lib.mkDefault true;

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
  modules.services.infrastructure.technitium.enable = lib.mkForce false;
  modules.services.providers.dns-technitium.enable = lib.mkForce false;
  modules.services.infrastructure.caddy.enable = lib.mkForce false;

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