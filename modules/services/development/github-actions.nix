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
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu9lBREFqV8dhEoTjma/muYKgs6nsjcKW3FVhe+t0Nu github-actions@david-nixos";
      description = "SSH public key for GitHub Actions";
    };
  };

  config = mkIf cfg.enable {
    # GitHub Actions user for automated deployments
    users.users.github-actions = {
      isNormalUser = true;
      description = "GitHub Actions user for automated deployments";
      home = "/home/github-actions";
      shell = pkgs.bash;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ cfg.sshKey ];
    };

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

