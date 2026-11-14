# Configuration for Julia-NixBook-Air - MacBook Air 2013 (MacBookAir6,x)
#
# Desktop profile (not workstation: no Steam/Resolve on this hardware).
# juliayoder is the only account, with no password: SDDM logs in
# automatically and the lock screen unlocks with an empty password.
#
# Remote admin: Triston's SSH keys are on juliayoder (mainUser.sshKeys
# default) and sudo authenticates via the forwarded SSH agent
# (enableSshAgentSudo). Local sudo doesn't work, since pam_unix for sudo
# rejects an empty password.
#
# Install from the julia-nixbook-air-installer ISO:
#   parted /dev/sda -- mklabel gpt
#   parted /dev/sda -- mkpart ESP fat32 1MiB 1GiB
#   parted /dev/sda -- set 1 esp on
#   parted /dev/sda -- mkpart root ext4 1GiB 100%
#   mkfs.fat -F 32 -n BOOT /dev/sda1
#   mkfs.ext4 -L nixos /dev/sda2
#   mount /dev/disk/by-label/nixos /mnt
#   mount --mkdir -o umask=077 /dev/disk/by-label/BOOT /mnt/boot
#   nixos-install --no-root-passwd --flake 'github:TristonYoder/nix-config#Julia-NixBook-Air' --refresh

{ config, pkgs, lib, ... }:
let
  user = config.modules.system.users.mainUser.name;
in
{
  imports = [ ./broadcom-wl.nix ];

  networking.hostName = "Julia-NixBook-Air";
  system.stateVersion = "26.05";

  # =============================================================================
  # USER
  # =============================================================================

  modules.system.users = {
    mainUser = {
      name = "juliayoder";
      # Distinct from tristonyoder (1000) and carolineyoder (1002) in case this
      # host ever mounts david's NFS shares, which match on numeric UID.
      uid = 1003;
      description = "Julia Yoder";
      extraGroups = [ "networkmanager" "wheel" ];
    };
    carolineyoder.enable = false;
  };

  users.users.${user}.hashedPassword = "";

  services.displayManager.autoLogin = {
    enable = true;
    inherit user;
  };

  # Empty password works at the console/greeter and on the Plasma lock screen.
  security.pam.services.login.allowNullPassword = true;
  security.pam.services.kde.allowNullPassword = true;

  home-manager.users.${user}.modules.plasma.enable = true;

  # =============================================================================
  # HARDWARE
  # =============================================================================

  # Apple SMC fan control -- the default firmware curve runs the Air hot.
  services.mbpfan.enable = true;

  # =============================================================================
  # PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [ firefox ];
}
