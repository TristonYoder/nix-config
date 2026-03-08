{ config, lib, ... }:

with lib;
let
  cfg = config.modules.system.remote-builder;
in
{
  options.modules.system.remote-builder = {
    enable = mkEnableOption "Distributed Nix builds (offload to remote builder)";

    buildHost = mkOption {
      type = types.str;
      default = "david";
      description = "Hostname of the remote build machine (reachable via Tailscale)";
    };

    maxJobs = mkOption {
      type = types.int;
      default = 8;
      description = "Maximum number of concurrent build jobs on the remote builder";
    };

    speedFactor = mkOption {
      type = types.int;
      default = 10;
      description = "Speed factor for the remote builder (higher = preferred over local builds)";
    };

    systems = mkOption {
      type = types.listOf types.str;
      default = [ "x86_64-linux" ];
      description = "Systems the remote builder can build for";
    };

    supportedFeatures = mkOption {
      type = types.listOf types.str;
      default = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
      description = "Supported features of the remote builder";
    };

    sshKeyFile = mkOption {
      type = types.path;
      default = config.age.secrets.nix-builder-key.path;
      description = "Path to the SSH private key for connecting to the remote builder";
    };
  };

  config = mkIf cfg.enable {
    nix.distributedBuilds = true;

    nix.buildMachines = [{
      hostName = cfg.buildHost;
      protocol = "ssh-ng";
      sshUser = "nix-ssh";
      sshKey = cfg.sshKeyFile;
      systems = cfg.systems;
      maxJobs = cfg.maxJobs;
      speedFactor = cfg.speedFactor;
      supportedFeatures = cfg.supportedFeatures;
    }];

    nix.settings.builders-use-substitutes = true;
  };
}
