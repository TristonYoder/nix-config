# Configuration for tyoder-mbp - macOS MacBook Pro (Apple Silicon)
# Friendly name: Triston's TPCC MacBook Pro
# Uses nix-darwin for system configuration

{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/darwin/github-runner.nix
  ];

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "tyoder-mbp";
  networking.localHostName = "tyoder-mbp";
  networking.computerName = "Triston Yoder's MacBook Pro";

  # =============================================================================
  # USER CONFIGURATION
  # =============================================================================

  users.users.tyoder = {
    name = "tyoder";
    home = "/Users/tyoder";
    shell = pkgs.zsh;
  };

  # Set primary user for system defaults
  system.primaryUser = "tyoder";

  # =============================================================================
  # SELF-HOSTED GITHUB ACTIONS RUNNER
  # =============================================================================

  modules.services.development.githubRunner = {
    enable = true;
    runners.stageplotiphar = {
      url = "https://github.com/TristonYoder/stagePlotiphar";
      tokenFile = "/Users/tyoder/.config/github-runners/stageplotiphar.token";
    };
  };
}

