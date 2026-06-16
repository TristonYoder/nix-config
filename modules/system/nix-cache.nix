{ config, lib, ... }:

with lib;
let
  cfg = config.modules.system.nixCache;
in
{
  options.modules.system.nixCache = {
    enable = mkEnableOption "Local Nix binary cache (david's build-offline-closures output)";

    cacheUrl = mkOption {
      type = types.str;
      default = "https://nix-cache.theyoder.family";
      description = ''
        URL of the binary cache written by the build-offline-closures CI job on
        david. Defaults to the internal HTTPS endpoint served by david over
        Tailscale. Override with file:///data/nix-builds/cache on hosts with
        the NFS /data mount for lower latency.
      '';
    };
  };

  config = mkIf cfg.enable {
    nix.settings.substituters = [ cfg.cacheUrl ];
    nix.settings.trusted-substituters = [ cfg.cacheUrl ];
  };
}
