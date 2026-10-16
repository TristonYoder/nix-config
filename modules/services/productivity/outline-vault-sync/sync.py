"""One-way sync of an Obsidian vault into Outline.

The vault is the only source of truth and Outline is a read-only copy.
Nothing here writes to the vault.

Mapping: each top-level vault folder is a collection, notes at the vault root
go to one root collection, and deeper folders become parent documents (their
folder note supplies the content, or the parent is left empty).
"""

import argparse
import fcntl
import hashlib
import json
import logging
import mimetypes
import os
import re
import sys
import time
import urllib.parse
import uuid
from dataclasses import dataclass

import requests

log = logging.getLogger("outline-vault-sync")

# Outline's DocumentValidation.maxTitleLength
TITLE_MAX = 100
STATE_VERSION = 1

# Sync-tool and editor artifacts, matched against every path segment. Hidden
# entries cover .obsidian, .trash, .stfolder, .stversions, .git and Syncthing's
# .syncthing.*.tmp files.
BUILTIN_IGNORE_SEGMENTS = [
    r"[.].*",
    r"~syncthing~.*[.]tmp",
    r".*[.]sync-conflict-.*",
    r".*[.]sw[a-p]",
    r".*~",
    r"4913",
    r".*[.]tmp",
]

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".avif"}


# --------------------------------------------------------------------------
# Path matching
#
# Patterns are written once in POSIX ERE syntax that Python's re also
# accepts, so the watcher's inotifywait --exclude and the sync use the same
# rules.
# --------------------------------------------------------------------------

def ere_escape(s):
    out = []
    for c in s:
        if c in ".*+?(){}|$[":
            out.append("[" + c + "]")
        elif c in "^\\":
            out.append("\\" + c)
        else:
            out.append(c)
    return "".join(out)


def glob_to_ere(pattern):
    """Vault-relative glob to ERE.

    '*' stays within a segment and '**' crosses segments. A match also covers
    everything below it, so 'AIOS/history/' and 'AIOS/history' are the same.
    A pattern without '/' matches at any depth.
    """
    p = pattern.strip().strip("/")
    out = []
    i = 0
    while i < len(p):
        if p.startswith("**", i):
            out.append(".*")
            i += 2
        elif p[i] == "*":
            out.append("[^/]*")
            i += 1
        elif p[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(ere_escape(p[i]))
            i += 1
    prefix = "" if "/" in p else "(.*/)?"
    return prefix + "".join(out) + "(/.*)?"


def ignore_ere(excludes):
    """ERE for a vault-relative path that should never be published."""
    alts = ["(.*/)?(" + "|".join(BUILTIN_IGNORE_SEGMENTS) + ")(/.*)?"]
    alts += [glob_to_ere(p) for p in excludes if p.strip().strip("/")]
    return "(" + "|".join(alts) + ")"


# --------------------------------------------------------------------------
# Vault scan
# --------------------------------------------------------------------------

@dataclass
class Vault:
    root: str
    notes: list        # vault-relative .md paths
    files: list        # vault-relative non-.md paths (attachment candidates)
    unreadable: list   # vault-relative paths we could not read


def scan(root, ignore_re):
    notes, files, unreadable = [], [], []

    def onerror(err):
        rel = os.path.relpath(err.filename, root)
        log.error("cannot read directory %s: %s", rel, err.strerror)
        unreadable.append(rel)

    for dirpath, dirnames, filenames in os.walk(root, onerror=onerror):
        reldir = os.path.relpath(dirpath, root)
        reldir = "" if reldir == "." else reldir

        def rel(name):
            return f"{reldir}/{name}" if reldir else name

        dirnames[:] = sorted(
            d for d in dirnames
            if not ignore_re.fullmatch(rel(d))
            and not os.path.islink(os.path.join(dirpath, d))
        )
        for name in sorted(filenames):
            r = rel(name)
            full = os.path.join(dirpath, name)
            # Symlinks could point outside the vault
            if ignore_re.fullmatch(r) or os.path.islink(full):
                continue
            if not os.access(full, os.R_OK):
                log.error("cannot read %s (permission denied)", r)
                unreadable.append(r)
                continue
            (notes if name.lower().endswith(".md") else files).append(r)
    return Vault(root, notes, files, unreadable)


# --------------------------------------------------------------------------
# Document tree
# --------------------------------------------------------------------------

@dataclass
class Node:
    key: str          # "A/B/" for a folder, "A/B/c.md" for a note
    collection: str   # collection name
    parent: object    # parent node key, None at the collection root
    title: str
    source: object    # vault-relative .md providing content, or None
    depth: int


def stem(rel):
    return rel[:-3] if rel.lower().endswith(".md") else rel


def build_tree(vault, root_collection, collection_names):
    def collection_of(rel):
        if "/" not in rel:
            return root_collection
        top = rel.split("/", 1)[0]
        return collection_names.get(top, top)

    def parent_of(rel):
        d = os.path.dirname(rel)
        return d + "/" if "/" in d else None

    dirs = set()
    for n in vault.notes:
        parts = n.split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]))

    # Folder notes: "A/B/B.md" (inside) wins over "A/B.md" (sibling). Top-level
    # folders are collections, so a note named after one stays a normal note.
    folder_note = {}
    for n in vault.notes:
        d = os.path.dirname(n)
        if "/" in d and os.path.basename(d) == os.path.basename(stem(n)):
            folder_note[d] = n
    for n in vault.notes:
        s = stem(n)
        if "/" in s and s in dirs and s not in folder_note:
            folder_note[s] = n

    nodes, file_to_key = {}, {}
    for d in sorted(dirs):
        if "/" not in d:
            continue
        key = d + "/"
        nodes[key] = Node(key, collection_of(d), parent_of(d),
                          os.path.basename(d)[:TITLE_MAX], folder_note.get(d),
                          d.count("/"))
        if d in folder_note:
            file_to_key[folder_note[d]] = key
    for n in vault.notes:
        if n in file_to_key:
            continue
        nodes[n] = Node(n, collection_of(n), parent_of(n),
                        os.path.basename(stem(n))[:TITLE_MAX], n, n.count("/"))
        file_to_key[n] = n
    return nodes, file_to_key


