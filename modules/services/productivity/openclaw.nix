{ config, lib, inputs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.openclaw;
  nixosModules = inputs.nix-openclaw.nixosModules or { };
  openclawModule =
    inputs.nix-openclaw.nixosModule
      or (nixosModules.openclaw or (nixosModules.default or null));
  matrixConfig =
    cfg.matrix.config
    // optionalAttrs (cfg.matrix.accessTokenFile != null) {
      accessTokenFile = cfg.matrix.accessTokenFile;
    };
in
{
  imports = lib.optional (openclawModule != null) openclawModule;

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

  config = mkIf cfg.enable (lib.throwIf (openclawModule == null)
    "nix-openclaw does not expose a NixOS module. Check the flake outputs for nixosModule/nixosModules."
    {
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
  });
}
