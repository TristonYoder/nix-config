let
  # SSH host key for the david machine
  # Generated with: nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
  david = "age19my5vpmrvl5u9ug4frpdmuuemjhdgemgqjm6xunknmfjf6efvdxs232kym";
  
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

