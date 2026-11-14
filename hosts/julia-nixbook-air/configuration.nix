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
  # TAILSCALE
  # =============================================================================

  # Logged in as the juliayoder headscale user. Not a router or exit node.
  # No Tailscale SSH: the headscale SSH policy only lets Triston into his own
  # and tagged nodes, so --ssh would block admin access; plain OpenSSH over
  # the tailnet works with the keys on juliayoder.
  modules.services.infrastructure.tailscale = {
    advertiseExitNode = false;
    advertiseRoutes = "";
    enableSSH = false;
  };

  # =============================================================================
  # HARDWARE
  # =============================================================================

  # Command/Control swap, lid sleep, and mbpfan (the firmware fan curve runs
  # the Air hot under Linux).
  modules.hardware.appleLaptop = {
    enable = true;
    fanControl = true;
  };

  # Panel is 1440x900; the desktop profile's auto-detect would pass
  # video=1920x1080 and run the boot console/splash at the wrong mode.
  modules.hardware.displayResolution.resolution = "1440x900";

  # =============================================================================
  # PACKAGES
  # =============================================================================

  # Workstation-profile apps minus the heavy/dev-only ones. 1Password comes
  # from programs._1password-gui below; Discover from modules.system.flatpak.
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox
    google-chrome
    kdePackages.plasma-browser-integration

    # Media players
    vlc

    # Development tools
    vscode

    # Security & Password Management
    bitwarden-desktop

    # Remote desktop -- client pointed at pits by home/modules/rustdesk.nix
    rustdesk-flutter

    # Terminal
    kitty
    ghostty

    # Notes & Knowledge Management
    obsidian
  ];

  # Module rather than the bare package: wires up the polkit policy and the
  # setgid helper the browser extensions use to talk to the desktop app.
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ user ];
  };

  # Flathub via Discover, so Julia can install her own apps without Nix.
  modules.system.flatpak.enable = true;

  # System-wide Flatpak installs ask polkit for admin auth, which an
  # empty-password account can't pass. Allow Flatpak actions (install,
  # update, uninstall, remotes) for juliayoder only -- nothing else.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id.indexOf("org.freedesktop.Flatpak.") == 0 &&
          subject.user == "${user}") {
        return polkit.Result.YES;
      }
    });
  '';
}
