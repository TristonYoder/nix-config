{ config, lib, pkgs, ... }:

# Homelab MCP server for Hermes.
#
# Exposes structured tools over SSE on localhost so Hermes can query:
#   Infrastructure  — systemd, journald, ZFS, disk, Tailscale, nix flake
#   Life / media    — Immich, Jellyseerr, Actual Budget, Vaultwarden stats
#   Environment     — weather, network stats
#
# Hermes reaches it at http://localhost:<port>/sse via --network=host.
# Enabled automatically when modules.services.ai.hermes-agent.homelabMcp.enable = true.

with lib;
let
  cfg = config.modules.services.ai.hermes-homelab-mcp;

  mcpServer = pkgs.writeText "hermes-homelab-mcp.py" ''
    #!/usr/bin/env python3
    """Homelab MCP SSE server for Hermes. Stdlib only — no mcp/fastmcp dependency."""
    import json, os, subprocess, threading, queue, time, traceback, uuid, urllib.request
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from urllib.parse import urlparse, parse_qs
    from datetime import date, datetime, timezone, timedelta

    ALLOW_RESTARTS = os.environ.get("HOMELAB_MCP_ALLOW_RESTARTS", "0") == "1"
    PORT           = int(os.environ.get("HOMELAB_MCP_PORT", "7830"))

    ACTUAL_API_URL    = os.environ.get("ACTUAL_API_URL",    "http://localhost:5007")
    ACTUAL_API_KEY    = os.environ.get("ACTUAL_API_KEY",    "")
    IMMICH_API_URL    = os.environ.get("IMMICH_API_URL",    "http://localhost:2283")
    IMMICH_API_KEY    = os.environ.get("IMMICH_API_KEY",    "")
    JELLYSEERR_URL    = os.environ.get("JELLYSEERR_URL",    "http://localhost:5055")
    JELLYSEERR_KEY    = os.environ.get("JELLYSEERR_API_KEY","")
    VAULTWARDEN_URL   = os.environ.get("VAULTWARDEN_URL",   "http://localhost:8222")
    WEATHER_LOCATION  = os.environ.get("WEATHER_LOCATION",  "")

    # ── Helpers ────────────────────────────────────────────────────────────────

    def run(cmd, timeout=15):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return (r.stdout + r.stderr).strip()
        except subprocess.TimeoutExpired:
            return f"[timeout after {timeout}s]"
        except FileNotFoundError:
            return f"[not found: {cmd[0]}]"

    def http_get(url, headers=None, timeout=10):
        req = urllib.request.Request(url, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            return {"error": str(e)}

    def http_post(url, data, headers=None, timeout=10):
        body = json.dumps(data).encode()
        h = {"Content-Type": "application/json", **(headers or {})}
        req = urllib.request.Request(url, data=body, headers=h, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            return {"error": str(e)}

    def actual_headers():
        h = {"Content-Type": "application/json"}
        if ACTUAL_API_KEY:
            h["x-api-key"] = ACTUAL_API_KEY
        return h

    def immich_headers():
        h = {"Accept": "application/json"}
        if IMMICH_API_KEY:
            h["x-api-key"] = IMMICH_API_KEY
        return h

    def jellyseerr_headers():
        h = {"Accept": "application/json"}
        if JELLYSEERR_KEY:
            h["X-Api-Key"] = JELLYSEERR_KEY
        return h

    # ── Tool definitions ───────────────────────────────────────────────────────

    TOOLS = [
      # ── Infrastructure ───────────────────────────────────────────────────
      {
        "name": "service_status",
        "description": "Get the current status of a systemd service.",
        "inputSchema": {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
      },
      {
        "name": "list_services",
        "description": "List systemd services, optionally filtered by state or name fragment.",
        "inputSchema": {"type":"object","properties":{
          "state":{"type":"string","description":"running, failed, inactive, etc."},
          "filter":{"type":"string","description":"Name substring to match."}
        }}
      },
      {
        "name": "service_logs",
        "description": "Fetch recent journal log lines for a systemd service.",
        "inputSchema": {"type":"object","properties":{
          "name":{"type":"string"},"lines":{"type":"integer"},"since":{"type":"string"}
        },"required":["name"]}
      },
      {
        "name": "zfs_pool_status",
        "description": "ZFS pool health. Omit pool for all pools.",
        "inputSchema": {"type":"object","properties":{
          "pool":{"type":"string"},"verbose":{"type":"boolean"}
        }}
      },
      {
        "name": "zfs_list",
        "description": "List ZFS datasets with usage statistics.",
        "inputSchema": {"type":"object","properties":{
          "type":{"type":"string"},"pool":{"type":"string"},
          "sort":{"type":"string"},"limit":{"type":"integer"}
        }}
      },
      {
        "name": "disk_usage",
        "description": "Filesystem disk usage (df -h). Optionally filter to filesystems above a threshold.",
        "inputSchema": {"type":"object","properties":{
          "path":{"type":"string"},"warn_above":{"type":"integer"}
        }}
      },
      {
        "name": "system_info",
        "description": "Hostname, uptime, load, memory summary.",
        "inputSchema": {"type":"object","properties":{}}
      },
      {
        "name": "tailscale_status",
        "description": "Tailscale mesh status and peer list.",
        "inputSchema": {"type":"object","properties":{
          "peers_only":{"type":"boolean"}
        }}
      },
      {
        "name": "nix_flake_info",
        "description": "Current flake inputs and last-modified dates from the system flake lock.",
        "inputSchema": {"type":"object","properties":{}}
      },
      # ── Life / media ─────────────────────────────────────────────────────
      {
        "name": "weather",
        "description": "Current weather and 3-day forecast for the configured location.",
        "inputSchema": {"type":"object","properties":{
          "location":{"type":"string","description":"Override location (city name or lat,lon)."}
        }}
      },
      {
        "name": "immich_on_this_day",
        "description": "Photos taken on this calendar date in prior years, from Immich.",
        "inputSchema": {"type":"object","properties":{
          "date":{"type":"string","description":"ISO date (YYYY-MM-DD). Defaults to today."},
          "limit":{"type":"integer","description":"Max photos to return (default 5)."}
        }}
      },
      {
        "name": "immich_search",
        "description": "Search Immich photos by date range, city, or description.",
        "inputSchema": {"type":"object","properties":{
          "query":{"type":"string","description":"Smart search query."},
          "date_from":{"type":"string","description":"ISO date YYYY-MM-DD."},
          "date_to":{"type":"string","description":"ISO date YYYY-MM-DD."},
          "city":{"type":"string"},
          "limit":{"type":"integer","default":10}
        }}
      },
      {
        "name": "immich_create_album",
        "description": "Create an Immich album from a list of asset IDs.",
        "inputSchema": {"type":"object","properties":{
          "name":{"type":"string"},"asset_ids":{"type":"array","items":{"type":"string"}}
        },"required":["name","asset_ids"]}
      },
      {
        "name": "jellyseerr_requests",
        "description": "List Jellyseerr media requests, optionally filtered by status.",
        "inputSchema": {"type":"object","properties":{
          "status":{"type":"string","description":"pending, approved, available, unavailable. Omit for all."},
          "limit":{"type":"integer","default":20}
        }}
      },
      {
        "name": "actual_spending_summary",
        "description": "Monthly spending totals by category from Actual Budget.",
        "inputSchema": {"type":"object","properties":{
          "month":{"type":"string","description":"YYYY-MM (defaults to current month)."}
        }}
      },
      {
        "name": "actual_budget_status",
        "description": "Per-category budget vs spent for a month — shows over/under at a glance.",
        "inputSchema": {"type":"object","properties":{
          "month":{"type":"string","description":"YYYY-MM (defaults to current month)."}
        }}
      },
      {
        "name": "actual_recent_transactions",
        "description": "Recent transactions across all accounts from Actual Budget.",
        "inputSchema": {"type":"object","properties":{
          "days":{"type":"integer","description":"Lookback window in days (default 7)."},
          "limit":{"type":"integer","default":30}
        }}
      },
      {
        "name": "vaultwarden_health",
        "description": "Vaultwarden admin stats: user count, active sessions, 2FA adoption.",
        "inputSchema": {"type":"object","properties":{}}
      },
    ] + ([{
        "name": "restart_service",
        "description": "Restart a systemd service. Requires confirmed_by (Matrix message ID of explicit human approval).",
        "inputSchema": {"type":"object","properties":{
          "name":{"type":"string"},"confirmed_by":{"type":"string"}
        },"required":["name","confirmed_by"]}
      }] if ALLOW_RESTARTS else [])

    # ── Tool implementations ───────────────────────────────────────────────────

    def _safe_name(s):
        return s.replace("-","").replace("_","").replace(".","").replace("/","").isalnum()

    def tool_service_status(args):
        n = args["name"]
        return run(["systemctl","status","--no-pager","-l", n])

    def tool_list_services(args):
        state = args.get("state","")
        filt  = args.get("filter","")
        cmd   = ["systemctl","list-units","--no-pager","--no-legend","--type=service"]
        if state: cmd += ["--state", state]
        out = run(cmd)
        if filt:
            out = "\n".join(l for l in out.splitlines() if filt.lower() in l.lower())
        return out or "(none)"

    def tool_service_logs(args):
        n     = args["name"]
        lines = str(args.get("lines", 50))
        since = args.get("since","")
        cmd = ["journalctl","-u",n,"--no-pager","-n",lines]
        if since: cmd += ["--since", since]
        return run(cmd, timeout=20)

    def tool_zfs_pool_status(args):
        pool    = args.get("pool","")
        verbose = args.get("verbose", False)
        cmd = ["zpool","status"] + (["-v"] if verbose else ["-x"])
        if pool: cmd.append(pool)
        return run(cmd)

    def tool_zfs_list(args):
        kind  = args.get("type","filesystem")
        pool  = args.get("pool","")
        sort  = args.get("sort","used")
        limit = int(args.get("limit",20))
        cmd = ["zfs","list","-t",kind,"-o","name,used,avail,refer,mountpoint","-s",sort,"-H"]
        if pool: cmd += ["-r", pool]
        out   = run(cmd)
        lines = out.splitlines()
        if len(lines) > limit:
            lines = lines[:limit] + [f"... ({len(lines)-limit} more)"]
        return "\n".join(lines) or "(none)"

    def tool_disk_usage(args):
        path  = args.get("path","")
        above = args.get("warn_above", 0)
        cmd   = ["df","-h","--output=source,size,used,avail,pcent,target"]
        if path: cmd.append(path)
        out = run(cmd)
        if above:
            hdr, *rows = out.splitlines()
            rows = [r for r in rows if _pct(r) >= above]
            out = ("\n".join([hdr]+rows)) if rows else f"(all below {above}%)"
        return out

    def _pct(row):
        try: return int(row.split()[-2].rstrip("%"))
        except: return 0

    def tool_system_info(args):
        return "\n\n".join(filter(None,[run(["uname","-a"]),run(["uptime"]),run(["free","-h"])]))

    def tool_tailscale_status(args):
        out = run(["tailscale","status"])
        if args.get("peers_only"):
            lines = out.splitlines()
            out = "\n".join(lines[1:]) if len(lines)>1 else "(no peers)"
        return out

    def tool_nix_flake_info(args):
        for path in ["/etc/nixos/flake.lock","/run/current-system/flake.lock"]:
            if os.path.exists(path):
                try:
                    data  = json.loads(open(path).read())
                    nodes = data.get("nodes",{})
                    lines = []
                    for name,node in sorted(nodes.items()):
                        if name == "root": continue
                        locked = node.get("locked",{})
                        rev    = locked.get("rev","")[:8]
                        lm     = locked.get("lastModified","")
                        lines.append(f"{name:30s}  rev={rev}  lastModified={lm}")
                    return "\n".join(lines) or "(empty)"
                except Exception as e:
                    return f"Error: {e}"
        return "flake.lock not found"

    def tool_weather(args):
        loc = args.get("location","") or WEATHER_LOCATION or "auto"
        url = f"https://wttr.in/{urllib.parse.quote(loc)}?format=4&M"
        try:
            req = urllib.request.Request(url, headers={"User-Agent":"curl/7.0"})
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.read().decode().strip()
        except Exception as e:
            return f"Weather unavailable: {e}"

    def tool_immich_on_this_day(args):
        today     = args.get("date") or date.today().isoformat()
        limit     = int(args.get("limit", 5))
        d         = date.fromisoformat(today)
        results   = []
        base_url  = IMMICH_API_URL.rstrip("/")
        for year_offset in range(1, 10):
            year = d.year - year_offset
            if year < 2000: break
            day_start = date(year, d.month, d.day)
            day_end   = day_start + timedelta(days=1)
            url = (f"{base_url}/api/search/metadata"
                   f"?takenAfter={day_start.isoformat()}T00:00:00.000Z"
                   f"&takenBefore={day_end.isoformat()}T00:00:00.000Z"
                   f"&withExif=true&size={limit}")
            data = http_get(url, immich_headers())
            assets = data.get("assets", {}).get("items", [])
            for a in assets:
                city = a.get("exifInfo", {}).get("city","")
                results.append({
                    "id":    a.get("id"),
                    "date":  a.get("localDateTime","")[:10],
                    "city":  city,
                    "type":  a.get("type",""),
                    "thumb": f"{base_url}/api/assets/{a.get('id')}/thumbnail",
                })
            if len(results) >= limit: break
        if not results:
            return f"No photos found on {d.month}/{d.day} in previous years."
        lines = [f"Photos from {d.strftime('%B %-d')} in past years:"]
        for r in results[:limit]:
            loc = f" — {r['city']}" if r['city'] else ""
            lines.append(f"  [{r['date']}]{loc}  {r['thumb']}")
        return "\n".join(lines)

    def tool_immich_search(args):
        query     = args.get("query","")
        date_from = args.get("date_from","")
        date_to   = args.get("date_to","")
        city      = args.get("city","")
        limit     = int(args.get("limit", 10))
        base_url  = IMMICH_API_URL.rstrip("/")
        params = {"withExif":"true", "size": str(limit)}
        if date_from: params["takenAfter"]  = f"{date_from}T00:00:00.000Z"
        if date_to:   params["takenBefore"] = f"{date_to}T23:59:59.999Z"
        if city:      params["city"]        = city
        qs  = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k,v in params.items())
        url = f"{base_url}/api/search/metadata?{qs}"
        if query:
            data = http_post(f"{base_url}/api/search/smart", {"query":query,"size":limit}, immich_headers())
            assets = data.get("assets",{}).get("items",[])
        else:
            data   = http_get(url, immich_headers())
            assets = data.get("assets",{}).get("items",[])
        if not assets:
            return "No photos found."
        lines = []
        for a in assets[:limit]:
            city_str = a.get("exifInfo",{}).get("city","")
            loc = f" — {city_str}" if city_str else ""
            lines.append(f"  {a.get('localDateTime','')[:10]}{loc}  id={a.get('id')}  {IMMICH_API_URL}/api/assets/{a.get('id')}/thumbnail")
        return f"Found {len(assets)} photo(s):\n" + "\n".join(lines)

    def tool_immich_create_album(args):
        name      = args["name"]
        asset_ids = args["asset_ids"]
        base_url  = IMMICH_API_URL.rstrip("/")
        result = http_post(f"{base_url}/api/albums",
                           {"albumName": name, "assetIds": asset_ids},
                           immich_headers())
        if "error" in result:
            return f"Failed: {result['error']}"
        album_id = result.get("id","")
        return f"Album '{name}' created with {len(asset_ids)} photos. ID: {album_id}"

    def tool_jellyseerr_requests(args):
        status = args.get("status","")
        limit  = int(args.get("limit", 20))
        url    = f"{JELLYSEERR_URL}/api/v1/request?take={limit}"
        if status: url += f"&filter={status}"
        data   = http_get(url, jellyseerr_headers())
        if "error" in data:
            return f"Jellyseerr error: {data['error']}"
        items = data.get("results", [])
        if not items:
            return "No requests found."
        lines = []
        for r in items:
            media     = r.get("media",{})
            title     = media.get("originalTitle","") or media.get("name","unknown")
            req_status= r.get("status", "?")
            typ       = r.get("type","")
            requested_by = r.get("requestedBy",{}).get("displayName","?")
            lines.append(f"  [{req_status}] {title} ({typ}) — requested by {requested_by}")
        return f"{len(items)} request(s):\n" + "\n".join(lines)

    def tool_actual_spending_summary(args):
        month = args.get("month") or date.today().strftime("%Y-%m")
        url   = f"{ACTUAL_API_URL}/api/budget-months/{month}/categories"
        data  = http_get(url, actual_headers())
        if "error" in data:
            return f"Actual Budget error: {data['error']}"
        cats  = data if isinstance(data, list) else data.get("categories", [])
        if not cats:
            return f"No category data for {month}."
        lines = [f"Spending summary for {month}:"]
        total = 0
        for c in sorted(cats, key=lambda x: abs(x.get("spent",0)), reverse=True):
            name    = c.get("name","?")
            spent   = abs(c.get("spent",0)) / 100
            budget  = abs(c.get("budgeted",0)) / 100
            total  += spent
            lines.append(f"  {name:30s}  spent=${spent:.2f}  budget=${budget:.2f}")
        lines.append(f"\n  Total spent: ${total:.2f}")
        return "\n".join(lines)

    def tool_actual_budget_status(args):
        month = args.get("month") or date.today().strftime("%Y-%m")
        url   = f"{ACTUAL_API_URL}/api/budget-months/{month}/categories"
        data  = http_get(url, actual_headers())
        if "error" in data:
            return f"Actual Budget error: {data['error']}"
        cats  = data if isinstance(data, list) else data.get("categories", [])
        over  = []
        under = []
        for c in cats:
            name    = c.get("name","?")
            spent   = abs(c.get("spent",0)) / 100
            budget  = abs(c.get("budgeted",0)) / 100
            if budget <= 0: continue
            pct = spent / budget * 100
            if pct > 100:
                over.append(f"  OVER  {name:28s} ${spent:.0f} / ${budget:.0f} ({pct:.0f}%)")
            elif pct > 80:
                under.append(f"  WARN  {name:28s} ${spent:.0f} / ${budget:.0f} ({pct:.0f}%)")
            else:
                under.append(f"  OK    {name:28s} ${spent:.0f} / ${budget:.0f} ({pct:.0f}%)")
        lines = [f"Budget status for {month}:"] + over + under
        return "\n".join(lines) if len(lines)>1 else f"No budgeted categories for {month}."

    def tool_actual_recent_transactions(args):
        days  = int(args.get("days", 7))
        limit = int(args.get("limit", 30))
        since = (date.today() - timedelta(days=days)).isoformat()
        url   = f"{ACTUAL_API_URL}/api/transactions?since_date={since}&limit={limit}"
        data  = http_get(url, actual_headers())
        if "error" in data:
            return f"Actual Budget error: {data['error']}"
        txns  = data if isinstance(data, list) else data.get("transactions", [])
        if not txns:
            return f"No transactions in the last {days} days."
        lines = [f"Recent transactions (last {days} days):"]
        for t in txns[:limit]:
            amt   = t.get("amount",0) / 100
            name  = t.get("payee_name","") or t.get("imported_payee","?")
            dt    = t.get("date","?")
            acct  = t.get("account_name","")
            lines.append(f"  {dt}  {name:30s}  ${amt:8.2f}  [{acct}]")
        return "\n".join(lines)

    def tool_vaultwarden_health(args):
        # Vaultwarden admin API — requires VAULTWARDEN_ADMIN_TOKEN in env
        token = os.environ.get("VAULTWARDEN_ADMIN_TOKEN","")
        if not token:
            return "VAULTWARDEN_ADMIN_TOKEN not set — admin API unavailable."
        url  = f"{VAULTWARDEN_URL}/admin/diagnostics"
        req  = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                data = json.loads(r.read().decode())
            return json.dumps(data, indent=2)
        except Exception as e:
            return f"Vaultwarden admin error: {e}"

    def tool_restart_service(args):
        if not ALLOW_RESTARTS:
            return "restart_service is disabled."
        name         = args.get("name","")
        confirmed_by = args.get("confirmed_by","")
        if not confirmed_by:
            return "ERROR: confirmed_by required — get explicit Matrix confirmation first."
        result = run(["systemctl","restart",name], timeout=30)
        return f"Restarted {name} (confirmed: {confirmed_by}).\n{result}"

    TOOL_IMPLS = {
        "service_status":            tool_service_status,
        "list_services":             tool_list_services,
        "service_logs":              tool_service_logs,
        "zfs_pool_status":           tool_zfs_pool_status,
        "zfs_list":                  tool_zfs_list,
        "disk_usage":                tool_disk_usage,
        "system_info":               tool_system_info,
        "tailscale_status":          tool_tailscale_status,
        "nix_flake_info":            tool_nix_flake_info,
        "weather":                   tool_weather,
        "immich_on_this_day":        tool_immich_on_this_day,
        "immich_search":             tool_immich_search,
        "immich_create_album":       tool_immich_create_album,
        "jellyseerr_requests":       tool_jellyseerr_requests,
        "actual_spending_summary":   tool_actual_spending_summary,
        "actual_budget_status":      tool_actual_budget_status,
        "actual_recent_transactions":tool_actual_recent_transactions,
        "vaultwarden_health":        tool_vaultwarden_health,
        "restart_service":           tool_restart_service,
    }

    # ── SSE MCP transport ──────────────────────────────────────────────────────

    _sessions = {}
    _sessions_lock = threading.Lock()

    def _send(session_id, event_type, data):
        msg = f"event: {event_type}\ndata: {json.dumps(data)}\n\n"
        with _sessions_lock:
            q = _sessions.get(session_id)
        if q: q.put(msg)

    def _handle_jsonrpc(session_id, body):
        try: req = json.loads(body)
        except Exception: return
        method = req.get("method","")
        rid    = req.get("id")
        params = req.get("params",{})

        def respond(result=None, error=None):
            r = {"jsonrpc":"2.0","id":rid}
            if error: r["error"] = error
            else:     r["result"] = result
            _send(session_id, "message", r)

        if method == "initialize":
            respond({"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"hermes-homelab-mcp","version":"2.0.0"}})
        elif method == "tools/list":
            respond({"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name","")
            args = params.get("arguments",{})
            impl = TOOL_IMPLS.get(name)
            if not impl:
                respond(error={"code":-32601,"message":f"Unknown tool: {name}"})
                return
            try:
                result = impl(args)
                respond({"content":[{"type":"text","text":str(result)}]})
            except Exception as e:
                respond(error={"code":-32000,"message":str(e),"data":traceback.format_exc()})
        elif method == "notifications/initialized":
            pass
        elif rid is not None:
            respond(error={"code":-32601,"message":f"Unknown: {method}"})

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args): pass

        def do_GET(self):
            if not self.path.startswith("/sse"):
                self.send_error(404); return
            sid = str(uuid.uuid4())
            q   = queue.Queue()
            with _sessions_lock: _sessions[sid] = q
            self.send_response(200)
            self.send_header("Content-Type","text/event-stream")
            self.send_header("Cache-Control","no-cache")
            self.send_header("Connection","keep-alive")
            self.end_headers()
            try:
                self.wfile.write(f'event: endpoint\ndata: "/message?session_id={sid}"\n\n'.encode())
                self.wfile.flush()
                while True:
                    try:
                        msg = q.get(timeout=30)
                        self.wfile.write(msg.encode())
                        self.wfile.flush()
                    except queue.Empty:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError): pass
            finally:
                with _sessions_lock: _sessions.pop(sid, None)

        def do_POST(self):
            if not self.path.startswith("/message"):
                self.send_error(404); return
            qs  = parse_qs(urlparse(self.path).query)
            sid = (qs.get("session_id",[None])[0])
            n   = int(self.headers.get("Content-Length",0))
            body = self.rfile.read(n)
            threading.Thread(target=_handle_jsonrpc, args=(sid,body), daemon=True).start()
            self.send_response(202)
            self.end_headers()

    if __name__ == "__main__":
        import urllib.parse
        server = HTTPServer(("127.0.0.1", PORT), Handler)
        print(f"hermes-homelab-mcp v2 listening on 127.0.0.1:{PORT}", flush=True)
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
      type    = types.port;
      default = 7830;
      description = "Port the MCP SSE server listens on (127.0.0.1 only).";
    };

    allowRestarts = mkOption {
      type    = types.bool;
      default = false;
      description = "Expose restart_service tool. Requires confirmed_by (Matrix confirmation message ID).";
    };

    weatherLocation = mkOption {
      type    = types.str;
      default = "";
      description = "Default location for weather tool (city name or lat,lon). Empty = wttr.in auto-detect.";
    };

    actualApiUrl = mkOption {
      type    = types.str;
      default = "http://localhost:${toString config.modules.services.productivity.actualHttpApi.port}";
      description = "Actual Budget HTTP API base URL.";
    };

    actualApiKeyEnvVar = mkOption {
      type    = types.str;
      default = "ACTUAL_HTTP_API_KEY";
      description = "Env var name holding the Actual HTTP API key.";
    };

    immichApiUrl = mkOption {
      type    = types.str;
      default = "http://localhost:${toString config.modules.services.media.immich.port}";
      description = "Immich API base URL.";
    };

    immichApiKeyEnvVar = mkOption {
      type    = types.str;
      default = "IMMICH_API_KEY";
      description = "Env var name holding the Immich API key.";
    };

    jellyseerrUrl = mkOption {
      type    = types.str;
      default = "http://localhost:${toString config.modules.services.media.jellyseerr.port}";
      description = "Jellyseerr base URL.";
    };

    jellyseerrApiKeyEnvVar = mkOption {
      type    = types.str;
      default = "JELLYSEERR_API_KEY";
      description = "Env var name holding the Jellyseerr API key.";
    };

    vaultwardenUrl = mkOption {
      type    = types.str;
      default = "http://localhost:${toString config.modules.services.productivity.vaultwarden.port}";
      description = "Vaultwarden base URL.";
    };

    environmentFile = mkOption {
      type    = types.nullOr types.path;
      default = null;
      description = "Agenix-decrypted env file supplying API keys referenced by *ApiKeyEnvVar options.";
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
        ACTUAL_API_URL             = cfg.actualApiUrl;
        ACTUAL_API_KEY_ENV         = cfg.actualApiKeyEnvVar;
        IMMICH_API_URL             = cfg.immichApiUrl;
        IMMICH_API_KEY_ENV         = cfg.immichApiKeyEnvVar;
        JELLYSEERR_URL             = cfg.jellyseerrUrl;
        JELLYSEERR_API_KEY_ENV     = cfg.jellyseerrApiKeyEnvVar;
        VAULTWARDEN_URL            = cfg.vaultwardenUrl;
        WEATHER_LOCATION           = cfg.weatherLocation;
      };

      serviceConfig = {
        ExecStart       = "${mcpBin}/bin/hermes-homelab-mcp";
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart         = "on-failure";
        RestartSec      = "5s";
        User            = "root";
        PrivateTmp      = true;
        ProtectHome     = "read-only";
        ProtectSystem   = "strict";
        ReadWritePaths  = [ "/run" "/tmp" ];
      };
    };
  };
}
