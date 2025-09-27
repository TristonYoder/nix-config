# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, lib, nixpkgs, nixpkgs-unstable, nix-bitcoin, ... }:
{
  # Note: Imports are now handled by the flake.nix file
  # This allows for better modularity and flake-based dependency management

  # Nix Flakes
  nix = {
    settings = {
        experimental-features = [ "nix-command" "flakes" ];
        warn-dirty = false;
    };
    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 90d";
    };
  };

  # Caddy
  # modules.caddy.enable = true;

  # Graphics Card
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };


  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 50;  # Keep only last 50 generations
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.splashMode = "normal";
  # boot.loader.grub.splashImage = 
  boot.loader.grub.backgroundColor = "#8275b4";
  boot.loader.grub.theme = "${pkgs.libsForQt5.breeze-grub}/grub/themes/breeze";
  boot.loader.grub.extraEntriesBeforeNixOS = true;



  # # Allow SSH for zfs auth
  # boot = {
  #   initrd.network = {
  #     enable = true;
  #     ssh = {
  #       enable = true;
  #       # To prevent ssh clients from freaking out because a different host key is used,
  #       # a different port for ssh is useful (assuming the same host has also a regular sshd running)
  #       port = 2222; 
  #       # hostKeys paths must be unquoted strings, otherwise you'll run into issues with boot.initrd.secrets
  #       # the keys are copied to initrd from the path specified; multiple keys can be set
  #       # you can generate any number of host keys using 
  #       # `ssh-keygen -t ed25519 -N "" -f /path/to/ssh_host_ed25519_key`
  #       hostKeys = [ /etc/ssh/ssh_host_rsa_key ];
  #       # public ssh key used for login
  #       authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz" ];
  #     };
  #   };
  # };

  networking.hostName = "david"; # Define your hostname.
  networking.domain = "theyoder.family";

  # Enable networking
  networking.networkmanager.enable = true;
  
  # Set your time zone.
  time.timeZone = "America/Indiana/Indianapolis";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma6.enable = true;
  services.desktopManager.plasma6.enable = true;

  # # Configure keymap in X11
  # services.xserver.xkb = {
  #   layout = "us";
  #   Variant = "";
  # };
  
#  # Enable RDP
#  services.xrdp = {
#    enable = true;
#    defaultWindowManager = "startplasma-x11";
#    openFirewall = true;
#  };

#  # Enable CUPS to print documents.
#  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.tristonyoder = {
    isNormalUser = true;
    description = "Triston Yoder";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
      firefox
      bitwarden-desktop
      vscode
      _1password-gui
      _1password-cli
      compose2nix
      # pkgs.audiobookshelf
    #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    gh
    git
    zsh
    quickemu
  ];

  # Set zsh as the default shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  # TODO: nixify this: https://github.com/TristonYoder/zsh_powerline_install
  ## Maybe go with oh-my-posh instead?

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 111 2049 3389 4000 4001 4002 20048 8234 ];
  networking.firewall.allowPing = true;
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-23.11/";
  
  # Note: system.copySystemConfiguration is not supported with flakes
  # Configuration is managed through the flake system instead
  # Prior system generations are still stored in:
  # /nix/var/nix/profiles/system-X-link/configuration.nix 
}
