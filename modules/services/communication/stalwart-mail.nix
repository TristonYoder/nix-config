{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.stalwart-mail;
in
{
  options.modules.services.communication.stalwart-mail = {
    enable = mkEnableOption "Stalwart mail server";
    
    domain = mkOption {
      type = types.str;
      default = "7andco.dev";
      description = "Primary domain for the mail server";
    };
    
    hostname = mkOption {
      type = types.str;
      default = "mail.7andco.dev";
      description = "Hostname for the mail server (MX record)";
    };
    
    webmailDomain = mkOption {
      type = types.str;
      default = "mail.7andco.dev";
      description = "Domain for webmail interface";
    };
    
    contactEmail = mkOption {
      type = types.str;
      default = "postmaster@7andco.dev";
      description = "Contact email for ACME certificates";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for mail server";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/stalwart";
      description = "Base directory for Stalwart mail data storage";
    };
    
    enablePostalRelay = mkOption {
      type = types.bool;
      default = false;
      description = "Enable relay through Postal mail server for outbound mail";
    };
    
    postalRelayHost = mkOption {
      type = types.str;
      default = "pits";
      description = "Postal relay hostname (via Tailscale)";
    };
    
    postalRelayPort = mkOption {
      type = types.int;
      default = 587;
      description = "Postal relay SMTP port";
    };
    
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 stalwart-mail stalwart-mail -"
      "d ${cfg.dataDir}/data 0750 stalwart-mail stalwart-mail -"
    ];
    
    # Declare agenix secrets for Stalwart mail passwords
    age.secrets.stalwart-postmaster-password = {
      file = ../../../secrets/stalwart-postmaster-password.age;
      owner = "stalwart-mail";
      group = "stalwart-mail";
      mode = "0400";
    };
    
    age.secrets.stalwart-admin-password = {
      file = ../../../secrets/stalwart-admin-password.age;
      owner = "stalwart-mail";
      group = "stalwart-mail";
      mode = "0400";
    };
    
    age.secrets.stalwart-admin-web-password = {
      file = ../../../secrets/stalwart-admin-web-password.age;
      owner = "stalwart-mail";
      group = "stalwart-mail";
      mode = "0400";
    };

    # Set up secret files for Stalwart
    # Passwords are managed via agenix
    environment.etc = {
      "stalwart/mail-pw-postmaster".source = config.age.secrets.stalwart-postmaster-password.path;
      "stalwart/mail-pw-admin".source = config.age.secrets.stalwart-admin-password.path;
      "stalwart/admin-pw".source = config.age.secrets.stalwart-admin-web-password.path;
      "stalwart/acme-secret".source = config.age.secrets.cloudflare-api-token.path;
    };

    # Stalwart mail server configuration
    services.stalwart-mail = {
      enable = true;
      package = pkgs.stalwart-mail;
      openFirewall = cfg.openFirewall;
      
      settings = {
        server = {
          hostname = cfg.hostname;
          
          tls = {
            enable = true;
            implicit = true;
          };
          
          listener = {
            # SMTP - Port 25 (incoming mail)
            smtp = {
              protocol = "smtp";
              bind = "[::]:25";
            };
            
            # SMTPS - Port 465 (submissions with TLS)
            submissions = {
              bind = "[::]:465";
              protocol = "smtp";
            };
            
            # IMAP - Port 993 (with TLS)
            imaps = {
              bind = "[::]:993";
              protocol = "imap";
            };
            
            # JMAP - Port 8080 (proxied through Caddy)
            jmap = {
              bind = "[::]:8080";
              url = "https://${cfg.webmailDomain}";
              protocol = "http";
            };
            
            # Management Interface - localhost only
            management = {
              bind = [ "127.0.0.1:8081" ];
              protocol = "http";
            };
          };
        };

        lookup.default = {
          hostname = cfg.hostname;
          domain = cfg.domain;
        };

        # ACME configuration for Let's Encrypt with Cloudflare DNS
        acme."letsencrypt" = {
          directory = "https://acme-v02.api.letsencrypt.org/directory";
          challenge = "dns-01";
          contact = cfg.contactEmail;
          domains = [ cfg.domain cfg.hostname ];
          provider = "cloudflare";
          secret = "%{file:/etc/stalwart/acme-secret}%";
        };

        # Authentication configuration
        session.auth = {
          mechanisms = "[plain]";
          directory = "'in-memory'";
        };

        # Storage configuration
        storage.data = "rocksdb";
        storage.blob = "rocksdb";
        storage.fts = "rocksdb";
        storage.lookup = "rocksdb";
        
        store."rocksdb" = {
          type = "rocksdb";
          path = "${cfg.dataDir}/data";
          compression = "lz4";
        };
        
        session.rcpt.directory = "'in-memory'";
        queue.outbound.next-hop = if cfg.enablePostalRelay then "'postal-relay'" else "'local'";
        
        # Relay configuration for Postal (only if enabled)
      } // optionalAttrs cfg.enablePostalRelay {
        relay."postal-relay" = {
          host = cfg.postalRelayHost;
          port = cfg.postalRelayPort;
          protocol = "smtp";
          auth = "plain";
          tls = {
            enable = true;
            implicit = false;
          };
        };
      } // {

        # Directory lookup for IMAP
        directory."imap".lookup.domains = [ cfg.domain ];

        # In-memory directory with user principals
        directory."in-memory" = {
          type = "memory";
          principals = [
            {
              class = "individual";
              name = "Postmaster";
              secret = "%{file:/etc/stalwart/mail-pw-postmaster}%";
              email = [ "postmaster@${cfg.domain}" ];
            }
            {
              class = "individual";
              name = "Admin";
              secret = "%{file:/etc/stalwart/mail-pw-admin}%";
              email = [ "admin@${cfg.domain}" ];
            }
          ];
        };

        # Fallback admin authentication for web interface
        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:/etc/stalwart/admin-pw}%";
        };
      };
    };

    # Caddy virtual host for webmail interface
    services.caddy.virtualHosts.${cfg.webmailDomain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:8080
        import cloudflare_tls
      '';
      serverAliases = [
        # MTA-STS for mail security policy
        "mta-sts.${cfg.domain}"
        # Autoconfig for mail clients
        "autoconfig.${cfg.domain}"
        "autodiscover.${cfg.domain}"
      ];
    };
    
    # Caddy virtual host for admin interface
    services.caddy.virtualHosts."admin.mail.7andco.dev" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:8081
        import cloudflare_tls
      '';
    };

    # Open additional firewall ports if needed
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ 
        25    # SMTP
        465   # SMTPS
        993   # IMAPS
      ];
    };
  };
}

