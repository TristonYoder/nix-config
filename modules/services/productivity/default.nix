{ ... }:
{
  # Import productivity service modules
  imports = [
    ./blueprint.nix
    ./vaultwarden.nix
    ./n8n.nix
    ./actual.nix
    ./actual-http-api.nix
    ./outline.nix
    ./tandoor.nix
    ./babybuddy.nix
    ./companion.nix
    ./stirling-pdf.nix
    ./paperless-ngx.nix
    ./miniflux.nix
  ];
}
