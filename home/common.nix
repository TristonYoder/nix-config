# Common Home Manager Configuration
# Shared settings across all users and platforms

{ config, pkgs, lib, ... }:

let
  # Platform detection
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  # Note: nixpkgs.config options are set globally via home-manager.useGlobalPkgs
  # Do not set nixpkgs.config here to avoid conflicts
  
  # Shared packages across all platforms
  home.packages = with pkgs; [
    # Development tools
    git
    gh
    compose2nix
    
    # Utilities
    wget
    curl
    ffmpeg
    zsh
    
    # Optional: 1Password CLI
    _1password-cli
  ] ++ (if isDarwin then [
    # macOS-only packages
    mas  # Mac App Store CLI
  ] else []);
  
  # Common environment variables
  home.sessionVariables = {
    # Terminal and locale settings
    TERM = "xterm-256color";
    LC_ALL = "en_US.UTF-8";
    LANG = "en_US.UTF-8";
    
    # Oh My Zsh settings
    DISABLE_UPDATE_PROMPT = "true";
    
    # Editor
    EDITOR = "cursor";
  };
  
  # Add local bin to PATH
  home.sessionPath = [
    "$HOME/.local/bin"
  ];
  
  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
  
  # =============================================================================
  # GIT CONFIGURATION
  # =============================================================================
  
  programs.git = {
    enable = true;
  } // (if isDarwin then {
    # Darwin uses home-manager-unstable which supports the new settings format
    settings = {
      user.name = "Triston Yoder";
      user.email = "triston@7co.dev";
      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;
      core.editor = "cursor";
      core.autocrlf = "input";
      credential.helper = "osxkeychain";
    };
  } else {
    # NixOS uses home-manager release-25.05 which may not support settings yet
    # Using deprecated format for backward compatibility
    userName = "Triston Yoder";
    userEmail = "triston@7co.dev";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;
      core.editor = "cursor";
      core.autocrlf = "input";
    };
  });
  
  # =============================================================================
  # ZSH CONFIGURATION
  # =============================================================================
  
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
      ".." = "cd ..";
      "..." = "cd ../..";
      grep = "grep --color=auto";
      fgrep = "fgrep --color=auto";
      egrep = "egrep --color=auto";
      h = "history";
      j = "jobs -l";
      which = "type -a";
      path = "echo -e $PATH | tr ':' '\\n'";
      now = "date";
      nowtime = "date +%T";
      nowdate = "date +%d-%m-%Y";
      ports = "netstat -tulanp";
      myip = "curl -s https://ipinfo.io/ip";
      weather = "curl -s wttr.in";
      
      # Nix rebuild aliases (with auto-reload for darwin)
      rebuild = "sudo nixos-rebuild switch --flake ~/Projects/nix-config";
      rebuild-darwin = "sudo darwin-rebuild switch --flake ~/Projects/nix-config && exec zsh";
      rebuild-home = "home-manager switch --flake ~/Projects/nix-config && exec zsh";
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "docker"
        "docker-compose"
        "kubectl"
        "helm"
        "aws"
        "terraform"
        "vscode"
      ];
      theme = "powerlevel10k/powerlevel10k";
      custom = "$HOME/.oh-my-zsh/custom";
    };
    
    initContent = ''
      # Powerlevel10k instant prompt
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
      
      # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
  };
  
  # Powerlevel10k configuration
  home.file.".p10k.zsh".source = ./p10k.zsh;
  
  # =============================================================================
  # SSH CONFIGURATION
  # =============================================================================
  
  programs.ssh = {
    enable = true;
  } // (if isDarwin then {
    # Darwin uses home-manager-unstable which supports the new matchBlocks format
    enableDefaultConfig = false;
    matchBlocks."*" = {
      # home-manager expects a string (e.g. "yes") or null for addKeysToAgent in this
      # compatible configuration; avoid a bare boolean which fails type-checking.
      addKeysToAgent = "yes";
      identityFile = "~/.ssh/id_ed25519";
      extraOptions = {
        UseKeychain = "yes";
      };
    };
  } else {
    # NixOS uses home-manager release-25.05 which may not support matchBlocks yet
    # Using deprecated format for backward compatibility
    addKeysToAgent = "yes";
    extraConfig = ''
      Host *
        AddKeysToAgent yes
        IdentityFile ~/.ssh/id_ed25519
    '';
  });
  
  # =============================================================================
  # ACTIVATION SCRIPTS
  # =============================================================================
  
  # Install Powerlevel10k theme
  home.activation.installPowerlevel10k = lib.hm.dag.entryAfter ["installPackages"] ''
    verboseEcho "Installing Powerlevel10k theme..."
    
    # Create Oh My Zsh custom directory if it doesn't exist
    run mkdir -p ${config.home.homeDirectory}/.oh-my-zsh/custom/themes
    
    # Clone Powerlevel10k if not already present
    if [[ ! -d "${config.home.homeDirectory}/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
      verboseEcho "Cloning Powerlevel10k theme..."
      run ${pkgs.git}/bin/git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${config.home.homeDirectory}/.oh-my-zsh/custom/themes/powerlevel10k"
    else
      verboseEcho "Powerlevel10k theme already installed, updating..."
      run cd "${config.home.homeDirectory}/.oh-my-zsh/custom/themes/powerlevel10k" && run ${pkgs.git}/bin/git pull
    fi
  '';
}

