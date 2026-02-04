{ config, lib, inputs, ... }:

with lib;
let
  cfg = config.modules.openclaw;
in
{
  imports = [ inputs.nix-openclaw.homeManagerModules.openclaw ];

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

  config = mkIf cfg.enable {
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
  };
}
