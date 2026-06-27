{ config, lib, pkgs, ... }:

with lib;
let
  nc  = config.modules.services.storage.nextcloud;
  cfg = nc.oidc;
  pkg = pkgs.nextcloud33;
in
{
  options.modules.services.storage.nextcloud.oidc = {
    enable = mkEnableOption "Nextcloud OIDC login via Pocket ID";

    issuerUrl = mkOption {
      type = types.str;
      default = "https://id.${config.networking.domain}";
      description = "OIDC issuer URL (Pocket ID base URL)";
    };

    clientId = mkOption {
      type = types.str;
      default = "nextcloud";
      description = "OIDC client ID registered in Pocket ID";
    };

    clientSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the OIDC client secret. Defaults to agenix-managed secret.";
    };

    # user_oidc provider identifier — used as the primary key in occ commands
    providerIdentifier = mkOption {
      type = types.str;
      default = "pocket-id";
      description = "Internal identifier for the OIDC provider (used in occ commands)";
    };
  };

  config = mkIf (nc.enable && cfg.enable) {
    age.secrets.nextcloud-oidc-client-secret = mkIf (cfg.clientSecretFile == null) {
      file = ../../../../secrets/nextcloud-oidc-client-secret.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    modules.services.storage.nextcloud._officeApps = {
      inherit (pkg.packages.apps) user_oidc;
    };

    systemd.services.nextcloud-configure-oidc = {
      description = "Configure Nextcloud OIDC provider (Pocket ID)";
      after    = [ "nextcloud-setup.service" ];
      requires = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "nextcloud";
      };
      script =
        let
          occ = "${config.services.nextcloud.occ}/bin/nextcloud-occ";
          secretFile = if cfg.clientSecretFile != null
            then cfg.clientSecretFile
            else config.age.secrets.nextcloud-oidc-client-secret.path;
          id = cfg.providerIdentifier;
        in
        ''
          CLIENT_SECRET=$(cat ${secretFile})

          # Create or update the provider
          if ${occ} user_oidc:provider --help 2>/dev/null | grep -q 'create-or-update'; then
            SUBCMD="create-or-update"
          else
            SUBCMD="create"
          fi

          ${occ} user_oidc:provider "$SUBCMD" "${id}" \
            --clientid="${cfg.clientId}" \
            --clientsecret="$CLIENT_SECRET" \
            --discoveryuri="${cfg.issuerUrl}/.well-known/openid-configuration" \
            --unique-uid=1 \
            --mapping-uid="preferred_username" \
            --mapping-display-name="name" \
            --mapping-email="email" \
            --check-bearer=1 \
            --send-id-token-hint=1

          # Disable built-in login form so Pocket ID is the only entry point
          ${occ} config:app:set user_oidc allow_multiple_user_backends --value="0"
        '';
    };
  };
}
