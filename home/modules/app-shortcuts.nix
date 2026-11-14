{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.appShortcuts;
in
{
  options.modules.appShortcuts = {
    enable = mkEnableOption "KDE app shortcuts generated from the vHosts app manifest";

    manifestUrl = mkOption {
      type    = types.str;
      default = "https://apps-manifest.theyoder.family/apps.json";
      description = "URL to the app manifest JSON served by the app-manifest provider.";
    };

    menuCategory = mkOption {
      type    = types.nullOr types.str;
      default = null;
      example = "theyoder.family";
      description = ''
        Put every generated shortcut in one launcher submenu with this name,
        instead of spreading them across the standard XDG categories.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      # Private XDG category the custom submenu matches on.
      menuXdgCategory = "X-AppShortcuts";

      updateScript = pkgs.writeShellScript "update-app-shortcuts" ''
        set -euo pipefail

        MANIFEST_URL="${cfg.manifestUrl}"
        APPS_DIR="$HOME/.local/share/applications"
        ICONS_DIR="$HOME/.local/share/icons/app-shortcuts"
        PREFIX="app-shortcut-"

        mkdir -p "$APPS_DIR" "$ICONS_DIR"

        manifest=$(${pkgs.curl}/bin/curl -sf --max-time 10 "$MANIFEST_URL") || {
          echo "app-shortcuts: failed to fetch manifest from $MANIFEST_URL" >&2
          exit 0
        }

        # Remove previously managed shortcuts
        rm -f "$APPS_DIR/$PREFIX"*.desktop

        echo "$manifest" | ${pkgs.jq}/bin/jq -r '.apps[] | @base64' | while IFS= read -r encoded; do
          app=$(echo "$encoded" | ${pkgs.coreutils}/bin/base64 -d)

          name=$(echo "$app"      | ${pkgs.jq}/bin/jq -r '.name')
          url=$(echo "$app"       | ${pkgs.jq}/bin/jq -r '.url')
          icon_slug=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.icon // ""')
          category=$(echo "$app"  | ${pkgs.jq}/bin/jq -r '.category // "services"')

          slug=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-\+$//')

          # Resolve icon: try dashboard-icons CDN, fall back to slug (KDE theme lookup)
          icon_val="application-x-executable"
          if [ -n "$icon_slug" ] && [ "$icon_slug" != "null" ]; then
            icon_file="$ICONS_DIR/$slug.png"
            cdn_url="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/''${icon_slug}.png"
            if ${pkgs.curl}/bin/curl -sf --max-time 5 "$cdn_url" -o "$icon_file" 2>/dev/null; then
              icon_val="$icon_file"
            else
              icon_val="$icon_slug"
            fi
          fi

          # Map category to XDG Categories
          case "$category" in
            media)          xdg_cat="AudioVideo;Video;Network;" ;;
            productivity)   xdg_cat="Office;Network;" ;;
            infrastructure) xdg_cat="System;Network;" ;;
            development)    xdg_cat="Development;Network;" ;;
            storage)        xdg_cat="System;FileTools;Network;" ;;
            communication)  xdg_cat="Network;Chat;" ;;
            gaming)         xdg_cat="Game;Network;" ;;
            *)              xdg_cat="Network;" ;;
          esac
          ${optionalString (cfg.menuCategory != null) ''
            # Only the custom category, so they appear in that submenu alone
            xdg_cat="${menuXdgCategory};"
          ''}

          cat > "$APPS_DIR/$PREFIX$slug.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Exec=${pkgs.firefox}/bin/firefox --new-window $url
Icon=$icon_val
Categories=''${xdg_cat}
StartupNotify=true
StartupWMClass=firefox
EOF
        done

        # Rebuild KDE's app cache so shortcuts appear immediately
        ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental 2>/dev/null || true
      '';
    in
    {
      home.packages = [ pkgs.jq pkgs.curl ];

      # Submenu for menuCategory: a merge file plus the .directory that names it.
      # Although Plasma loads plasma-applications.menu, KDE's parser resolves its
      # <DefaultMergeDirs/> to menus/applications-merged/ (prefix dropped);
      # plasma-applications-merged/ is ignored -- confirmed with
      # `kbuildsycoca6 --menutest` on Julia-NixBook-Air.
      xdg.configFile."menus/applications-merged/app-shortcuts.menu" = mkIf (cfg.menuCategory != null) {
        text = ''
          <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
            "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
          <Menu>
            <Name>Applications</Name>
            <Menu>
              <Name>app-shortcuts</Name>
              <Directory>app-shortcuts.directory</Directory>
              <Include>
                <Category>${menuXdgCategory}</Category>
              </Include>
            </Menu>
          </Menu>
        '';
      };

      xdg.dataFile."desktop-directories/app-shortcuts.directory" = mkIf (cfg.menuCategory != null) {
        text = ''
          [Desktop Entry]
          Type=Directory
          Name=${cfg.menuCategory}
          Icon=applications-internet
        '';
      };

      systemd.user.services.app-shortcuts = {
        Unit = {
          Description = "Generate KDE app shortcuts from vHosts manifest";
          After       = [ "network-online.target" "graphical-session.target" ];
          Wants       = [ "network-online.target" ];
          PartOf      = [ "graphical-session.target" ];
        };
        Service = {
          Type            = "oneshot";
          ExecStart       = "${updateScript}";
          RemainAfterExit = true;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    }
  );
}
