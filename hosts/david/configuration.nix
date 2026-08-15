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

  # QEMU user-mode emulation for aarch64-linux — lets `nix build` cross-build
  # ARM outputs (e.g. nixosConfigurations.installer-aarch64) directly on this
  # x86_64 host, so CI (which only reaches david, not a personal Mac) can
  # build both installer ISO architectures without a native ARM builder.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # nixos-raspberrypi's binary cache — required for nixosConfigurations.
  # installer-rpi5 (and the stage-plotiphar host). Their custom Pi 5 kernel
  # build fails under QEMU emulation (a HOSTCC-vs-target-binary mismatch in
  # the kernel's kconfig tooling — confirmed: "Exec format error" trying to
  # build linux_rpi-bcm2712 via boot.binfmt above). Trusting this cache
  # means david fetches the prebuilt kernel instead of compiling it —
  # strictly less rebuilding, not more.
  nix.settings = {
    substituters = lib.mkAfter [ "https://nixos-raspberrypi.cachix.org" ];
    trusted-public-keys = lib.mkAfter [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

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

  # Actual Budget: plain REST wrapper (jhonderson/actual-http-api) and MCP
  # server (agigante80/actual-mcp-server), both talking to the actual.nix
  # service directly via @actual-app/api. Credentials in
  # actual-http-api-secrets.age / actual-mcp-secrets.age (modules/secrets.nix).
  modules.services.productivity.actualHttpApi.enable = true;
  modules.services.productivity.actualMcp.enable = true;

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

  # Blueprint - personal dashboard (native, non-Docker, from TristonYoder/blueprint's own flake)
  modules.services.productivity.blueprint = {
    enable = true;
    domain = "blueprint.tristonyoder.com";
  };

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

  # ---------------------------------------------------------------------------
  # WordPress sites (containers defined in docker/websites/)
  #
  # Domains below are the canonical siteurl/home values stored in each site's
  # wp_options table — not the (stale) hostnames in the docker/websites/ file
  # headers. All three are Cloudflare-proxied publicly and resolve to david
  # internally via Technitium split-horizon DNS.
  # ---------------------------------------------------------------------------

  # carolineyoder.com — WordPress personal site
  modules.services.vHosts.hosts."carolineyoder.com" = {
    public = true;
    reverseProxyPort = 1128;
    displayName = "Caroline Yoder";
    category = "public";
  };

  # elizabethallen.photography — WordPress photography portfolio.
  # This is the CANONICAL domain: wp-config.php pins WP_HOME/WP_SITEURL here,
  # and those constants override the wp_options values, so every other hostname
  # 301s to this one.
  modules.services.vHosts.hosts."elizabethallen.photography" = {
    public = true;
    reverseProxyPort = 1996;
    displayName = "Elizabeth Allen Photography";
    category = "public";
  };

  # Secondary domain for the same site. WordPress 301s it to the canonical host
  # above, so it is served but not monitored separately.
  modules.services.vHosts.hosts."carolineelizabeth.photography" = {
    public = true;
    reverseProxyPort = 1996;
    displayName = "Caroline Elizabeth Photography";
    category = "public";
    monitor = false;
  };

  # 7andco.studio — WordPress studio site.
  # Subdomain multisite (SUBDOMAIN_INSTALL = true). Only the root blog exists
  # today; adding a subsite means adding a wildcard *.7andco.studio vHost here,
  # otherwise Caddy will not have a cert or route for it.
  modules.services.vHosts.hosts."7andco.studio" = {
    public = true;
    reverseProxyPort = 7777;
    displayName = "7 and Co Studio";
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

  # InvokeAI — proxy to tristons-workstation (RTX 4080)
  modules.services.ai.invokeAi = {
    enable = true;
    proxyHost = "tristons-workstation.${config.networking.domain}";
  };

  # Nix installer ISOs - static file server over /data/nix-iso (ZFS dataset).
  # Internal-only (public defaults false) — these are install media, no
  # secrets, but no reason to expose them to the open internet either.
  modules.services.vHosts.hosts."nix-iso.${config.networking.domain}" = {
    rawConfig = true;
    displayName = "Nix ISOs";
    category = "infrastructure";
    monitor = false; # directory listing, not a service with a stable 200
    extraConfig = ''
      root * /data/nix-iso
      file_server browse
    '';
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
    dashboard.enable = true;
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

  modules.services.media.dailyBriefPodcast = {
    enable = true;
    owner = "tristonyoder";
    audioScriptDir = "/data/tristonyoder/home/Documents/Obsidian Vault/AIOS/history/daily-briefs";
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

  # Self-hosted GitHub Actions runners for TristonYoder/stagePlotiphar.
  # Name must be unique per registered runner across all hosts hitting this
  # repo — defaults to the attrset key, so don't reuse these names elsewhere
  # or the later registration will --replace this one.
  modules.services.development.githubRunner = {
    enable = true;
    runners."stageplotiphar-david" = {
      url = "https://github.com/TristonYoder/stagePlotiphar";
      tokenFile = config.age.secrets.github-runner-token.path;
    };
    # Ephemeral, fresh-container-per-job runner — target with
    # `runs-on: [self-hosted, ephemeral-container]` when a job needs a
    # clean environment instead of the persistent native runner above.
    runners."stageplotiphar-david-clean" = {
      backend = "container";
      url = "https://github.com/TristonYoder/stagePlotiphar";
      tokenFile = config.age.secrets.github-runner-token.path;
    };
  };

  # ===========================================================================
  # DESKTOP
  # ===========================================================================

  # Shared Plasma look and panel layout. david is a server that gets used as a
  # workstation, so it gets the same desktop as everything else.
  #
  # ~/.config is host-local under homeSplit, so this host owns its own
  # plasma-org.kde.plasma.desktop-appletsrc and no longer contends with
  # tristons-workstation over the panel layout.
  home-manager.users.tristonyoder.modules.plasma.enable = true;

  # ===========================================================================
  # HOME DIRECTORIES — host-local, with shared data symlinked in
  # ===========================================================================

  # /home/<user> is a real directory on david's root NVMe; only the paths listed
  # in modules/system/home-split.nix are symlinked out to /data. This host owns
  # the shared storage, so it is the one that creates directories under it --
  # manageSharedRoot must stay false on the NFS clients.
  #
  # profiles/server.nix defaults useDataDrive on; homeSplit replaces it.
  modules.system.users.useDataDrive = false;
  modules.system.users.homeSplit = {
    enable = true;
    manageSharedRoot = true;
  };

}
