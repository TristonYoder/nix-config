# Public 13 Years Producer demo for Apple App Review (Pager app).
#
# The headless Producer runs a simulated show forever. Reviewers point the Pager at
# <publicHost>:13380 and see it live. Stateless: restarts rebuild the show.
#
# THREAT MODEL: anything published is attacked. The pager feed (13380) only takes
# PING/SYNC/MESSAGE, so a stranger can at most read the fake show or post messages into it.
# The Control API (13390) is unauthenticated and controls the show; it is only published on
# controlBind (loopback by default).
#
#   - Egress: dedicated bridge, no masquerade, no inter-container traffic. The container can
#     only answer inbound connections; it can never originate one (LAN, pits, internet).
#     Same pattern as app-review-ssh.nix.
#   - Abuse: per-source rate limit and per-source/global concurrent-connection caps on new
#     pager connections, in DOCKER-USER (DNAT'd traffic goes through FORWARD, never INPUT,
#     so networking.firewall does not apply to published ports).
#   - Container: UID 65532, read-only rootfs, no capabilities, no-new-privileges,
#     memory/CPU/pid limits, no host mounts, no secrets.
#   - Logs: container stdout -> journald; kernel LOG of new pager connections (source IP).
#
# The image is pinned by digest and fetched at build time (dockerTools.pullImage), so it is
# part of the system closure: nothing is pulled at runtime and the edge profile's daily
# `docker image prune --all` can't remove it. To move to a new image, change digest + hash.
#
# Reset: the container is recreated every resetInterval (hourly).
#
# Teardown: set enable = false (or delete the block) and rebuild.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.thirteenYearsDemo;

  containerName = "13years-demo";
  network = "demo13";
  bridge = "br-demo13";
  subnet = "172.30.78.0/24";
  pagerPort = 13380;   # inside the container
  controlPort = 13390; # inside the container

  image = pkgs.dockerTools.pullImage {
    imageName = cfg.imageName;
    imageDigest = cfg.digest;
    hash = cfg.imageHash;
    finalImageName = cfg.imageName;
    finalImageTag = cfg.tag;
  };

  dockerBin = "${pkgs.docker}/bin/docker";

  # Idempotent. Runs before every container start: network and firewall.
  prepScript = ''
    ${dockerBin} network inspect ${network} >/dev/null 2>&1 || \
      ${dockerBin} network create --driver bridge --subnet ${subnet} \
        -o com.docker.network.bridge.name=${bridge} \
        -o com.docker.network.bridge.enable_icc=false \
        -o com.docker.network.bridge.enable_ip_masquerade=false \
        ${network} >/dev/null

    # Forwarded traffic. DOCKER-USER is evaluated before Docker's own accept rules.
    iptables -w -N DOCKER-USER 2>/dev/null || true
    iptables -w -N DEMO13 2>/dev/null || iptables -w -F DEMO13
    # Replies only; the container never originates anything.
    iptables -w -A DEMO13 -i ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A DEMO13 -i ${bridge} -j DROP
    # New pager connections: caps, rate limit, log, accept. Nothing else gets in.
    iptables -w -A DEMO13 -o ${bridge} -p tcp --dport ${toString pagerPort} -m conntrack --ctstate NEW \
      -m connlimit --connlimit-above ${toString cfg.maxConnTotal} --connlimit-mask 0 \
      -j REJECT --reject-with tcp-reset
    iptables -w -A DEMO13 -o ${bridge} -p tcp --dport ${toString pagerPort} -m conntrack --ctstate NEW \
      -m connlimit --connlimit-above ${toString cfg.maxConnPerSource} --connlimit-mask 32 \
      -j REJECT --reject-with tcp-reset
    iptables -w -A DEMO13 -o ${bridge} -p tcp --dport ${toString pagerPort} -m conntrack --ctstate NEW \
      -m hashlimit --hashlimit-name demo13 --hashlimit-mode srcip \
      --hashlimit-above ${cfg.connRate} --hashlimit-burst ${toString cfg.connBurst} -j DROP
    iptables -w -A DEMO13 -o ${bridge} -p tcp --dport ${toString pagerPort} -m conntrack --ctstate NEW \
      -m limit --limit 30/min --limit-burst 60 -j LOG --log-prefix "13years-demo: " --log-level 6
    iptables -w -A DEMO13 -o ${bridge} -p tcp --dport ${toString pagerPort} -m conntrack --ctstate NEW -j RETURN
    iptables -w -A DEMO13 -o ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A DEMO13 -o ${bridge} -j DROP
    iptables -w -C DOCKER-USER -j DEMO13 2>/dev/null || iptables -w -I DOCKER-USER 1 -j DEMO13

    # Traffic to pits itself. Replies are allowed: docker-proxy (the controlBind publish)
    # connects from the host into the bridge, so its replies arrive on INPUT.
    iptables -w -N DEMO13-IN 2>/dev/null || iptables -w -F DEMO13-IN
    iptables -w -A DEMO13-IN -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A DEMO13-IN -j DROP
    iptables -w -C INPUT -i ${bridge} -j DEMO13-IN 2>/dev/null || iptables -w -I INPUT 1 -i ${bridge} -j DEMO13-IN

    # IPv6: the network has no v6, so drop anything that shows up.
    ip6tables -w -C INPUT -i ${bridge} -j DROP 2>/dev/null || ip6tables -w -I INPUT 1 -i ${bridge} -j DROP
    ip6tables -w -C FORWARD -i ${bridge} -j DROP 2>/dev/null || ip6tables -w -I FORWARD 1 -i ${bridge} -j DROP
    ip6tables -w -C FORWARD -o ${bridge} -j DROP 2>/dev/null || ip6tables -w -I FORWARD 1 -o ${bridge} -j DROP
  '';

  teardownScript = ''
    iptables -w -D DOCKER-USER -j DEMO13 2>/dev/null || true
    iptables -w -F DEMO13 2>/dev/null || true
    iptables -w -X DEMO13 2>/dev/null || true
    iptables -w -D INPUT -i ${bridge} -j DEMO13-IN 2>/dev/null || true
    iptables -w -F DEMO13-IN 2>/dev/null || true
    iptables -w -X DEMO13-IN 2>/dev/null || true
    ip6tables -w -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
    ip6tables -w -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
    ip6tables -w -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
    ${dockerBin} network rm ${network} >/dev/null 2>&1 || true
  '';
