{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.githubRunner;

  runnerModule = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = ''
          Repository or organization URL to register this runner against.
          Use an org URL (e.g. "https://github.com/TristonYoder") only if
          `tokenFile` contains an org-wide token — a repo-scoped token needs
          the full repo URL.
        '';
        example = "https://github.com/TristonYoder/stagePlotiphar";
      };

      tokenFile = mkOption {
        type = types.path;
        description = ''
          Path to a file containing a GitHub fine-grained PAT (preferred,
          auto-refreshes registration tokens) or a one-hour runner
          registration token. Never inline the token value — see
          modules/secrets.nix for the agenix pattern.
        '';
      };

      extraLabels = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra labels for this runner, in addition to the defaults.";
      };

      replace = mkOption {
        type = types.bool;
        default = true;
        description = "Replace any existing runner registered under the same name.";
      };

      ephemeral = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Deregister and reconfigure after every job. Only safe when
          `tokenFile` contains a PAT — a one-hour registration token will
          fail to re-register after it expires.
        '';
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Extra packages available on PATH to workflow jobs.";
      };

      dockerAccess = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Put the `docker` CLI on PATH and add the runner's (dynamic) user to
          the `docker` group so workflow jobs can build/run containers.
          Requires `virtualisation.docker.enable` on this host. Note the
          `docker` group is effectively root-equivalent via the socket —
          same trust level as this repo's other CI automation.
        '';
      };
    };
  };
in
{
  options.modules.services.development.githubRunner = {
    enable = mkEnableOption "Self-hosted GitHub Actions runner(s)";

    runners = mkOption {
      type = types.attrsOf runnerModule;
      default = { };
      description = "Named self-hosted runner instances to register on this host.";
      example = literalExpression ''
        {
          stageplotiphar = {
            url = "https://github.com/TristonYoder/stagePlotiphar";
            tokenFile = config.age.secrets.github-runner-stageplotiphar-token.path;
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = mapAttrsToList
      (name: runner: {
        assertion = !runner.dockerAccess || config.virtualisation.docker.enable;
        message = ''modules.services.development.githubRunner.runners."${name}".dockerAccess requires virtualisation.docker.enable on this host.'';
      })
      cfg.runners;

    services.github-runners = mapAttrs
      (name: runner: {
        enable = true;
        url = runner.url;
        tokenFile = runner.tokenFile;
        extraLabels = runner.extraLabels;
        replace = runner.replace;
        ephemeral = runner.ephemeral;
        extraPackages = with pkgs; [ nix git ]
          ++ optionals runner.dockerAccess [ config.virtualisation.docker.package pkgs.docker-compose ]
          ++ runner.extraPackages;
        serviceOverrides = mkIf runner.dockerAccess {
          SupplementaryGroups = [ "docker" ];
        };
      })
      cfg.runners;
  };
}
