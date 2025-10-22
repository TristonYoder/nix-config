let
  # =============================================================================
  # HOST KEYS - SSH host keys for servers (public keys, safe to commit)
  # =============================================================================
  # Generated with: ssh <host> "cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age
  
  david = "age19my5vpmrvl5u9ug4frpdmuuemjhdgemgqjm6xunknmfjf6efvdxs232kym";
  
  pits = "age1jja99mf5qfczutr574nve8vhpt7azm8aq4ukqqrstdn0agud23nscazh6r";
  
  # =============================================================================
  # ADMIN KEYS - Keys for managing secrets from local machines
  # =============================================================================
  # Option 1: Use a dedicated agenix key (recommended)
  # ssh-keygen -t ed25519 -f ~/.ssh/agenix -C "agenix-secrets@nix-config" -N ""
  # cat ~/.ssh/agenix.pub | ssh-to-age
  #
  # Option 2: Use your personal SSH key
  # ssh-add -L | ssh-to-age
  
  adminKeys = [
    "age1m32sa7vq84004w6spg5tp7vzmszecxpp0da6z6dj8fxs70y34flshd46jq"  # Dedicated agenix key
  ];
  
  # =============================================================================
  # KEY GROUPS - Define which keys can access which secrets
  # =============================================================================
  
  # Secrets accessible by both servers + admins (shared secrets)
  allServers = [ david pits ] ++ adminKeys;
  
  # Secrets for david only
  davidKeys = [ david ] ++ adminKeys;
  
  # Secrets for pits only
  pitsKeys = [ pits ] ++ adminKeys;
in
{
  # =============================================================================
  # SHARED SECRETS - Accessible by multiple servers
  # =============================================================================
  
  # Cloudflare API Token - Used by both servers for Caddy DNS-01 challenge
  "cloudflare-api-token.age".publicKeys = allServers;
  
  # =============================================================================
  # DAVID-SPECIFIC SECRETS
  # =============================================================================
  
  # Matrix Synapse registration shared secret (only on david)
  "matrix-registration-secret.age".publicKeys = davidKeys;
  
  # Pixelfed environment secrets (only on david)
  "pixelfed-env.age".publicKeys = davidKeys;
  
  # BlueBubbles server password for mautrix-imessage bridge (only on david)
  # Note: Secret is declared in the module itself (modules/services/communication/mautrix-imessage.nix)
  # to avoid user creation ordering issues
  "bluebubbles-password.age".publicKeys = davidKeys;
  
  # Vaultwarden admin token (only on david)
  "vaultwarden-admin-token.age".publicKeys = davidKeys;
  
  # PostgreSQL password for Affine (only on david)
  "postgres-affine-password.age".publicKeys = davidKeys;
  
  # Google OAuth Secret for Outline
  "outline-google-secret.age".publicKeys = davidKeys;
  
  # Affine Database Password
  "affine-db-password.age".publicKeys = davidKeys;
  
  # Tandoor Secrets
  "tandoor-secrets.age".publicKeys = davidKeys;
  
  # Docmost Secrets
  "docmost-secrets.age".publicKeys = davidKeys;
  
  # WordPress Secrets (all 3 sites)
  "wordpress-studio-secrets.age".publicKeys = davidKeys;
  "wordpress-photography-secrets.age".publicKeys = davidKeys;
  "wordpress-carolineyoder-secrets.age".publicKeys = davidKeys;
  
  # Outline Application Secrets
  "outline-secrets.age".publicKeys = davidKeys;
  
  # NextDNS Dynamic DNS Link
  "nextdns-link.age".publicKeys = davidKeys;
  
  # =============================================================================
  # SHARED SECRETS (Both Servers)
  # =============================================================================
  
  # Cloudflare tunnel token - shared by both david and pits for redundancy
  "cloudflared-token-current.age".publicKeys = allServers;
  
  # =============================================================================
  # PITS-SPECIFIC SECRETS
  # =============================================================================
  
  # Tailscale auth key for pits edge server
  "tailscale-authkey-pits.age".publicKeys = pitsKeys;
  
  # Stalwart Mail Server passwords (accessible by all servers for flexibility)
  "stalwart-postmaster-password.age".publicKeys = allServers;
  "stalwart-admin-password.age".publicKeys = allServers;
  "stalwart-admin-web-password.age".publicKeys = allServers;
}

