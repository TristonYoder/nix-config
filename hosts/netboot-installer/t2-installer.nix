# PXE netboot installer for T2 MacBook Pro hardware, served from david.
#
# Netboot counterpart to hosts/tristons-nixbook-pro/installer.nix (which
# builds an ISO for USB installs) — same T2 firmware/cache setup, just
# delivered over the network instead of a flashed stick.

{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  hardware.apple-t2.firmware = {
    enable = true;
    version = "sonoma";
  };

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    substituters = lib.mkAfter [ "https://cache.soopy.moe" ];
    trusted-public-keys = lib.mkAfter [
      "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
    ];
  };

  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkForce "yes";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDv25/0nLCy/VRqOYPu10PA5lUcireG1GEUk1+mFMPbL7q7o+9GqJ8INhlncvd6tc5sm5ZblK5aqrZxKW8Cy78OZpPfPTyVWVIcxos+SWba1Fbi+Xco0ZT3BqRvCcgkLM/jCIVfr5Hzo2iP5lvt21KN2OY7XpwlqdCfmZyyjwPGwFfniEbwvHZSaxgSllXqTcLrpYt75ryn58T7HKF0m7vCGguct62UtKibLUw0jsgFk5rbXGqggGOH7W/Gg0gnzCN5eB3azbpFvRMW106lMz7iXIy1ZyfeQrGATH+TlEgYsU/ROk2LSQOun99DqJOAts6ZaeFu5+VDsJh0S17tIud5"
  ];

  networking.firewall.enable = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
