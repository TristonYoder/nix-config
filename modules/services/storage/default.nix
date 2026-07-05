{ ... }:
{
  # Import storage service modules
  imports = [
    ./nfs.nix
    ./nextcloud
    ./nextcloud/collabora.nix
    ./nextcloud/onlyoffice.nix
    ./samba.nix
    ./syncthing.nix
    ./mp3-player-sync.nix
    ./wii-hdd-sync.nix
    ./zfs.nix
  ];
}