# --------------------------------------------------------------------------
# Link resolution (Obsidian semantics: exact path, then path suffix, then
# basename; ties go to the linking note's folder, then the shortest path)
# --------------------------------------------------------------------------

class Resolver:
    def __init__(self, paths, strip_ext):
        self.paths = paths
        self.strip_ext = strip_ext
        self.by_path, self.by_name = {}, {}
        for p in paths:
            k = self._norm(p)
            self.by_path.setdefault(k, []).append(p)
            self.by_name.setdefault(k.rsplit("/", 1)[-1], []).append(p)

    def _norm(self, p):
        p = p.strip().lstrip("/").lower()
        if self.strip_ext and p.endswith(".md"):
            p = p[:-3]
        return p

    def resolve(self, target, src):
        t = self._norm(target)
        if not t:
            return None
        srcdir = os.path.dirname(src)
        rel = self._norm(os.path.normpath(os.path.join(srcdir, target.strip())))
        cands = (self.by_path.get(rel) or self.by_path.get(t)
                 or ([p for p in self.paths if self._norm(p).endswith("/" + t)]
                     if "/" in t else self.by_name.get(t, [])))
        if not cands:
            return None
        return min(cands, key=lambda p: (os.path.dirname(p) != srcdir,
                                         p.count("/"), len(p), p))


# --------------------------------------------------------------------------
# Markdown transform
# --------------------------------------------------------------------------

