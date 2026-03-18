{ ... }:
{
  # Import productivity service modules
  imports = [
    ./vaultwarden.nix
    ./n8n.nix
    ./actual.nix
    ./actual-http-api.nix
    ./outline.nix
    ./tandoor.nix
    ./babybuddy.nix
    ./companion.nix
  ];
}
