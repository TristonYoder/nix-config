{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.github-actions;
in
{
  options.modules.services.development.github-actions = {
    enable = mkEnableOption "GitHub Actions CI/CD integration";
    
    sshKey = mkOption {
      type = types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu9lBREFqV8dhEoTjma/muYKgs6nsjcKW3FVhe+t0Nu github-actions@nix-config";
      description = "SSH public key for GitHub Actions";
    };
  };

  config = mkIf cfg.enable {
    # GitHub Actions group
    users.groups.github-actions = {};

    # GitHub Actions user for automated deployments
    users.users.github-actions = {
      isSystemUser = true;
      description = "GitHub Actions user for automated deployments";
      home = "/home/github-actions";
      shell = pkgs.bash;
      group = "github-actions";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ cfg.sshKey ];
    };

    # Keep the deploy account out of the graphical login screen. isSystemUser
    # normally allocates a UID below SDDM's MinimumUid (1000) so it's hidden
    # anyway, but hosts where the account predates isSystemUser kept a
    # grandfathered UID above 1000 (david is uid 1001) and would otherwise
    # show it as a pickable user. Inert on hosts that don't run SDDM.
    services.displayManager.sddm.settings.Users.HideUsers = "github-actions";

    # Sudo permissions for GitHub Actions user
    security.sudo.extraRules = [
      {
        users = [ "github-actions" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/backups/nixos 755 root root -"
      "d /var/log 755 root root -"
      "f /var/log/nixos-deploy.log 644 root root -"
    ];

    # Required packages
    environment.systemPackages = with pkgs; [
      rsync
      dnsutils
      git
      bash
    ];
  };
}

