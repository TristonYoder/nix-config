{ config, lib, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.nixCacheServer;
in
{
  options.modules.services.infrastructure.nixCacheServer = {
    enable = mkEnableOption "Nix binary cache server";

    cacheDir = mkOption {
      type = types.str;
      default = "/data/nix-builds/cache";
      description = "Directory where nix copy --to file:// writes signed .nar/.narinfo files.";
    };
  };

  config = mkIf cfg.enable {
    modules.services.vHosts.hosts."nix-cache.${config.networking.domain}" = {
      rawConfig = true;
      public = false;
      displayName = "Nix Cache";
      category = "infrastructure";
      monitor = false;
      extraConfig = ''
        root * ${cfg.cacheDir}
        file_server
      '';
    };
  };
}
