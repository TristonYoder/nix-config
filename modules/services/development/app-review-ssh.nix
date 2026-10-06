# Throwaway SSH server for Apple App Review (Puddle Jumper).
#
# THREAT MODEL: the container is presumed compromised. Its password is typed into a public
# form and the reviewer gets an interactive shell. Everything below assumes root in there.
#
#   - Egress: the container's bridge is firewalled so the container can never originate a
#     connection (LAN, pits itself, other containers, internet). Only replies to inbound
#     connections on the published port pass. Fails closed: the container unit requires the
#     rules to install, and removes them (and the network) when it stops.
#   - Nothing sensitive inside: read-only rootfs, no host mounts except the SSH host key
#     (an identity the client pins, not a credential for anything) and a password hash
#     generated on the host. Neither is in the repo; both live in /var/lib/app-review-ssh.
#   - Caps: all capabilities dropped but what sshd needs, no-new-privileges, memory/CPU/pid
#     limits, size-capped tmpfs for the only writable paths.
#   - Logs: sshd logs to stderr -> docker journald driver (host journal), plus a kernel LOG
#     rule for new inbound connections. sshd does not log passwords at LogLevel VERBOSE.
#
# CLIENT CONSTRAINTS (Puddle Jumper): Ed25519 host key only (no RSA), key stable across
# restarts (client hard-fails on mismatch), default OpenSSH algorithms left untouched, and
# password auth enabled. Do not add Ciphers/KexAlgorithms/MACs lines here.
#
# Teardown: see `app-review-ssh-info`, or remove the enable line and rebuild.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.appReviewSsh;

  stateDir = "/var/lib/app-review-ssh";
  network = "apprev";
  bridge = "br-apprev";
  subnet = "172.30.77.0/24";
  containerName = "app-review-ssh";
  user = "reviewer";

  sshdConfig = pkgs.writeText "sshd_config" ''
    Port 22
    HostKey /etc/ssh/ssh_host_ed25519_key
    PasswordAuthentication yes
    KbdInteractiveAuthentication no
    PubkeyAuthentication no
    PermitEmptyPasswords no
    PermitRootLogin no
    AllowUsers ${user}
    UsePAM yes
    MaxAuthTries 4
    LoginGraceTime 30
    MaxStartups 10:30:30
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitUserEnvironment no
    PrintMotd yes
    PrintLastLog no
    UseDNS no
    ClientAliveInterval 30
    ClientAliveCountMax 4
    LogLevel VERBOSE
    PidFile none
  '';

  # This nixpkgs OpenSSH has no libcrypt: with UsePAM no, every password is rejected even when
  # the hash is right. PAM does the check. Keep the stack minimal (no pam_loginuid,
  # pam_limits etc.; they need capabilities the container does not have).
  pamConfig = pkgs.writeText "pam-sshd" ''
    auth    required ${pkgs.linux-pam}/lib/security/pam_unix.so
    account required ${pkgs.linux-pam}/lib/security/pam_unix.so
    session required ${pkgs.linux-pam}/lib/security/pam_permit.so
  '';

  # The password hash goes straight into passwd (mounted from the host at run time, @HASH@
  # filled in there). pam_unix cannot read /etc/shadow from sshd's PAM context here, and the
  # hash is for a password that is public anyway.
  passwdTemplate = pkgs.writeText "passwd" ''
    root:*:0:0:root:/root:/bin/false
    sshd:*:74:74:sshd privsep:/var/empty:/bin/false
    ${user}:@HASH@:1000:1000:App Review:/home/${user}:/bin/bash
    nobody:*:65534:65534:nobody:/var/empty:/bin/false
  '';

  groupFile = pkgs.writeText "group" ''
    root:x:0:
    sshd:x:74:
    ${user}:x:1000:
    nogroup:x:65534:
  '';

  nsswitch = pkgs.writeText "nsswitch.conf" ''
    passwd: files
    group: files
    shadow: files
    hosts: files dns
  '';

  profile = pkgs.writeText "profile" ''
    export PATH=/bin
    export LANG=C.UTF-8
    export TERMINFO_DIRS=/share/terminfo
    export PAGER=less
    export EDITOR=nano
    alias ls='ls --color=auto'
    alias ll='ls -la --color=auto'
    alias grep='grep --color=auto'
    PS1='\[\e[1;32m\]${user}@app-review\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
    cd "$HOME" 2>/dev/null
  '';

  motd = pkgs.writeText "motd" ''

    Welcome to the Puddle Jumper App Review test server.
    This is a disposable sandbox with no network access.

    Try: uname -a | ls -la | top | htop | nano | colors

  '';

  # ANSI colour / 256-colour demo for eyeballing the terminal.
  colors = pkgs.writeShellScriptBin "colors" ''
    for i in $(seq 0 7); do printf '\e[4%dm  \e[0m' "$i"; done; echo
    for i in $(seq 8 15); do printf '\e[48;5;%dm  \e[0m' "$i"; done; echo
    for i in $(seq 16 231); do
      printf '\e[48;5;%dm \e[0m' "$i"
      [ $(( (i - 15) % 36 )) -eq 0 ] && echo
    done
    echo "size: $(stty size)"
    printf '\e[1mbold\e[0m \e[3mitalic\e[0m \e[4munderline\e[0m \e[7mreverse\e[0m\n'
  '';

  image = pkgs.dockerTools.buildLayeredImage {
    name = containerName;
    tag = "latest";
    contents = with pkgs; [
      dockerTools.binSh
      bashInteractive
      coreutils
      util-linux
      procps
      htop
      ncurses
      less
      nano
      gnugrep
      gnused
      gawk
      findutils
      which
      openssh
      colors
    ];
    extraCommands = ''
      mkdir -p etc/ssh etc/pam.d var/empty var/log run tmp home/${user} root
      chmod 1777 tmp
      chmod 0755 var/empty
      sed 's|@HASH@|!|' ${passwdTemplate} > etc/passwd
      cp ${groupFile} etc/group
      cp ${nsswitch} etc/nsswitch.conf
      cp ${profile} etc/profile
      cp ${motd} etc/motd
      cp ${pamConfig} etc/pam.d/sshd
      # Bind-mount targets; the real contents come from the host at run time.
      : > etc/ssh/ssh_host_ed25519_key
      : > etc/ssh/ssh_host_ed25519_key.pub
    '';
    config = {
      Cmd = [ "${pkgs.openssh}/bin/sshd" "-D" "-e" "-f" "${sshdConfig}" ];
      ExposedPorts."22/tcp" = { };
    };
  };

  dockerBin = "${pkgs.docker}/bin/docker";

  # Idempotent. Runs before every container start: state, network, firewall.
  prepScript = ''
    state=${stateDir}
    install -d -m 0755 "$state" "$state/hostkeys"

    # Host key: generated once, then stable. The fingerprint depends on this file.
    if [ ! -f "$state/hostkeys/ssh_host_ed25519_key" ]; then
      ssh-keygen -q -t ed25519 -N "" -C app-review-ssh -f "$state/hostkeys/ssh_host_ed25519_key"
    fi
    chmod 0600 "$state/hostkeys/ssh_host_ed25519_key"
    chmod 0644 "$state/hostkeys/ssh_host_ed25519_key.pub"

    # Password: typeable (no ambiguous characters, no shift), generated on the host, never in git.
    if [ ! -s "$state/password" ]; then
      pw=$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 16 || true)
      printf '%s\n' "$pw" | fold -w4 | paste -sd- - > "$state/password"
    fi
    chmod 0600 "$state/password"

    hash=$(tr -d '\n' < "$state/password" | openssl passwd -6 -stdin)
    umask 077
    sed "s|@HASH@|$hash|" ${passwdTemplate} > "$state/passwd"
    umask 022
    chmod 0644 "$state/passwd"

    # Dedicated bridge: no NAT out, no inter-container traffic.
    ${dockerBin} network inspect ${network} >/dev/null 2>&1 || \
      ${dockerBin} network create --driver bridge --subnet ${subnet} \
        -o com.docker.network.bridge.name=${bridge} \
        -o com.docker.network.bridge.enable_icc=false \
        -o com.docker.network.bridge.enable_ip_masquerade=false \
        ${network} >/dev/null

    # Firewall. DOCKER-USER is evaluated before Docker's own accept rules.
    iptables -w -N DOCKER-USER 2>/dev/null || true
    iptables -w -N APPREV 2>/dev/null || iptables -w -F APPREV
    # Replies to inbound connections only; the container never originates anything.
    iptables -w -A APPREV -i ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A APPREV -i ${bridge} -j DROP
    # Log new inbound connections (source IP) in the host kernel log, out of reach of the container.
    iptables -w -A APPREV -o ${bridge} -p tcp --dport 22 -m conntrack --ctstate NEW \
      -m limit --limit 30/min --limit-burst 60 -j LOG --log-prefix "app-review-ssh: " --log-level 6
    iptables -w -A APPREV -o ${bridge} -p tcp --dport 22 -m conntrack --ctstate NEW -j RETURN
    iptables -w -A APPREV -o ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A APPREV -o ${bridge} -j DROP
    iptables -w -C DOCKER-USER -j APPREV 2>/dev/null || iptables -w -I DOCKER-USER 1 -j APPREV
    # The container reaching pits itself (including its public listeners) is the other path out.
    iptables -w -C INPUT -i ${bridge} -j DROP 2>/dev/null || iptables -w -I INPUT 1 -i ${bridge} -j DROP
    # IPv6: the network has no v6, so just drop anything that shows up.
    ip6tables -w -C INPUT -i ${bridge} -j DROP 2>/dev/null || ip6tables -w -I INPUT 1 -i ${bridge} -j DROP
    ip6tables -w -C FORWARD -i ${bridge} -j DROP 2>/dev/null || ip6tables -w -I FORWARD 1 -i ${bridge} -j DROP
    ip6tables -w -C FORWARD -o ${bridge} -j DROP 2>/dev/null || ip6tables -w -I FORWARD 1 -o ${bridge} -j DROP
  '';

  teardownScript = ''
    iptables -w -D DOCKER-USER -j APPREV 2>/dev/null || true
    iptables -w -F APPREV 2>/dev/null || true
    iptables -w -X APPREV 2>/dev/null || true
    iptables -w -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
    ip6tables -w -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
    ip6tables -w -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
    ip6tables -w -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
    ${dockerBin} network rm ${network} >/dev/null 2>&1 || true
  '';

  infoScript = pkgs.writeShellScriptBin "app-review-ssh-info" ''
    set -eu
    state=${stateDir}
    if [ "$(id -u)" -ne 0 ]; then echo "run as root (reads the password)" >&2; exit 1; fi
    echo "Host:        ${if cfg.publicHost != null then cfg.publicHost else "<public hostname or IP of pits>"}"
    echo "Port:        ${toString cfg.port}"
    echo "Username:    ${user}"
    echo "Password:    $(cat "$state/password")"
    echo "Fingerprint: $(${pkgs.openssh}/bin/ssh-keygen -lf "$state/hostkeys/ssh_host_ed25519_key.pub" | cut -d' ' -f2)"
    echo
    echo "Teardown:    systemctl stop docker-${containerName}.service && rm -rf $state && ${dockerBin} rmi ${containerName}:latest"
    echo "             (then delete the enable line and rebuild, or it returns at next boot)"
  '';
