{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.homebrew;
  # Homebrew is in /usr/local on Intel and /opt/homebrew on Apple Silicon
  brew = if pkgs.stdenv.isAarch64 then "/opt/homebrew/bin/brew" else "/usr/local/bin/brew";
in
{
  options.homebrew = {
    enable = mkEnableOption "Homebrew package management";

    onActivation = {
      autoUpdate = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to auto update Homebrew on activation";
      };
    cleanup = mkOption {
      type = types.enum [ "zap" "uninstall" "smart" "none" ];
      default = "smart";
      description = "What to do with unmanaged packages: 'zap' (remove completely), 'uninstall' (uninstall only), 'smart' (remove only orphaned packages), 'none' (no cleanup)";
    };
    };

    taps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Homebrew taps to install";
    };

    brews = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Homebrew formulas to install";
    };

    casks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Homebrew casks to install";
    };
  };

  config = mkIf cfg.enable {
    home.activation = {
      installHomebrewTaps = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD echo "Installing Homebrew taps..."
        for tap in ${concatStringsSep " " cfg.taps}; do
          if ! "$BREW" tap list | grep -q "^$tap"; then
            $DRY_RUN_CMD echo "Installing tap: $tap"
            $DRY_RUN_CMD "$BREW" tap "$tap"
          else
            $DRY_RUN_CMD echo "Tap already installed: $tap"
          fi
        done
      '';

      installHomebrewBrews = lib.hm.dag.entryAfter ["installHomebrewTaps"] ''
        $DRY_RUN_CMD echo "Installing Homebrew brews..."
        BREW="$BREW"
        for brew in ${concatStringsSep " " cfg.brews}; do
          if ! "$BREW" list --formula "$brew" &>/dev/null; then
            $DRY_RUN_CMD echo "Installing brew: $brew"
            $DRY_RUN_CMD "$BREW" install "$brew"
          else
            $DRY_RUN_CMD echo "Brew already installed: $brew"
          fi
        done
      '';

      installHomebrewCasks = lib.hm.dag.entryAfter ["installHomebrewBrews"] ''
        $DRY_RUN_CMD echo "Installing Homebrew casks..."
        BREW="$BREW"
        for cask in ${concatStringsSep " " cfg.casks}; do
          if ! "$BREW" list --cask "$cask" &>/dev/null; then
            $DRY_RUN_CMD echo "Installing cask: $cask"
            $DRY_RUN_CMD "$BREW" install --cask "$cask"
          else
            $DRY_RUN_CMD echo "Cask already installed: $cask"
          fi
        done
      '';

      cleanupHomebrew = lib.hm.dag.entryAfter ["installHomebrewCasks"] ''
        ${if cfg.onActivation.cleanup == "smart" then ''
          $DRY_RUN_CMD echo "Smart cleanup: removing only orphaned Homebrew packages..."
          BREW="$BREW"
          
          # Get lists of managed packages
          MANAGED_TAPS="${concatStringsSep " " cfg.taps}"
          MANAGED_BREWS="${concatStringsSep " " cfg.brews}"
          MANAGED_CASKS="${concatStringsSep " " cfg.casks}"
          
          # Remove unmanaged taps (skip core taps)
          for tap in $("$BREW" tap list | cut -d: -f1 | grep -v "^homebrew/core$" | grep -v "^homebrew/cask$"); do
            if [[ ! " $MANAGED_TAPS " =~ " $tap " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged tap: $tap"
              $DRY_RUN_CMD "$BREW" untap "$tap"
            fi
          done
          
          # Smart cleanup: only remove packages that are truly orphaned
          for brew in $("$BREW" list --formula); do
            if [[ ! " $MANAGED_BREWS " =~ " $brew " ]]; then
              # Check if this package is a dependency of other installed packages
              if "$BREW" uses --installed "$brew" --recursive | grep -q .; then
                $DRY_RUN_CMD echo "Keeping $brew (required by other packages)"
              else
                $DRY_RUN_CMD echo "Removing orphaned brew: $brew"
                $DRY_RUN_CMD "$BREW" uninstall --formula "$brew" || true
              fi
            fi
          done
          
          # Remove unmanaged casks (casks don't have dependencies, so safe to remove)
          for cask in $("$BREW" list --cask); do
            if [[ ! " $MANAGED_CASKS " =~ " $cask " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged cask: $cask"
              $DRY_RUN_CMD "$BREW" uninstall --cask "$cask"
            fi
          done
        '' else if cfg.onActivation.cleanup == "zap" then ''
          $DRY_RUN_CMD echo "Cleaning up unmanaged Homebrew packages..."
          BREW="$BREW"
          
          # Get lists of managed packages
          MANAGED_TAPS="${concatStringsSep " " cfg.taps}"
          MANAGED_BREWS="${concatStringsSep " " cfg.brews}"
          MANAGED_CASKS="${concatStringsSep " " cfg.casks}"
          
          # Remove unmanaged taps (skip core taps)
          for tap in $("$BREW" tap list | cut -d: -f1 | grep -v "^homebrew/core$" | grep -v "^homebrew/cask$"); do
            if [[ ! " $MANAGED_TAPS " =~ " $tap " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged tap: $tap"
              $DRY_RUN_CMD "$BREW" untap "$tap"
            fi
          done
          
          # Remove unmanaged brews (safe dependency-aware cleanup)
          for brew in $("$BREW" list --formula); do
            if [[ ! " $MANAGED_BREWS " =~ " $brew " ]]; then
              # Check if this package is a dependency of other installed packages
              if "$BREW" uses --installed "$brew" --recursive | grep -q .; then
                $DRY_RUN_CMD echo "Skipping $brew (required by other packages)"
              else
                $DRY_RUN_CMD echo "Removing unmanaged brew: $brew"
                $DRY_RUN_CMD "$BREW" uninstall --formula "$brew" || true
              fi
            fi
          done
          
          # Remove unmanaged casks (casks don't have dependencies, so safe to remove)
          for cask in $("$BREW" list --cask); do
            if [[ ! " $MANAGED_CASKS " =~ " $cask " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged cask: $cask"
              $DRY_RUN_CMD "$BREW" uninstall --cask "$cask"
            fi
          done
        '' else if cfg.onActivation.cleanup == "uninstall" then ''
          $DRY_RUN_CMD echo "Uninstalling unmanaged Homebrew packages..."
          BREW="$BREW"
          
          # Get lists of managed packages
          MANAGED_TAPS="${concatStringsSep " " cfg.taps}"
          MANAGED_BREWS="${concatStringsSep " " cfg.brews}"
          MANAGED_CASKS="${concatStringsSep " " cfg.casks}"
          
          # Remove unmanaged taps (skip core taps)
          for tap in $("$BREW" tap list | cut -d: -f1 | grep -v "^homebrew/core$" | grep -v "^homebrew/cask$"); do
            if [[ ! " $MANAGED_TAPS " =~ " $tap " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged tap: $tap"
              $DRY_RUN_CMD "$BREW" untap "$tap"
            fi
          done
          
          # Remove unmanaged brews (safe dependency-aware cleanup)
          for brew in $("$BREW" list --formula); do
            if [[ ! " $MANAGED_BREWS " =~ " $brew " ]]; then
              # Check if this package is a dependency of other installed packages
              if "$BREW" uses --installed "$brew" --recursive | grep -q .; then
                $DRY_RUN_CMD echo "Skipping $brew (required by other packages)"
              else
                $DRY_RUN_CMD echo "Removing unmanaged brew: $brew"
                $DRY_RUN_CMD "$BREW" uninstall --formula "$brew" || true
              fi
            fi
          done
          
          # Remove unmanaged casks (casks don't have dependencies, so safe to remove)
          for cask in $("$BREW" list --cask); do
            if [[ ! " $MANAGED_CASKS " =~ " $cask " ]]; then
              $DRY_RUN_CMD echo "Removing unmanaged cask: $cask"
              $DRY_RUN_CMD "$BREW" uninstall --cask "$cask"
            fi
          done
        '' else ''
          $DRY_RUN_CMD echo "Skipping Homebrew cleanup (cleanup = none)"
        ''}
      '';

      updateHomebrew = lib.hm.dag.entryAfter ["cleanupHomebrew"] ''
        ${if cfg.onActivation.autoUpdate then ''
          $DRY_RUN_CMD echo "Updating Homebrew..."
          BREW="$BREW"
          $DRY_RUN_CMD "$BREW" update
        '' else ''
          $DRY_RUN_CMD echo "Skipping Homebrew update (autoUpdate = false)"
        ''}
      '';
    };

    # Set BREW variable for use in activation scripts
    # Use architecture-appropriate path (Intel: /usr/local, Apple Silicon: /opt/homebrew)
    home.activation.setBrewPath = lib.hm.dag.entryBefore ["writeBoundary"] ''
      export BREW="${brew}"
    '';
  };
}