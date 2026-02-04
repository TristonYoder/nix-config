{ config, lib, inputs, ... }:

with lib;
let
  cfg = config.modules.openclaw;
  homeManagerModules = inputs.nix-openclaw.homeManagerModules or { };
  openclawModule =
    inputs.nix-openclaw.homeManagerModule
      or (homeManagerModules.openclaw or (homeManagerModules.default or null));
  moduleAvailable = openclawModule != null;
in
{
  imports = lib.optional moduleAvailable openclawModule;

  options.modules.openclaw = {
    enable = mkEnableOption "OpenClaw node client";

    gatewayHost = mkOption {
      type = types.str;
      default = "david";
      description = "Tailscale hostname of the OpenClaw gateway.";
    };

    firstParty = {
      peekaboo = mkEnableOption "Screenshot capture";
      poltergeist = mkEnableOption "macOS UI control";
      camsnap = mkEnableOption "Camera capture";
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    (lib.optionalAttrs (!moduleAvailable) {
      warnings = [
        "nix-openclaw does not expose a Home Manager module. Check the flake outputs for homeManagerModule/homeManagerModules."
      ];
    })
    (lib.optionalAttrs moduleAvailable {
      programs.openclaw = {
        enable = true;
        config = {
          gateway = {
            mode = "remote";
            remote.url = "ws://${cfg.gatewayHost}:18789";
          };

          node.enable = true;
        };

        firstParty = {
          peekaboo.enable = cfg.firstParty.peekaboo;
          poltergeist.enable = cfg.firstParty.poltergeist;
          camsnap.enable = cfg.firstParty.camsnap;
        };
      };
    })
  ]);
}
