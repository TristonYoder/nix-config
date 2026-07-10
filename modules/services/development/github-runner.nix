{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.githubRunner;

  runnerModule = types.submodule {
    options = {
      backend = mkOption {
        type = types.enum [ "native" "container" ];
        default = "native";
        description = ''
          "native": persistent systemd service (services.github-runners) —
          long-lived install/work directory, state persists across jobs.

          "container": ephemeral Docker container (myoung34/github-runner)
          that deregisters itself after each job. systemd's default
          Restart=always then starts a brand-new container for the next
          job, so every job gets a clean filesystem. Requires
          virtualisation.oci-containers.backend = "docker".
        '';
      };

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
        description = "Replace any existing runner registered under the same name. Native backend only.";
      };

      ephemeral = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Deregister and reconfigure after every job. Only safe when
          `tokenFile` contains a PAT — a one-hour registration token will
          fail to re-register after it expires. Native backend only — the
          container backend is always ephemeral by design.
        '';
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Extra packages available on PATH to workflow jobs. Native backend only.";
      };

      dockerAccess = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Native backend: puts `docker` CLI on PATH and adds the runner's
          (dynamic) user to the `docker` group so jobs can build/run
          containers. Container backend: bind-mounts the host docker socket
          into the runner container (docker-outside-of-docker). Either way
          requires `virtualisation.docker.enable` on this host. Note this is
          effectively root-equivalent host access via the socket — same
          trust level as this repo's other CI automation.
        '';
      };

      containerImage = mkOption {
        type = types.str;
        default = "ghcr.io/myoung34/github-runner:ubuntu-noble";
        description = "Image to use when backend = \"container\".";
      };
    };
  };

  nativeRunners = filterAttrs (_: r: r.backend == "native") cfg.runners;
  containerRunners = filterAttrs (_: r: r.backend == "container") cfg.runners;

  containerEnvFile = name: "/run/github-runner-container-${name}.env";
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
          stageplotiphar-native = {
            url = "https://github.com/TristonYoder/stagePlotiphar";
            tokenFile = config.age.secrets.github-runner-stageplotiphar-token.path;
          };
          stageplotiphar-clean = {
            backend = "container";
            url = "https://github.com/TristonYoder/stagePlotiphar";
            tokenFile = config.age.secrets.github-runner-stageplotiphar-token.path;
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions =
      (mapAttrsToList
        (name: runner: {
          assertion = !runner.dockerAccess || config.virtualisation.docker.enable;
          message = ''modules.services.development.githubRunner.runners."${name}".dockerAccess requires virtualisation.docker.enable on this host.'';
        })
        cfg.runners)
      ++ (mapAttrsToList
        (name: _: {
          assertion = config.virtualisation.oci-containers.backend == "docker";
          message = ''modules.services.development.githubRunner.runners."${name}": backend = "container" requires virtualisation.oci-containers.backend = "docker".'';
        })
        containerRunners);

    # ── Native backend: persistent systemd-managed runner ─────────────────
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
      nativeRunners;

    # ── Container backend: ephemeral runner, fresh container per job ──────
    virtualisation.oci-containers.containers = mapAttrs
      (name: runner: {
        image = runner.containerImage;
        autoStart = true;
        environment = {
          RUNNER_SCOPE = "repo";
          REPO_URL = runner.url;
          RUNNER_NAME = name;
          RANDOM_RUNNER_SUFFIX = "false";
          EPHEMERAL = "true";
          DISABLE_AUTO_UPDATE = "true";
          RUN_AS_ROOT = "true";
          LABELS = concatStringsSep "," (runner.extraLabels ++ [ "ephemeral-container" ]);
        };
        # ACCESS_TOKEN/RUNNER_TOKEN come from a runtime-generated env file
        # (see systemd preStart below), never from the Nix store.
        environmentFiles = [ (containerEnvFile name) ];
        volumes = optional runner.dockerAccess "/var/run/docker.sock:/var/run/docker.sock";
      })
      containerRunners;

    # Regenerate the container's token env file on every (re)start — systemd's
    # default Restart=always for oci-containers means this runs before each
    # job's fresh container, same as the native backend's ExecStartPre.
    systemd.services = mapAttrs'
      (name: runner: nameValuePair "docker-${name}" {
        preStart = ''
          set -euo pipefail
          token=$(cat ${escapeShellArg runner.tokenFile})
          envfile=${escapeShellArg (containerEnvFile name)}
          if [[ "$token" == ghp_* || "$token" == github_pat_* ]]; then
            printf 'ACCESS_TOKEN=%s\n' "$token" > "$envfile"
          else
            printf 'RUNNER_TOKEN=%s\n' "$token" > "$envfile"
          fi
          chmod 600 "$envfile"
        '';
      })
      containerRunners;
  };
}
