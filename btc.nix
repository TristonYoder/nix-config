# You can directly copy and import this file to use nix-bitcoin
# in an existing NixOS configuration.
# Make sure to check and edit all lines marked by 'FIXME:'

# See ./flakes/flake.nix on how to include nix-bitcoin in a flake-based
# system configuration.

# NixOS Options Search:
# https://search.nixos.org/flakes?channel=unstable&sort=relevance&type=options&query=bitcoin

let
  # FIXME:
  # Overwrite `builtins.fetchTarball {}` with the output of
  # command ../helper/fetch-release
  nix-bitcoin = builtins.fetchTarball {
  url = "https://github.com/fort-nix/nix-bitcoin/archive/v0.0.117.tar.gz";
  sha256 = "sha256-JN/PFBOVqWKc76zSdOunYoG5Q0m8W4zfrEh3V4EOIuk=";
};
in
{ config, pkgs, lib, ... }: {
  imports = [
    "${nix-bitcoin}/modules/modules.nix"
  ];

  # Automatically generate all secrets required by services.
  # The secrets are stored in /etc/nix-bitcoin-secrets
  nix-bitcoin.generateSecrets = true;

  # Enable some services.
  # See ./configuration.nix for all available features.

  services = {
    bitcoind.enable = true;
    bitcoind.listen = true;
    bitcoind.address = "0.0.0.0";
    bitcoind.tor.enforce = false;
    bitcoind.rpc.address = "0.0.0.0";
    # Allow RPC connections from external addresses
    bitcoind.rpc.allowip = [
      "10.150.100.0/23" # Allow a subnet
      "127.0.0.1" # Allow a specific address
      "0.0.0.0/0" # Allow all addresses
      ];

    # HMAC Cheat Sheet: zsh command
    # python3 -c 'import hashlib, hmac; import os; salt="mysecretsalt"; password="{a_secret_was_here}"; hex_salt = salt.encode().hex(); print(hex_salt + "$" + hmac.new(bytes.fromhex(hex_salt), password.encode(), hashlib.sha256).hexdigest())'

    bitcoind.rpc.users = {
      cgminer = {
        name = "cgminer";
        passwordHMAC = "{a_secret_was_here}${a_secret_was_here}";
        rpcwhitelist = [
          "getblocktemplate"
          "getmininginfo"
          "getwork"
          "submitblock"
          "getrawtransaction"
          "sendrawtransaction"
          "createrawtransaction"
          "getblockchaininfo"
          "getblockcount"
          "getmempoolinfo"
          "gettxout"
          "getmempoolancestors"
          "getmempooldescendants"
          "validateaddress"
          "signrawtransactionwithkey"
          "decodepsbt"
          "fundrawtransaction"
          "createmultisig"
          "getinfo"
          "getnetworkinfo"
          "uptime"
          "help"
          "ping"
        ];
      };
    };
    
    bitcoind.dataDir = "/data/docker-appdata/bitcoind";

    clightning.enable = true;
    clightning.dataDir = "/data/docker-appdata/clightning";
#    clightning-rest.enable = true;
    clightning.port = 9736;
#    clightning-rest.lndconnect.enable = true;

    electrs.enable = true;
    electrs.address = "0.0.0.0";
    electrs.tor.enforce = false;

    # lnd
    lnd.enable = true;
    lnd.lndconnect.enable = true;


    # Example for mempool
 #   mempool.enable = true;
 #   mempool.frontend.enable = true;
 #   mempool.frontend.address = "0.0.0.0";
 #   mempool.frontend.port = 8998;

    # # Ride the Lighting
    # rtl.enable = true;
    # rtl.nodes.clightning.enable = true;
    # rtl.nodes.lnd.loop = true;

    # BTC Pay
    btcpayserver.enable = true;
    btcpayserver.lightningBackend = "clightning";
    btcpayserver.port = 8997;
    btcpayserver.address = "0.0.0.0";

    
    # Enable Tor if needed
    tor.enable = true;
  };


  # Enable interactive access to nix-bitcoin features (like bitcoin-cli) for
  # your system's main user
  nix-bitcoin.operator = {
    enable = true;
    # FIXME: Set this to your system's main user
    name = "tristonyoder";
  };

  # Prevent garbage collection of the nix-bitcoin source
  system.extraDependencies = [ nix-bitcoin ];

#  # CG Miner
#  services.cgminer = {
#    enable = true;
#    pools = [
#      {
#        pass = "{a_secret_was_here}";
#        url = "http://172.0.0.1:8332";
#        user = "cgminer";
#      }
#      # You can add more pools like this:
#      # {
#      #   password = "another_password";
#      #   url = "http://another.pool.url:port";
#      #   username = "another_username";
#      # }
#    ];
#  };
}
