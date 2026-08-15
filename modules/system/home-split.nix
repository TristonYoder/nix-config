# Home directory split: host-local $HOME, shared data symlinked in.
#
# This is the successor to `modules.system.users.useDataDrive`, which symlinked
# the *entire* home directory onto shared storage. That model breaks down as
# soon as two hosts share one home:
#
#   ~/.zshrc -> /nix/store/<hash>-home-manager-files/.zshrc
#
# Home Manager writes store paths into the home directory, and each host builds
# its own `home-manager-files` derivation. Whichever host activated last wins
# the file, and on the other host that store path does not exist -- so ~/.zshrc
# dangles and the shell comes up unconfigured. Both hosts keep overwriting each
# other because each tracks its own generation state. The same applies to
# ~/.config/git/config, the plasma-manager autostart entry, and any other
# HM-managed file. Plasma's panel layout has the same shape of problem for a
# different reason (plasma-manager rebuilds the appletsrc at every login).
#
# The fix is to invert the default. $HOME is host-local storage, and only
# explicitly listed paths are symlinked out to the shared root. Anything a new
# application drops in $HOME -- dotfile, cache, state directory -- is host-local
# automatically, with no blocklist to maintain.
#
# Symlinks, not bind mounts, deliberately: on NFS clients /data is an automount,
# and a bind mount would have to be established at boot, forcing the mount early
# and reintroducing the ordering cycle documented in CLAUDE.md. `L+` only calls
# symlink(2), so these rules never touch the shared filesystem and never trigger
# the automount. A shared path resolves lazily on first access.
#
# The per-user path lists live here rather than in host configs on purpose:
# hosts that share a home must agree on the split, and a shared default is
# structural agreement rather than a comment asking two files to stay in sync.

{ config, lib, pkgs, ... }:

with lib;
let
  usersCfg = config.modules.system.users;
  cfg = usersCfg.homeSplit;

  # systemd.tmpfiles path fields containing spaces must be quoted. This applies
  # to the path field only -- the trailing argument field (a symlink target
  # here) takes the rest of the line, and quoting it makes systemd-tmpfiles
  # embed the quote characters in the target it creates. Verified on david:
  #   L+ "/tmp/x/Calibre Library" - - - - "/tmp/x/target dir"
  #     -> Calibre Library -> "/tmp/x/target dir"   (literal quotes, broken)
  #   L+ "/tmp/x/Calibre Library" - - - - /tmp/x/target dir
  #     -> Calibre Library -> /tmp/x/target dir     (correct)
  q = path: if hasInfix " " path then "\"${path}\"" else path;

  # All proper directory prefixes of a relative path, so nested shared paths
  # like ".config/iopenpodcli" get their parent created in the local home first.
  #   "a/b/c" -> [ "a" "a/b" ]     "Documents" -> [ ]
  prefixesOf = path:
    let
      parts = splitString "/" path;
      n = builtins.length parts;
    in
    map (i: concatStringsSep "/" (take (i + 1) parts)) (range 0 (n - 2));

  userRules = name: userCfg:
    let
      localHome = "/home/${name}";
      sharedHome = "${cfg.sharedRoot}/${name}/home";
      group = config.users.users.${name}.group or "users";

      linked = userCfg.sharedPaths ++ userCfg.sharedFiles;

      # Parents needed inside the local home, deduplicated across all paths.
      parents = unique (concatMap prefixesOf linked);
    in
    # The local home itself -- covers the case where a host mounts a dedicated
    # subvolume/dataset here, whose root would otherwise stay owned by root.
    [ "d ${q localHome} 0755 ${name} ${group} -" ]
    ++ map (p: "d ${q "${localHome}/${p}"} 0755 ${name} ${group} -") parents
    # L+ replaces whatever is at the path, so a stale real directory left over
    # from before the split is corrected on the next boot rather than silently
    # shadowing the shared copy.
    ++ map (p: "L+ ${q "${localHome}/${p}"} - - - - ${sharedHome}/${p}") linked
    # Only the host that owns the storage creates entries under it. On NFS
    # clients this must not happen: creating anything under /data would
    # trigger the automount during early boot.
    ++ optionals cfg.manageSharedRoot (
      let
        modeOf = p: userCfg.modes.${p} or "0755";
      in
      [ "d ${q sharedHome} 0755 ${name} ${cfg.sharedGroup} -" ]
      ++ map (p: "d ${q "${sharedHome}/${p}"} ${modeOf p} ${name} ${cfg.sharedGroup} -")
        (unique (parents ++ userCfg.sharedPaths))
      ++ map (p: "f ${q "${sharedHome}/${p}"} ${userCfg.modes.${p} or "0644"} ${name} ${cfg.sharedGroup} -")
        userCfg.sharedFiles
    );
