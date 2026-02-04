{ config, lib, inputs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.openclaw;
  matrixConfig =
    cfg.matrix.config
    // optionalAttrs (cfg.matrix.accessTokenFile != null) {
      accessTokenFile = cfg.matrix.accessTokenFile;
    };
in
{
  imports = [ inputs.nix-openclaw.nixosModules.openclaw ];

  options.modules.services.productivity.openclaw = {
    enable = mkEnableOption "OpenClaw gateway";

    bind = mkOption {
      type = types.str;
      default = "127.0.0.1:18789";
      description = "Bind address for the OpenClaw gateway control plane.";
    };

    allowTailscale = mkOption {
      type = types.bool;
      default = true;
      description = "Allow Tailscale identity headers for gateway auth.";
    };

    matrix = {
      enable = mkEnableOption "Matrix channel integration";

      accessTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the Matrix access token file.";
      };

      config = mkOption {
        type = types.attrs;
        default = { };
        description = "Additional Matrix channel configuration passed to OpenClaw.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.openclaw = {
      enable = true;
      config = {
        gateway = {
          mode = "local";
          bind = cfg.bind;
          auth.allowTailscale = cfg.allowTailscale;
        };

        channels = mkIf cfg.matrix.enable {
          matrix = matrixConfig;
        };
      };
    };
  };
}
