# Caddy virtual host configurations for Docker services
  # Centralizes reverse proxy settings for Docker-based services

  { config, lib, ... }:

  {
    # Audiobookshelf - Audiobook and podcast server
    services.caddy.virtualHosts."audiobooks.theyoder.family" = {
      extraConfig = ''
        reverse_proxy http://localhost:13378
        import cloudflare_tls
      '';
    };

    # OpenAudible - Audible audiobook management
    services.caddy.virtualHosts."audiobooksync.theyoder.family" = {
      extraConfig = ''
        reverse_proxy http://localhost:13379
        import cloudflare_tls
      '';
    };
  }