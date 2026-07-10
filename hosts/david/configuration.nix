# Configuration for david - Main Server
# Hosts all services including infrastructure, media, productivity, and storage

{ config, pkgs, lib, nixpkgs, nixpkgs-unstable, nix-bitcoin, ... }:
let
  # Tailscale IP for tristons-workstation. LiteLLM uses aiodns which bypasses
  # /etc/hosts, so we must use the raw IP rather than the hostname everywhere
  # LiteLLM resolves endpoints. Update this if the device re-registers on Tailscale.
  workstationIp = "100.110.37.61";
in
{
  imports = [
    ../../modules/services/tailscale-router.nix
  ];

  # =============================================================================
  # NETWORK: Bridge for Tailscale router container
  # =============================================================================
  # tailscale-router.nix creates br0 on enp4s0f0 with static 10.150.100.30/23,
  # and a container at 10.150.100.31/23 via macvlan.
  # Disable DHCP so the second NIC doesn't conflict.
  networking.useDHCP = lib.mkForce false;
  networking.interfaces.enp4s0f1.useDHCP = false;

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "david";
  system.stateVersion = "23.11"; # Did you read the comment?

  # tristons-workstation is reachable via Tailscale but not via VLAN from david's br0.
  # Pin it to the Tailscale IP so internal service lookups (LiteLLM → Ollama) work.
  networking.hosts.${workstationIp} = [ "tristons-workstation.theyoder.family" "tristons-workstation" ];
  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-23.11/";

  # ZFS encryption key is loaded via postDeviceCommands (key file, not interactive).
  # Force scripted initrd so postDeviceCommands remains supported; without this,
  # boot.zfs.requestEncryptionCredentials auto-enables systemd stage 1 in 26.05
  # which drops postDeviceCommands support.
  boot.initrd.systemd.enable = lib.mkForce false;

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================
  
  # All module enables are set in ../../profiles/server.nix
  # You can override any profile settings here if needed for this specific host
  
  # GroupMe Bridge - Whitelist user for provisioning
  modules.services.communication.mautrix-groupme = {
    provisioningWhitelist = [
      "@triston:${config.networking.domain}"
    ];
  };
  
  # iMessage Bridge - disabled: go-modules hash mismatch in nixpkgs 26.05, re-enable after fix
  modules.services.communication.mautrix-imessage = {
    enable = false;
    blueBubblesUrl = "http://macservices:1234";
    provisioningWhitelist = [
      "@triston:${config.networking.domain}"
    ];
  };
  
  # Stalwart Mail Server
  modules.services.communication.stalwart-mail.enable = false;

  # Stirling PDF's default port 7878 collides with Radarr, which also runs on
  # this host and already owns that port.
  modules.services.productivity.stirlingPdf.port = 7879;

  # Scrutiny and Pixelfed both default to port 8085. Pixelfed's port is
  # externally referenced (PITS reverse proxy, ActivityPub webfinger), so
  # move Scrutiny instead — it's Caddy-proxied and localhost-only.
  modules.services.infrastructure.scrutiny.port = 8087;

  # dns-sync: use local Technitium directly (avoids Caddy loopback for the API)
  modules.services.providers.dns-technitium.url = "http://localhost:5380";

  # Navidrome - Music streaming server (Subsonic-compatible)
  modules.services.media.navidrome.enable = true;

  # Feishin - Web music player (Jellyfin/Navidrome/Subsonic client)
  modules.services.media.feishin.enable = true;

  # AzuraCast - Internet radio station management (azuracast.* admin, radio.* public player)
  modules.services.media.azuracast.enable = true;

  # Auto-create an AzuraCast station for each m3u file (Plexamp/Jellyfin mixes)
  # dropped into the shared m3u/playlist folder, and mirror every station into
  # Navidrome as an Internet Radio Station
  modules.services.media.azuracastPlaylistStations = {
    enable = true;
    apiKeyFile = config.age.secrets.azuracast-api-key.path;

    navidromeSync = {
      enable = true;
      user = "jonathan";
      passwordFile = config.age.secrets.navidrome-api-password.path;
    };
  };

  # Beets - Auto-organize music library from Downloads into Music
  modules.services.media.beets.enable = true;

  # Music dedup - Daily hard-link deduplication of the music library
  modules.services.media.musicDedup.enable = true;

  # JellyPlex-Watched sync (continuous)
  modules.services.media.jellyplexWatched = {
    enable = true;
    plexTokenFile = config.age.secrets.plex-token.path;
    jellyfinTokenFile = config.age.secrets.jellyfin-token.path;
    extraEnv = {
      # Map Plex users to Jellyfin users when names don't match
      # Format: JSON dictionary { "plex_user": "jellyfin_user" }
      USER_MAPPING = ''{ "tristonyoder": "Triston Yoder" }'';
    };
  };
  
  # =============================================================================
  # CADDY CONFIGURATION FOR TECHNITIUM DNS
  # =============================================================================

  # Technitium DNS Web UI and DoH - dns01.<baseDomain>
  modules.services.vHosts.hosts."dns01.${config.networking.domain}" = {
    rawConfig = true;  # Use custom routing for multi-backend setup
    public = false;  # Restrict to internal networks (auto-applied by module)
    displayName = "DNS";
    category = "infrastructure";
    icon = "technitium-dns-server";
    monitor = false;
    extraConfig = ''
      # DNS over HTTPS endpoint - Technitium runs DoH on port 5353
      handle /dns-query* {
        reverse_proxy http://localhost:5353 {
          header_up Host {upstream_hostport}
          header_up X-Real-IP {remote_host}
        }
      }

      # Web UI for all other paths
      handle {
        reverse_proxy http://localhost:5380 {
          header_up Host {upstream_hostport}
          header_up X-Real-IP {remote_host}
        }
      }
    '';
  };

  # Elizabeth Allen Photography - WordPress site
  modules.services.vHosts.hosts."elizabethallen.photography" = {
    public = true;
    reverseProxyPort = 1996;
    displayName = "Elizabeth Allen Photography";
    category = "public";
  };

  # Tunarr - Virtual IPTV tuner for Plex/Jellyfin
  modules.services.vHosts.hosts."tunarr.${config.networking.domain}" = {
    reverseProxyPort = 8100;
    displayName = "Tunarr";
    category = "media";
    icon = "tunarr";
  };

  # Dispatcharr - IPTV and stream management
  modules.services.vHosts.hosts."tv.${config.networking.domain}" = {
    reverseProxyPort = 9191;
    displayName = "Dispatcharr";
    category = "media";
  };

  # Threadfin - IPTV EPG proxy and M3U playlist management
  modules.services.vHosts.hosts."local-epg.tv.${config.networking.domain}" = {
    reverseProxyPort = 34400;
    displayName = "Threadfin EPG";
    category = "media";
    monitor = false;
  };

  # Tidarr - Tidal music downloader
  modules.services.vHosts.hosts."tidal.${config.networking.domain}" = {
    reverseProxyPort = 8484;
    displayName = "Tidarr";
    category = "media";
  };

  # InvokeAI
  modules.services.vHosts.hosts."invoke.${config.networking.domain}" = {
    reverseProxyHost = "tristons-workstation.${config.networking.domain}";
    reverseProxyPort = 9090;
    displayName = "InvokeAI";
    category = "ai";
    icon = "invoke-ai";
    monitor = false; # runs on workstation, not always reachable
  };

  # Home Assistant - runs on a separate device on the LAN.
  # DNS-only (A record); no Caddy reverse proxy, so casting/discovery/local
  # network features keep working and outages here can't take david's proxy down.
  modules.services.vHosts.hosts."home.${config.networking.domain}" = {
    ipAddress = "10.150.2.117";
    serverAliases = [ "ha.${config.networking.domain}" "house.${config.networking.domain}" ];
    displayName = "Home Assistant";
    category = "home-automation";
    icon = "home-assistant";
  };

  # Music Assistant - runs on the same device as Home Assistant. DNS-only, no reverse proxy.
  modules.services.vHosts.hosts."ma.${config.networking.domain}" = {
    ipAddress = "10.150.2.117";
    serverAliases = [ "musicassistant.${config.networking.domain}" ];
    displayName = "Music Assistant";
    category = "media";
    icon = "music-assistant";
  };

  # =============================================================================
  # AI — each service enabled via profiles/server.nix (mkDefault true)
  # =============================================================================

  modules.services.ai.litellm = {
    # rpc.statd (NFS) grabs port 4000 dynamically via rpcbind; use 4100 to avoid the conflict.
    port = 4100;
    models = [
      # ── Embeddings ────────────────────────────────────────────────────────────
      { name = "embed";            model = "ollama/nomic-embed-text";      apiBase = "http://${workstationIp}:11434"; }

      # ── Local inference (tristons-workstation RTX 4080) ──────────────────────
      { name = "local";            model = "ollama/hermes3";               apiBase = "http://${workstationIp}:11434"; }
      { name = "local-fast";       model = "ollama/llama3.2:3b";           apiBase = "http://${workstationIp}:11434"; }
      { name = "local-tool";       model = "ollama/qwen2.5:14b";           apiBase = "http://${workstationIp}:11434"; }
      { name = "local-code";       model = "ollama/qwen2.5-coder:14b";     apiBase = "http://${workstationIp}:11434"; }
      { name = "local-general";    model = "ollama/phi4:14b";              apiBase = "http://${workstationIp}:11434"; }

      # ── API models (all external/non-local routes go through OpenRouter now —
      # one provider, one key, one place to see spend/rate-limits across
      # everything that isn't self-hosted) ──────────────────────────────────────
      # fast: general tasking, routing, summarization
      { name = "fast";             model = "openrouter/anthropic/claude-sonnet-4.6"; apiKeyEnv = "OPENROUTER_API_KEY"; }
      # smart: tool-heavy agentic work, coding, complex reasoning
      { name = "smart";            model = "openrouter/anthropic/claude-opus-4.8";   apiKeyEnv = "OPENROUTER_API_KEY"; }
      # max: hardest problems, long-horizon tasks
      { name = "max";              model = "openrouter/anthropic/claude-fable-5";    apiKeyEnv = "OPENROUTER_API_KEY"; }

      # -- OpenRouter free tier --
      # quick: fast/low-effort interactive turns. Free tier is rate-limited
      # (20 req/min, 50-1000 req/day depending on account balance) — router_settings
      # fallback below drops to local-fast the moment it's throttled. gpt-oss-20b
      # is a reasoning model — its chain-of-thought sometimes leaks into visible
      # output, especially on long multi-step tool-calling turns.
      { name = "quick";            model = "openrouter/openai/gpt-oss-20b:free"; apiKeyEnv = "OPENROUTER_API_KEY"; }
      # quick-large: same free tier, but a plain instruct model (no reasoning-
      # leak risk) and from Hermes's own labs — good alternative when quick's
      # output looks garbled on a given turn.
      { name = "quick-large";      model = "openrouter/nousresearch/hermes-3-llama-3.1-405b:free"; apiKeyEnv = "OPENROUTER_API_KEY"; }

      # -- OpenRouter paid --
      # value: real (uncapped, no free-tier flakiness) but cheap — ~$0.23/$0.34
      # per M tokens vs. fast's (Sonnet) ~$3/$15. Consistently near the top of
      # open-weight benchmarks for coding/reasoning; good middle ground between
      # quick's free-tier caps and escalating all the way to fast/smart/max.
      { name = "value";            model = "openrouter/deepseek/deepseek-v3.2"; apiKeyEnv = "OPENROUTER_API_KEY"; }
    ];
    environmentFile = config.age.secrets.hermes-env.path;
    extraSettings.router_settings.fallbacks = [ { quick = [ "local-fast" ]; } ];
  };

  modules.services.ai.hermes-agent = {
    enable = true;
    model = "quick";  # LiteLLM route: OpenRouter free tier, falls back to local-fast when rate-limited
    backgroundReviewModel = "local-general";  # keep background review off the free quota
    environmentFile = config.age.secrets.hermes-env.path;
    # HERMES_MANAGED=true (in environmentFile) blocks /sethome; homeRoom is the only path.
    homeRoom = "!evHgyPMGVZyKzGopQo:theyoder.family";
    extraVolumes = [
      "/data/tristonyoder/home/Projects/nix-config:/nix-config:ro"
    ];
    # Hermes's brain (SOUL.md, memory, skills) is git-versioned separately from
    # this repo — TristonYoder/hermes-brain (private: it can carry Triston's own
    # conversation content, unlike this public repo). Hermes commits its own
    # deliberate changes; this timer is just a safety net for what it forgets.
    vaultGit = {
      enable = true;
      remote = "git@github.com:TristonYoder/hermes-brain.git";
      deployKeyFile = config.age.secrets.hermes-brain-deploy-key.path;
    };
  };

  modules.services.ai.open-webui = {
    ollamaHost = "http://tristons-workstation.${config.networking.domain}:11434";
    enableQdrant = true;
    environmentFile = config.age.secrets.hermes-env.path;
  };

  # =============================================================================
  # STORAGE: USB Drive Sync
  # =============================================================================

  modules.services.storage.wiiHddSync.enable = true;

  modules.services.storage.ipodSync = {
    enable = true;
    user = "tristonyoder";
    configFile = "/data/tristonyoder/home/.config/iopenpodcli/config.yaml";
    autoMount = true;  # headless server — no udisks desktop session
  };

  modules.services.storage.mp3PlayerSync = {
    enable = true;
    uuid = "EC95-4FBB";
    jellyfinApiKeyFile = config.age.secrets.jellyfin-api-key.path;
    playlists = [
      "Judah's MP3 Player"
    ];
  };

  # Serve the Nix binary cache over HTTPS so all Tailscale hosts can use it.
  modules.services.infrastructure.nixCacheServer.enable = true;

  # =============================================================================
  # DEVELOPMENT: GitLab
  # =============================================================================
  modules.services.development.gitlab = {
    enable = true;
    oidc = {
      enable = true;
      clientId = "8022fa8b-0d2c-4e78-973c-717c059cdad2";
    };
  };

  # =============================================================================
  # DEVELOPMENT: GitLab Runner
  # =============================================================================
  # Not turned on yet — GitLab itself has to be live first, since a runner
  # token can only be created from the GitLab UI (Admin Area > CI/CD >
  # Runners > "New instance runner", or a group/project's own Runners
  # settings). That's also where tags, protected-branches-only, and
  # run-untagged-jobs get set now — GitLab >= 17 removed the old
  # registration-token flow, so those are no longer Nix-side options.
  #
  # Once you've created a runner and have its token, give it to me and I'll
  # encrypt it (same flow as the OIDC secret) and fill in runners.docker below.
  modules.services.development.gitlabRunner = {
    enable = false;
    concurrent = 3;
    # runners.docker = {
    #   tokenFile = config.age.secrets.gitlab-runner-docker-token.path;
    #   dockerPrivileged = true; # for Docker-in-Docker image builds
    # };
  };

  # david has the cache on local disk — no need to route through HTTPS.
  modules.system.nixCache.cacheUrl = "file:///data/nix-builds/cache";
  modules.system.nixCache.priority = 20;

  # Conservative GC for the build machine — keep 3 months or 30 generations.
  nix.gc = {
    automatic = true;
    dates = "monthly";
    options = "--delete-older-than 365d --max-old-count 30";
  };

  # =============================================================================
  # ADDITIONAL SERVICES
  # =============================================================================
  
  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [ pkgs.curl ];
      script = "curl $(cat ${config.age.secrets.nextdns-link.path})";
      startAt = "hourly";
    };
  };

}
