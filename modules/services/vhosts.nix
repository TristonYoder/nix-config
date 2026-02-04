{ lib, ... }:

with lib;
{
  options.modules.services.vHosts = mkOption {
    type = types.attrsOf (types.submodule ({ name, ... }: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to create this virtual host.";
        };

        virtualHost = mkOption {
          type = types.str;
          default = name;
          description = "Virtual host name (defaults to the attribute key).";
        };

        reverseProxyAddress = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Explicit upstream reverse proxy target (overrides host/port/SSL if set).";
        };

        reverseProxyHost = mkOption {
          type = types.str;
          default = "localhost";
          description = "Reverse proxy host (defaults to the local machine).";
        };

        reverseProxyPort = mkOption {
          type = types.port;
          default = 80;
          description = "Reverse proxy port.";
        };

        reverseProxySSL = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to use HTTPS when building the reverse proxy address.";
        };

        managedProxy = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to use the managed reverse proxy template.";
        };

        public = mkOption {
          type = types.bool;
          default = false;
          description = "Whether the virtual host should be publicly accessible.";
        };

        dnsRecord = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to include this virtual host in managed DNS records.";
        };

        dnsChallenge = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable DNS-01 TLS for this host (provider-specific in proxy module).";
        };

        serverAliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional hostnames served by this virtual host.";
        };

        extraConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Additional reverse proxy config appended to this virtual host.";
        };
      };
    }));
    default = { };
    description = "Agnostic virtual host definitions used by reverse proxy modules.";
  };
}
