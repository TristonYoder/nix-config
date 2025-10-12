let
  # SSH host key for the david machine
  # This should be the age public key derived from /etc/ssh/ssh_host_ed25519_key.pub
  # To get this key on the server, run:
  #   ssh-keyscan david.theyoder.family | ssh-to-age
  # or:
  #   nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
  david = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderKeyReplaceMeWithActualHostKey";
  
  # Add admin user keys here (for managing secrets from your machine)
  # Get your key with: ssh-add -L | ssh-to-age
  adminKeys = [
    # Add your personal SSH key converted to age format here
  ];
  
  allKeys = [ david ] ++ adminKeys;
in
{
  # Cloudflare API Token for DNS-01 challenge
  "cloudflare-api-token.age".publicKeys = allKeys;
  
  # Cloudflared tunnel token
  "cloudflared-token.age".publicKeys = allKeys;
  
  # Vaultwarden admin token
  "vaultwarden-admin-token.age".publicKeys = allKeys;
  
  # PostgreSQL passwords
  "postgres-affine-password.age".publicKeys = allKeys;
  
  # Add more secrets as needed
}