in
{
  options.modules.services.development.appReviewSsh = {
    enable = mkEnableOption "disposable SSH server for Apple App Review";
    port = mkOption {
      type = types.port;
      default = 22022;
      description = "Public TCP port, published straight to the container's sshd.";
    };
    resetInterval = mkOption {
      type = types.str;
      default = "hourly";
      description = ''
        systemd OnCalendar expression for the reset. Restarting discards everything the
        container wrote (rootfs is read-only, the rest is tmpfs) and drops open sessions.
        The host key and password persist.
      '';
    };
    publicHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Hostname shown by app-review-ssh-info.";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.${containerName} = {
      image = "${containerName}:latest";
      imageFile = image;
      ports = [ "${toString cfg.port}:22/tcp" ];
      volumes = [
        "${stateDir}/hostkeys/ssh_host_ed25519_key:/etc/ssh/ssh_host_ed25519_key:ro"
        "${stateDir}/hostkeys/ssh_host_ed25519_key.pub:/etc/ssh/ssh_host_ed25519_key.pub:ro"
        "${stateDir}/passwd:/etc/passwd:ro"
      ];
      extraOptions = [
        "--network=${network}"
        "--hostname=app-review"
        "--init"
        "--read-only"
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=SETUID"
        "--cap-add=SETGID"
        "--cap-add=SYS_CHROOT"
        "--cap-add=KILL"
        "--security-opt=no-new-privileges:true"
        "--memory=256m"
        "--memory-swap=256m"
        "--cpus=0.5"
        "--pids-limit=128"
        "--ulimit=nofile=1024:1024"
        "--stop-timeout=5"
        "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=16m"
        "--tmpfs=/run:rw,noexec,nosuid,nodev,size=4m"
        "--tmpfs=/var/log:rw,noexec,nosuid,nodev,size=4m"
        "--tmpfs=/home/${user}:rw,nosuid,nodev,size=32m,uid=1000,gid=1000,mode=0700"
      ];
    };

    systemd.services."docker-${containerName}" = {
      path = with pkgs; [ coreutils gnugrep gnused openssh openssl iptables ];
      preStart = mkBefore prepScript;
      postStop = teardownScript;
    };

    # Fresh container on a schedule: anything a reviewer (or attacker) left behind is gone.
    systemd.services.app-review-ssh-reset = {
      description = "Reset the App Review SSH container";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart docker-${containerName}.service";
      };
    };
    systemd.timers.app-review-ssh-reset = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.resetInterval;
        Persistent = false;
      };
    };

    environment.systemPackages = [ infoScript ];
  };
}