in
{
  options.modules.services.development.thirteenYearsDemo = {
    enable = mkEnableOption "public 13 Years Producer demo for App Review";

    imageName = mkOption {
      type = types.str;
      default = "ghcr.io/tristonyoder/13years-producer";
    };
    tag = mkOption {
      type = types.str;
      default = "1.5.0-demo";
    };
    digest = mkOption {
      type = types.str;
      description = "Manifest-list digest (sha256:...) of the tag. The tag is informational; this is what's pulled.";
    };
    imageHash = mkOption {
      type = types.str;
      description = "Nix hash of the pulled image (from nix-prefetch-docker).";
    };

    name = mkOption {
      type = types.str;
      default = "13 Years Demo";
      description = "THIRTEEN_NAME, shown on the Pager.";
    };
    timezone = mkOption {
      type = types.str;
      default = "America/Indiana/Indianapolis";
    };
    simItemSeconds = mkOption {
      type = types.ints.positive;
      default = 30;
    };
    simIdleResume = mkOption {
      type = types.ints.positive;
      default = 300;
    };

    publicPagerPort = mkOption {
      type = types.port;
      default = 13380;
      description = "Public TCP port for the pager feed.";
    };
    controlBind = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address the unauthenticated Control API is published on. Never a public address.";
    };
    controlPort = mkOption {
      type = types.port;
      default = 13390;
    };

    maxConnPerSource = mkOption {
      type = types.ints.positive;
      default = 16;
      description = "Concurrent pager connections per source IP (reviewers may share a NAT).";
    };
    maxConnTotal = mkOption {
      type = types.ints.positive;
      default = 256;
    };
    connRate = mkOption {
      type = types.str;
      default = "30/min";
      description = "New pager connections per source IP, above which they are dropped.";
    };
    connBurst = mkOption {
      type = types.ints.positive;
      default = 60;
    };

    resetInterval = mkOption {
      type = types.str;
      default = "hourly";
      description = ''
        systemd OnCalendar expression for recreating the container. Stateless, so this
        discards anything posted into the show and starts it over. Connected pagers drop
        and reconnect.
      '';
    };

    publicHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DNS name given to reviewers (DNS-only A record to this host; raw TCP, no proxy).";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = !(elem cfg.controlBind [ "0.0.0.0" "::" "" ]);
      message = "thirteenYearsDemo.controlBind must not be a wildcard: the Control API is unauthenticated.";
    }];

    # Every pager uses this server as its clock reference.
    services.timesyncd.enable = mkDefault true;

    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.${containerName} = {
      image = "${cfg.imageName}:${cfg.tag}";
      imageFile = image;
      ports = [
        "${toString cfg.publicPagerPort}:${toString pagerPort}/tcp"
        "${cfg.controlBind}:${toString cfg.controlPort}:${toString controlPort}/tcp"
      ];
      environment = {
        THIRTEEN_SIMULATE = "1";
        THIRTEEN_NAME = cfg.name;
        TZ = cfg.timezone;
        SIM_ITEM_SECONDS = toString cfg.simItemSeconds;
        SIM_IDLE_RESUME = toString cfg.simIdleResume;
      };
      extraOptions = [
        "--network=${network}"
        "--user=65532:65532"
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
        "--memory=256m"
        "--memory-swap=256m"
        "--cpus=0.5"
        "--pids-limit=64"
        "--ulimit=nofile=4096:4096"
        "--stop-timeout=5"
        # The demo image keeps HOME/XDG_CONFIG_HOME/THIRTEEN_DATA_DIR in /tmp.
        "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=16m,uid=65532,gid=65532,mode=0700"
      ];
    };

    systemd.services."docker-${containerName}" = {
      path = with pkgs; [ iptables ];
      preStart = mkBefore prepScript;
      postStop = teardownScript;
    };

    # Fresh container on a schedule: messages strangers posted into the show are gone.
    systemd.services.thirteen-years-demo-reset = {
      description = "Reset the 13 Years demo Producer container";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart docker-${containerName}.service";
      };
    };
    systemd.timers.thirteen-years-demo-reset = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.resetInterval;
        Persistent = false;
      };
    };
  };
}
