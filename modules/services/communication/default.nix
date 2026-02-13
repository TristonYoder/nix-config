{ ... }:
{
  # Import communication service modules
  imports = [
    ./mattermost.nix
    ./matrix-synapse.nix
    ./mautrix-groupme.nix
    ./mautrix-imessage.nix
    ./pixelfed.nix
    ./postal.nix
    ./stalwart-mail.nix
    ./wellknown.nix
  ];
}

