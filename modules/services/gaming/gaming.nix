{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.gaming;
in
{
  options.modules.services.gaming = {
    enable = mkEnableOption "Gaming support";

    steam = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Steam gaming platform";
      };

      steamRomManager = mkOption {
        type = types.bool;
        default = false;
        description = "Install Steam ROM Manager";
      };
    };

    emulators = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable game emulators (Dolphin)";
      };
    };

    cloudGaming = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable cloud gaming clients (GeForce NOW)";
      };
    };
  };

  config = mkIf cfg.enable {
    # Steam
    programs.steam = mkIf cfg.steam.enable {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };

    environment.systemPackages =
      (optional cfg.steam.enable pkgs.steam)
      ++ (optional cfg.steam.steamRomManager pkgs.steam-rom-manager)
      ++ (optional cfg.emulators.enable pkgs.dolphin-emu)
      ++ (optional cfg.cloudGaming.enable pkgs.gfn-electron);
  };
}
