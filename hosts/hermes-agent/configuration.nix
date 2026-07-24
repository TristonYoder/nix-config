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