FRONTMATTER_RE = re.compile(r"^---[ \t]*\n(.*?\n)?(---|\.\.\.)[ \t]*(\n|$)", re.S)
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})[ \t]*([^`\s]*)")
INLINE_CODE_RE = re.compile(r"(`+)(.+?)\1", re.S)
COMMENT_RE = re.compile(r"%%.*?%%", re.S)
CALLOUT_RE = re.compile(r"^((?:[ \t]*>)+)[ \t]*\[!([^\]\n]+)\][+-]?[ \t]*(.*)$", re.M)
MDLINK_RE = re.compile(r"(!?)\[([^\]\n]*)\]\(\s*(<[^>\n]+>|[^)\s]+)(\s+\"[^\"\n]*\")?\s*\)")
EMBED_RE = re.compile(r"!\[\[([^\]\n]+)\]\]")
WIKILINK_RE = re.compile(r"\[\[([^\]\n]+)\]\]")
DROP_FENCES = {"dataview", "dataviewjs"}


def split_fences(text):
    """Yield (is_code, info, chunk) segments."""
    out, buf = [], []
    fence, info = None, ""
    for line in text.split("\n"):
        if fence is None:
            m = FENCE_RE.match(line)
            if m:
                if buf:
                    out.append((False, "", "\n".join(buf)))
                fence, info, buf = m.group(1), m.group(2).lower(), [line]
            else:
                buf.append(line)
        else:
            buf.append(line)
            s = line.strip()
            if s and set(s) == {fence[0]} and len(s) >= len(fence):
                out.append((True, info, "\n".join(buf)))
                fence, buf = None, []
    if buf:
        out.append((fence is not None, info, "\n".join(buf)))
    return out


def escape_label(s):
    return s.replace("[", "\\[").replace("]", "\\]")


def strip_head(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    m = FRONTMATTER_RE.match(text)
    if m:
        text = text[m.end():]
    text = text.lstrip("\n")
    # Outline stores the title separately and rejects text that opens with an H1
    if re.match(r"#[ \t]", text):
        text = text.split("\n", 1)[1] if "\n" in text else ""
    return text.lstrip("\n")


class Renderer:
    """Turns a note into Outline markdown.

    link_for(node_key) returns a URL or None (None leaves plain text).
    attachment_for(rel) returns a URL or None.
    """

    def __init__(self, vault, file_to_key, link_for, attachment_for):
        self.vault = vault
        self.file_to_key = file_to_key
        self.notes = Resolver(list(file_to_key), strip_ext=True)
        self.files = Resolver(vault.files, strip_ext=False)
        self.link_for = link_for
        self.attachment_for = attachment_for

    def render(self, src):
        with open(os.path.join(self.vault.root, src), encoding="utf-8",
                  errors="replace") as f:
            text = strip_head(f.read())
        parts = []
        for is_code, info, chunk in split_fences(text):
            if is_code:
                if info not in DROP_FENCES:
                    parts.append(chunk)
            else:
                parts.append(self._prose(chunk, src))
        text = "\n".join(parts).strip("\n")
        if re.match(r"#[ \t]", text):
            text = "#" + text
        return text + "\n" if text else ""

    def _note_link(self, target, label, src):
        page = target.split("#", 1)[0]
        rel = self.notes.resolve(page, src) if page.strip() else None
        url = self.link_for(self.file_to_key[rel]) if rel else None
        return f"[{escape_label(label)}]({url})" if url else label

    def _file_link(self, target, label, src, image):
        rel = self.files.resolve(target, src)
        url = self.attachment_for(rel) if rel else None
        if not url:
            return label
        return f"{'!' if image else ''}[{escape_label(label)}]({url})"

    def _prose(self, text, src):
        code = []

        def keep_code(m):
            body = m.group(2).strip()
            # Inline Dataview queries
            if body.startswith("=") or body.startswith("$="):
                return ""
            code.append(m.group(0))
            return f"\x00{len(code) - 1}\x00"

        text = INLINE_CODE_RE.sub(keep_code, text)
        text = COMMENT_RE.sub("", text)
        text = CALLOUT_RE.sub(
            lambda m: f"{m.group(1)} **{m.group(3).strip() or m.group(2).strip().capitalize()}**",
            text)

        def mdlink(m):
            bang, label, target = m.group(1), m.group(2), m.group(3)
            target = target[1:-1] if target.startswith("<") else target
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:|[#/]", target):
                return m.group(0)
            target = urllib.parse.unquote(target).split("#", 1)[0]
            ext = os.path.splitext(target)[1].lower()
            if ext == ".md" or (not ext and not bang):
                if ext != ".md" and not self.notes.resolve(target, src):
                    return m.group(0)
                return self._note_link(target, label or stem(os.path.basename(target)), src)
            if not self.files.resolve(target, src):
                return m.group(0)
            return self._file_link(target, label or os.path.basename(target), src,
                                   bool(bang) and ext in IMAGE_EXTS)

        text = MDLINK_RE.sub(mdlink, text)

        def wikilink(m, embed):
            target, _, alias = m.group(1).replace("\\|", "|").partition("|")
            target, alias = target.strip(), alias.strip()
            page, _, frag = target.partition("#")
            ext = os.path.splitext(page)[1].lower()
            if embed and ext and ext != ".md":
                # Image embed aliases are sizes ("300", "300x200"), not labels
                image = ext in IMAGE_EXTS
                label = alias if alias and not re.fullmatch(r"\d+(x\d+)?", alias) else os.path.basename(page)
                return self._file_link(page, label, src, image)
            label = alias or (f"{page} > {frag}" if page and frag else page or frag)
            if label.lower().endswith(".md"):
                label = label[:-3]
            return self._note_link(target, label, src)

        text = EMBED_RE.sub(lambda m: wikilink(m, True), text)
        text = WIKILINK_RE.sub(lambda m: wikilink(m, False), text)
        return re.sub(r"\x00(\d+)\x00", lambda m: code[int(m.group(1))], text)


# --------------------------------------------------------------------------
# Outline API
# --------------------------------------------------------------------------

class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


class Outline:
    MAX_TRIES = 8

    def __init__(self, base, token, delay):
        self.base = base.rstrip("/")
        self.delay = delay
        self.calls = 0
        self._last = 0.0
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {token}",
                               "Accept": "application/json"})

    def _send(self, retry_errors, fn):
        for attempt in range(1, self.MAX_TRIES + 1):
            pause = self._last + self.delay - time.monotonic()
            if pause > 0:
                time.sleep(pause)
            self._last = time.monotonic()
            self.calls += 1
            backoff = min(60, 2 ** attempt)
            try:
                r = fn()
            except (requests.ConnectionError, requests.Timeout) as e:
                if not retry_errors or attempt == self.MAX_TRIES:
                    raise ApiError(0, str(e))
                log.warning("request failed (%s), retrying in %ss", e, backoff)
                time.sleep(backoff)
                continue
            if r.status_code == 429 or (retry_errors and r.status_code in (502, 503, 504)):
                if attempt == self.MAX_TRIES:
                    break
                try:
                    wait = float(r.headers.get("Retry-After", "")) + 0.5
                except ValueError:
                    wait = backoff
                log.warning("HTTP %s, backing off %.1fs", r.status_code, wait)
                time.sleep(wait)
                continue
            if r.ok:
                return r.json() if r.content else {}
            try:
                msg = r.json().get("message") or r.text
            except ValueError:
                msg = r.text
            raise ApiError(r.status_code, msg[:300])
        raise ApiError(r.status_code, "gave up after repeated rate limiting")

    def call(self, method, body=None, retry_errors=True):
        url = f"{self.base}/api/{method}"
        res = self._send(retry_errors, lambda: self.s.post(url, json=body or {}, timeout=60))
        return res.get("data")

    def paged(self, method, body=None):
        out, offset, limit = [], 0, 100
        while True:
            page = self.call(method, dict(body or {}, offset=offset, limit=limit))
            out += page
            if len(page) < limit:
                return out
            offset += limit

    def upload(self, spec, name, data, ctype):
        if spec.get("mode") == "put":
            url, headers = spec["url"], spec.get("headers") or {}
            fn = lambda: requests.put(url, data=data, headers=headers, timeout=300)  # noqa: E731
        else:
            url = spec["uploadUrl"]
            # Local storage uploads go back through the API and need the token;
            # presigned S3 posts must not carry it.
            local = url.startswith("/")
            url = self.base + url if local else url
            sess = self.s if local else requests
            fn = lambda: sess.post(url, data=spec.get("form") or {},  # noqa: E731
                                   files={"file": (name, data, ctype)}, timeout=300)
        self._send(False, fn)


# --------------------------------------------------------------------------
# Sync
# --------------------------------------------------------------------------

def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


class Sync:
    def __init__(self, cfg, args, vault, nodes, file_to_key, api, state_path):
        self.cfg, self.args, self.vault = cfg, args, vault
        self.nodes, self.file_to_key, self.api = nodes, file_to_key, api
        self.state_path = state_path
        self.dry = args.dry_run
        self.stats = dict(created=0, adopted=0, updated=0, archived=0,
                          restored=0, skipped=0, errors=0)
        self.state = self._load_state()
        self.trees = {}
        self.claimed = set()
        self.renderer = Renderer(vault, file_to_key, self._link_for, self._attachment_for)
        self._doc_for_upload = None

    # ---- state ----------------------------------------------------------

    def _load_state(self):
        try:
            with open(self.state_path) as f:
                st = json.load(f)
            if st.get("version") == STATE_VERSION:
                return st
            log.warning("state file version mismatch, rebuilding from Outline")
        except FileNotFoundError:
            log.info("no state file, rebuilding mapping from Outline")
        except (OSError, ValueError) as e:
            log.error("unreadable state file (%s), rebuilding mapping from Outline", e)
        return {"version": STATE_VERSION, "nodes": {}, "attachments": {}}

    def save(self):
        if self.dry:
            return
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.state, f, indent=1, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.state_path)

    # ---- helpers --------------------------------------------------------

    def _err(self, key, what, e):
        self.stats["errors"] += 1
        log.error("%s: %s failed: %s", key, what, e)

    def _link_for(self, key):
        entry = self.state["nodes"].get(key)
        return entry and entry.get("url")

    def _attachment_for(self, rel):
        full = os.path.join(self.vault.root, rel)
        try:
            with open(full, "rb") as f:
                data = f.read()
        except OSError as e:
            self._err(rel, "read attachment", e)
            return None
        h = sha(data)
        cached = self.state["attachments"].get(rel)
        if cached and cached["hash"] == h:
            return cached["url"]
        if self.dry:
            log.info("would upload attachment %s", rel)
            return f"attachment:{rel}"
        name = os.path.basename(rel)
        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        body = {"name": name, "size": len(data), "contentType": ctype,
                "preset": "documentAttachment"}
        if self._doc_for_upload:
            body["documentId"] = self._doc_for_upload
        try:
            spec = self.api.call("attachments.create", body, retry_errors=False)
            self.api.upload(spec, name, data, ctype)
        except ApiError as e:
            self._err(rel, "upload attachment", e)
            return None
        url = spec["attachment"]["url"]
        self.state["attachments"][rel] = {"hash": h, "url": url}
        self.save()
        log.info("uploaded attachment %s", rel)
        return url

    def _render(self, node, doc_id):
        if not node.source:
            return ""
        self._doc_for_upload = doc_id
        try:
            return self.renderer.render(node.source)
        finally:
            self._doc_for_upload = None

    def _tree(self, coll_id):
        """Published documents of a collection, indexed for title-path matching."""
        if coll_id not in self.trees:
            children, ids = {}, {}

            def walk(items, parent):
                for it in items:
                    children.setdefault(parent, []).append(it)
                    ids[it["id"]] = it
                    walk(it.get("children") or [], it["id"])
            if not coll_id.startswith("dry-run"):
                walk(self.api.call("collections.documents", {"id": coll_id}) or [], None)
            self.trees[coll_id] = (children, ids)
        return self.trees[coll_id]

    # ---- collections ----------------------------------------------------

    def collections(self):
        existing = {}
        for c in self.api.paged("collections.list"):
            existing.setdefault(c["name"], c["id"])
        protected = set(self.cfg.get("protectedCollections", []))
        ids = {}
        for name in sorted({n.collection for n in self.nodes.values()}):
            if name in protected:
                raise SystemExit(f"vault folder maps to protected collection {name!r}; "
                                 "rename it with collectionNames")
            if name in existing:
                ids[name] = existing[name]
                continue
            if self.dry:
                log.info("would create collection %r", name)
                ids[name] = f"dry-run:{name}"
                continue
            c = self.api.call("collections.create", {
                "name": name,
                "permission": self.cfg.get("collectionPermission"),
                "sort": {"field": "title", "direction": "asc"},
            }, retry_errors=False)
            log.info("created collection %r", name)
            ids[name] = c["id"]
        return ids

    # ---- pass 1: structure ----------------------------------------------

    def _verify(self, key, entry):
        """--full: make sure a mapped document is still live in Outline."""
        _, ids = self._tree(entry["collectionId"])
        if entry["id"] in ids:
            entry["url"] = ids[entry["id"]]["url"]
            return True
        try:
            doc = self.api.call("documents.info", {"id": entry["id"]})
        except ApiError as e:
            if e.status in (403, 404):
                log.warning("%s: document %s is gone, recreating", key, entry["id"])
                return False
            raise
        if doc.get("archivedAt") or doc.get("deletedAt"):
            if self.dry:
                log.info("would restore %s", key)
                return True
            self.api.call("documents.restore", {"id": entry["id"]})
            self.stats["restored"] += 1
            log.info("restored %s (was archived or deleted in Outline)", key)
        return True

    def _create(self, node, coll_id, parent_id):
        if self.dry:
            log.info("would create %s", node.key)
            return {"id": f"dry-run:{node.key}", "url": f"dry-run:{node.key}"}, ""
        # Client-chosen id makes a retried create detectable instead of a duplicate
        doc_id = str(uuid.uuid4())
        text = self._render(node, None)
        body = {"id": doc_id, "title": node.title, "text": text, "publish": True,
                "collectionId": coll_id}
        if parent_id:
            body["parentDocumentId"] = parent_id
        try:
            doc = self.api.call("documents.create", body)
        except ApiError:
            try:
                doc = self.api.call("documents.info", {"id": doc_id})
            except ApiError:
                doc = None
            if not doc:
                raise
        log.info("created %s", node.key)
        self.stats["created"] += 1
        return doc, sha(node.title + "\0" + text)

    def structure(self, coll_ids):
        nodes_state = self.state["nodes"]
        for node in sorted(self.nodes.values(), key=lambda n: (n.depth, n.key)):
            coll_id = coll_ids[node.collection]
            entry = nodes_state.get(node.key)
            try:
                if entry and entry.get("collectionId") != coll_id:
                    # Collection renamed or recreated: the old doc is not in our tree
                    nodes_state.pop(node.key)
                    entry = None
                if entry and self.args.full and not self._verify(node.key, entry):
                    nodes_state.pop(node.key)
                    entry = None
                if entry:
                    continue
                parent_id = None
                if node.parent:
                    parent = nodes_state.get(node.parent)
                    if not parent:
                        raise RuntimeError(f"parent {node.parent} is missing")
                    parent_id = parent["id"]
                children, _ = self._tree(coll_id)
                match = next((d for d in children.get(parent_id, [])
                              if d["title"] == node.title and d["id"] not in self.claimed), None)
                if match:
                    doc, rendered = match, None
                    self.stats["adopted"] += 1
                    log.info("adopted existing document for %s", node.key)
                else:
                    doc, rendered = self._create(node, coll_id, parent_id)
                self.claimed.add(doc["id"])
                nodes_state[node.key] = {"id": doc["id"], "url": doc["url"],
                                         "collectionId": coll_id, "renderedHash": rendered}
                self.save()
            except (ApiError, OSError, RuntimeError) as e:
                self._err(node.key, "create", e)

    # ---- pass 2: content ------------------------------------------------

    def content(self):
        for node in sorted(self.nodes.values(), key=lambda n: n.key):
            entry = self.state["nodes"].get(node.key)
            if not entry:
                continue
            try:
                if node.source:
                    with open(os.path.join(self.vault.root, node.source), "rb") as f:
                        entry["contentHash"] = sha(f.read())
                text = self._render(node, entry["id"])
                h = sha(node.title + "\0" + text)
                if h == entry.get("renderedHash") and not self.args.force:
                    self.stats["skipped"] += 1
                    continue
                if self.dry:
                    log.info("would update %s", node.key)
                    continue
                try:
                    self.api.call("documents.update",
                                  {"id": entry["id"], "title": node.title, "text": text})
                except ApiError as e:
                    if e.status not in (403, 404):
                        raise
                    # Deleted in Outline since the last run; the next run recreates it
                    log.warning("%s: document %s is gone, will recreate next run",
                                node.key, entry["id"])
                    self.state["nodes"].pop(node.key)
                    self.save()
                    continue
                entry["renderedHash"] = h
                self.stats["updated"] += 1
                log.info("updated %s", node.key)
                self.save()
            except (ApiError, OSError) as e:
                self._err(node.key, "update", e)

    # ---- pass 3: archive ------------------------------------------------

    def archive(self):
        unreadable = self.vault.unreadable

        def shielded(key):
            # A note we could not read is not a deleted note
            return any(key == u or key.startswith(u.rstrip("/") + "/")
                       # It may have been the folder note of a folder document
                       or key in (os.path.dirname(u) + "/", stem(u) + "/")
                       for u in unreadable)

        gone = [k for k in self.state["nodes"] if k not in self.nodes and not shielded(k)]
        if not gone:
            return
        limit = int(self.cfg.get("maxArchivePerRun", 20))
        if len(gone) > limit and not self.args.allow_mass_archive:
            self.stats["errors"] += 1
            log.error("refusing to archive %d documents (limit %d); "
                      "touch allow-mass-archive in the state directory to permit it. "
                      "First few: %s", len(gone), limit, ", ".join(sorted(gone)[:10]))
            return
        # Deepest first: archiving a parent in Outline takes its children with it
        for key in sorted(gone, key=lambda k: (-k.rstrip("/").count("/"), k)):
            entry = self.state["nodes"][key]
            if self.dry:
                log.info("would archive %s", key)
                continue
            try:
                self.api.call("documents.archive", {"id": entry["id"]})
                log.info("archived %s", key)
                self.stats["archived"] += 1
            except ApiError as e:
                if e.status not in (400, 403, 404):
                    self._err(key, "archive", e)
                    continue
                log.warning("%s: already archived or gone (%s)", key, e)
            self.state["nodes"].pop(key)
            self.save()

    def run(self):
        coll_ids = self.collections()
        self.structure(coll_ids)
        self.content()
        self.archive()
        live = set(self.vault.files)
        for rel in [r for r in self.state["attachments"] if r not in live]:
            self.state["attachments"].pop(rel)
        self.save()


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--config", required=True, help="JSON config written by the NixOS module")
    ap.add_argument("--token-file", help="default: $CREDENTIALS_DIRECTORY/token")
    ap.add_argument("--full", action="store_true",
                    help="also verify every mapped document still exists in Outline")
    ap.add_argument("--force", action="store_true", help="re-upload every document")
    ap.add_argument("--dry-run", action="store_true", help="read from Outline, change nothing")
    ap.add_argument("--allow-mass-archive", action="store_true")
    ap.add_argument("--list", action="store_true", help="print the planned tree (offline)")
    ap.add_argument("--render", metavar="NOTE", help="print a note as it would be uploaded (offline)")
    ap.add_argument("--print-watch-exclude", action="store_true",
                    help="print the inotifywait --exclude regex")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stdout)
    with open(args.config) as f:
        cfg = json.load(f)
    root = cfg["vault"].rstrip("/")
    ignore = ignore_ere(cfg.get("excludes", []))

    if args.print_watch_exclude:
        print("^" + ere_escape(root) + "/" + ignore + "$")
        return 0

    if not os.path.isdir(root):
        log.error("vault %s is not a directory; refusing to sync", root)
        return 1
    vault = scan(root, re.compile(ignore))
    if not vault.notes:
        log.error("no notes found in %s; refusing to sync (is it mounted?)", root)
        return 1
    nodes, file_to_key = build_tree(vault, cfg.get("rootCollection", "Vault"),
                                    cfg.get("collectionNames", {}))

    if args.list or args.render:
        r = Renderer(vault, file_to_key, lambda k: f"outline:{k}", lambda p: f"attachment:{p}")
        if args.render:
            sys.stdout.write(r.render(args.render))
            return 0
        for n in sorted(nodes.values(), key=lambda n: (n.collection, n.key)):
            print(f"{n.collection} | {'  ' * n.depth}{n.title}"
                  f"{'' if n.source else ' (empty)'}  <- {n.source or n.key}")
        return 0

    token_file = args.token_file or os.path.join(os.environ.get("CREDENTIALS_DIRECTORY", ""), "token")
    with open(token_file) as f:
        token = f.read().strip()

    state_dir = cfg["stateDir"]
    allow_file = os.path.join(state_dir, "allow-mass-archive")
    args.allow_mass_archive = args.allow_mass_archive or os.path.exists(allow_file)

    with open(os.path.join(state_dir, "lock"), "w") as lock:
        # The watcher-triggered and nightly units share the state file
        fcntl.flock(lock, fcntl.LOCK_EX)
        started = time.monotonic()
        api = Outline(cfg["outlineUrl"], token, float(cfg.get("requestDelay", 0.2)))
        sync = Sync(cfg, args, vault, nodes, file_to_key, api,
                    os.path.join(state_dir, "state.json"))
        try:
            sync.run()
        except ApiError as e:
            sync.stats["errors"] += 1
            log.error("aborted: %s", e)
        if os.path.exists(allow_file) and not args.dry_run:
            os.remove(allow_file)
        s = sync.stats
        log.info("%ssync done: created=%d adopted=%d updated=%d archived=%d restored=%d "
                 "skipped=%d errors=%d unreadable=%d api_calls=%d (%.1fs)",
                 "dry-run " if args.dry_run else "", s["created"], s["adopted"],
                 s["updated"], s["archived"], s["restored"], s["skipped"], s["errors"],
                 len(vault.unreadable), api.calls, time.monotonic() - started)
        return 1 if s["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
