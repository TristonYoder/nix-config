{ ... }:
{
  # Import communication service modules
  imports = [
    ./matrix-synapse.nix
    ./mautrix-groupme.nix
    ./mautrix-imessage.nix
    ./pixelfed.nix
    ./stalwart-mail.nix
    ./wellknown.nix
  ];
}