in
{
  options.modules.system.users.homeSplit = {
    enable = mkEnableOption ''
      host-local home directories with shared data symlinked in.
      Mutually exclusive with useDataDrive
    '';

    sharedRoot = mkOption {
      type = types.str;
      default = "/data";
      description = ''
        Root of the shared storage. Each user's shared data is expected at
        <sharedRoot>/<username>/home, matching the layout useDataDrive created.
      '';
    };

    manageSharedRoot = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Create and own directories under sharedRoot. Enable only on the host
        that physically holds the storage (david). On NFS clients this must
        stay false -- creating a directory under an automounted /data would
        trigger the mount during early boot, which is exactly the boot-order
        cycle the automount design exists to avoid.
      '';
    };

    sharedGroup = mkOption {
      type = types.str;
      default = "nextcloud";
      description = "Group applied to directories created under sharedRoot.";
    };

    users = mkOption {
      description = ''
        Per-user shared path lists, relative to the home directory. Both
        directories and individual files are supported.

        Defaults live in this module rather than in host configs so that every
        host participating in the split agrees on it by construction.
      '';
      type = types.attrsOf (types.submodule {
        options = {
          sharedPaths = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ "Documents" ".ssh" ".config/someapp" ];
            description = ''
              Directories symlinked from the local home to shared storage.
            '';
          };

          sharedFiles = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ ".zsh_history" ];
            description = ''
              Individual files symlinked from the local home to shared storage.
              Kept separate from sharedPaths so that manageSharedRoot creates
              each entry with the right type -- a file entry created as a
              directory would break the application that owns it.
            '';
          };

          modes = mkOption {
            type = types.attrsOf types.str;
            default = { };
            example = { ".ssh" = "0700"; };
            description = ''
              Per-path mode override applied under sharedRoot, for paths whose
              permissions matter to the application that owns them.

              These modes are reapplied to existing directories on every boot,
              not just at creation: systemd-tmpfiles only leaves an existing
              entry alone when the mode field is "-", and "-" would create new
              entries as root rather than as the owning user.
            '';
          };
        };
      });
      default = {
        tristonyoder.sharedPaths = [
          # Data directories
          "Desktop"
          "Documents"
          "Downloads"
          "Movies"
          "Music"
          "Pictures"
          "Public"
          "Templates"
          "Videos"

          # Work and project trees
          "Development"
          "Projects"
          "Sites"
          "Sync"

          # Asset libraries
          "AppData"
          "Calibre Library"
          "Splice"
          "fonts"
          "vaults"

          # Dotfiles that are genuinely portable. Everything else -- .config,
          # .cache, .local, and any dotfile a new app invents -- stays local.
          # Sharing .claude also makes the cross-machine memory rsync in
          # CLAUDE.md unnecessary.
          ".claude"
          ".ssh"

          # david's ipodSync module reads this path directly on the shared
          # root, so the two hosts must be looking at the same file.
          ".config/iopenpodcli"
        ];

        tristonyoder.sharedFiles = [ ".zsh_history" ];

        # ssh refuses to use a private key whose directory is group- or
        # world-writable, and sshd's StrictModes checks the same for
        # authorized_keys. The shared-root default of 0755 is wrong here.
        tristonyoder.modes.".ssh" = "0700";

        carolineyoder.sharedPaths = [
          "Desktop"
          "Documents"
          "Downloads"
          "Music"
          "Pictures"
          "Videos"
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !usersCfg.useDataDrive;
        message = ''
          modules.system.users.homeSplit and modules.system.users.useDataDrive
          are mutually exclusive: useDataDrive symlinks all of /home/<user>
          onto shared storage, which is precisely what homeSplit replaces.
          Set modules.system.users.useDataDrive = false; on this host.
        '';
      }
      {
        assertion = usersCfg.enable;
        message = "modules.system.users.homeSplit requires modules.system.users.enable.";
      }
    ];

    systemd.tmpfiles.rules = concatLists (mapAttrsToList userRules cfg.users);

    # Refuse to activate while /home/<user> is still the useDataDrive symlink.
    #
    # This guard is not optional politeness -- without it this configuration
    # destroys data. If /home/tristonyoder is a symlink to
    # /data/tristonyoder/home, then the rule
    #
    #   L+ /home/tristonyoder/Documents - - - - /data/tristonyoder/home/Documents
    #
    # resolves its path through that symlink onto the real shared directory.
    # L+ means "remove whatever is here, then create the symlink", so it would
    # delete the real Documents and leave a symlink pointing at itself.
    #
    # Activation scripts run before systemd-tmpfiles, so failing here aborts
    # the switch while everything is still intact. Run
    # scripts/migrate-home-split.sh first; it replaces the symlink with a
    # populated local directory.
    system.activationScripts.homeSplitPreflight = stringAfter [ "specialfs" ] ''
      homeSplitFailed=0
      for home in ${escapeShellArgs (map (name: "/home/${name}") (attrNames cfg.users))}; do
        if [ -L "$home" ]; then
          echo "homeSplit: $home is still a symlink to $(readlink "$home")" >&2
          homeSplitFailed=1
        fi
      done
      if [ "$homeSplitFailed" -ne 0 ]; then
        echo "" >&2
        echo "homeSplit: refusing to activate -- systemd-tmpfiles would follow" >&2
        echo "these symlinks and replace the real shared directories with" >&2
        echo "self-referential links. Run scripts/migrate-home-split.sh for each" >&2
        echo "affected user first, then rebuild." >&2
        exit 1
      fi
    '';
  };
}
