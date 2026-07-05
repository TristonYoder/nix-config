{ ... }:
{
  # Import service category modules
  imports = [
    ./vhosts.nix
    ./providers
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
