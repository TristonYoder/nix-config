{ config, lib, ... }:

with lib;
let
  cfg = config.modules.system.nixCache;
in
{
  options.modules.system.nixCache = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Pull pre-built closures from david's binary cache.";
    };

    cacheUrl = mkOption {
      type = types.str;
      default = "https://nix-cache.theyoder.family";
      description = ''
        URL of the binary cache written by the build-offline-closures CI job on
        david. Defaults to the internal HTTPS endpoint served by david over
        Tailscale.
      '';
    };

    priority = mkOption {
      type = types.int;
      default = 30;
      description = ''
        Substituter priority. Lower number = higher priority.
        cache.nixos.org is 40; our cache defaults to 30 so it is preferred.
        Hosts with direct disk access (file://) should use 20.
      '';
    };

    trustedPublicKey = mkOption {
      type = types.nullOr types.str;
      default = "nix-cache.theyoder.family:NgpfqkeBWGMBuRI6uaxIqVTPEPRtyd4DcTJcvAFv4T4=";
      description = ''
        Public key for verifying signed paths from the binary cache.
        Format: "nix-cache.theyoder.family:<base64>".
        Set after running: nix-store --generate-binary-cache-key nix-cache.theyoder.family priv.pem pub.pem
      '';
    };
  };

  config = mkIf cfg.enable {
    # extra-* appends to the defaults so cache.nixos.org remains a fallback.
    nix.settings.extra-substituters = [ "${cfg.cacheUrl}?priority=${toString cfg.priority}" ];
    nix.settings.extra-trusted-substituters = [ cfg.cacheUrl ];
    nix.settings.extra-trusted-public-keys = lib.optional (cfg.trustedPublicKey != null) cfg.trustedPublicKey;
  };
}
