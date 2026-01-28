# Example configuration for enabling Immich OAuth support with agenix secrets
# 
# Usage:
# 1. Create the encrypted secret file:
#    cd /path/to/nix-config
#    echo -n "your-client-secret" | ./secrets/encrypt-secret.sh immich-oauth-client-secret.age
#
# 2. Add to your host's configuration.nix:

{ config, lib, ... }:

{
  # Import agenix module if not already imported
  imports = [ inputs.agenix.homeManagerModules.default ];

  # Define the secret
  age.secrets.immichOAuthClientSecret = {
    file = ../secrets/immich-oauth-client-secret.age;
    owner = "immich";
    group = "immich";
    mode = "0400";
  };

  # Enable Immich with OAuth
  modules.services.media.immich = {
    enable = true;
    domain = "photos.theyoder.family";
    publicProxyDomain = "share.photos.theyoder.family";
    
    oauth = {
      enable = true;
      
      # OAuth provider configuration (example: Authentik)
      issuerUrl = "https://auth.example.com/application/o/immich/";
      clientId = "your-client-id";
      clientSecretFile = config.age.secrets.immichOAuthClientSecret.path;
      
      # User provisioning
      autoRegister = true;
      autoLaunch = false;
      buttonText = "Login with Authentik";
      
      # Scopes and claims
      scope = "openid email profile";
      roleClaim = "immich_role";
      storageLabelClaim = "preferred_username";
      storageQuotaClaim = "immich_quota";
      
      # Optional: set default quota (in bytes, e.g., 100GB)
      defaultStorageQuota = 107374182400;
      
      # Mobile settings (if supporting OAuth on mobile)
      mobileOverrideEnabled = false;
      mobileRedirectUri = "";
    };
  };
}

# Notes:
# - The clientSecretFile should point to a file encrypted with agenix
# - The secret will be read at evaluation time and passed to Immich
# - Ensure the secret file is in .gitignore and never committed
# - For production, rotate client secrets regularly
# - All oauth settings have sensible defaults and can be omitted if not needed
