# Third-party Plasma theme assets, packaged from upstream git.
#
# None of these are in nixpkgs. nixpkgs' `ant-theme` ships only the GTK theme
# (share/themes/Ant) — not the Plasma look-and-feel, desktop theme, Aurorae
# window decoration, color scheme, or icons. All of this was originally
# installed by hand through the KDE Store ("Get New Global Themes..."), which
# is exactly what made the look unreproducible.
#
# Everything installs under $out/share, so the Home Manager profile puts it on
# XDG_DATA_DIRS and Plasma discovers it the same way it discovered
# ~/.local/share.
#
# To update: bump `rev`, then get the new hash with
#   nix flake prefetch --json github:<owner>/<repo>/<rev> | grep hash

{ pkgs }:

let
  inherit (pkgs) fetchFromGitHub stdenvNoCC lib;
in
{
  # Ant-Dark by EliverLara — look-and-feel, desktop theme, Aurorae decoration,
  # color scheme, icon theme, SDDM theme and wallpapers, all from one repo.
  #
  # Upstream master is still the Plasma 5 release. Verified against the KDE
  # Store's Plasma 6 build (what was installed by hand on tristons-nixbook-pro):
  # the desktop theme, Aurorae theme and the look-and-feel's defaults/previews/
  # splash are byte-identical, and only the look-and-feel wrapper differs. So we
  # reshape just that wrapper below rather than hunting for another source.
  ant-dark = stdenvNoCC.mkDerivation {
    pname = "ant-dark-plasma";
    version = "0-unstable-2026-03-24";

    src = fetchFromGitHub {
      owner = "EliverLara";
      repo = "Ant";
      rev = "79ddc06b40ad1e96c87d9270c71d7db3bfa0c3cd";
      hash = "sha256-dAx05R9QWkDcuzJF/GUhK2R7hGjY7JvtTyXEDpE+p5E=";
    };

    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      kde=kde/Dark

      mkdir -p \
        $out/share/plasma/look-and-feel \
        $out/share/plasma/desktoptheme \
        $out/share/aurorae/themes \
        $out/share/icons \
        $out/share/sddm/themes \
        $out/share/color-schemes \
        $out/share/wallpapers

      cp -r $kde/plasma/desktoptheme/Ant-Dark $out/share/plasma/desktoptheme/
      cp -r $kde/aurorae/Ant-Dark             $out/share/aurorae/themes/
      cp -r $kde/icons/Ant-Dark               $out/share/icons/
      cp -r $kde/sddm/Ant-Dark                $out/share/sddm/themes/

      # The look-and-feel package needs two fixups for Plasma 6:
      #
      # 1. KF6's KPackage no longer reads metadata.desktop, so an upstream
      #    checkout is simply invisible to Plasma 6. Write the JSON form
      #    instead. (kns:// dependency hints are dropped — they only tell the
      #    KDE Store what else to download, which is our job now.)
      # 2. contents/{components,lockscreen,logout,osd} are KF5-era QML that the
      #    Plasma 6 package dropped. Shipping them risks a broken lock screen
      #    and logout dialog, so keep only what the Plasma 6 build ships.
      lnf=$out/share/plasma/look-and-feel/Ant-Dark
      mkdir -p $lnf/contents
      for c in defaults previews splash; do
        cp -r $kde/plasma/look-and-feel/Ant-Dark/contents/$c $lnf/contents/
      done

      cat > $lnf/metadata.json <<'EOF'
      {
          "KPackageStructure": "Plasma/LookAndFeel",
          "KPlugin": {
              "Authors": [ { "Email": "eliverlara@gmail.com", "Name": "EliverLara" } ],
              "Category": "Plasma Look And Feel",
              "EnabledByDefault": true,
              "Id": "Ant-Dark",
              "License": "GPL 3+",
              "Name": "Ant-Dark",
              "ServiceTypes": [ "Plasma/LookAndFeel" ],
              "Version": "0.1",
              "Website": "https://github.com/EliverLara/Ant/tree/master/kde/Dark"
          }
      }
      EOF

      install -m444 $kde/color-schemes/Ant-Dark.colors $out/share/color-schemes/
      install -m444 $kde/wallpaper/Ant-Dark.jpg    $out/share/wallpapers/
      install -m444 $kde/wallpaper/Ant-Dark-s2.jpg $out/share/wallpapers/
      install -m444 $kde/wallpaper/Ant-Dark.svg    $out/share/wallpapers/

      runHook postInstall
    '';

    meta = {
      description = "Ant-Dark theme for KDE Plasma 6";
      homepage = "https://github.com/EliverLara/Ant";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux;
    };
  };

  # Application launcher used in the dock.
  andromeda-launcher = stdenvNoCC.mkDerivation {
    pname = "andromeda-launcher";
    version = "0.6";

    src = fetchFromGitHub {
      owner = "EliverLara";
      repo = "AndromedaLauncher";
      rev = "6bd0ac49b60888dd502169b0eacf5ca5146b1ec1";
      hash = "sha256-MSYD8eH6m4vWfvoAfHkqMed+ZGjFE0Ln75cqIZYq9Eg=";
    };

    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/plasma/plasmoids/AndromedaLauncher
      cp -r metadata.json contents $out/share/plasma/plasmoids/AndromedaLauncher/
      runHook postInstall
    '';

    meta = {
      description = "Modern application launcher plasmoid for Plasma 6";
      homepage = "https://github.com/EliverLara/AndromedaLauncher";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux;
    };
  };

  # Quick-settings panel plasmoid. Upstream is a CMake project, but
  # plasma_install_package(package) just copies package/ verbatim — there is
  # nothing compiled, so we skip cmake entirely.
  kde-control-station = stdenvNoCC.mkDerivation {
    pname = "kde-control-station";
    version = "2.8.0";

    src = fetchFromGitHub {
      owner = "EliverLara";
      repo = "kde-control-station";
      rev = "bb473188a19d6cbe89a9c1bb5b08c7ddc609375d";
      hash = "sha256-Hjjz3RefycImPgAuTUchr8Jikh4HlLf+fOPuh0aMP2M=";
    };

    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/plasma/plasmoids/KdeControlStation
      cp -r package/metadata.json package/contents \
        $out/share/plasma/plasmoids/KdeControlStation/
      runHook postInstall
    '';

    meta = {
      description = "Modern control center plasmoid for Plasma 6";
      homepage = "https://github.com/EliverLara/kde-control-station";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;
    };
  };
}
