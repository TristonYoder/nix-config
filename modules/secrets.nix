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
    
    # Kasm Workspaces secrets
    kasm-admin-password = {
      file = ../secrets/kasm-admin-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    
    kasm-user-password = {
      file = ../secrets/kasm-user-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    
    kasm-redis-password = {
      file = ../secrets/kasm-redis-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    
    kasm-postgres-password = {
      file = ../secrets/kasm-postgres-password.age;
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
    
    # postgres-affine-password = {
    #   file = ../secrets/postgres-affine-password.age;
    #   owner = "postgres";
    #   group = "postgres";
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
    
    # cloudflared-token = {
    #   file = ../secrets/cloudflared-token.age;
    #   owner = "cloudflared";
    #   group = "cloudflared";
    #   mode = "0400";
    # };
  });
}

