{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.gitlabRunner;
in
{
  options.modules.services.development.gitlabRunner = {
    enable = mkEnableOption "GitLab Runner (CI/CD job executor)";

    concurrent = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum number of jobs running concurrently across all registered runners.";
    };

    pruneDockerCache = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Periodically run `docker system prune` for the runner's Docker
        resources. Docker executor + Docker-in-Docker builds accumulate
        images/layers over time; this keeps disk usage in check.
      '';
    };

    pruneDockerCacheSchedule = mkOption {
      type = types.str;
      default = "weekly";
      description = "systemd.time(7) calendar spec for the Docker cache prune timer.";
    };

    # GitLab >= 17 has removed *registration tokens* — the only supported
    # workflow now is *runner authentication tokens*: create the runner in
    # the GitLab UI first (Admin Area, or a group/project's CI/CD settings
    # > Runners > "New instance/group/project runner"), which is also where
    # you set tags, protected-branches-only, and run-untagged-jobs — none of
    # that is configurable from Nix anymore for token-based runners. GitLab
    # then shows you a token once; that's what tokenFile below points to.
    runners = mkOption {
      default = { };
      description = ''
        Runner instances to register. Each key is a systemd unit-name-safe
        runner name.

        For anything not covered by these options (preBuildScript,
        dockerAllowedImages, custom environment variables, ...), set
        services.gitlab-runner.services.<name>.<option> directly — this
        wrapper only covers the common path.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            tokenFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to a file with two lines:
                  CI_SERVER_URL=https://git.7co.dev
                  CI_SERVER_TOKEN=<runner authentication token>
                Generate the token in the GitLab UI when creating this
                runner, then encrypt this file with agenix (see secrets/README.md).
              '';
            };

            executor = mkOption {
              type = types.str;
              default = "docker";
              description = "gitlab-runner executor (docker, shell, etc).";
            };

            dockerImage = mkOption {
              type = types.nullOr types.str;
              default = "debian:stable";
              description = ''
                Default image for jobs on this runner (only used by
                Docker-family executors). Individual pipelines can still
                override this per-job with `image:` in .gitlab-ci.yml.
              '';
            };

            dockerPrivileged = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Give job containers extended privileges. Required for
                Docker-in-Docker image builds (a `docker:dind` service in
                .gitlab-ci.yml). This is a real container-escape risk on a
                shared host — only set true for runners you trust with CI
                content that builds images.
              '';
            };

            dockerVolumes = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "/var/run/docker.sock:/var/run/docker.sock" ];
              description = "Extra bind mounts for job containers.";
            };

            limit = mkOption {
              type = types.int;
              default = 0;
              description = "Max concurrent jobs on this specific runner. 0 = unlimited (bounded only by the global concurrent setting).";
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    services.gitlab-runner = {
      enable = true;
      settings.concurrent = cfg.concurrent;

      services = mapAttrs (_: r: {
        authenticationTokenConfigFile = r.tokenFile;
        executor = r.executor;
        dockerImage = r.dockerImage;
        dockerPrivileged = r.dockerPrivileged;
        dockerVolumes = r.dockerVolumes;
        limit = r.limit;
      }) cfg.runners;

      clear-docker-cache = mkIf cfg.pruneDockerCache {
        enable = true;
        dates = cfg.pruneDockerCacheSchedule;
      };
    };
  };
}
