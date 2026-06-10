# Shared configuration for both ISO variants (minimal + plasma)
{ lib, pkgs, ... }:
{
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

  # Trackpad regression fix
  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  # Install helper available at the shell as 't2-install'
  environment.systemPackages = [
    pkgs.git
    (pkgs.writeScriptBin "t2-install" (builtins.readFile ./install.sh))
  ];
}
