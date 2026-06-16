{ config, lib, ... }:

with lib;
let
  cfg = config.modules.system.nixCache;
in
{
  options.modules.system.nixCache = {
    enable = mkEnableOption "Local NFS Nix binary cache";

    cacheUrl = mkOption {
      type = types.str;
      default = "file:///data/nix-builds/cache";
      description = ''
        URL of the local binary cache built by the build-offline-closures CI job
        on david. Defaults to the NFS-mounted path for hosts with /data mounted;
        override with a remote URL (e.g. http://david.vpn.theyoder.family/nix-cache)
        for hosts that access david over Tailscale instead.
      '';
    };
  };

  config = mkIf cfg.enable {
    nix.settings.substituters = [ cfg.cacheUrl ];
    nix.settings.trusted-substituters = [ cfg.cacheUrl ];
  };
}
