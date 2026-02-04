{ ... }:
{
  # Import service category modules
  imports = [
    ./vhosts.nix
    ./infrastructure
    ./media
    ./productivity
    ./storage
    ./development
    ./communication
    ./ai
  ];
}
