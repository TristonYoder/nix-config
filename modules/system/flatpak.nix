{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.flatpak;
in
{
  options.modules.system.flatpak = {
    enable = mkEnableOption "Flatpak with the Flathub remote, browsable from KDE Discover";
  };

  config = mkIf cfg.enable {
    services.flatpak.enable = true;

    # Discover is the graphical store; it picks up the Flatpak backend
    # automatically when flatpak is installed.
    environment.systemPackages = [ pkgs.kdePackages.discover ];

    system.activationScripts.flatpak-flathub = stringAfter [ "var" ] ''
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    '';
  };
}
