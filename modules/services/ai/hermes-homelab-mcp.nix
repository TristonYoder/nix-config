{ config, lib, pkgs, ... }:

# Homelab MCP server for Hermes.
#
# Exposes structured tools for querying the local NixOS host over SSE transport:
#   service_status / list_services / service_logs / restart_service (gated)
#   zfs_pool_status / zfs_list
#   disk_usage / system_info
#   tailscale_status / tailscale_peers
#
# Hermes reaches it at http://localhost:<port>/sse via --network=host.
# Enabled automatically when modules.services.ai.hermes-agent.homelabMcp.enable = true.

with lib;
let
  cfg = config.modules.services.ai.hermes-homelab-mcp;

  # Minimal SSE MCP server — stdlib only, no mcp/fastmcp dependency.
  # Implements: initialize, tools/list, tools/call.
  # SSE transport: GET /sse opens event stream; POST /message sends requests.
  mcpServer = pkgs.writeText "hermes-homelab-mcp.py" ''
    #!/usr/bin/env python3
    """
    Homelab MCP SSE server for Hermes.
    Exposes systemd, ZFS, disk, and Tailscale status as MCP tools.
    """
    import json, os, subprocess, threading, queue, time, traceback, uuid
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from urllib.parse import urlparse, parse_qs

    ALLOW_RESTARTS = os.environ.get("HOMELAB_MCP_ALLOW_RESTARTS", "0") == "1"
    PORT = int(os.environ.get("HOMELAB_MCP_PORT", "7830"))

    # ---------------------------------------------------------------------------
    # Tool definitions
    # ---------------------------------------------------------------------------

    TOOLS = [
      {
        "name": "service_status",
        "description": "Get the status of a systemd service.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name": {"type": "string", "description": "Service name (e.g. 'jellyfin')"}
          },
          "required": ["name"]
        }
      },
      {
        "name": "list_services",
        "description": "List systemd services, optionally filtered by state or name fragment.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "state":  {"type": "string", "description": "Filter by state: running, failed, inactive, etc."},
            "filter": {"type": "string", "description": "Name fragment to match (substring)."}
          }
        }
      },
      {
        "name": "service_logs",
        "description": "Fetch recent journal log lines for a systemd service.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name":  {"type": "string", "description": "Service name."},
            "lines": {"type": "integer", "description": "Number of lines to return (default 50)."},
            "since": {"type": "string", "description": "Relative time filter, e.g. '1 hour ago'."}
          },
          "required": ["name"]
        }
      },
      {
        "name": "zfs_pool_status",
        "description": "Get ZFS pool health status (equivalent to zpool status -x or full status).",
        "inputSchema": {
          "type": "object",
          "properties": {
            "pool": {"type": "string", "description": "Pool name. Omit for all pools."},
            "verbose": {"type": "boolean", "description": "Include per-vdev detail (default false)."}
          }
        }
      },
      {
        "name": "zfs_list",
        "description": "List ZFS datasets or volumes with usage statistics.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "type":   {"type": "string", "description": "filesystem, volume, snapshot (default: filesystem)."},
            "pool":   {"type": "string", "description": "Restrict to datasets under this pool."},
            "sort":   {"type": "string", "description": "Sort by property (default: used)."},
            "limit":  {"type": "integer", "description": "Maximum rows (default 20)."}
          }
        }
      },
      {
        "name": "disk_usage",
        "description": "Report filesystem disk usage (df -h), optionally for a specific path.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path":      {"type": "string",  "description": "Path to report (default: all mounted filesystems)."},
            "warn_above": {"type": "integer", "description": "Only show filesystems above this % used (0-100)."}
          }
        }
      },
      {
        "name": "system_info",
        "description": "Get host system information: hostname, uptime, load, memory.",
        "inputSchema": {"type": "object", "properties": {}}
      },
      {
        "name": "tailscale_status",
        "description": "Get Tailscale node status and connected peer list.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "peers_only": {"type": "boolean", "description": "Only list peers, not self (default false)."}
          }
        }
      },
      {
        "name": "nix_flake_info",
        "description": "Show current flake inputs and their last-modified dates from the system flake lock.",
        "inputSchema": {"type": "object", "properties": {}}
      },
    ] + ([{
        "name": "restart_service",
        "description": "Restart a systemd service. REQUIRES explicit human confirmation in Matrix before calling — include the confirmation message ID in the call.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name":           {"type": "string", "description": "Service name to restart."},
            "confirmed_by":   {"type": "string", "description": "Matrix message ID of the human confirmation."}
          },
          "required": ["name", "confirmed_by"]
        }
      }] if ALLOW_RESTARTS else [])

    # ---------------------------------------------------------------------------
    # Tool implementations
    # ---------------------------------------------------------------------------

    def run(cmd, timeout=10):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return (r.stdout + r.stderr).strip()
        except subprocess.TimeoutExpired:
            return f"[timeout after {timeout}s]"
        except FileNotFoundError:
            return f"[command not found: {cmd[0]}]"

    def tool_service_status(args):
        name = args["name"]
        if not name.replace("-", "").replace("_", "").replace(".", "").isalnum():
            return "Invalid service name."
        return run(["systemctl", "status", "--no-pager", "-l", name])

    def tool_list_services(args):
        state  = args.get("state", "")
        filt   = args.get("filter", "")
        cmd = ["systemctl", "list-units", "--no-pager", "--no-legend", "--type=service"]
        if state:
            cmd += ["--state", state]
        out = run(cmd)
        if filt:
            out = "\n".join(l for l in out.splitlines() if filt.lower() in l.lower())
        return out or "(none)"

    def tool_service_logs(args):
        name  = args["name"]
        lines = str(args.get("lines", 50))
        since = args.get("since", "")
        if not name.replace("-", "").replace("_", "").replace(".", "").isalnum():
            return "Invalid service name."
        cmd = ["journalctl", "-u", name, "--no-pager", "-n", lines]
        if since:
            cmd += ["--since", since]
        return run(cmd, timeout=15)

    def tool_zfs_pool_status(args):
        pool    = args.get("pool", "")
        verbose = args.get("verbose", False)
        cmd = ["zpool", "status"] + (["-v"] if verbose else ["-x"])
        if pool:
            cmd.append(pool)
        return run(cmd)

    def tool_zfs_list(args):
        kind  = args.get("type", "filesystem")
        pool  = args.get("pool", "")
        sort  = args.get("sort", "used")
        limit = int(args.get("limit", 20))
        cmd = ["zfs", "list", "-t", kind, "-o", "name,used,avail,refer,mountpoint",
               "-s", sort, "-H"]
        if pool:
            cmd += ["-r", pool]
        out = run(cmd)
        lines = out.splitlines()
        if len(lines) > limit:
            lines = lines[:limit] + [f"... ({len(lines) - limit} more)"]
        return "\n".join(lines) or "(none)"

    def tool_disk_usage(args):
        path       = args.get("path", "")
        warn_above = args.get("warn_above", 0)
        cmd = ["df", "-h", "--output=source,size,used,avail,pcent,target"]
        if path:
            cmd.append(path)
        out = run(cmd)
        if warn_above:
            header, *rows = out.splitlines()
            rows = [r for r in rows if _pct(r) >= warn_above]
            out = "\n".join([header] + rows) if rows else f"(all filesystems below {warn_above}%)"
        return out

    def _pct(row):
        try:
            return int(row.split()[-2].rstrip("%"))
        except (IndexError, ValueError):
            return 0

    def tool_system_info(args):
        parts = [
            run(["uname", "-a"]),
            run(["uptime"]),
            run(["free", "-h"]),
        ]
        return "\n\n".join(p for p in parts if p)

    def tool_tailscale_status(args):
        peers_only = args.get("peers_only", False)
        out = run(["tailscale", "status"])
        if peers_only:
            lines = out.splitlines()
            # First line is self; skip it
            out = "\n".join(lines[1:]) if len(lines) > 1 else "(no peers)"
        return out

    def tool_nix_flake_info(args):
        lock = "/etc/nixos/flake.lock"
        if not os.path.exists(lock):
            lock = "/run/current-system/flake.lock"
        if not os.path.exists(lock):
            return "flake.lock not found at /etc/nixos/flake.lock or /run/current-system/flake.lock"
        try:
            data = json.loads(open(lock).read())
            nodes = data.get("nodes", {})
            lines = []
            for name, node in sorted(nodes.items()):
                if name == "root":
                    continue
                locked = node.get("locked", {})
                rev    = locked.get("rev", "")[:8]
                lm     = locked.get("lastModified", "")
                lines.append(f"{name:30s}  rev={rev}  lastModified={lm}")
            return "\n".join(lines) or "(empty lock)"
        except Exception as e:
            return f"Error reading flake.lock: {e}"

    def tool_restart_service(args):
        if not ALLOW_RESTARTS:
            return "restart_service is disabled on this host."
        name         = args.get("name", "")
        confirmed_by = args.get("confirmed_by", "")
        if not confirmed_by:
            return "ERROR: confirmed_by is required. Get explicit human confirmation in Matrix first."
        if not name.replace("-", "").replace("_", "").replace(".", "").isalnum():
            return "Invalid service name."
        result = run(["systemctl", "restart", name], timeout=30)
        return f"Restarted {name} (confirmed by {confirmed_by}).\n{result}"

    TOOL_IMPLS = {
        "service_status":   tool_service_status,
        "list_services":    tool_list_services,
        "service_logs":     tool_service_logs,
        "zfs_pool_status":  tool_zfs_pool_status,
        "zfs_list":         tool_zfs_list,
        "disk_usage":       tool_disk_usage,
        "system_info":      tool_system_info,
        "tailscale_status": tool_tailscale_status,
        "nix_flake_info":   tool_nix_flake_info,
        "restart_service":  tool_restart_service,
    }

    # ---------------------------------------------------------------------------
    # Minimal SSE MCP server
    # ---------------------------------------------------------------------------

    # session_id → queue of outbound SSE strings
    _sessions = {}
    _sessions_lock = threading.Lock()

    def _send(session_id, event_type, data):
        msg = f"event: {event_type}\ndata: {json.dumps(data)}\n\n"
        with _sessions_lock:
            q = _sessions.get(session_id)
        if q:
            q.put(msg)

    def _handle_jsonrpc(session_id, body):
        try:
            req = json.loads(body)
        except Exception:
            return
        method = req.get("method", "")
        rid    = req.get("id")
        params = req.get("params", {})

        def respond(result=None, error=None):
            r = {"jsonrpc": "2.0", "id": rid}
            if error:
                r["error"] = error
            else:
                r["result"] = result
            _send(session_id, "message", r)

        if method == "initialize":
            respond({
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "hermes-homelab-mcp", "version": "1.0.0"}
            })
        elif method == "tools/list":
            respond({"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name", "")
            args = params.get("arguments", {})
            impl = TOOL_IMPLS.get(name)
            if not impl:
                respond(error={"code": -32601, "message": f"Unknown tool: {name}"})
                return
            try:
                result = impl(args)
                respond({"content": [{"type": "text", "text": str(result)}]})
            except Exception as e:
                respond(error={"code": -32000, "message": str(e),
                               "data": traceback.format_exc()})
        elif method == "notifications/initialized":
            pass  # no response needed
        else:
            if rid is not None:
                respond(error={"code": -32601, "message": f"Method not found: {method}"})

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # suppress access log noise

        def do_GET(self):
            if not self.path.startswith("/sse"):
                self.send_error(404)
                return
            session_id = str(uuid.uuid4())
            q = queue.Queue()
            with _sessions_lock:
                _sessions[session_id] = q
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            # Send endpoint event so client knows where to POST
            endpoint_event = f"event: endpoint\ndata: \"/message?session_id={session_id}\"\n\n"
            try:
                self.wfile.write(endpoint_event.encode())
                self.wfile.flush()
                while True:
                    try:
                        msg = q.get(timeout=30)
                        self.wfile.write(msg.encode())
                        self.wfile.flush()
                    except queue.Empty:
                        # keep-alive ping
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                with _sessions_lock:
                    _sessions.pop(session_id, None)

        def do_POST(self):
            if not self.path.startswith("/message"):
                self.send_error(404)
                return
            qs = parse_qs(urlparse(self.path).query)
            session_id = (qs.get("session_id", [None])[0])
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            threading.Thread(
                target=_handle_jsonrpc, args=(session_id, body), daemon=True
            ).start()
            self.send_response(202)
            self.end_headers()

    if __name__ == "__main__":
        server = HTTPServer(("127.0.0.1", PORT), Handler)
        print(f"hermes-homelab-mcp listening on 127.0.0.1:{PORT}", flush=True)
        server.serve_forever()
  '';

  mcpBin = pkgs.writeShellScriptBin "hermes-homelab-mcp" ''
    exec ${pkgs.python3}/bin/python3 ${mcpServer} "$@"
  '';

in
{
  options.modules.services.ai.hermes-homelab-mcp = {
    enable = mkEnableOption "Hermes homelab MCP server";

    port = mkOption {
      type = types.port;
      default = 7830;
      description = "Port the MCP SSE server listens on (127.0.0.1 only).";
    };

    allowRestarts = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the restart_service tool. Each call requires explicit Matrix confirmation (enforced by the calling skill).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ mcpBin ];

    systemd.services.hermes-homelab-mcp = {
      description = "Hermes homelab MCP SSE server";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];

      environment = {
        HOMELAB_MCP_PORT           = toString cfg.port;
        HOMELAB_MCP_ALLOW_RESTARTS = if cfg.allowRestarts then "1" else "0";
      };

      serviceConfig = {
        ExecStart     = "${mcpBin}/bin/hermes-homelab-mcp";
        Restart       = "on-failure";
        RestartSec    = "5s";
        # Run as root so systemctl, journalctl, zpool, df all work without sudo.
        # The server only binds 127.0.0.1 — not exposed externally.
        User          = "root";
        # Harden what we can while preserving host visibility
        PrivateTmp    = true;
        ProtectHome   = "read-only";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/run" "/tmp" ];
      };
    };
  };
}
