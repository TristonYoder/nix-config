{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.users;
in
{
  options.modules.system.users = {
    enable = mkEnableOption "User account configuration";

    useDataDrive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Symlink /home/username to /data/username/home.
        Enable on hosts with a separate /data partition (e.g., servers with ZFS).
      '';
    };

    enableSshAgentSudo = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Allow sudo to authenticate via a forwarded/local SSH agent key (pam_ssh_agent_auth)
        instead of a Unix password, using mainUser.sshKeys as the trusted key list.
        Lets a fresh host with no password ever set still be administered remotely over SSH.
      '';
    };

    mainUser = {
      name = mkOption {
        type = types.str;
        default = "tristonyoder";
        description = "Main user account name";
      };

      uid = mkOption {
        type = types.int;
        default = 1000;
        description = ''
          Fixed UID, pinned so it's identical on every host. Without this,
          NixOS auto-assigns UIDs in user-creation order, which can silently
          diverge per host (confirmed: tristons-workstation assigned 1001
          while every other host has 1000) and breaks NFS (sec=sys checks
          raw numeric UID, not username — a mismatch causes "permission
          denied" reading a perfectly valid, correctly-owned directory).

          Only affects NEW accounts: NixOS's user activation refuses to
          change the UID of an account that already exists (logs a
          "not applying UID change" warning instead). A host whose UID has
          already drifted needs a one-time manual fix before rebuilding:
          `sudo usermod -u <uid> <name>` (and chown any locally-owned files
          if the account has real local data, not just an NFS-backed home).
        '';
      };

      description = mkOption {
        type = types.str;
        default = "Triston Yoder";
        description = "User description/full name";
      };

      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [ "networkmanager" "wheel" "docker" "nextcloud" ];
        description = "Additional groups for main user";
      };

      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          firefox
          bitwarden-desktop
          vscode
          _1password-gui
          _1password-cli
          compose2nix
        ];
        description = "Packages for main user";
      };

      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDv25/0nLCy/VRqOYPu10PA5lUcireG1GEUk1+mFMPbL7q7o+9GqJ8INhlncvd6tc5sm5ZblK5aqrZxKW8Cy78OZpPfPTyVWVIcxos+SWba1Fbi+Xco0ZT3BqRvCcgkLM/jCIVfr5Hzo2iP5lvt21KN2OY7XpwlqdCfmZyyjwPGwFfniEbwvHZSaxgSllXqTcLrpYt75ryn58T7HKF0m7vCGguct62UtKibLUw0jsgFk5rbXGqggGOH7W/Gg0gnzCN5eB3azbpFvRMW106lMz7iXIy1ZyfeQrGATH+TlEgYsU/ROk2LSQOun99DqJOAts6ZaeFu5+VDsJh0S17tIud5"
        ];
        description = "SSH public keys for main user";
      };
    };
  };

  config = mkIf cfg.enable {
    security.pam.sshAgentAuth = mkIf cfg.enableSshAgentSudo {
      enable = true;
      authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    };

    security.pam.services.sudo.sshAgentAuth = mkIf cfg.enableSshAgentSudo true;

    # sudo's `env_reset` strips SSH_AUTH_SOCK before PAM auth even runs, so
    # pam_ssh_agent_auth never sees a forwarded agent to check against —
    # `sudo -A`/agent forwarding silently falls through to "a password is
    # required" with no indication the agent was ever consulted. Without
    # this, enableSshAgentSudo only works for local console logins, not the
    # remote-SSH-administration case it's actually meant for.
    security.sudo.extraConfig = mkIf cfg.enableSshAgentSudo ''
      Defaults env_keep += "SSH_AUTH_SOCK"
    '';

    users.users.${cfg.mainUser.name} = {
      isNormalUser = true;
      uid = cfg.mainUser.uid;
      description = cfg.mainUser.description;
      extraGroups = cfg.mainUser.extraGroups;
      packages = cfg.mainUser.packages;
      openssh.authorizedKeys.keys = cfg.mainUser.sshKeys;
      home = "/home/${cfg.mainUser.name}";
      # On useDataDrive hosts, tmpfiles creates /home/<user> as an L+ symlink.
      # createHome = true (the isNormalUser default) would conflict — activation
      # tries mkdir on the path that already exists as a symlink, exiting with 17.
      createHome = !cfg.useDataDrive;
    };

    # Caroline Yoder user account (on all desktop/laptop/workstation hosts)
    # uid pinned to match david (1002) for the same NFS reason as mainUser.uid above.
    users.users.carolineyoder = mkIf config.modules.system.desktop.enable {
      isNormalUser = true;
      uid = 1002;
      description = "Caroline Yoder";
      extraGroups = [ "nextcloud" ];
      packages = with pkgs; [
        firefox
        bitwarden-desktop
        _1password-gui
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"  # Same key as tristonyoder for now
      ];
      home = "/home/carolineyoder";
      # On useDataDrive hosts, tmpfiles creates /home/carolineyoder as an L+ symlink;
      # createHome would conflict. On regular desktop hosts, let NixOS create it normally.
      createHome = !cfg.useDataDrive;
    };

    # Data drive setup: symlink /home to /data for persistent storage
    systemd.tmpfiles.rules = mkIf cfg.useDataDrive [
      # Main data directory
      "d /data 0755 root root -"

      # User directories with nextcloud group access
      "d /data/tristonyoder 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder 0755 carolineyoder nextcloud -"

      # Actual home directories on data drive
      "d /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder/home 0755 carolineyoder nextcloud -"

      # Symlinks from standard /home paths to data drive
      # L+ creates symlink, replacing existing file/directory if needed
      "L+ /home/tristonyoder - - - - /data/tristonyoder/home"
      "L+ /home/carolineyoder - - - - /data/carolineyoder/home"

      # Ensure proper permissions on data directories
      "Z /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "Z /data/carolineyoder/home 0755 carolineyoder nextcloud -"
    ];

  };
}

