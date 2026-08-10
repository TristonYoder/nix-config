{ ... }:
{
  # Import productivity service modules
  imports = [
    ./blueprint.nix
    ./vaultwarden.nix
    ./n8n.nix
    ./actual.nix
    ./actual-http-api.nix
    ./actual-mcp.nix
    ./outline.nix
    ./tandoor.nix
    ./babybuddy.nix
    ./companion.nix
    ./stirling-pdf.nix
    ./paperless-ngx.nix
    ./miniflux.nix
    # b1church.nix is intentionally absent: it wraps an external flake and is
    # imported directly in flake.nix for david, so hosts that don't use it
    # never pull the input. Same reasoning as hermes-agent.nix.
  ];
}
