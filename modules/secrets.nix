{ config, lib, pkgs, ... }:

with lib;
{
  # =============================================================================
  # AGENIX SECRETS CONFIGURATION
  # =============================================================================
  # This module declares all agenix-managed secrets and their ownership/permissions
  # The actual encrypted files are in /secrets/*.age
  # Decrypted secrets are available at runtime in /run/agenix/
  
  # Explicitly configure age identity paths for decryption
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_rsa_key"
  ];
  
  # Note: Not specifying ageBin to let agenix use its default implementation
  # which has proper SSH key handling built-in
  
  # Ensure age and ssh-to-age are available system-wide
  environment.systemPackages = with pkgs; [
    age
    ssh-to-age
  ];
  
  age.secrets =
    (optionalAttrs config.services.caddy.enable {
      "cloudflare-api-token" = {
        file = ../secrets/cloudflare-api-token.age;
        owner = "caddy";
        group = "caddy";
        mode = "0400";
      };
    })

    // (optionalAttrs (config.modules.system.krdp.enable && !config.services.caddy.enable) {
      "cloudflare-api-token" = {
        file = ../secrets/cloudflare-api-token.age;
        owner = "root";
        mode = "0400";
      };
    })

    // (optionalAttrs config.modules.services.providers.dns-technitium.enable {
      "technitium-api-token" = { file = ../secrets/technitium-api-token.age; owner = "root"; group = "root"; mode = "0400"; };
    })

    // (optionalAttrs (config.networking.hostName == "david") {
      # Docker-compose services loaded directly in flake.nix for david have no
      # NixOS module enable option, so hostname is the only available gate here.
      # Encryption in secrets/secrets.nix (davidKeys) is the real access control;
      # this guard just avoids deploying unused secrets to other hosts.
      "babybuddy-secrets" = { file = ../secrets/babybuddy-secrets.age; owner = "root"; group = "docker"; mode = "0440"; };
      "outline-google-secret" = { file = ../secrets/outline-google-secret.age; owner = "root"; group = "docker"; mode = "0440"; };
      "affine-db-password" = { file = ../secrets/affine-db-password.age; owner = "root"; group = "docker"; mode = "0440"; };
      "affine-postgres-password" = { file = ../secrets/affine-postgres-password.age; owner = "root"; group = "docker"; mode = "0440"; };
      "affine-oidc-secret" = { file = ../secrets/affine-oidc-secret.age; owner = "root"; group = "docker"; mode = "0440"; };
      "tandoor-secrets" = { file = ../secrets/tandoor-secrets.age; owner = "root"; group = "docker"; mode = "0440"; };
      "docmost-secrets" = { file = ../secrets/docmost-secrets.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-studio-mysql" = { file = ../secrets/wordpress-studio-mysql.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-studio-wp" = { file = ../secrets/wordpress-studio-wp.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-photography-mysql" = { file = ../secrets/wordpress-photography-mysql.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-photography-wp" = { file = ../secrets/wordpress-photography-wp.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-carolineyoder-mysql" = { file = ../secrets/wordpress-carolineyoder-mysql.age; owner = "root"; group = "docker"; mode = "0440"; };
      "wordpress-carolineyoder-wp" = { file = ../secrets/wordpress-carolineyoder-wp.age; owner = "root"; group = "docker"; mode = "0440"; };
      "outline-secrets" = { file = ../secrets/outline-secrets.age; owner = "root"; group = "docker"; mode = "0440"; };
      "nextdns-link" = { file = ../secrets/nextdns-link.age; owner = "root"; group = "root"; mode = "0400"; };
      "pocket-id-encryption-key" = { file = ../secrets/pocket-id-encryption-key.age; owner = "root"; group = "docker"; mode = "0440"; };
      # tidarr: docker-only service (docker/media/media-aq.nix), no NixOS module enable
      "tidarr-oidc-secret" = { file = ../secrets/tidarr-oidc-secret.age; mode = "0400"; };
      # hermes-agent: NixOS module loaded only on david (external flake dep), no universal enable option
      "hermes-env" = { file = ../secrets/hermes-env.age; mode = "0400"; };
      # Deploy key (write access) for the private TristonYoder/hermes-brain repo —
      # the vault git-sync timer pushes Hermes's brain (SOUL.md/memory/skills) there.
      "hermes-brain-deploy-key" = { file = ../secrets/hermes-brain-deploy-key.age; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.gaming.romm.enable {
      # Encrypted to davidKeys only — enabling romm on another host requires
      # re-encrypting these secrets to that host's key first.
      "romm-auth-secret-key" = { file = ../secrets/romm-auth-secret-key.age; owner = "root"; group = "docker"; mode = "0440"; };
      "romm-db-password" = { file = ../secrets/romm-db-password.age; owner = "root"; group = "docker"; mode = "0440"; };
      "romm-oidc-secret" = { file = ../secrets/romm-oidc-secret.age; owner = "root"; group = "docker"; mode = "0440"; };
      "romm-steamgriddb-key" = { file = ../secrets/romm-steamgriddb-key.age; owner = "root"; group = "docker"; mode = "0440"; };
      "romm-igdb-client-id" = { file = ../secrets/romm-igdb-client-id.age; owner = "root"; group = "docker"; mode = "0440"; };
      "romm-igdb-client-secret" = { file = ../secrets/romm-igdb-client-secret.age; owner = "root"; group = "docker"; mode = "0440"; };
    })

    // (optionalAttrs config.modules.services.infrastructure.nixCacheServer.enable {
      # Encrypted to davidKeys only
      "nix-cache-signing-key" = { file = ../secrets/nix-cache-signing-key.age; owner = "github-actions"; group = "github-actions"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.infrastructure.cloudflared.enable {
      # Encrypted to davidKeys only
      "cloudflared-token-current" = { file = ../secrets/cloudflared-token-current.age; owner = "cloudflared"; group = "cloudflared"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.infrastructure.headscale.enable {
      # Encrypted to pitsKeys only
      "headscale-api-key" = { file = ../secrets/headscale-api-key.age; owner = "headscale"; group = "headscale"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.infrastructure.headscale.oidc.enable {
      # Encrypted to pitsKeys only
      "headscale-oidc-secret" = { file = ../secrets/headscale-oidc-secret.age; owner = "headscale"; group = "headscale"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.communication.matrix-synapse.enable {
      # Encrypted to davidKeys only
      "matrix-registration-secret" = { file = ../secrets/matrix-registration-secret.age; owner = "matrix-synapse"; group = "matrix-synapse"; mode = "0400"; };
    })

    // (optionalAttrs config.services.nextcloud.enable {
      # Encrypted to davidKeys only
      "nextcloud-admin-password" = { file = ../secrets/nextcloud-admin-password.age; owner = "nextcloud"; group = "nextcloud"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.media.jellyplexWatched.enable {
      # Encrypted to davidKeys only
      "plex-token" = { file = ../secrets/plex-token.age; owner = "jellyplex-watched"; group = "jellyplex-watched"; mode = "0400"; };
      "jellyfin-token" = { file = ../secrets/jellyfin-token.age; owner = "jellyplex-watched"; group = "jellyplex-watched"; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.storage.mp3PlayerSync.enable {
      # Encrypted to davidKeys only
      "jellyfin-api-key" = { file = ../secrets/jellyfin-api-key.age; mode = "0400"; };
    })

    // (optionalAttrs config.modules.services.media.azuracastPlaylistSync.enable {
      # Encrypted to davidKeys only
      "azuracast-api-key" = { file = ../secrets/azuracast-api-key.age; mode = "0400"; };
    })

    ;
}
