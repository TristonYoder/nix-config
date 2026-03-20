{ ... }:
{
  # Import service category modules
  imports = [
    ./appData.nix
    ./vhosts.nix
    ./infrastructure
    ./media
    ./productivity
    ./storage
    ./development
    ./communication
    ./ai
    ./gaming
  ];
}
