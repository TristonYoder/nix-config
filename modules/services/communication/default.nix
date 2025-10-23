{ ... }:
{
  # Import communication service modules
  imports = [
    ./matrix-synapse.nix
    ./mautrix-groupme.nix
    ./mautrix-imessage.nix
    ./pixelfed.nix
    ./postal.nix
    ./stalwart-mail.nix
    ./wellknown.nix
  ];
}

