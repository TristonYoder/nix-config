{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.mas;
  mas = "${pkgs.mas}/bin/mas";
in
{
  options.mas = {
    enable = mkEnableOption "Mac App Store package management via mas";

    onActivation = {
      autoUpdate = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to auto update App Store apps on activation";
      };
      cleanup = mkOption {
        type = types.enum [ "uninstall" "none" ];
        default = "uninstall";
        description = "What to do with unmanaged apps: 'uninstall' (remove unmanaged apps), 'none' (no cleanup)";
      };
    };

    apps = mkOption {
      type = types.listOf (types.submodule {
        options = {
          id = mkOption {
            type = types.str;
            description = "Mac App Store app ID";
          };
          name = mkOption {
            type = types.str;
            description = "Human-readable app name";
          };
        };
      });
      default = [ ];
      description = "Mac App Store apps to install";
    };
  };

  config = mkIf cfg.enable {
    home.activation = {
      installMasApps = lib.hm.dag.entryAfter ["installPackages"] ''
        $DRY_RUN_CMD echo "Installing Mac App Store apps via mas..."
        
        # Ensure mas is available
        MAS_CMD="${mas}"
        if ! "$MAS_CMD" list &> /dev/null; then
          $DRY_RUN_CMD echo "mas not found, skipping App Store app installation"
          exit 0
        fi
        
        # Install each configured app if not already installed
        ${concatMapStringsSep "\n" (app: ''
          $DRY_RUN_CMD echo "Checking if ${app.name} (${app.id}) is installed..."
          
          if ! "$MAS_CMD" list | grep -q "^${app.id}"; then
            $DRY_RUN_CMD echo "Installing ${app.name} (${app.id})..."
            $DRY_RUN_CMD ${mas} install "${app.id}" || {
              $DRY_RUN_CMD echo "Failed to install ${app.name} (${app.id})"
              # Continue with other apps even if one fails
            }
          else
            $DRY_RUN_CMD echo "${app.name} is already installed"
          fi
        '') cfg.apps}
        
        $DRY_RUN_CMD echo "Mac App Store app installation complete"
      '';

      cleanupMasApps = lib.hm.dag.entryAfter ["installMasApps"] ''
        ${if cfg.onActivation.cleanup == "uninstall" then ''
          $DRY_RUN_CMD echo "Cleaning up unmanaged Mac App Store apps..."
          
          # Ensure mas is available
          MAS_CMD="${mas}"
          if ! "$MAS_CMD" list &> /dev/null; then
            $DRY_RUN_CMD echo "mas not found, skipping App Store app cleanup"
            exit 0
          fi
          
          # Get list of managed app IDs
          MANAGED_APPS="${concatStringsSep " " (map (app: app.id) cfg.apps)}"
          
          # Get all installed apps and check against managed list
          "$MAS_CMD" list | while read -r line; do
            app_id=$(echo "$line" | ${pkgs.gawk}/bin/awk '{print $1}')
            app_name=$(echo "$line" | cut -d' ' -f2-)
            
            # Skip if this app is in our managed list
            if [[ " $MANAGED_APPS " =~ " $app_id " ]]; then
              $DRY_RUN_CMD echo "Keeping managed app: $app_name ($app_id)"
            else
              $DRY_RUN_CMD echo "Removing unmanaged app: $app_name ($app_id)"
              $DRY_RUN_CMD ${mas} uninstall "$app_id" || {
                $DRY_RUN_CMD echo "Failed to uninstall $app_name ($app_id)"
                # Continue with other apps even if one fails
              }
            fi
          done
        '' else ''
          $DRY_RUN_CMD echo "Skipping Mac App Store app cleanup (cleanup = none)"
        ''}
      '';

      updateMasApps = lib.hm.dag.entryAfter ["cleanupMasApps"] ''
        ${if cfg.onActivation.autoUpdate then ''
          $DRY_RUN_CMD echo "Updating Mac App Store apps..."
          
          # Ensure mas is available
          MAS_CMD="${mas}"
          if ! "$MAS_CMD" list &> /dev/null; then
            $DRY_RUN_CMD echo "mas not found, skipping App Store app updates"
            exit 0
          fi
          
          $DRY_RUN_CMD ${mas} upgrade
        '' else ''
          $DRY_RUN_CMD echo "Skipping Mac App Store app updates (autoUpdate = false)"
        ''}
      '';
    };
  };
}
