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
  
  age.secrets = {
    # -------------------------------------------------------------------------
    # SHARED SECRETS - Used by multiple services/servers
    # -------------------------------------------------------------------------
    
    cloudflare-api-token = {
      file = ../secrets/cloudflare-api-token.age;
      owner = "caddy";
      group = "caddy";
      mode = "0400";
    };
    
    # Cloudflare Tunnel Token (shared by both hosts for redundancy)
    cloudflared-token-current = {
      file = ../secrets/cloudflared-token-current.age;
      owner = "cloudflared";
      group = "cloudflared";
      mode = "0400";
    };
  } // (optionalAttrs (config.networking.hostName == "david") {
    # -------------------------------------------------------------------------
    # DAVID-SPECIFIC SECRETS
    # -------------------------------------------------------------------------
    
    matrix-registration-secret = {
      file = ../secrets/matrix-registration-secret.age;
      owner = "matrix-synapse";
      group = "matrix-synapse";
      mode = "0400";
    };
    
    # Google OAuth Secret for Outline
    outline-google-secret = {
      file = ../secrets/outline-google-secret.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # Affine Database Password (for affine containers)
    affine-db-password = {
      file = ../secrets/affine-db-password.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # Affine Postgres Password (for postgres container)
    affine-postgres-password = {
      file = ../secrets/affine-postgres-password.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # Tandoor Secrets (DB password + secret key)
    tandoor-secrets = {
      file = ../secrets/tandoor-secrets.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # Docmost Secrets (DB password + app secret)
    docmost-secrets = {
      file = ../secrets/docmost-secrets.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # WordPress Studio 7andco Secrets
    wordpress-studio-mysql = {
      file = ../secrets/wordpress-studio-mysql.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    wordpress-studio-wp = {
      file = ../secrets/wordpress-studio-wp.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # WordPress Photography Secrets
    wordpress-photography-mysql = {
      file = ../secrets/wordpress-photography-mysql.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    wordpress-photography-wp = {
      file = ../secrets/wordpress-photography-wp.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # WordPress CarolineYoder Secrets
    wordpress-carolineyoder-mysql = {
      file = ../secrets/wordpress-carolineyoder-mysql.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    wordpress-carolineyoder-wp = {
      file = ../secrets/wordpress-carolineyoder-wp.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # Outline Secrets (SECRET_KEY, UTILS_SECRET, DB password)
    outline-secrets = {
      file = ../secrets/outline-secrets.age;
      owner = "root";
      group = "docker";
      mode = "0440";
    };
    
    # NextDNS Dynamic DNS Link
    nextdns-link = {
      file = ../secrets/nextdns-link.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    
    # TODO: Create these secrets when ready
    # vaultwarden-admin-token = {
    #   file = ../secrets/vaultwarden-admin-token.age;
    #   owner = "vaultwarden";
    #   group = "vaultwarden";
    #   mode = "0400";
    # };
  }) // (optionalAttrs (config.networking.hostName == "pits") {
    # -------------------------------------------------------------------------
    # PITS-SPECIFIC SECRETS
    # -------------------------------------------------------------------------
    
    # TODO: Create these secrets when ready
    # tailscale-authkey-pits = {
    #   file = ../secrets/tailscale-authkey-pits.age;
    #   owner = "root";
    #   group = "root";
    #   mode = "0400";
    # };
  });
}

