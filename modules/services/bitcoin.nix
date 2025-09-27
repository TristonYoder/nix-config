{ config, lib, pkgs, nix-bitcoin, ... }:

{
  # =============================================================================
  # BITCOIN SERVICES - nix-bitcoin integration
  # =============================================================================

  # Note: nix-bitcoin modules are imported via flake.nix

  # Automatically generate all secrets required by services.
  # The secrets are stored in /etc/nix-bitcoin-secrets
  nix-bitcoin.generateSecrets = true;
  
  # Set secrets setup method for flake compatibility
  nix-bitcoin.secretsSetupMethod = "auto";

  # Enable Bitcoin services
  services = {
    bitcoind = {
      enable = true;
      listen = true;
      address = "0.0.0.0";
      tor.enforce = false;
      rpc.address = "0.0.0.0";
      # Allow RPC connections from external addresses
      rpc.allowip = [
        "10.150.100.0/23" # Allow a subnet
        "127.0.0.1" # Allow a specific address
        "0.0.0.0/0" # Allow all addresses
      ];
      
      # HMAC Cheat Sheet: zsh command
      # python3 -c 'import hashlib, hmac; import os; salt="mysecretsalt"; password="{a_secret_was_here}"; hex_salt = salt.encode().hex(); print(hex_salt + "$" + hmac.new(bytes.fromhex(hex_salt), password.encode(), hashlib.sha256).hexdigest())'
      
      rpc.users = {
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
      
      dataDir = "/data/docker-appdata/bitcoind";
    };

    clightning = {
      enable = true;
      dataDir = "/data/docker-appdata/clightning";
      port = 9736;
    };

    electrs = {
      enable = true;
      address = "0.0.0.0";
      tor.enforce = false;
    };

    # Lightning Network Daemon
    lnd = {
      enable = true;
      lndconnect.enable = true;
    };

    # BTC Pay Server
    btcpayserver = {
      enable = true;
      lightningBackend = "clightning";
      port = 8997;
      address = "0.0.0.0";
    };

    # Enable Tor if needed
    tor.enable = true;
  };

  # Enable interactive access to nix-bitcoin features (like bitcoin-cli) for
  # your system's main user
  nix-bitcoin.operator = {
    enable = true;
    # Set this to your system's main user
    name = "tristonyoder";
  };

  # Prevent garbage collection of the nix-bitcoin source
  system.extraDependencies = [ nix-bitcoin ];

  # =============================================================================
  # COMMENTED OUT SERVICES - Available for future use
  # =============================================================================

  # # Mempool - Bitcoin block explorer
  # services.mempool = {
  #   enable = true;
  #   frontend.enable = true;
  #   frontend.address = "0.0.0.0";
  #   frontend.port = 8998;
  # };

  # # Ride the Lightning - Lightning Network management
  # services.rtl = {
  #   enable = true;
  #   nodes.clightning.enable = true;
  #   nodes.lnd.loop = true;
  # };

  # # CG Miner - Bitcoin mining
  # services.cgminer = {
  #   enable = true;
  #   pools = [
  #     {
  #       pass = "{a_secret_was_here}";
  #       url = "http://172.0.0.1:8332";
  #       user = "cgminer";
  #     }
  #     # You can add more pools like this:
  #     # {
  #     #   password = "another_password";
  #     #   url = "http://another.pool.url:port";
  #     #   username = "another_username";
  #     # }
  #   ];
  # };
}
