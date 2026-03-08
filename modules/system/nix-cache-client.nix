{ config, lib, ... }:

with lib;
let
  cfg = config.modules.system.nix-cache-client;
in
{
  options.modules.system.nix-cache-client = {
    enable = mkEnableOption "Nix binary cache client (use david as substituter)";

    cacheUrl = mkOption {
      type = types.str;
      default = "https://cache.${config.networking.domain}";
      description = "URL of the binary cache server";
    };

    publicKey = mkOption {
      type = types.str;
      description = "Public signing key of the binary cache (from `nix key convert-secret-to-public`)";
    };
  };

  config = mkIf cfg.enable {
    nix.settings = {
      substituters = [ cfg.cacheUrl ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
