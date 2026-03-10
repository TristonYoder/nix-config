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
      # PlayStation
      duckstation = mkEnableOption "DuckStation (PS1 emulator)" // { default = true; };
      pcsx2 = mkEnableOption "PCSX2 (PS2 emulator)" // { default = true; };
      rpcs3 = mkEnableOption "RPCS3 (PS3 emulator)" // { default = true; };
      ppsspp = mkEnableOption "PPSSPP (PSP emulator)" // { default = true; };
      shadps4 = mkEnableOption "shadPS4 (PS4 emulator)" // { default = true; };

      # Nintendo
      dolphin = mkEnableOption "Dolphin (GameCube/Wii emulator)" // { default = true; };
      ryujinx = mkEnableOption "Ryujinx (Switch emulator)" // { default = true; };
      melonDS = mkEnableOption "melonDS (DS emulator)" // { default = true; };
      mgba = mkEnableOption "mGBA (GBA emulator)" // { default = true; };
      azahar = mkEnableOption "Azahar (3DS emulator)" // { default = true; };
      cemu = mkEnableOption "Cemu (Wii U emulator)" // { default = true; };

      # Multi-system / Other
      retroarch = mkEnableOption "RetroArch (multi-system frontend)" // { default = true; };
      scummvm = mkEnableOption "ScummVM (point-and-click adventures)" // { default = true; };
      mame = mkEnableOption "MAME (arcade emulator)" // { default = true; };
    };

    cloudGaming = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable cloud gaming clients (GeForce NOW)";
      };
      moonlight = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Moonlight streaming client";
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
      # PlayStation
      ++ (optional cfg.emulators.duckstation pkgs.duckstation)
      ++ (optional cfg.emulators.pcsx2 pkgs.pcsx2)
      ++ (optional cfg.emulators.rpcs3 pkgs.rpcs3)
      ++ (optional cfg.emulators.ppsspp pkgs.ppsspp)
      ++ (optional cfg.emulators.shadps4 pkgs.shadps4)
      # Nintendo
      ++ (optional cfg.emulators.dolphin pkgs.dolphin-emu)
      ++ (optional cfg.emulators.ryujinx pkgs.ryujinx)
      ++ (optional cfg.emulators.melonDS pkgs.melonDS)
      ++ (optional cfg.emulators.mgba pkgs.mgba)
      ++ (optional cfg.emulators.azahar pkgs.azahar)
      ++ (optional cfg.emulators.cemu pkgs.cemu)
      # Multi-system / Other
      ++ (optional cfg.emulators.retroarch pkgs.retroarchFull)
      ++ (optional cfg.emulators.scummvm pkgs.scummvm)
      ++ (optional cfg.emulators.mame pkgs.mame)
      ++ (optional cfg.cloudGaming.enable pkgs.gfn-electron)
      ++ (optional cfg.cloudGaming.moonlight pkgs.moonlight-qt);

    # Add udev rules for DolphinBar when dolphin is enabled
    # The idVendor and idProduct might need to be adjusted based on your specific DolphinBar.
    # You can find them by running `lsusb` with the DolphinBar plugged in.
    services.udev.extraRules = lib.mkIf cfg.emulators.dolphin ''
      # Mayflash DolphinBar (likely ID 057e:0306 or similar)
      SUBSYSTEM=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0306", MODE="0666"
    '';
  };
}
