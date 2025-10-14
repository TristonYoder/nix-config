{ config, lib, pkgs, ... }:

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
  
  # Specify which age implementation to use (rage is the Rust implementation)
  age.ageBin = "${pkgs.rage}/bin/rage";
  
  # Ensure age/rage is available system-wide
  environment.systemPackages = with pkgs; [
    age
    rage
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
    
    # -------------------------------------------------------------------------
    # DAVID-SPECIFIC SECRETS
    # -------------------------------------------------------------------------
    
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
  };
}

