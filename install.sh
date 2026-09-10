#!/usr/bin/env bash
# alirezapanel 1.1.0 -- one-file ONLINE installer, 2026-09-09
# Debian 12/13 or Ubuntu 24.04, x86_64, systemd, fresh server.
# No build toolchain, Docker, Node.js, or npm is installed on the target.
# Upstream executables and their full interfaces are retained; a small gateway
# supplies shared authentication, integrated navigation and visual branding.
# This file contains ALL integration code; upstream binaries are downloaded.
# Integration code: GPL-3.0-or-later. Upstream licenses/attribution are retained.
set -Eeuo pipefail
umask 027
export LC_ALL=C.UTF-8

ROOT=/opt/alirezapanel
ETC=/etc/alirezapanel
MODE=${1:-install}
VPN_VERSION=v1.9.4
AGH_VERSION=v0.107.79
VPN_SHA=18ec321d9074b319bd5756508bbc523ab5d95450b832c406acdd72e987a2da8f
AGH_SHA=c48f4a43000665484c5ec28177de11a004759b620dae8f77b2aabefc9ef3687f
STAGE=
CHANGED=0
REPAIR_STOPPED=0

say() { printf '\n[alirezapanel] %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
help() {
    cat <<'HELP'
alirezapanel -- vpn-ui + the complete AdGuard Home interface

  sudo bash install.sh              Install on a fresh supported server
  sudo bash install.sh --repair     Reinstall integration and pinned binaries;
                                   preserve settings/users and make a backup
  sudo bash install.sh --check      Read-only service and connectivity checks
  sudo bash install.sh --fix-restart Apply only the restart-page fix to an existing installation
  sudo bash install.sh --enable-nodes Add/update Nodes without reinstalling VPN or DNS
  bash install.sh --help            Show this help

Optional first-install environment variables:
  ALIREZA_HOST       Public IP or domain (no scheme or port)
  ALIREZA_PORT       Public panel port; defaults depend on access mode
  ALIREZA_TLS_MODE   domain | ip | none (interactive installer asks when omitted)
  ALIREZA_ACME_EMAIL Optional Let's Encrypt email for domain mode
  ALIREZA_USER       Initial administrator, default admin
  ALIREZA_PASSWORD   16..72 UTF-8 bytes; randomly generated if omitted
  ALIREZA_CERT       Existing PEM certificate chain (optional)
  ALIREZA_KEY        Matching PEM private key (required with ALIREZA_CERT)

Examples:
  sudo env ALIREZA_TLS_MODE=domain ALIREZA_HOST=panel.example.com bash install.sh
  sudo env ALIREZA_TLS_MODE=ip bash install.sh
  sudo env ALIREZA_TLS_MODE=none bash install.sh

Domain mode can obtain a Let's Encrypt certificate automatically. IP mode uses
a self-signed HTTPS certificate unless ALIREZA_CERT/ALIREZA_KEY are supplied.
The server must reach GitHub, its package repositories and DNS upstreams.
Allow the selected public panel port and TCP/UDP port 53 in your hosting firewall if
DNS should be reachable from clients. VPN ports depend on the protocols you enable.
Native services are NOT provisioned until selected in UI.
Designed for light use on 1 vCPU / 1 GiB RAM; no capacity guarantee is made.
This installer has NOT been validated on a live 1 GiB Linux server.
HELP
}

case "$MODE" in
    --help|-h) help; exit 0 ;;
    install|--repair|--check|--fix-restart|--enable-nodes) ;;
    *) help; exit 2 ;;
esac
[[ $# -le 1 ]] || die 'Only one operation may be specified.'
[[ $EUID -eq 0 ]] || die 'Run with: sudo bash install.sh'
if [[ "$MODE" == --check ]]; then
    [[ -f "$ROOT/gateway/manage.py" ]] || die 'alirezapanel is not installed.'
    exec python3 "$ROOT/gateway/manage.py" check
fi
command -v systemctl >/dev/null || die 'A Linux server running systemd is required.'
if [[ "$MODE" == --enable-nodes ]]; then
    [[ -f "$ROOT/gateway/gateway.py" ]] || die 'Install alirezapanel first.'
    exec 9>/run/lock/alirezapanel-install.lock
    flock -n 9 || die 'Another installer is running.'
    python3 - "$0" "$ROOT" <<'NODES_UPDATE_PY'
import pathlib, re, sys
installer=pathlib.Path(sys.argv[1]).read_text()
pattern=r"cat > \"\$STAGE/([^\"\n]+)\" <<'NODE_EMBEDDED_([A-Z_]+)_EOF'\n(.*?)\nNODE_EMBEDDED_\2_EOF"
files={name:content for name,tag,content in re.findall(pattern,installer,re.S)}
namespace={}
exec(compile(files['nodes_install.py'],'nodes_install.py','exec'),namespace)
namespace['install'](sys.argv[2],files)
NODES_UPDATE_PY
    install -d -o alirezapanel -g alirezapanel -m 700 /var/lib/alirezapanel-nodes
    install -d -m 755 /etc/systemd/system/alirezapanel.service.d
    cat > /etc/systemd/system/alirezapanel.service.d/nodes.conf <<'NODE_UNIT'
[Service]
StateDirectory=alirezapanel-nodes
StateDirectoryMode=0700
ReadWritePaths=/var/lib/alirezapanel-nodes
NODE_UNIT
    systemctl daemon-reload
    systemctl restart alirezapanel.service
    systemctl is-active --quiet alirezapanel.service || die 'Gateway did not start; inspect its logs.'
    say 'Nodes enabled. Refresh the panel. Repeat --enable-nodes on each node server.'
    exit 0
fi
if [[ "$MODE" == --fix-restart ]]; then
    [[ -f "$ROOT/gateway/gateway.py" ]] || die 'alirezapanel is not installed.'
    exec 9>/run/lock/alirezapanel-install.lock
    flock -n 9 || die 'Another alirezapanel installer is running.'
    python3 - "$0" "$ROOT/gateway/gateway.py" <<'RESTART_FIX_PY'
import os, pathlib, re, shutil, sys, tempfile, time
installer = pathlib.Path(sys.argv[1]).read_text()
target = pathlib.Path(sys.argv[2])
current = target.read_text()
anchor = '    def brand_html(self, text, base, agh=False):\n'
if current.count(anchor) != 1:
    raise SystemExit('Unsupported gateway layout; nothing changed.')
embedded = installer.split("<<'ALIREZAPANEL_EMBEDDED_0_EOF'\n", 1)[1].split('\nALIREZAPANEL_EMBEDDED_0_EOF', 1)[0]
start = embedded.index('    def fix_restart_html(self, document):\n')
method = embedded[start:embedded.index(anchor, start)]
call = '        if not agh:\n            text = self.fix_restart_html(text)\n'
if '    def fix_restart_html(self, document):\n' in current:
    start = current.index('    def fix_restart_html(self, document):\n')
    current = current[:start] + current[current.index(anchor, start):]
current = current.replace(anchor + call, anchor, 1)
updated = current.replace(anchor, method + anchor + call, 1)
compile(updated, str(target), 'exec')
backup = target.with_name('gateway.py.before-restart-fix-' + str(time.time_ns()))
shutil.copy2(target, backup)
metadata = target.stat()
fd, temporary = tempfile.mkstemp(prefix='.restart-fix-', dir=target.parent)
try:
    with os.fdopen(fd, 'w') as stream:
        stream.write(updated)
        stream.flush()
        os.fsync(stream.fileno())
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    os.chmod(temporary, metadata.st_mode & 0o7777)
    os.replace(temporary, target)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print('Gateway backup:', backup)
RESTART_FIX_PY
    systemctl restart alirezapanel.service
    systemctl is-active --quiet alirezapanel.service || die 'Gateway did not start; inspect journalctl -u alirezapanel.'
    say 'Restart-page fix installed. Refresh the settings page before pressing Restart.'
    exit 0
fi
[[ -d /run/systemd/system ]] || die 'systemd must be running; ordinary Docker containers are not supported.'
[[ $(uname -m) == x86_64 ]] || die 'vpn-ui v1.9.4 provides only an x86_64/amd64 binary. ARM is not supported by this installer.'
[[ -f /etc/os-release ]] || die 'Cannot identify operating system.'
# shellcheck disable=SC1091
. /etc/os-release
case "$ID:$VERSION_ID" in
    debian:12|debian:13|ubuntu:24.04) ;;
    *) die 'Supported: Debian 12/13 or Ubuntu 24.04 on x86_64.' ;;
esac
exec 9>/run/lock/alirezapanel-install.lock
flock -n 9 || die 'Another alirezapanel installer is running.'
if [[ -f "$ETC/installed" && "$MODE" == install ]]; then
    say 'Already installed; preserving all settings. Use --repair to repair the installation.'
    exec python3 "$ROOT/gateway/manage.py" info
fi
if [[ ! -f "$ETC/owner" ]]; then
    [[ ! -e "$ROOT" && ! -e "$ETC" ]] || die 'Unrecognized existing alirezapanel files; refusing to overwrite them.'
    for existing in /opt/vpn-ui /etc/vpn-ui /etc/x-ui /opt/AdGuardHome /etc/AdGuardHome.yaml; do
        [[ ! -e "$existing" ]] || die "Found existing installation: $existing. Use a fresh server; automatic migration is not included."
    done
    for unit in alirezapanel.service alirezapanel-vpn.service alirezapanel-dns.service AdGuardHome.service vpn-ui.service x-ui.service; do
        [[ "$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)" == not-found ]] || \
            die "Existing service $unit would conflict; use a fresh server."
    done
fi
if [[ "$MODE" == install && ! -f "$ETC/owner" && -z "${ALIREZA_TLS_MODE:-}" && -t 0 && -t 1 ]]; then
    printf '\n============================================================\n'
    printf ' alirezapanel - Public access setup\n'
    printf '============================================================\n'
    printf 'Choose how the panel should be opened:\n'
    printf '  1) Domain + valid SSL (Let\x27s Encrypt)\n'
    printf '  2) Server IP + HTTPS (self-signed SSL)\n'
    printf '  3) Server IP/domain without SSL (plain HTTP)\n'
    printf '\nSelection [1-3]: '
    read -r access_choice
    case "$access_choice" in
        1)
            printf 'Domain (example: panel.example.com): '
            read -r domain_input
            [[ -n "$domain_input" ]] || die 'A domain is required for SSL domain mode.'
            domain_input=${domain_input#http://}
            domain_input=${domain_input#https://}
            domain_input=${domain_input%%/*}
            [[ "$domain_input" != *:* ]] || die 'Enter the domain without scheme or port.'
            export ALIREZA_TLS_MODE=domain
            export ALIREZA_HOST="$domain_input"
            export ALIREZA_PORT="${ALIREZA_PORT:-443}"
            printf 'Optional email for Let\x27s Encrypt notices (press Enter to skip): '
            read -r acme_email_input
            [[ -z "$acme_email_input" ]] || export ALIREZA_ACME_EMAIL="$acme_email_input"
            ;;
        2)
            export ALIREZA_TLS_MODE=ip
            export ALIREZA_PORT="${ALIREZA_PORT:-8443}"
            ;;
        3)
            export ALIREZA_TLS_MODE=none
            export ALIREZA_PORT="${ALIREZA_PORT:-8080}"
            printf 'Optional public domain/IP (press Enter to auto-detect server IP): '
            read -r plain_host_input
            if [[ -n "$plain_host_input" ]]; then
                plain_host_input=${plain_host_input#http://}
                plain_host_input=${plain_host_input#https://}
                plain_host_input=${plain_host_input%%/*}
                [[ "$plain_host_input" != *:* ]] || die 'Enter the host without scheme or port.'
                export ALIREZA_HOST="$plain_host_input"
            fi
            ;;
        *) die 'Invalid selection. Run the installer again and choose 1, 2 or 3.' ;;
    esac
fi

# Non-interactive installs preserve the historical secure default.
export ALIREZA_TLS_MODE="${ALIREZA_TLS_MODE:-ip}"
case "$ALIREZA_TLS_MODE" in
    domain|ip|none) ;;
    *) die 'ALIREZA_TLS_MODE must be: domain, ip or none.' ;;
esac

if [[ -f "$ETC/installed" ]]; then
    # Refuse a silent binary downgrade after an upstream UI update: the database
    # may already have migrated to a newer schema.
    installed_vpn=$("$ROOT/vpn/vpn-ui-amd64" -v 2>/dev/null || true)
    installed_agh=$("$ROOT/adguard/AdGuardHome" --version 2>/dev/null || true)
    [[ -z "$installed_vpn" || "$installed_vpn" == "${VPN_VERSION#v}" || "$installed_vpn" == "$VPN_VERSION" ]] || die 'VPN was upgraded. Use a matching installer/backup; --repair will not silently downgrade its database.'
    [[ -z "$installed_agh" || "$installed_agh" == *"$AGH_VERSION"* ]] || die 'DNS was upgraded. Use a matching installer/backup; --repair will not silently downgrade its database.'
fi
available_kb=$(df -Pk /opt | awk 'NR==2 {print $4}')
[[ "$available_kb" =~ ^[0-9]+$ ]] && (( available_kb >= 2097152 )) || die 'At least 2 GiB of free disk space under /opt is required.'
memory_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
(( memory_kb >= 850000 )) || die 'At least approximately 1 GiB RAM is required.'

cleanup() {
    local code=$?
    trap - EXIT
    if [[ -n "$STAGE" && "$STAGE" == /opt/.alirezapanel-install.* && -d "$STAGE" ]]; then
        rm -rf -- "$STAGE"
    fi
    if (( code != 0 )); then
        if (( REPAIR_STOPPED )); then
            systemctl start alirezapanel-dns alirezapanel-vpn alirezapanel 2>/dev/null || true
        fi
        printf '\nInstallation did not complete; success has NOT been reported.\n' >&2
        if (( CHANGED )); then
            printf 'Owned files are preserved for diagnosis. Use: sudo bash install.sh --repair\n' >&2
            printf 'Logs: journalctl -u alirezapanel -u alirezapanel-vpn -u alirezapanel-dns -n 100\n' >&2
        fi
    fi
    exit "$code"
}
trap cleanup EXIT
say 'Installing small runtime dependencies from your distribution.'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl python3 python3-aiohttp python3-yaml python3-bcrypt \
    openssl iproute2 dnsutils sqlite3 tar util-linux

if [[ "$MODE" == install && ! -f "$ETC/owner" && "$ALIREZA_TLS_MODE" == domain && -z "${ALIREZA_CERT:-}" ]]; then
    [[ -n "${ALIREZA_HOST:-}" ]] || die 'ALIREZA_HOST is required for domain SSL mode.'
    say "Preparing automatic SSL for domain: $ALIREZA_HOST"
    apt-get install -y --no-install-recommends certbot
    if ! getent ahostsv4 "$ALIREZA_HOST" >/dev/null 2>&1; then
        die "The domain $ALIREZA_HOST does not currently resolve to IPv4. Point its A record to this server first."
    fi
    certbot_args=(certonly --standalone --non-interactive --agree-tos --preferred-challenges http -d "$ALIREZA_HOST")
    if [[ -n "${ALIREZA_ACME_EMAIL:-}" ]]; then
        certbot_args+=(--email "$ALIREZA_ACME_EMAIL")
    else
        certbot_args+=(--register-unsafely-without-email)
    fi
    certbot "${certbot_args[@]}" || die 'Let\x27s Encrypt certificate issuance failed. Verify DNS A record and inbound TCP port 80.'
    export ALIREZA_CERT="/etc/letsencrypt/live/$ALIREZA_HOST/fullchain.pem"
    export ALIREZA_KEY="/etc/letsencrypt/live/$ALIREZA_HOST/privkey.pem"
fi

STAGE=$(mktemp -d /opt/.alirezapanel-install.XXXXXXXX)
chmod 700 "$STAGE"
fetch() {
    curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --retry-delay 3 \
        --connect-timeout 20 --max-time 1800 --output "$2" "$1"
}
say "Downloading pinned upstream releases: VPN $VPN_VERSION and DNS $AGH_VERSION."
fetch "https://github.com/Sir-MmD/vpn-ui/releases/download/$VPN_VERSION/vpn-ui-amd64" "$STAGE/vpn-ui-amd64"
fetch "https://github.com/AdguardTeam/AdGuardHome/releases/download/$AGH_VERSION/AdGuardHome_linux_amd64.tar.gz" "$STAGE/adguard.tar.gz"
printf '%s  %s\n' "$VPN_SHA" "$STAGE/vpn-ui-amd64" "$AGH_SHA" "$STAGE/adguard.tar.gz" | sha256sum --check --strict
tar -xzf "$STAGE/adguard.tar.gz" -C "$STAGE" --no-same-owner
[[ -f "$STAGE/AdGuardHome/AdGuardHome" ]] || die 'AdGuard release archive is incomplete.'
chmod 755 "$STAGE/vpn-ui-amd64" "$STAGE/AdGuardHome/AdGuardHome"
"$STAGE/vpn-ui-amd64" -v
"$STAGE/AdGuardHome/AdGuardHome" --version

# Embedded integration files follow. They are written to a private staging
# directory, compiled/checked there, and only then copied to their final paths.

cat > "$STAGE/gateway.py" <<'ALIREZAPANEL_EMBEDDED_0_EOF'
#!/usr/bin/env python3
"""alirezapanel integration gateway. Upstream programs remain unmodified.

The VPN session, including current super-admin privileges, is verified by the
VPN backend for EVERY DNS request. AdGuard credentials never reach the browser.
Only HTML is transformed; API payloads, downloads and WebSockets are preserved.
"""
import asyncio
import contextlib
import html
import json
import logging
import re
import sqlite3
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

import aiohttp
from aiohttp import web
from nodes import Nodes
from multidict import CIMultiDict
from yarl import URL

LOG = logging.getLogger("alirezapanel")
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
       "te", "trailer", "transfer-encoding", "upgrade", "content-length"}
SCRIPT_RE = re.compile(r"<script\b[^>]*>.*?</script\s*>", re.I | re.S)


def clean_headers(headers, extra=()):
    excluded = HOP | {x.strip().lower() for x in headers.get("Connection", "").split(",")} | set(extra)
    return CIMultiDict((k, v) for k, v in headers.items() if k.lower() not in excluded)


class Gateway:
    def __init__(self, config):
        self.config = config
        self.root = Path(config["assets"])
        self._settings = None
        self._settings_at = 0
        self.agh_lock = asyncio.Lock()
        self.nodes = Nodes(self)
        self.agh_logged_in = False

    def vpn_settings(self):
        if self._settings is not None and time.monotonic() - self._settings_at < 2:
            return self._settings
        # Database is read-only; only the installer changes initial defaults.
        uri = Path(self.config["vpn_db"]).resolve().as_uri() + "?mode=ro"
        with contextlib.closing(sqlite3.connect(uri, uri=True, timeout=2)) as db:
            data = dict(db.execute("SELECT key,value FROM settings"))
        base = "/" + data.get("webBasePath", "/").strip("/")
        base = base.rstrip("/") + "/"
        port = int(data.get("webPort", 18080))
        host = data.get("webListen") or "127.0.0.1"
        if host in ("0.0.0.0", "::"):
            host = "127.0.0.1"
        if host == "::1":
            host = "[::1]"
        cert = data.get("webCertFile", "")
        tls = True
        if cert:
            tls = ssl.create_default_context(cafile=cert)
            # The destination is a local service; trust only its configured cert.
            tls.check_hostname = False
            tls.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        origin = ("https" if cert else "http") + "://" + host + ":" + str(port)
        self._settings = (base, origin, tls)
        self._settings_at = time.monotonic()
        return self._settings

    async def start(self, app):
        await self.nodes.start()
        timeout = aiohttp.ClientTimeout(total=None, connect=15, sock_read=300)
        self.vpn = aiohttp.ClientSession(timeout=timeout, cookie_jar=aiohttp.DummyCookieJar(),
                                        auto_decompress=False, connector=aiohttp.TCPConnector(limit=64))
        self.agh = aiohttp.ClientSession(timeout=timeout, cookie_jar=aiohttp.CookieJar(unsafe=True),
                                        auto_decompress=False, connector=aiohttp.TCPConnector(limit=32))

    async def stop(self, app):
        await self.nodes.stop()
        await self.vpn.close()
        await self.agh.close()

    async def is_admin(self, request):
        base, origin, tls = self.vpn_settings()
        if "vpn-ui" not in request.cookies:
            return False
        headers = {"Cookie": request.headers.get("Cookie", ""), "Accept": "application/json",
                   "X-Requested-With": "XMLHttpRequest", "Host": request.host,
                   "Accept-Encoding": "identity"}
        async with self.vpn.get(origin + base + "panel/admins/permissions", headers=headers,
                                ssl=tls, allow_redirects=False,
                                timeout=aiohttp.ClientTimeout(total=8)) as response:
            if response.status != 200 or response.content_type != "application/json":
                return False
            data = await response.json()
            # Never mistake upstream's HTTP-200 permission errors for success.
            return data.get("success") is True and isinstance(data.get("obj"), list) and bool(data["obj"])

    async def agh_login(self, force=False):
        async with self.agh_lock:
            if self.agh_logged_in and not force:
                return
            async with self.agh.post(self.config["agh_origin"] + "/control/login",
                                     json={"name": self.config["agh_user"],
                                           "password": self.config["agh_password"]},
                                     allow_redirects=False) as response:
                await response.read()
                if response.status != 200:
                    raise web.HTTPBadGateway(text="DNS service authentication failed. Run alirezapanel check.")
            self.agh_logged_in = True

    def fix_restart_html(self, document):
        pattern = re.compile(r"(async restartPanel\(\)\s*\{.*?)(        this\.loading\(true\);.*?)(\n      \},)", re.S)
        def patch(match):
            if 'HttpUtil.post("/panel/setting/restartPanel")' not in match[2] or 'window.location.replace' not in match[2]:
                return match[0]
            return match[1] + r'''        this.loading(true);
        try {
          const msg = await HttpUtil.post("/panel/setting/restartPanel");
          if (!msg || !msg.success) return;

          // The browser must stay on the public gateway's scheme, host and port.
          // webPort and webCertFile describe the private VPN listener only.
          const target = new URL(window.location.href);
          const base = String(this.allSetting.webBasePath || "/").replace(/^\/+|\/+$/g, "");
          target.pathname = "/" + (base ? base + "/" : "") + "panel/settings";
          target.search = "";
          target.hash = "";
          // Upstream schedules SIGHUP after three seconds. Do not mistake the
          // still-running old listener for completion of the restart.
          await PromiseUtil.sleep(5000);
          const deadline = Date.now() + 90000;
          while (Date.now() < deadline) {
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), 3000);
            try {
              const response = await fetch(target.href, {
                credentials: "same-origin", cache: "no-store",
                signal: controller.signal, redirect: "follow",
              });
              const page = await response.text();
              if (response.ok && new URL(response.url).origin === target.origin &&
                  (response.headers.get("Content-Type") || "").includes("text/html") &&
                  page.includes('data-alireza-theme')) {
                window.location.replace(target.href);
                return;
              }
            } catch (_) { /* Brief connection failures are expected on restart. */ }
            finally { clearTimeout(timer); }
            await PromiseUtil.sleep(1500);
          }
          throw new Error("Panel did not become ready within 90 seconds. Run alirezapanel check on the server.");
        } catch (error) {
          window.alert(error.message || "Panel restart failed. Please try again.");
        } finally {
          this.loading(false);
        }''' + match[3]
        return pattern.sub(patch, document, count=1)

    def brand_html(self, text, base, agh=False):
        if not agh:
            text = self.fix_restart_html(text)
        # Don't replace arbitrary JavaScript/JSON identifiers, protocol names,
        # URLs, user configuration or legal attribution. Branding is DOM-only.
        text = re.sub(r"<title>.*?</title>", "<title>alirezapanel" + (" · DNS" if agh else "") + "</title>",
                      text, count=1, flags=re.I | re.S)
        opts = json.dumps({"base": base, "dns": agh}, ensure_ascii=True).replace("<", "\\u003c")
        # The stylesheet loads after the upstream styles. Mark the document before
        # first paint; don't override saved user theme choices on every visit.
        tag = ('<link rel="stylesheet" href="' + html.escape(base, quote=True) +
               '_alireza/theme.css?v=1.1.0"><script>document.documentElement.setAttribute("data-alireza-theme","ember");'
               'window.ALIREZA=' + opts + ';</script><script defer src="' +
               html.escape(base, quote=True) + '_alireza/brand.js?v=1.1.0"></script>')
        if not agh:
            tag += '<script defer src="' + html.escape(base, quote=True) + '_alireza/nodes.js?v=1.0.0"></script>'
        return re.sub(r"</head\s*>", tag + "</head>", text, count=1, flags=re.I)

    def dns_shell(self, upstream_html, base):
        head = re.search(r"<head\b[^>]*>(.*?)</head>", upstream_html, re.I | re.S)
        if not head or "Vue.component('a-sidebar'" not in upstream_html:
            raise web.HTTPBadGateway(text="VPN UI layout differs from the pinned version. Run alirezapanel check.")
        scripts = []
        for script in SCRIPT_RE.findall(upstream_html):
            if re.search(r"\bsrc\s*=", script, re.I):
                if "websocket.js" not in script:
                    scripts.append(script)
            elif any(marker in script for marker in
                     ("const PERMS =", "const basePath =", "Vue.component('a-sidebar'", "function createThemeSwitcher()")):
                scripts.append(script)
        # Reuse the REAL sidebar and theme components, not a separate imitation.
        # The dashboard's polling, admin forms and WebSocket aren't loaded here.
        sprite = re.search(r'<svg\b[^>]*>\s*<symbol.*?</svg>', upstream_html, re.I | re.S)
        src = html.escape(base + "dns/", quote=True)
        body = '''<body><div id="message"></div>''' + (sprite.group(0) if sprite else "") + '''
<div id="app" v-cloak class="bo-shell" :class="themeSwitcher.currentTheme">
  <a-sidebar></a-sidebar><div class="bo-main">
  <header class="bo-topbar"><div class="bo-topbar-inner"><h1 class="bo-topbar-title">alirezapanel · DNS</h1></div></header>
  <main class="bo-content" style="padding:0;min-width:0">
  <iframe id="alireza-dns" title="alirezapanel DNS" src="''' + src + '''" style="display:block;width:100%;height:calc(100dvh - 80px);min-height:480px;border:0" allow="clipboard-write"></iframe>
  </main></div></div>''' + "\n".join(scripts) + '''
<script>const app=new Vue({el:'#app',data:{themeSwitcher}});</script></body>'''
        return self.brand_html("<!doctype html><html><head>" + head.group(1) + "</head>" + body + "</html>", base)

    def validate_origin(self, request):
        if request.headers.get("Sec-Fetch-Site") == "cross-site":
            raise web.HTTPForbidden(text="Cross-site requests are not allowed.")
        if request.method not in ("GET", "HEAD", "OPTIONS") or request.headers.get("Upgrade", "").lower() == "websocket":
            origin = request.headers.get("Origin")
            if origin:
                if urlsplit(origin).netloc != request.host or urlsplit(origin).scheme != request.scheme:
                    raise web.HTTPForbidden(text="Origin mismatch.")
            elif request.headers.get("X-Alirezapanel-Request") != "1":
                raise web.HTTPForbidden(text="API clients must send X-Alirezapanel-Request: 1.")

    async def handle(self, request):
        try:
            return await self.dispatch(request)
        except web.HTTPException:
            raise
        except (aiohttp.ClientError, asyncio.TimeoutError, sqlite3.Error, OSError, ValueError):
            LOG.warning("An upstream service is unavailable", exc_info=True)
            raise web.HTTPBadGateway(text="alirezapanel: service temporarily unavailable. Run alirezapanel check.")

    async def dispatch(self, request):
        node_response = await self.nodes.route(request)
        if node_response is not None:
            return node_response
        self.validate_origin(request)
        base, vpn_origin, tls = self.vpn_settings()
        if request.path == "/" and base != "/":
            raise web.HTTPFound(base)
        if not request.path.startswith(base):
            raise web.HTTPNotFound()
        relative = request.path[len(base):]
        if relative == "_alireza/brand.js":
            return web.FileResponse(self.root / "brand.js", headers={"Cache-Control": "no-cache"})
        if relative == "_alireza/theme.css":
            return web.FileResponse(self.root / "theme.css", headers={"Cache-Control": "no-cache"})
        if relative == "_alireza/logo.svg":
            return web.FileResponse(self.root / "logo.svg", headers={"Cache-Control": "public,max-age=86400"})
        if relative == "_alireza/session":
            return web.json_response({"admin": await self.is_admin(request)}, headers={"Cache-Control": "no-store"})
        if relative in ("panel/dns", "panel/dns/"):
            if not await self.is_admin(request):
                raise web.HTTPFound(base)
            async with self.vpn.get(vpn_origin + base + "panel/admins", ssl=tls,
                                    headers={"Cookie": request.headers.get("Cookie", ""),
                                             "Host": request.host, "Accept-Encoding": "identity"},
                                    allow_redirects=False) as response:
                if response.status != 200:
                    raise web.HTTPBadGateway(text="VPN interface is unavailable.")
                document = self.dns_shell(await response.text(), base)
            return web.Response(text=document, content_type="text/html", headers={"Cache-Control": "no-store"})
        agh = relative == "dns" or relative.startswith("dns/")
        if agh:
            if not await self.is_admin(request):
                if request.headers.get("Sec-Fetch-Dest") in ("iframe", "document"):
                    return web.Response(status=401, content_type="text/html", text=
                        '<!doctype html><title>alirezapanel</title><p>Session expired or DNS access denied.</p><a target="_top" href="' +
                        html.escape(base, quote=True) + '">Sign in to alirezapanel</a>')
                raise web.HTTPUnauthorized(text="Super-admin session required.")
            if relative == "dns":
                raise web.HTTPFound(base + "dns/")
            rest = relative[4:]
            if rest in ("control/logout", "login.html", "control/login"):
                # Logout really ends the shared VPN session, including an iframe.
                return web.Response(content_type="text/html", text=
                    '<!doctype html><script>top.location.replace(' + json.dumps(base + 'logout') + ');</script>')
            await self.agh_login()
            origin = self.config["agh_origin"]
            raw_prefix = len(URL(base + "dns/").raw_path)
            path = "/" + request.raw_path[raw_prefix:]
            session = self.agh
            tls = True
        else:
            origin = vpn_origin
            path = request.raw_path
            session = self.vpn
        headers = clean_headers(request.headers, ("accept-encoding", "forwarded", "x-forwarded-for",
                                                   "x-forwarded-proto", "x-forwarded-host", "x-real-ip"))
        headers["Accept-Encoding"] = "identity"
        headers["Host"] = request.host
        headers["X-Forwarded-For"] = request.remote or "127.0.0.1"
        headers["X-Real-IP"] = request.remote or "127.0.0.1"
        headers["X-Forwarded-Proto"] = request.scheme
        headers["X-Forwarded-Host"] = request.host
        if agh:
            headers.popall("Cookie", None)
            headers.popall("Authorization", None)
            headers["X-Forwarded-Prefix"] = base + "dns"
        target = URL(origin + path, encoded=True)
        if request.headers.get("Upgrade", "").lower() == "websocket":
            return await self.websocket(request, target, headers, session, tls)
        # Stream request bodies (including database imports), never load an
        # unbounded upload into the gateway's RAM.
        async with session.request(request.method, target, headers=headers, ssl=tls,
                                   data=request.content if request.can_read_body else None,
                                   allow_redirects=False) as response:
            if agh and response.status in (401, 403):
                self.agh_logged_in = False
                # Don't replay a write; next request obtains a fresh AGH session.
            out = clean_headers(response.headers, ("content-security-policy",) if agh else ())
            if agh:
                out.popall("Set-Cookie", None)
                out.popall("WWW-Authenticate", None)
            if "Location" in out:
                loc = out["Location"]
                if loc.startswith(origin):
                    loc = loc[len(origin):]
                if agh and loc.startswith("/") and not loc.startswith("//"):
                    loc = base + "dns" + loc
                out["Location"] = loc
            if not agh and "Set-Cookie" in out:
                cookies = out.getall("Set-Cookie")
                out.popall("Set-Cookie")
                for value in cookies:
                    if value.startswith("vpn-ui="):
                        if "secure" not in value.lower():
                            value += "; Secure"
                        if "samesite=" not in value.lower():
                            value += "; SameSite=Lax"
                    out.add("Set-Cookie", value)
            content_type = response.headers.get("Content-Type", "").lower()
            if "text/html" in content_type and response.status == 200 and request.method != "HEAD":
                chunks, size = [], 0
                async for chunk in response.content.iter_chunked(65536):
                    size += len(chunk)
                    if size > 8 * 1024 * 1024:
                        raise web.HTTPBadGateway(text="Upstream HTML exceeds integration limit.")
                    chunks.append(chunk)
                raw = b"".join(chunks)
                encoding = response.headers.get("Content-Encoding", "").lower()
                if encoding:
                    raise web.HTTPBadGateway(text="Upstream did not honor identity encoding.")
                document = self.brand_html(raw.decode("utf-8"), base, agh)
                out.popall("ETag", None)
                out.popall("Last-Modified", None)
                out["Cache-Control"] = "no-store"
                out["X-Frame-Options"] = "SAMEORIGIN"
                return web.Response(body=document.encode("utf-8"), status=response.status, headers=out)
            result = web.StreamResponse(status=response.status, headers=out)
            await result.prepare(request)
            async for chunk in response.content.iter_chunked(65536):
                await result.write(chunk)
            await result.write_eof()
            return result

    async def websocket(self, request, target, headers, session, tls):
        headers = clean_headers(headers, ("sec-websocket-key", "sec-websocket-version", "sec-websocket-extensions",
                                           "sec-websocket-protocol"))
        protocols = tuple(x.strip() for x in request.headers.get("Sec-WebSocket-Protocol", "").split(",") if x.strip())
        async with session.ws_connect(target, headers=headers, ssl=tls, protocols=protocols,
                                       autoping=True, heartbeat=25, max_msg_size=16 * 1024 * 1024) as upstream:
            downstream = web.WebSocketResponse(protocols=protocols, heartbeat=25, max_msg_size=16 * 1024 * 1024)
            await downstream.prepare(request)

            async def relay(source, destination):
                async for message in source:
                    if message.type == aiohttp.WSMsgType.TEXT:
                        await destination.send_str(message.data)
                    elif message.type == aiohttp.WSMsgType.BINARY:
                        await destination.send_bytes(message.data)
                    elif message.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                        break

            tasks = [asyncio.create_task(relay(downstream, upstream)), asyncio.create_task(relay(upstream, downstream))]
            try:
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            finally:
                for task in tasks:
                    task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
                await downstream.close()
            return downstream


def create_app(config):
    gateway = Gateway(config)
    app = web.Application(client_max_size=1024 ** 3)
    app.on_startup.append(gateway.start)
    app.on_cleanup.append(gateway.stop)
    app.router.add_route("*", "/{tail:.*}", gateway.handle)
    return app


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    config = json.loads(Path(sys.argv[1] if len(sys.argv) > 1 else "/etc/alirezapanel/gateway.json").read_text())
    context = None
    if config.get("tls_enabled", True):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(config["tls_cert"], config["tls_key"])
    web.run_app(create_app(config), host=config.get("listen", "0.0.0.0"), port=config["port"],
                ssl_context=context, access_log=None, print=None)
ALIREZAPANEL_EMBEDDED_0_EOF

cat > "$STAGE/manage.py" <<'ALIREZAPANEL_EMBEDDED_1_EOF'
#!/usr/bin/env python3
"""Installer helper and local diagnostics, embedded in install.sh."""
import argparse
from contextlib import closing
import getpass
import hashlib
import http.cookiejar
import ipaddress
import json
import os
import secrets
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path('/opt/alirezapanel')
ETC = Path('/etc/alirezapanel')


def save(path, obj, mode=0o600):
    temp = path.with_suffix(path.suffix + '.new')
    temp.write_text(json.dumps(obj, indent=2) + '\n')
    temp.chmod(mode)
    os.replace(temp, path)


def init():
    import bcrypt
    import yaml
    if (ETC / 'gateway.json').exists():
        print('Preserving existing credentials and settings.')
        return
    tls_mode = os.environ.get('ALIREZA_TLS_MODE', 'ip').strip().lower()
    if tls_mode not in ('domain', 'ip', 'none'):
        raise SystemExit('ALIREZA_TLS_MODE must be domain, ip or none.')
    default_port = '443' if tls_mode == 'domain' else ('8080' if tls_mode == 'none' else '8443')
    port = int(os.environ.get('ALIREZA_PORT', default_port))
    if not 1 <= port <= 65535 or port in (53, 18080, 18081):
        raise SystemExit('ALIREZA_PORT must be 1..65535, excluding 53, 18080 and 18081.')

    # Keep DNS on the standard port without taking over the host resolver.
    # Listen on the server's primary IPv4 address only, avoiding 0.0.0.0:53 and
    # localhost conflicts with systemd-resolved while remaining reachable by clients.
    primary_ipv4 = None
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(('1.1.1.1', 53))
            primary_ipv4 = sock.getsockname()[0]
    except OSError:
        pass
    if not primary_ipv4 or primary_ipv4.startswith('127.'):
        raise SystemExit('Could not detect a non-loopback IPv4 address for the public DNS listener.')
    dns_bind_hosts = [primary_ipv4]

    host = os.environ.get('ALIREZA_HOST', '').strip()
    if not host:
        # No external IP-discovery request: use the preferred local IPv4 address.
        host = primary_ipv4 or '127.0.0.1'
    if tls_mode == 'domain' and not os.environ.get('ALIREZA_HOST', '').strip():
        raise SystemExit('ALIREZA_HOST is required when ALIREZA_TLS_MODE=domain.')
    try:
        address = ipaddress.ip_address(host)
        san = 'IP:' + str(address)
    except ValueError:
        import re
        if len(host) > 253 or not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', host):
            raise SystemExit('ALIREZA_HOST must be an IP address or a DNS hostname, without scheme or port.')
        san = 'DNS:' + host
    username = os.environ.get('ALIREZA_USER', 'admin')
    if not username or len(username) > 64 or any(ord(c) < 33 for c in username):
        raise SystemExit('Invalid ALIREZA_USER.')
    password = os.environ.get('ALIREZA_PASSWORD') or secrets.token_urlsafe(24)
    if len(password.encode()) < 16 or len(password.encode()) > 72:
        raise SystemExit('ALIREZA_PASSWORD must contain 16..72 UTF-8 bytes.')
    base = '/' + secrets.token_urlsafe(18) + '/'
    private_password = secrets.token_urlsafe(32)
    # Random private credentials protect AGH even if its native TLS UI is enabled.
    agh_config = {
        'http': {'address': '127.0.0.1:18081', 'session_ttl': '720h',
                 'pprof': {'enabled': False, 'port': 6060}},
        'users': [{'name': 'alirezapanel', 'password': bcrypt.hashpw(private_password.encode(), bcrypt.gensalt()).decode()}],
        'auth_attempts': 5, 'block_auth_min': 15, 'theme': 'dark', 'language': 'en',
        'dns': {'bind_hosts': dns_bind_hosts, 'port': 53, 'serve_plain_dns': True,
                'upstream_dns': ['https://dns.cloudflare.com/dns-query', 'https://dns.google/dns-query'],
                'bootstrap_dns': ['1.1.1.1', '9.9.9.9'],
                'fallback_dns': ['1.1.1.1', '9.9.9.9'],
                'cache_enabled': True, 'cache_size': 4194304, 'max_goroutines': 100,
                'ratelimit': 20, 'refuse_any': True, 'upstream_mode': 'load_balance',
                'enable_dnssec': True},
        'querylog': {'enabled': True, 'file_enabled': True, 'interval': '24h', 'size_memory': 500},
        'statistics': {'enabled': True, 'interval': '24h'},
        'tls': {'enabled': False}, 'schema_version': 34,
    }
    (ROOT / 'adguard/AdGuardHome.yaml').write_text(yaml.safe_dump(agh_config, sort_keys=False))
    cert, key = str(ETC / 'tls/cert.pem'), str(ETC / 'tls/key.pem')
    supplied_cert, supplied_key = os.environ.get('ALIREZA_CERT'), os.environ.get('ALIREZA_KEY')
    if bool(supplied_cert) != bool(supplied_key):
        raise SystemExit('Set both ALIREZA_CERT and ALIREZA_KEY, or neither.')
    if supplied_cert:
        shutil.copyfile(supplied_cert, cert)
        shutil.copyfile(supplied_key, key)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
    else:
        # Keep local certificate files even in HTTP mode so repair/permissions remain stable.
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
                        '-days', '365', '-keyout', key, '-out', cert, '-subj', '/CN=alirezapanel',
                        '-addext', 'subjectAltName=' + san + ',IP:127.0.0.1,DNS:localhost'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cfg = {'port': port, 'listen': '0.0.0.0', 'vpn_db': str(ROOT / 'vpn/vpn-ui.db'),
           'agh_origin': 'http://127.0.0.1:18081', 'agh_user': 'alirezapanel',
           'agh_password': private_password, 'assets': str(ROOT / 'gateway'),
           'tls_cert': cert, 'tls_key': key, 'tls_enabled': tls_mode != 'none',
           'tls_mode': tls_mode, 'host': host,
           'dns_bind_hosts': dns_bind_hosts, 'dns_port': 53}
    save(ETC / 'access.json', {'username': username, 'password': password, 'base': base, 'host': host, 'port': port})
    save(ETC / 'gateway.json', cfg, 0o640)


def seed_vpn():
    import bcrypt
    access = json.loads((ETC / 'access.json').read_text())
    path = ROOT / 'vpn/vpn-ui.db'
    # The upstream CLI creates/migrates its own schema. Only initial settings are
    # inserted after it exits and before any managed service starts.
    if (ETC / 'vpn-seeded').exists():
        return
    with closing(sqlite3.connect(path)) as db, db:
        def put(key, value):
            db.execute('DELETE FROM settings WHERE key=?', (key,))
            db.execute('INSERT INTO settings(key,value) VALUES (?,?)', (key, value))
        for k, v in {'webListen': '127.0.0.1', 'webPort': '18080', 'webBasePath': access['base'],
                     'webCertFile': '', 'webKeyFile': '', 'serverName': 'alirezapanel',
                     'systemdServiceName': 'alirezapanel-vpn', 'subTitle': 'alirezapanel'}.items():
            put(k, v)
        # Never put passwords on the process command line or in installation logs.
        result = db.execute('UPDATE users SET username=?,password=? WHERE id=(SELECT MIN(id) FROM users)',
                            (access['username'], bcrypt.hashpw(access['password'].encode(), bcrypt.gensalt()).decode()))
        if result.rowcount != 1:
            raise SystemExit('Could not initialize the upstream administrator row.')
        # Preserve the original traffic plane: AdGuard listens directly on the
        # server IPv4 address at port 53 instead of installing NAT/redirect rules.
        # Xray and native clients can use that same reachable server IP as DNS.
    (ETC / 'vpn-seeded').write_text('Initial settings applied. Do not remove.\n')


def current_base():
    cfg = json.loads((ETC / 'gateway.json').read_text())
    with closing(sqlite3.connect('file:' + cfg['vpn_db'] + '?mode=ro', uri=True)) as db:
        row = db.execute("SELECT value FROM settings WHERE key='webBasePath' ORDER BY id DESC LIMIT 1").fetchone()
    return '/' + (row[0] if row else '/').strip('/') + '/' if row and row[0] != '/' else '/'


def info():
    cfg = json.loads((ETC / 'gateway.json').read_text())
    host = cfg['host']
    if ':' in host:
        host = '[' + host + ']'
    scheme = 'https' if cfg.get('tls_enabled', True) else 'http'
    print('\nalirezapanel\nURL: ' + scheme + '://' + host + ':' + str(cfg['port']) + current_base())
    print('Initial credentials: /etc/alirezapanel/access.json (root only)')
    dns_hosts = cfg.get('dns_bind_hosts', [])
    if dns_hosts:
        print('DNS on server IP: ' + ', '.join(item + ':53' for item in dns_hosts) + ' (TCP/UDP)')
    else:
        print('DNS warning: no server IPv4 address is configured.')
    print('Help: alirezapanel help | Check: alirezapanel check | Access: alirezapanel credentials')
    print('Documentation: /opt/alirezapanel/README.txt')


def probe():
    cfg = json.loads((ETC / 'gateway.json').read_text())
    if cfg.get('tls_enabled', True):
        tls = ssl.create_default_context(cafile=cfg['tls_cert'])
        tls.check_hostname = False
        tls.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        url = 'https://127.0.0.1:' + str(cfg['port']) + current_base()
        kwargs = {'context': tls}
    else:
        url = 'http://127.0.0.1:' + str(cfg['port']) + current_base()
        kwargs = {}
    with urllib.request.urlopen(url, timeout=3, **kwargs) as response:
        if response.status != 200 or b'_alireza/brand.js' not in response.read():
            raise SystemExit('The integrated login is not ready yet.')


def check(login=False):
    cfg = json.loads((ETC / 'gateway.json').read_text())
    for unit in ('alirezapanel-vpn', 'alirezapanel-dns', 'alirezapanel'):
        subprocess.run(['systemctl', 'is-active', '--quiet', unit], check=True)
        print('OK service:', unit)
    jar = http.cookiejar.CookieJar()
    if cfg.get('tls_enabled', True):
        # Pin the local certificate; a public certificate needn't contain localhost.
        tls = ssl.create_default_context(cafile=cfg['tls_cert'])
        tls.check_hostname = False
        tls.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=tls), urllib.request.HTTPCookieProcessor(jar))
        url = 'https://127.0.0.1:' + str(cfg['port']) + current_base()
    else:
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        url = 'http://127.0.0.1:' + str(cfg['port']) + current_base()
    with opener.open(url, timeout=20) as response:
        text = response.read().decode()
        assert 'alirezapanel' in text and '_alireza/brand.js' in text, 'Brand injection failed'
    print('OK public gateway and branded login')
    try:
        opener.open(url + 'dns/control/status', timeout=20)
        raise RuntimeError('DNS API unexpectedly allowed anonymous access')
    except urllib.error.HTTPError as exc:
        if exc.code != 401:
            raise
    print('OK anonymous DNS access rejected')
    if login:
        access = json.loads((ETC / 'access.json').read_text())
        req = urllib.request.Request(url + 'login',
              data=urllib.parse.urlencode({'username': access['username'], 'password': access['password']}).encode(),
              headers={'X-Alirezapanel-Request': '1', 'Content-Type': 'application/x-www-form-urlencoded'})
        with opener.open(req, timeout=20) as response:
            assert json.load(response)['success'] is True, 'VPN login failed'
        with opener.open(url + 'dns/control/status', timeout=30) as response:
            assert json.load(response)['running'] is True, 'DNS API failed'
        with opener.open(url + 'panel/dns', timeout=20) as response:
            page = response.read().decode()
            assert 'alireza-dns' in page and "Vue.component('a-sidebar'" in page, 'DNS shell failed'
        with opener.open(url + 'dns/', timeout=20) as response:
            assert '_alireza/brand.js' in response.read().decode(), 'DNS branding failed'
        print('OK shared login, full DNS interface, VPN sidebar and DNS API')
    # Test actual DNS resolution on every address AdGuard was configured to bind.
    for dns_host in cfg.get('dns_bind_hosts', []):
        result = subprocess.run(['dig', '@' + dns_host, '-p', '53', 'example.com', 'A', '+time=5', '+tries=1'],
                                check=True, capture_output=True, text=True)
        if 'status: NOERROR' not in result.stdout or 'ANSWER: 0' in result.stdout:
            raise SystemExit('DNS resolution failed on ' + dns_host + ':53. Check upstream connectivity and firewall settings.')
        print('OK actual DNS query:', dns_host + ':53')


if __name__ == '__main__':
    command = sys.argv[1] if len(sys.argv) > 1 else 'info'
    if command == 'init': init()
    elif command == 'seed': seed_vpn()
    elif command == 'info': info()
    elif command == 'check': check('--login' in sys.argv)
    elif command == 'probe': probe()
    else: raise SystemExit('Unknown helper command')
ALIREZAPANEL_EMBEDDED_1_EOF

cat > "$STAGE/brand.js" <<'ALIREZAPANEL_EMBEDDED_2_EOF'
/* alirezapanel presentation adapter. No upstream API/config rewriting. */
(() => {
  'use strict';
  const config = window.ALIREZA;
  if (!config) return;
  const base = config.base;
  const brand = 'alirezapanel';
  const names = /AdGuard\s*Home|VPN[\s-]?UI|3X-UI/gi;
  const ignored = 'script,style,textarea,input,pre,code,[contenteditable="true"],.logs__table,.query-log,.ace_editor';
  const replace = (value) => value.replace(names, brand);
  const seen = new WeakSet();
  function visit(root) {
    if (root.nodeType === Node.TEXT_NODE) {
      if (root.parentElement && !root.parentElement.closest(ignored)) {
        const next = replace(root.nodeValue);
        if (next !== root.nodeValue) root.nodeValue = next;
      }
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE || root.matches(ignored)) return;
    for (const attr of ['title', 'alt', 'aria-label']) {
      if (root.hasAttribute(attr)) {
        const previous = root.getAttribute(attr), next = replace(previous);
        if (next !== previous) root.setAttribute(attr, next);
      }
    }
    for (const child of root.childNodes) visit(child);
  }
  function identity() {
    const title = brand + (config.dns ? ' · DNS' : '');
    if (document.title !== title) document.title = title;
    for (const icon of document.querySelectorAll('link[rel~="icon"]')) {
      const target = base + '_alireza/logo.svg?v=1.1.0';
      if (icon.getAttribute('href') !== target) icon.setAttribute('href', target);
    }
    if (!document.querySelector('link[rel~="icon"]')) {
      const link = document.createElement('link'); link.rel = 'icon';
      link.href = base + '_alireza/logo.svg?v=1.1.0'; document.head.appendChild(link);
    }
    for (const logo of document.querySelectorAll('.bo-rail-brand img,.login-logo img,.header-brand-img,img[alt="alirezapanel"]')) {
      if (seen.has(logo)) continue;
      seen.add(logo);
      if (logo.tagName.toLowerCase() === 'img') {
        logo.src = base + '_alireza/logo.svg?v=1.1.0'; logo.alt = brand;
      } else {
        // Keep React's own SVG node, replacing only its visual mark via CSS.
        logo.style.display = 'none';
      }
      const parent = logo.parentElement;
      if (parent && !parent.querySelector('.alireza-name')) {
        const label = document.createElement('span');
        label.className = 'alireza-name'; label.textContent = brand;
        parent.appendChild(label);
      }
    }
    if (!config.dns && typeof Vue !== 'undefined' && typeof PERMS !== 'undefined' && PERMS.superAdmin) {
      const nav = document.querySelector('.bo-rail');
      const component = nav && nav.__vue__;
      if (component && Array.isArray(component.tabs) && !component.tabs.some(t => t.key === base + 'panel/dns')) {
        component.tabs.splice(component.tabs.length - 1, 0, {key: base + 'panel/dns', icon: 'global', title: 'DNS'});
        if (location.pathname.replace(/\/$/, '') === base + 'panel/dns') component.requestUri = base + 'panel/dns';
      }
    }
  }
  const style = document.createElement('style');
  style.textContent = '.alireza-name{font:600 15px system-ui,sans-serif;letter-spacing:-.4px;white-space:nowrap}' +
    '.bo-rail-brand a{display:flex;align-items:center;gap:7px;flex-wrap:wrap;justify-content:center}' +
    '.bo-rail-brand .alireza-name{font-size:11px}.bo-rail-brand img{width:30px;height:30px;object-fit:contain}' +
    '.bo-rail--collapsed .alireza-name{display:none}';
  document.head.appendChild(style);
  let pending = false;
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === 'characterData') visit(record.target);
      else for (const node of record.addedNodes) visit(node);
    }
    if (!pending) { pending = true; requestAnimationFrame(() => { pending = false; identity(); }); }
  });
  visit(document.body); identity();
  observer.observe(document.documentElement, {childList: true, subtree: true, characterData: true});
  if (config.dns) {
    // Sync expiry UI without polling the dashboard or sharing the private AGH login.
    setInterval(async () => {
      if (document.hidden) return;
      try {
        const response = await fetch(base + '_alireza/session', {credentials:'same-origin', cache:'no-store'});
        if (response.ok && !(await response.json()).admin) top.location.replace(base);
      } catch (_) { /* A temporary network loss must not destroy work in a form. */ }
    }, 60000);
  }
})();
ALIREZAPANEL_EMBEDDED_2_EOF

cat > "$STAGE/theme.css" <<'ALIREZAPANEL_EMBEDDED_3_EOF'
/* alirezapanel / Ember. Presentation only; no protocol or API changes.
   No remote fonts, canvas, blur filters or continuous animation. */
html[data-alireza-theme="ember"],
html[data-alireza-theme="ember"] body,
html[data-alireza-theme="ember"][data-theme="ultra-dark"] body.dark {
  --ap-bg:#0e0e11; --ap-surface:#18181c; --ap-raised:#212126;
  --ap-border:#303037; --ap-text:#f5f2ef; --ap-muted:#b7b2ad;
  --ap-orange:#ff963f; --ap-orange-hover:#ffb170; --ap-orange-soft:#35271e;
  --ap-on-orange:#211208; --ap-ring:rgba(255,150,63,.25);
  --bg:var(--ap-bg); --surface:var(--ap-surface); --surface-2:var(--ap-raised);
  --border:var(--ap-border); --border-strong:#49413a;
  --text:var(--ap-text); --text-2:var(--ap-muted); --text-3:#a9a39d;
  --accent:var(--ap-orange); --accent-strong:var(--ap-orange);
  --accent-weak:var(--ap-orange-soft); --on-accent:var(--ap-on-orange);
  --color-primary-100:var(--ap-orange);
  --radius-sm:8px; --radius-md:12px; --radius-lg:16px; --radius-xl:20px;
  --dark-color-background:var(--ap-bg);
  --dark-color-surface-100:var(--ap-surface);
  --dark-color-surface-200:var(--ap-raised);
  --dark-color-surface-300:#303037; --dark-color-surface-400:#393940;
  --dark-color-surface-500:#34343c; --dark-color-surface-600:#3e3e46;
  --dark-color-surface-700:#131316; --dark-color-surface-700-rgb:19,19,22;
  --dark-color-text-primary:var(--ap-text); --dark-color-text-secondary:var(--ap-muted);
  --dark-color-stroke:var(--ap-border); --dark-color-table-hover:#242125;
  --dark-color-table-header-bg:#141417; --dark-color-table-body-bg:var(--ap-surface);
  --dark-color-table-row-selected:#35271e; --dark-color-table-row-selected-hover:#433024;
  --dark-color-table-column-sorted-bg:#28211d; --dark-color-table-ring:#443328;
  --dark-color-table-filter-dropdown-bg:var(--ap-raised);
  --dark-color-table-pagination-surface:var(--ap-raised);
  --dark-color-scrollbar:#444149; --dark-color-scrollbar-webkit:#625b57;
  --dark-color-scrollbar-webkit-hover:#9d7760;
  --dark-color-spin-container:var(--ap-surface); --dark-color-tooltip:#303037;
  --dark-color-codemirror-line-hover:#35271e;
  --dark-color-codemirror-line-selection:#4a3526;
  /* Native AdGuard custom properties, including dropdowns and query-log rows. */
  --black:var(--ap-text); --bgcolor:var(--ap-bg); --mcolor:var(--ap-text);
  --scolor:var(--ap-muted); --border-color:var(--ap-border);
  --header-bgcolor:#141416; --card-bgcolor:var(--ap-surface);
  --card-border-color:var(--ap-border); --ctrl-bgcolor:#111114;
  --ctrl-select-bgcolor:var(--ap-raised); --ctrl-dropdown-color:var(--ap-text);
  --ctrl-dropdown-bgcolor-focus:var(--ap-orange-soft); --ctrl-dropdown-color-focus:var(--ap-orange);
  --form-disabled-bgcolor:#242429; --form-disabled-color:#a39c96;
  --rt-nodata-bgcolor:var(--ap-surface); --rt-nodata-color:var(--ap-muted);
  --modal-overlay-bgcolor:rgba(0,0,0,.7); --loading-bg:var(--ap-bg);
  --logs__table-bgcolor:var(--ap-surface); --logs__row--white-bgcolor:var(--ap-surface);
  --logs__row--blue-bgcolor:#232d3d; --logs__text-color:var(--ap-text);
  --alert-message-color:#ecd9c7; --alert-message-border:#58402e; --alert-message-bg:#30251e;
  --checkbox-bg:#4a4541; --radio-bg:#4a4541;
  color-scheme:dark;
}
/* Keep the native light-mode choice usable, with the same orange identity. */
html[data-alireza-theme="ember"] body.light,
html[data-alireza-theme="ember"][data-theme="light"],
html[data-alireza-theme="ember"][data-theme="light"] body {
  --ap-bg:#f5f1eb; --ap-surface:#fffdf9; --ap-raised:#eee7de;
  --ap-border:#dfd4c8; --ap-text:#29231e; --ap-muted:#6b6057;
  --ap-orange:#a94008; --ap-orange-hover:#873004; --ap-orange-soft:#fae4d1;
  --ap-on-orange:#fffaf4; --ap-ring:rgba(169,64,8,.18);
  --border-strong:#c9b5a4; --text-3:#76685d;
  --header-bgcolor:#fffaf3; --ctrl-bgcolor:#fffcf8;
  --form-disabled-bgcolor:#e9e1d8; --form-disabled-color:#796d64;
  --logs__row--blue-bgcolor:#e5effd; --loading-bg:#f5f1eb;
  --alert-message-color:#644025; --alert-message-bg:#fff1df;
  --alert-message-border:#e4c29f; color-scheme:light;
}
html[data-alireza-theme="ember"] body {
  background:var(--ap-bg)!important; color:var(--ap-text);
  -webkit-font-smoothing:antialiased;
  scrollbar-color:#625b57 var(--ap-bg); scrollbar-width:thin;
}
html[data-alireza-theme="ember"] ::selection { background:#8e4b23; color:#fff7ef; }
html[data-alireza-theme="ember"] :is(a,button,input,textarea,select,[tabindex]):focus-visible {
  outline:2px solid var(--ap-orange)!important; outline-offset:3px;
}
html[data-alireza-theme="ember"] :is(h1,h2,h3,h4,h5,h6) { color:var(--ap-text); }
html[data-alireza-theme="ember"] a { color:var(--ap-orange); }
html[data-alireza-theme="ember"] a:hover { color:var(--ap-orange-hover); }
html[data-alireza-theme="ember"] :is(.text-muted,.card-subtitle,.form-text) { color:var(--ap-muted)!important; }

/* VPN shell: compact rail, warm accent and quiet surfaces. */
html[data-alireza-theme="ember"] .bo-shell { background:var(--ap-bg); }
html[data-alireza-theme="ember"] .bo-rail {
  background:var(--ap-surface); border-inline-end:1px solid var(--ap-border);
  padding-block:22px 16px; gap:24px;
}
html[data-alireza-theme="ember"] .bo-rail-brand { min-height:58px; }
html[data-alireza-theme="ember"] .bo-rail-brand img { filter:none; }
html[data-alireza-theme="ember"] .bo-rail-nav { gap:4px; }
html[data-alireza-theme="ember"] .bo-rail-item {
  position:relative; color:var(--ap-muted); border:1px solid transparent;
  border-radius:12px; padding-block:10px;
  transition:background-color .14s,border-color .14s,color .14s;
}
html[data-alireza-theme="ember"] .bo-rail-item:hover { background:var(--ap-raised); color:var(--ap-text); }
html[data-alireza-theme="ember"] .bo-rail-item.is-active {
  color:var(--ap-orange); background:var(--ap-orange-soft); border-color:#634027;
}
html[data-alireza-theme="ember"] .bo-rail-item.is-active::before {
  content:""; position:absolute; inset-inline-start:-7px; top:22%; bottom:22%;
  width:3px; border-radius:3px; background:var(--ap-orange);
}
html[data-alireza-theme="ember"] .bo-topbar { background:var(--ap-surface); border-color:var(--ap-border); }
html[data-alireza-theme="ember"] .bo-topbar-inner { min-height:66px; }
html[data-alireza-theme="ember"] .bo-topbar-title { font-weight:650; letter-spacing:-.35px; }
html[data-alireza-theme="ember"] .bo-content { padding-top:22px; }
html[data-alireza-theme="ember"] :is(.bo-tile,.ant-card,.lgt-card) {
  border-color:var(--ap-border); border-radius:16px; background:var(--ap-surface);
  box-shadow:0 4px 18px rgba(0,0,0,.08);
}
html[data-alireza-theme="ember"] :is(.bo-tile,.ant-card):hover { border-color:#4b3c32; }
html[data-alireza-theme="ember"] #app.login-app {
  background:radial-gradient(ellipse at 50% 0,rgba(255,128,39,.11),transparent 58%),var(--ap-bg);
}
html[data-alireza-theme="ember"] #app.login-app .lgt-card {
  border-top:3px solid var(--ap-orange); border-radius:22px; box-shadow:0 20px 70px rgba(0,0,0,.2);
}
html[data-alireza-theme="ember"] #app.login-app .lgt-brand { letter-spacing:-.5px; font-size:23px; }
html[data-alireza-theme="ember"] #app.login-app .lgt-submit {
  background:var(--ap-orange); color:var(--ap-on-orange); border-radius:10px; font-weight:700;
}

/* Forms, dialogs and tables are deliberately scoped to native components. */
html[data-alireza-theme="ember"] :is(.ant-input,.ant-input-number,.ant-select-selection,.ant-select-dropdown,
 .ant-calendar-picker-container,.ant-calendar,.ant-modal-content,.ant-popover-inner,.ant-dropdown-menu) {
  background:var(--ap-surface)!important; color:var(--ap-text)!important; border-color:var(--ap-border)!important;
}
html[data-alireza-theme="ember"] :is(.ant-modal-header,.ant-card-head,.ant-table-thead>tr>th) {
  background:var(--ap-raised)!important; color:var(--ap-text)!important; border-color:var(--ap-border)!important;
}
html[data-alireza-theme="ember"] :is(.ant-modal-title,.ant-form-item-label>label,.ant-modal-close,.ant-select-arrow) { color:var(--ap-text)!important; }
html[data-alireza-theme="ember"] :is(.ant-table-tbody>tr>td,.ant-modal-footer) { border-color:var(--ap-border)!important; }
html[data-alireza-theme="ember"] .ant-table-tbody>tr>td { background:var(--ap-surface); color:var(--ap-text); }
html[data-alireza-theme="ember"] .ant-table-tbody>tr:hover:not(.ant-table-expanded-row)>td { background:var(--ap-raised)!important; }
html[data-alireza-theme="ember"] :is(.ant-select-dropdown-menu-item,.ant-dropdown-menu-item) { color:var(--ap-text); }
html[data-alireza-theme="ember"] :is(.ant-select-dropdown-menu-item-active,.ant-select-dropdown-menu-item-selected,
 .ant-dropdown-menu-item:hover,.ant-tabs-tab-active) { color:var(--ap-orange)!important; background:var(--ap-orange-soft); }
html[data-alireza-theme="ember"] .ant-btn:not(.ant-btn-primary):not(.ant-btn-danger):not(.ant-btn-link) {
  background:var(--ap-raised); color:var(--ap-text); border-color:var(--ap-border); border-radius:8px;
}
html[data-alireza-theme="ember"] .ant-btn-primary:not([disabled]) {
  background:var(--ap-orange)!important; border-color:var(--ap-orange)!important; color:var(--ap-on-orange)!important;
  font-weight:600; border-radius:8px; text-shadow:none;
}
html[data-alireza-theme="ember"] :is(.ant-switch-checked,.ant-checkbox-checked .ant-checkbox-inner,.ant-radio-inner::after,.ant-tabs-ink-bar) {
  background-color:var(--ap-orange)!important; border-color:var(--ap-orange)!important;
}
html[data-alireza-theme="ember"] :is(.ant-checkbox-checked .ant-checkbox-inner::after) { border-color:var(--ap-on-orange)!important; }
html[data-alireza-theme="ember"] :is(.ant-pagination-item-active,.ant-radio-checked .ant-radio-inner) { border-color:var(--ap-orange)!important; }
html[data-alireza-theme="ember"] .ant-pagination-item-active a { color:var(--ap-orange)!important; }
html[data-alireza-theme="ember"] :is(input,textarea)::placeholder { color:#928a83; opacity:1; }
html[data-alireza-theme="ember"] :is(button:disabled,input:disabled,textarea:disabled,.ant-btn[disabled]) { opacity:.55; cursor:not-allowed; }

/* Full native AdGuard interface, inside its own iframe. */
html[data-alireza-theme="ember"] #root .header {
  background:var(--ap-surface); border-bottom:1px solid var(--ap-border); box-shadow:none;
}
html[data-alireza-theme="ember"] #root .header .nav-link { color:var(--ap-muted); }
html[data-alireza-theme="ember"] #root .header .nav-link:hover,
html[data-alireza-theme="ember"] #root .header .nav-link.active { color:var(--ap-orange); border-color:var(--ap-orange); }
html[data-alireza-theme="ember"] .alireza-name { color:var(--ap-text); }
html[data-alireza-theme="ember"] #root .alireza-name::before {
  content:""; display:inline-block; width:9px; height:9px; background:var(--ap-orange);
  margin-inline-end:8px; border-radius:3px; vertical-align:middle;
}
html[data-alireza-theme="ember"] #root .card {
  border:1px solid var(--ap-border); border-radius:16px; background:var(--ap-surface);
  box-shadow:0 4px 18px rgba(0,0,0,.08);
}
html[data-alireza-theme="ember"] #root .card-header { border-color:var(--ap-border); padding-block:18px; }
html[data-alireza-theme="ember"] #root .card-title { letter-spacing:-.25px; font-weight:600; }
html[data-alireza-theme="ember"] #root .page-title { font-weight:650; letter-spacing:-.7px; }
html[data-alireza-theme="ember"] #root :is(.btn-primary,.btn-outline-primary) {
  border-color:var(--ap-orange)!important; color:var(--ap-orange)!important; background:transparent; border-radius:8px;
}
html[data-alireza-theme="ember"] #root .btn-primary {
  background:var(--ap-orange)!important; color:var(--ap-on-orange)!important; font-weight:600;
}
html[data-alireza-theme="ember"] #root .btn-outline-primary:hover {
  background:var(--ap-orange-soft)!important; color:var(--ap-orange-hover)!important;
}
html[data-alireza-theme="ember"] #root :is(.btn-secondary,.btn-outline-secondary) {
  background:var(--ap-raised); color:var(--ap-text); border-color:var(--ap-border); border-radius:8px;
}
html[data-alireza-theme="ember"] #root :is(.form-control,.form-control:focus,.custom-select,.select__control) {
  background:var(--ctrl-bgcolor); color:var(--ap-text); border-color:var(--ap-border); border-radius:9px;
}
html[data-alireza-theme="ember"] #root :is(.form-control:focus,.custom-select:focus) {
  border-color:var(--ap-orange); box-shadow:0 0 0 3px var(--ap-ring);
}
html[data-alireza-theme="ember"] #root :is(.dropdown-menu,.modal-content,.popover,.select__menu) {
  background:var(--ap-surface); color:var(--ap-text); border:1px solid var(--ap-border); border-radius:12px;
}
html[data-alireza-theme="ember"] #root :is(.dropdown-item,.modal-title,.close) { color:var(--ap-text); }
html[data-alireza-theme="ember"] #root .dropdown-item:hover { background:var(--ap-orange-soft); color:var(--ap-orange); }
html[data-alireza-theme="ember"] #root :is(.table,.ReactTable,.rt-thead,.rt-tbody) { color:var(--ap-text); border-color:var(--ap-border); }
html[data-alireza-theme="ember"] #root :is(.rt-thead,.table thead th) { background:var(--ap-raised); }
html[data-alireza-theme="ember"] #root :is(.ReactTable .rt-tr-group,.table td,.table th) { border-color:var(--ap-border); }
html[data-alireza-theme="ember"] #root .ReactTable.-highlight .rt-tbody .rt-tr:not(.-padRow):hover { background:var(--ap-raised); }
html[data-alireza-theme="ember"] #root :is(.custom-control-input:checked~.custom-control-label::before,.custom-switch-input:checked~.custom-switch-indicator) {
  background-color:var(--ap-orange); border-color:var(--ap-orange);
}
html[data-alireza-theme="ember"] #root input { accent-color:var(--ap-orange); }
html[data-alireza-theme="ember"] #root .footer { background:var(--ap-bg); border-color:var(--ap-border); color:var(--ap-muted); }
html[data-alireza-theme="ember"] #alireza-dns { background:var(--ap-bg); height:calc(100dvh - 68px)!important; }
@media (max-width:600px) {
  html[data-alireza-theme="ember"] .bo-topbar-inner { min-height:58px; padding-inline:14px; }
  html[data-alireza-theme="ember"] .bo-topbar-title { font-size:16px; }
  html[data-alireza-theme="ember"] #root .card { border-radius:12px; }
  html[data-alireza-theme="ember"] #alireza-dns { height:calc(100dvh - 60px)!important; min-height:400px!important; }
}
@media (prefers-reduced-motion:reduce) {
  html[data-alireza-theme="ember"] :is(.bo-rail-item,.ant-btn,.btn,.lgt-rise) { transition:none!important; animation:none!important; }
}
ALIREZAPANEL_EMBEDDED_3_EOF

cat > "$STAGE/logo.svg" <<'ALIREZAPANEL_EMBEDDED_4_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect width="48" height="48" rx="14" fill="#ff963f"/><path d="M24 8 38 14v10c0 8-7 13-14 16C17 37 10 32 10 24V14Z" fill="#211208"/><path d="m17 29 7-14 7 14m-11-5h8" fill="none" stroke="#ffb170" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
ALIREZAPANEL_EMBEDDED_4_EOF

cat > "$STAGE/README.txt" <<'ALIREZAPANEL_EMBEDDED_5_EOF'
alirezapanel 1.1.0
=================

One online installer. Full upstream VPN-UI v1.9.4 and AdGuard Home v0.107.79
executables; no features are compiled out. The real AdGuard interface is shown
inside the VPN sidebar through an authenticated same-origin iframe. Both web
interfaces receive the alirezapanel display name. Internal filenames, protocols,
API keys, upstream URLs and license notices retain their original names.

EMBER UI (1.1)
Orange and charcoal styling for both complete interfaces: navigation, dashboard
cards, forms, tables and dialogs. Status and destructive-action colors retain
their meaning. Native light-mode controls remain available with a matching warm
palette. No external fonts, continuous animations or blur effects are added.
On a previous installation run: sudo bash install.sh --repair
Repair preserves settings and takes a backup; services pause during repair.

SUPPORTED TARGET
Debian 12/13 or Ubuntu 24.04, x86_64/amd64, systemd, a fresh server with at least
approximately 1 GiB RAM and 2 GiB free disk space. GitHub and distribution package
repositories must be reachable. VPN-UI's released bundle is about 346 MB. No Go,
Node, npm, Docker or on-server source compilation is needed for the panel itself.
Some optional protocols (notably AmneziaWG) still need upstream kernel module
compilation/packages when enabled. Protocol compatibility remains upstream's.

INSTALL
  sudo bash install.sh
  sudo env ALIREZA_HOST=panel.example.com bash install.sh

Your HTTPS URL is printed when installation completes. Default port: 8443.
Display initial credentials with: sudo alirezapanel credentials
Change the password and enable two-factor authentication in the VPN admin UI.
Generated initial credentials remain in /etc/alirezapanel/access.json (0600).
That file is only an initial recovery record, not a password synchronization file.

TLS
The default certificate is self-signed; browsers will display a trust warning.
Supply a real certificate at install using both ALIREZA_CERT and ALIREZA_KEY.
For later renewal replace /etc/alirezapanel/tls/cert.pem and key.pem with the
matching PEM files, keep root:alirezapanel ownership and mode 0640, and run
  sudo systemctl restart alirezapanel
The installer does not claim automatic public certificate issuance or renewal.

ONE LOGIN / ACCESS
Log into the VPN panel normally, including its existing 2FA. Only super admins
see DNS; delegated administrators/resellers cannot change a server-wide resolver.
Every DNS request is authorized again by VPN-UI's own super-admin endpoint. The
gateway never decodes cookies itself and never gives the private AdGuard password
or cookie to a browser. Logout in the DNS interface logs out of the VPN session.

DEFAULT PORTS
  8443 TCP          Unified HTTPS interface, public (configurable)
  18080 TCP         VPN web backend, loopback only
  18081 TCP         AdGuard HTTP backend, loopback only
  53 TCP and UDP     AdGuard DNS resolver, primary server IPv4
systemd-resolved and resolv.conf are not modified. AdGuard binds the detected
server IPv4 instead of localhost or 0.0.0.0:53 to avoid resolver conflicts.
The hosting firewall must permit the HTTPS port, TCP/UDP 53 for public DNS, and
any VPN ports you enable.

DNS AND VPN / TUNNEL COMPATIBILITY
The original Xray template, routing rules, outbounds, firewall and tunnel
configuration are preserved. No global DNS interception or traffic redirection
is inserted. This avoids silently overriding split routing, SSH/VPN outbounds,
private networks and per-account routing/limits. DNS and VPN are both installed
and managed in one interface. AdGuard listens directly on TCP/UDP port 53 at
the primary IPv4 address detected on the server. Xray and native clients can use
the server's reachable/public IP as their DNS server on port 53. No loopback DNS
listener and no alternate DNS port are created. If the VPS provider uses NAT,
use the provider's public IP and make sure TCP/UDP 53 is forwarded to the server.
Create users/inbounds and provision the protocols you want in VPN-UI as usual.
Client-side DNS that never enters the tunnel, third-party DoH/DoT, and programs
using their own encrypted DNS are not forcibly intercepted by this integration.
Query attribution may show the proxy/loopback client instead of each VPN user.
Test your selected client/protocol's DNS path in the DNS query log.

ADGUARD SETTINGS
All native dashboard, query log, statistics, filters, allowlists, rewrites,
blocked services, client settings, DNS, encryption and DHCP screens are retained.
DHCP and native encrypted-DNS listeners still require appropriate network/port
configuration. They are not enabled automatically on a VPS. If you later connect
an Xray/protocol DNS policy to AdGuard, keep it in sync with AdGuard's DNS listener.
Exposing a native listener uses that listener's own AdGuard behavior, not the
integrated gateway. Do not expose a recursive resolver to arbitrary Internet
clients; configure allowed clients when enabling a public DNS listener.

RESOURCE DEFAULTS
AdGuard cache: 4 MiB, query-log memory buffer: 500 entries, log retention: 24h,
statistics retention: 24h, concurrent DNS queries: 100. These are configurable
in the original UI and are not deleted features. Go soft heap limits: VPN 300 MiB,
AdGuard 160 MiB, with moderately more frequent garbage collection. These are NOT
hard total-memory limits, do not include every child VPN daemon, and cannot
guarantee fitting arbitrary traffic/filter lists into 1 GiB. Only enable needed
VPN services and avoid enormous filter lists on a small machine. The Python
gateway streams downloads/uploads and WebSockets instead of buffering them;
only HTML is buffered (up to 8 MiB). No extra dashboard polling runs in the shell.
Swap and global kernel settings are not modified. No 1-GiB load benchmark has
been performed by the author in this Windows development environment.

SETTINGS THAT HAVE TWO LAYERS
VPN-UI and AdGuard retain their native configuration pages. The added public
gateway's port/listen/certificate settings live in /etc/alirezapanel/gateway.json;
restart alirezapanel after changing them. VPN-UI's web port is its INTERNAL port,
not the public gateway port. Keep it bound to loopback. The gateway reads VPN
port/base-path/certificate changes from the VPN database, but changing the VPN
bind address to a public address can expose its native UI directly. The AdGuard
HTTP socket is pinned by the service to loopback:18081 for shared authentication.
This integration does not pretend the two original settings models became one.

OPERATIONS
  sudo alirezapanel info          URL and paths
  sudo alirezapanel credentials   Initial credentials (root only)
  sudo alirezapanel status        Service state
  sudo alirezapanel check         Services, HTTPS, unauthorized access, DNS lookup
  sudo alirezapanel logs          Recent service logs
  sudo alirezapanel restart       Restart all three services
  sudo alirezapanel backup        Consistent backup (briefly stops VPN/DNS)
  sudo alirezapanel vpn info      Original VPN management CLI
  sudo bash install.sh --repair   Backup, restore pinned binaries/integration,
                                 preserve users and configuration

Backups are root-only under /var/backups/alirezapanel. Repair does not reset
passwords, regenerate certificates or replace DNS/filter/user configuration.
Rerunning the normal install after success only displays installation info.
No automatic migration of an existing standalone installation is attempted.

UPDATES
Upstream update controls remain present, but newer UI/API layouts may require
an updated integration. Take a backup first and validate DNS access after an
upstream update. The installer intentionally pins known versions/hashes instead
of silently pulling latest. --repair refuses a detected version mismatch to
avoid downgrading a migrated database. Use a matching integration/backup after
upstream upgrades. No background integration auto-update runs.

VALIDATION AND LIMITS
The installer verifies the release SHA-256 hashes, compiles embedded Python,
validates AdGuard configuration and systemd units, then tests HTTPS branding,
anonymous DNS denial, initial shared admin login, the integrated shell, AdGuard
status and a real DNS query. It reports success ONLY if those checks pass.
Development verification includes proxy/auth/stream/WebSocket tests and the real
AdGuard executable on Windows. Full Linux installation, kernel VPN protocols,
all AdGuard settings flows and sustained 1-GiB performance remain unverified.

SOURCE AND LICENSE
See SOURCES.txt, LICENSE-vpn-ui.txt and LICENSE-AdGuardHome.txt in this directory.
Original GPL licenses and author notices are retained. Integration source is
embedded in install.sh and installed in /opt/alirezapanel/gateway, under GPL-3.0
or later. alirezapanel is an independent integration of the upstream projects.
ALIREZAPANEL_EMBEDDED_5_EOF

cat > "$STAGE/LICENSE-vpn-ui.txt" <<'ALIREZAPANEL_EMBEDDED_6_EOF'
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Use with the GNU Affero General Public License.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU Affero General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the special requirements of the GNU Affero General Public License,
section 13, concerning interaction through a network will apply to the
combination as such.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If the program does terminal interaction, make it output a short
notice like this when it starts in an interactive mode:

    <program>  Copyright (C) <year>  <name of author>
    This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, your program's commands
might be different; for a GUI interface, you would use an "about box".

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU GPL, see
<https://www.gnu.org/licenses/>.

  The GNU General Public License does not permit incorporating your program
into proprietary programs.  If your program is a subroutine library, you
may consider it more useful to permit linking proprietary applications with
the library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.  But first, please read
<https://www.gnu.org/licenses/why-not-lgpl.html>.
ALIREZAPANEL_EMBEDDED_6_EOF


cat > "$STAGE/nodes.py" <<'NODE_EMBEDDED_PY_EOF'
"""Optional node control plane. No VPN database writes or protocol generation.

All inbound operations use the node's unmodified native controller. Node tokens
are only accepted by an explicit route allowlist, never as a panel login.
"""
import asyncio
import base64
import contextlib
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import ssl
import tempfile
import time
from urllib.parse import quote, urlsplit
import uuid

import aiohttp
from aiohttp import web
from multidict import CIMultiDict
from yarl import URL
import yaml

AGENT = '/_alireza/node-agent/v1/'
PUBLIC = '/_alireza/subscriptions/'
LIMIT = 8 * 1024 * 1024
HOP = {'connection','keep-alive','proxy-authenticate','proxy-authorization','te',
       'trailer','transfer-encoding','upgrade','content-length'}

def headers_clean(headers):
    excluded = HOP | {s.strip().lower() for s in headers.get('Connection','').split(',')}
    return CIMultiDict((k,v) for k,v in headers.items() if k.lower() not in excluded)

def no_store(data, status=200):
    return web.json_response(data, status=status, headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer'})

async def bounded(response, limit=LIMIT):
    chunks, size = [], 0
    async for chunk in response.content.iter_chunked(65536):
        size += len(chunk)
        if size > limit:
            raise web.HTTPBadGateway(text='Node response exceeds its size limit.')
        chunks.append(chunk)
    return b''.join(chunks)

def descriptor(text):
    if not isinstance(text,str) or len(text)>24000:
        raise ValueError('Invalid node certificate package.')
    data = json.loads(text)
    endpoint = str(data['endpoint']).rstrip('/')
    url = URL(endpoint)
    if data.get('version') != 1 or url.scheme != 'https' or not url.host or url.user or url.password or url.path not in ('','/') or url.query_string or url.fragment:
        raise ValueError('Node endpoint must be an HTTPS origin without credentials or a path.')
    pem = data['certificate']
    der = ssl.PEM_cert_to_DER_cert(pem)
    return {'endpoint':endpoint,'certificate':pem,'fingerprint':hashlib.sha256(der).hexdigest()}

def permitted(method, tail):
    # URL decoding has already happened in aiohttp. Reject traversal/ambiguous
    # path separators before matching, rather than trying to normalize them.
    path = tail.split('?',1)[0]
    if '\\' in path or any(p in ('.','..') for p in path.split('/')) or path.startswith('/'):
        return False
    if method in ('GET','HEAD') and (path.startswith('assets/') or path in ('panel/inbounds','panel/inbounds/','ws','panel/core','panel/core/')):
        return True
    if method in ('GET','POST') and path.startswith('panel/api/inbounds/'):
        return True
    if method == 'GET' and path in ('panel/core/status','panel/core/catalog','panel/core/provision-status'):
        return True
    if method == 'POST' and path == 'panel/core/provision':
        return True
    if method == 'POST' and path in ('panel/setting/defaultSettings','panel/setting/inboundForm'):
        return True
    if method == 'GET' and path in tuple('panel/api/server/'+p for p in ('status','serverName','panelLocation','getNewUUID','getNewX25519Cert','getNewmldsa65','getNewmlkem768','getNewVlessEnc','getXrayVersion')):
        return True
    if method == 'POST' and path=='panel/api/server/getNewEchCert':
        return True
    return False

class Nodes:
    def __init__(self, gateway):
        self.g = gateway
        self.folder = Path(gateway.config.get('nodes_state','/var/lib/alirezapanel-nodes'))
        self.file = self.folder/'state.json'
        self.lock = asyncio.Lock()
        self.login_lock = asyncio.Lock()
        self.cookie = ''
        self.cookie_at = 0
        self.pool = asyncio.Semaphore(8)
        self.subscription_pool = asyncio.Semaphore(2)
        self.channels = {}
        self.state = None

    async def start(self):
        self.folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.state = json.loads(self.file.read_text(encoding='utf-8')) if self.file.exists() else {
            'version':1,'id':str(uuid.uuid4()),'token':None,'service':None,'nodes':{},'profiles':{}}
        self.remote = aiohttp.ClientSession(cookie_jar=aiohttp.DummyCookieJar(),
            timeout=aiohttp.ClientTimeout(total=None,connect=8,sock_read=90),
            connector=aiohttp.TCPConnector(limit=32),auto_decompress=False)

    async def stop(self):
        for tasks in self.channels.values():
            for task in tuple(tasks): task.cancel()
        await self.remote.close()

    async def channel(self, key, operation):
        task=asyncio.current_task()
        tasks=self.channels.setdefault(key,set()); tasks.add(task)
        try:
            return await operation
        finally:
            tasks.discard(task)

    def disconnect(self, key):
        for task in tuple(self.channels.get(key,())):
            task.cancel()

    def save(self):
        fd, name = tempfile.mkstemp(prefix='.state-',dir=self.folder)
        try:
            with os.fdopen(fd,'w',encoding='utf-8') as f:
                json.dump(self.state,f,ensure_ascii=True)
                f.flush(); os.fsync(f.fileno())
            os.chmod(name,0o600)
            os.replace(name,self.file)
        finally:
            if os.path.exists(name): os.unlink(name)

    async def admin(self, request):
        self.g.validate_origin(request)
        if not await self.g.is_admin(request):
            raise web.HTTPForbidden(text='Super-admin access required.')

    async def body(self, request):
        raw = bytearray()
        async for chunk in request.content.iter_chunked(16384):
            raw.extend(chunk)
            if len(raw)>65536: break
        if len(raw)>65536: raise web.HTTPRequestEntityTooLarge(max_size=65536,actual_size=len(raw))
        data = json.loads(raw)
        if not isinstance(data,dict): raise ValueError('Expected an object.')
        return data

    async def provision(self, request):
        # Explicit native admin API, never SQL insertion or changes to accounts,
        # clients, settings or protocol tables. Credentials stay on this server.
        if self.state['service']: return
        async with self.lock:
            if self.state['service']: return
            credentials = {'username':'alireza-node-'+secrets.token_hex(6),'password':secrets.token_urlsafe(40)}
            base,origin,tls = self.g.vpn_settings()
            data = dict(credentials,nickname='alirezapanel node connector',enable='true',isSuperAdmin='true')
            async with self.g.vpn.post(origin+base+'panel/admins/add',data=data,ssl=tls,
                headers={'Cookie':request.headers.get('Cookie',''),'Host':request.host},allow_redirects=False) as response:
                result = json.loads(await bounded(response))
                if response.status!=200 or result.get('success') is not True:
                    raise web.HTTPBadGateway(text='Unable to create the node connector account.')
            self.state['service']=credentials
            self.state['token']=secrets.token_urlsafe(48)
            self.save()

    async def session(self, host):
        async with self.login_lock:
            if self.cookie and time.monotonic()-self.cookie_at<60:
                return self.cookie
            if not self.state['service']:
                raise web.HTTPServiceUnavailable(text='Open Nodes and enable this node first.')
            base,origin,tls = self.g.vpn_settings()
            async with self.g.vpn.post(origin+base+'login',data=self.state['service'],ssl=tls,
                headers={'Host':host},allow_redirects=False) as response:
                data = json.loads(await bounded(response))
                cookie = response.cookies.get('vpn-ui')
                if response.status!=200 or data.get('success') is not True or not cookie:
                    self.cookie=''
                    raise web.HTTPServiceUnavailable(text='Node connector account is unavailable; check Admins on this node.')
                self.cookie='vpn-ui='+cookie.coded_value
                self.cookie_at=time.monotonic()
                return self.cookie

    def auth(self, request):
        token = self.state.get('token') or ''
        supplied = request.headers.get('Authorization','')
        if request.scheme!='https' or not token or not hmac.compare_digest(supplied,'Bearer '+token):
            raise web.HTTPUnauthorized(text='Node authentication failed.')

    async def local_data(self, host):
        base,origin,tls=self.g.vpn_settings()
        async with self.g.vpn.get(origin+base+'panel/api/inbounds/list',ssl=tls,
            headers={'Cookie':await self.session(host),'Host':host},allow_redirects=False) as response:
            data=json.loads(await bounded(response))
            if response.status!=200 or data.get('success') is not True:
                raise web.HTTPBadGateway(text='Unable to list node inbounds.')
        clients={}
        for inbound in data.get('obj') or []:
            settings=inbound.get('settings') or '{}'
            settings=json.loads(settings) if isinstance(settings,str) else settings
            for client in settings.get('clients') or []:
                sid=client.get('subId') or client.get('subID')
                if sid and re.fullmatch(r'[A-Za-z0-9_-]{1,200}',sid):
                    clients[sid]={'id':sid,'name':client.get('email') or sid}
        return {'clients':list(clients.values()),'inbounds':len(data.get('obj') or [])}

    async def info(self, host):
        base,_,_=self.g.vpn_settings()
        return {'version':1,'id':self.state['id'],'base':base,'name':host}

    async def remote_data(self, node, path):
        async with self.pool:
            async with self.remote.get(node['endpoint']+AGENT+path,
                ssl=aiohttp.Fingerprint(bytes.fromhex(node['fingerprint'])),
                headers={'Authorization':'Bearer '+node['token'],'X-Alirezapanel-Request':'1'},
                allow_redirects=False,timeout=aiohttp.ClientTimeout(total=15)) as response:
                raw=await bounded(response)
                if response.status!=200: raise web.HTTPBadGateway(text='Node unavailable or token revoked.')
                return json.loads(raw)

    async def route(self, request):
        if request.path.startswith(AGENT):
            self.auth(request)
            tail=request.path[len(AGENT):]
            if request.method=='GET' and tail=='info': return no_store(await self.info(request.host))
            if request.method=='GET' and tail=='catalog': return no_store(await self.local_data(request.host))
            if request.method=='GET' and tail.startswith('sub/'):
                return await self.local_sub_response(request,tail[4:])
            if tail.startswith('relay/'):
                tail=tail[6:]
                if not permitted(request.method,tail): raise web.HTTPForbidden(text='This operation is outside node inbound access.')
                base,_,_=self.g.vpn_settings()
                headers=CIMultiDict(request.headers)
                for key in ('Authorization','Cookie','Origin','Referer','Sec-Fetch-Site'):
                    headers.popall(key,None)
                headers['Cookie']=await self.session(request.host)
                headers['X-Alirezapanel-Request']='1'
                clone=request.clone(rel_url=URL(base+quote(tail,safe='/@:-._~')+('?' + request.query_string if request.query_string else ''),encoded=True),headers=headers)
                if tail=='ws':
                    return await self.channel('agent',self.g.dispatch(clone))
                return await self.g.dispatch(clone)
            raise web.HTTPNotFound()
        if request.path.startswith(PUBLIC):
            try:
                await asyncio.wait_for(self.subscription_pool.acquire(),timeout=1)
            except asyncio.TimeoutError:
                raise web.HTTPTooManyRequests(headers={'Retry-After':'5'})
            try:
                return await self.public_sub(request)
            finally:
                self.subscription_pool.release()
        base,_,_=self.g.vpn_settings()
        if not request.path.startswith(base): return None
        tail=request.path[len(base):]
        if tail=='_alireza/nodes.js':
            return web.FileResponse(self.g.root/'nodes.js',headers={'Cache-Control':'no-cache'})
        if tail.startswith('_alireza/remote/'):
            await self.admin(request)
            parts=tail[len('_alireza/remote/'):].split('/',1)
            if len(parts)!=2 or parts[0] not in self.state['nodes']: raise web.HTTPNotFound()
            return await self.proxy(request,parts[0],parts[1],base)
        if tail in ('panel/nodes','panel/nodes/'):
            await self.admin(request)
            base,origin,tls=self.g.vpn_settings()
            async with self.g.vpn.get(origin+base+'panel/admins',ssl=tls,headers={
                'Cookie':request.headers.get('Cookie',''),'Host':request.host,'Accept-Encoding':'identity'},allow_redirects=False) as response:
                if response.status!=200: raise web.HTTPBadGateway()
                page=self.g.dns_shell((await bounded(response)).decode(),base)
            page=page.replace('alirezapanel · DNS','alirezapanel · Nodes').replace('id="alireza-dns"','id="alireza-nodes"')
            page=page.replace('src="'+html.escape(base+'dns/',quote=True)+'"','src="'+html.escape(base+'_alireza/nodes-ui',quote=True)+'"')
            return web.Response(text=page,content_type='text/html',headers={'Cache-Control':'no-store'})
        if tail=='_alireza/nodes-ui':
            await self.admin(request)
            page=(self.g.root/'nodes.html').read_text(encoding='utf-8')
            page=page.replace('__BASE_JSON__',json.dumps(base)).replace('__BASE_ATTR__',html.escape(base,quote=True))
            return web.Response(text=page,content_type='text/html',headers={'Cache-Control':'no-store'})
        if tail.startswith('_alireza/nodes/'):
            await self.admin(request)
            try:
                return await self.manage(request,tail[len('_alireza/nodes/'):],base)
            except (ValueError,KeyError,TypeError) as error:
                raise web.HTTPBadRequest(text=str(error))
            except aiohttp.ServerFingerprintMismatch:
                raise web.HTTPBadGateway(text='Node certificate changed or does not match. Copy its current connection certificate again.')
        return None

    async def manage(self, request, operation, base):
        if request.method=='GET' and operation=='list':
            return no_store({'nodes':[{'id':k,'name':v['name'],'endpoint':v['endpoint']} for k,v in self.state['nodes'].items()],
                'profiles':[dict(v,id=k,url=request.scheme+'://'+request.host+PUBLIC+k) for k,v in self.state['profiles'].items()]})
        if request.method!='POST': raise web.HTTPMethodNotAllowed(request.method,['POST'])
        data=await self.body(request)
        if operation=='identity':
            if request.scheme!='https' or not self.g.config.get('tls_enabled',True):
                raise ValueError('Enable HTTPS on this panel before connecting nodes.')
            await self.provision(request)
            pem=Path(self.g.config['tls_cert']).read_text(encoding='utf-8')
            pem=re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',pem,re.S).group(0)
            package=json.dumps({'version':1,'endpoint':request.scheme+'://'+request.host,'certificate':pem},indent=2)
            return no_store({'certificate':package,'token':self.state['token']})
        if operation=='rotate':
            async with self.lock:
                self.state['token']=secrets.token_urlsafe(48); self.save()
                self.disconnect('agent')
            return no_store({'success':True})
        if operation=='disable':
            async with self.lock:
                self.state['token']=None; self.save()
                self.disconnect('agent')
            return no_store({'success':True})
        if operation=='add':
            node=descriptor(data.get('certificate'))
            token=data.get('token','').strip()
            if not re.fullmatch(r'[A-Za-z0-9_-]{40,128}',token): raise ValueError('Invalid API token.')
            node['token']=token
            info=await self.remote_data(node,'info')
            if info.get('version')!=1 or str(uuid.UUID(info['id']))!=info['id']: raise ValueError('Unsupported node.')
            if info['id']==self.state['id']: raise ValueError('This is the local server; choose Local in Inbounds.')
            node.update(name=str(info.get('name') or URL(node['endpoint']).host)[:120],base=info['base'])
            async with self.lock:
                if len(self.state['nodes'])>=64 and info['id'] not in self.state['nodes']: raise ValueError('Maximum 64 nodes.')
                self.state['nodes'][info['id']]=node; self.save()
                self.disconnect(info['id'])
            return no_store({'success':True,'id':info['id']})
        if operation in ('delete','rename','check','catalog'):
            ident=data.get('id')
            if operation=='catalog' and ident=='local':
                await self.provision(request)
                return no_store(await self.local_data(request.host))
            node=self.state['nodes'].get(ident)
            if not node: raise web.HTTPNotFound()
            if operation=='catalog': return no_store(await self.remote_data(node,'catalog'))
            if operation=='check':
                info=await self.remote_data(node,'info')
                if info.get('id')!=ident: raise ValueError('Node identity changed; reconnect it.')
                return no_store({'success':True})
            async with self.lock:
                if operation=='delete':
                    if any(any(s['node']==ident for s in p['sources']) for p in self.state['profiles'].values()):
                        raise ValueError('Remove this node from combined subscriptions before deleting it.')
                    del self.state['nodes'][ident]
                    self.disconnect(ident)
                else:
                    name=str(data.get('name','')).strip()
                    if not name or len(name)>120: raise ValueError('Name must be 1–120 characters.')
                    node['name']=name
                self.save()
            return no_store({'success':True})
        if operation=='profile':
            sources=data.get('sources')
            if not isinstance(sources,list) or not 1<=len(sources)<=32: raise ValueError('Choose 1–32 subscriptions.')
            checked=[]
            for entry in sources:
                n=entry.get('node'); sid=entry.get('sub')
                if n!='local' and n not in self.state['nodes']: raise ValueError('Unknown node.')
                if not isinstance(sid,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,200}',sid): raise ValueError('Invalid subscription.')
                row={'node':n,'sub':sid}
                if row not in checked: checked.append(row)
            name=str(data.get('name') or 'alirezapanel')[:120]
            # Validate each selected subscription before publishing a bearer URL.
            await asyncio.gather(*(self.source_bytes(s,'links',request.host) for s in checked))
            async with self.lock:
                if len(self.state['profiles'])>=1000: raise ValueError('Maximum 1000 combined subscriptions.')
                ident=secrets.token_urlsafe(32)
                self.state['profiles'][ident]={'name':name,'sources':checked}; self.save()
            return no_store({'url':request.scheme+'://'+request.host+PUBLIC+ident})
        if operation=='delete-profile':
            async with self.lock:
                self.state['profiles'].pop(data.get('id'),None); self.save()
            return no_store({'success':True})
        raise web.HTTPNotFound()

    async def proxy(self, request, ident, tail, base):
        if not permitted(request.method,tail): raise web.HTTPForbidden(text='Use the node panel directly for settings outside inbounds.')
        node=self.state['nodes'][ident]
        path=quote(tail,safe='/@:-._~')+('?' + request.query_string if request.query_string else '')
        target=URL(node['endpoint']+AGENT+'relay/'+path,encoded=True)
        headers=headers_clean(request.headers)
        for name in ('Host','Cookie','Origin','Referer','Authorization','X-Forwarded-For','X-Real-IP','Forwarded'):
            headers.popall(name,None)
        headers['Authorization']='Bearer '+node['token']
        headers['X-Alirezapanel-Request']='1'
        headers['Accept-Encoding']='identity'
        tls=aiohttp.Fingerprint(bytes.fromhex(node['fingerprint']))
        if request.headers.get('Upgrade','').lower()=='websocket':
            return await self.channel(ident,self.g.websocket(request,target,headers,self.remote,tls))
        async with self.remote.request(request.method,target,headers=headers,ssl=tls,
            data=request.content if request.can_read_body else None,allow_redirects=False) as response:
            out=headers_clean(response.headers)
            for key in ('Set-Cookie','WWW-Authenticate','Content-Security-Policy','ETag','Last-Modified'):
                out.popall(key,None)
            out['Cache-Control']='no-store'
            out['Referrer-Policy']='no-referrer'
            if 300<=response.status<400:
                raise web.HTTPBadGateway(text='Node session or path changed. Recheck the node connection.')
            typ=response.headers.get('Content-Type','').lower()
            mount=base+'_alireza/remote/'+ident+'/'
            if response.status==200 and request.method!='HEAD' and ('text/html' in typ or tail.split('?',1)[0] in (
                'assets/js/model/inbound.js','assets/js/model/dbinbound.js','assets/js/util/index.js','assets/js/util/export.js')):
                body=(await bounded(response)).decode()
                if 'text/html' in typ:
                    body=self.mount_html(body,node,mount,base,ident)
                else:
                    # Display addresses must refer to the selected node. Only
                    # hostname reads in link/export UI are adapted, never JSON,
                    # protocol identifiers, configuration or native executables.
                    body=re.sub(r'(?<![\w.])(?:window\.)?location\.hostname',json.dumps(URL(node['endpoint']).host),body)
                return web.Response(body=body.encode(),status=response.status,headers=out)
            result=web.StreamResponse(status=response.status,headers=out)
            await result.prepare(request)
            async for chunk in response.content.iter_chunked(65536): await result.write(chunk)
            await result.write_eof()
            return result

    def mount_html(self, body, node, mount, master, ident):
        match=re.search(r"const basePath = (['\"])(.*?)\1;",body)
        if not match: raise web.HTTPBadGateway(text='Unsupported node interface layout.')
        old=match[2]
        # Rewrite only UI resource and navigation paths. Embedded configuration
        # values, share links, host addresses and API JSON remain unchanged.
        body=re.sub(r"(['\"])"+re.escape(old)+r"(?=(?:assets/|panel/|logout/|_alireza/))",lambda m:m[1]+mount,body)
        body=body.replace(match[0],'const basePath = '+json.dumps(mount)+';',1)
        body=re.sub(r'window\.ALIREZA=\{.*?\};',lambda m:'window.ALIREZA='+json.dumps({'base':master,'dns':False,'node':ident,'mount':mount})+';',body,count=1)
        # Brand/theme are provided by the main panel and are not agent API routes.
        body=body.replace(mount+'_alireza/',master+'_alireza/')
        body=body.replace('window.location.hostname',json.dumps(URL(node['endpoint']).host))
        body=re.sub(r'(?<![\w.])location\.hostname',json.dumps(URL(node['endpoint']).host),body)
        return body

    def sub_target(self, kind, sid, host, suffix=''):
        if kind not in ('links','json','clash','page') or not re.fullmatch(r'[A-Za-z0-9_-]{1,200}',sid): raise web.HTTPNotFound()
        if suffix and not re.fullmatch(r'configs/[A-Za-z0-9_.-]+',suffix): raise web.HTTPNotFound()
        uri=Path(self.g.config['vpn_db']).resolve().as_uri()+'?mode=ro'
        with contextlib.closing(sqlite3.connect(uri,uri=True,timeout=2)) as db:
            s=dict(db.execute('SELECT key,value FROM settings'))
        if s.get('subEnable','false')!='true': raise web.HTTPServiceUnavailable(text='Enable subscription on the selected node first.')
        listen=s.get('subListen') or '127.0.0.1'
        if listen in ('0.0.0.0','::'): listen='127.0.0.1'
        if ':' in listen and not listen.startswith('['): listen='['+listen+']'
        path=s.get({'links':'subPath','page':'subPath','json':'subJsonPath','clash':'subClashPath'}[kind],
                   {'links':'/sub/','page':'/sub/','json':'/json/','clash':'/clash/'}[kind])
        path='/'+path.strip('/')+'/'
        cert=s.get('subCertFile','')
        tls=True
        if cert:
            tls=ssl.create_default_context(cafile=cert); tls.check_hostname=False
            tls.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
        url=('https' if cert else 'http')+'://'+listen+':'+str(int(s.get('subPort','2097')))+path+sid
        if suffix: url+='/'+suffix
        return url,tls,path

    async def sub_bytes(self, kind, sid, host, suffix=''):
        target,tls,path=self.sub_target(kind,sid,host,suffix)
        async with self.g.vpn.get(target,ssl=tls,headers={'Host':host,'Accept':'text/html' if kind=='page' else '*/*',
            'User-Agent':'alirezapanel-nodes/1','Accept-Encoding':'identity'},allow_redirects=False,
            timeout=aiohttp.ClientTimeout(total=20)) as response:
            raw=await bounded(response,1024*1024)
            if response.status!=200: raise web.HTTPBadGateway(text='Subscription is unavailable on a selected node.')
            return raw,headers_clean(response.headers),path

    async def local_sub_response(self, request, tail):
        parts=tail.split('/',2)
        if len(parts)<2: raise web.HTTPNotFound()
        kind,sid=parts[:2]; suffix=parts[2] if len(parts)>2 else ''
        raw,headers,_=await self.sub_bytes(kind,sid,request.host,suffix)
        headers.popall('Set-Cookie',None); headers['Cache-Control']='no-store'
        return web.Response(body=raw,headers=headers)

    async def source_bytes(self, source, kind, host, suffix=''):
        if source['node']=='local': return await self.sub_bytes(kind,source['sub'],host,suffix)
        node=self.state['nodes'].get(source['node'])
        if not node: raise web.HTTPServiceUnavailable(text='Selected node was removed.')
        target=node['endpoint']+AGENT+'sub/'+kind+'/'+quote(source['sub'],safe='')
        if suffix: target+='/'+suffix
        async with self.pool:
            async with self.remote.get(target,ssl=aiohttp.Fingerprint(bytes.fromhex(node['fingerprint'])),
                headers={'Authorization':'Bearer '+node['token'],'X-Alirezapanel-Request':'1'},
                allow_redirects=False,timeout=aiohttp.ClientTimeout(total=25)) as response:
                raw=await bounded(response,1024*1024)
                if response.status!=200: raise web.HTTPBadGateway(text='A selected subscription node is unavailable.')
                return raw,headers_clean(response.headers),''

    async def public_sub(self, request):
        if request.method!='GET': raise web.HTTPMethodNotAllowed(request.method,['GET'])
        parts=request.path[len(PUBLIC):].strip('/').split('/')
        profile=self.state['profiles'].get(parts[0])
        if not profile: raise web.HTTPNotFound()
        kind=parts[1] if len(parts)>1 else 'links'
        if len(parts)==1 and 'text/html' in request.headers.get('Accept',''):
            root=PUBLIC+parts[0]
            links=''.join('<li><a href="'+html.escape(root+'/'+k)+'">'+label+'</a></li>' for k,label in (
                ('links','Base64 / V2Ray'),('json','Xray JSON'),('clash','Clash / Mihomo')))
            links+=''.join('<li>'+html.escape(self.source_name(s))+' — '+''.join('<a href="'+root+'/source/'+str(i)+'/'+k+'">'+k+'</a> ' for k in ('links','json','clash'))+'</li>' for i,s in enumerate(profile['sources']))
            return web.Response(text='<!doctype html><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>alirezapanel</title><body style="background:#111;color:#eee;font:18px system-ui;padding:30px"><h1>'+html.escape(profile['name'])+'</h1><ul>'+links+'</ul><p>Native protocol config files remain available from each node’s Inbounds page.</p></body>',content_type='text/html',headers={'Cache-Control':'no-store'})
        if kind=='source':
            if len(parts)!=4 or not parts[2].isdigit() or int(parts[2])>=len(profile['sources']) or parts[3] not in ('links','json','clash'): raise web.HTTPNotFound()
            raw,headers,_=await self.source_bytes(profile['sources'][int(parts[2])],parts[3],request.host)
            headers.popall('Set-Cookie',None); headers['Cache-Control']='no-store'
            return web.Response(body=raw,headers=headers)
        if kind not in ('links','json','clash') or len(parts)>2: raise web.HTTPNotFound()
        # Fail closed instead of returning a truncated profile that makes clients
        # silently delete the servers which happen to be offline during refresh.
        results=await asyncio.gather(*(self.source_bytes(s,kind,request.host) for s in profile['sources']))
        raw,typ=merge_subscriptions(kind,[r[0] for r in results],[self.source_name(s) for s in profile['sources']])
        return web.Response(body=raw,content_type=typ,headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer',
            'profile-title':'base64:'+base64.b64encode(profile['name'].encode()).decode(),
            'profile-web-page-url':request.scheme+'://'+request.host+PUBLIC+parts[0]})

    def source_name(self, source):
        return 'Local' if source['node']=='local' else self.state['nodes'].get(source['node'],{}).get('name','Node')

def merge_subscriptions(kind, bodies, names):
    if kind=='links':
        links=[]
        for raw in bodies:
            text=raw.decode().strip()
            if text and '://' not in text:
                text=base64.b64decode(text,validate=True).decode()
            lines=[s.strip() for s in text.splitlines() if s.strip()]
            if any('://' not in s for s in lines): raise ValueError('A source did not return a native URI subscription.')
            links.extend(lines)
        return base64.b64encode(('\n'.join(dict.fromkeys(links))+'\n').encode()),'text/plain'
    if kind=='json':
        configs=[]
        for name,raw in zip(names,bodies):
            if not raw.strip(): continue
            data=json.loads(raw)
            # Native VPN-UI returns one object for a single configuration, an
            # array for several, and an empty body for unsupported protocols.
            if isinstance(data,dict): data=[data]
            if not isinstance(data,list): raise ValueError('A node did not return an Xray JSON configuration.')
            for config in data:
                if not isinstance(config,dict): raise ValueError('Invalid Xray configuration.')
                configs.append(config)
        return json.dumps(configs,ensure_ascii=False).encode(),'application/json'
    proxies=[]
    for index,(name,raw) in enumerate(zip(names,bodies)):
        data=yaml.safe_load(raw)
        if not isinstance(data,dict) or not isinstance(data.get('proxies'),list): raise ValueError('A node did not return a Clash profile.')
        mapping={p['name']:str(index+1)+' · '+name+' · '+p['name'] for p in data['proxies']}
        for p in data['proxies']:
            p['name']=mapping[p['name']]
            if 'dialer-proxy' in p:
                if p['dialer-proxy'] not in mapping: raise ValueError('Source has a dialer-proxy group; use its native Clash link.')
                p['dialer-proxy']=mapping[p['dialer-proxy']]
            proxies.append(p)
    if not proxies: raise ValueError('No Clash-compatible proxies in the selected subscriptions.')
    result={'mixed-port':7890,'mode':'rule','proxies':proxies,
        'proxy-groups':[{'name':'alirezapanel','type':'select','proxies':[p['name'] for p in proxies]}],
        'rules':['MATCH,alirezapanel']}
    return yaml.safe_dump(result,allow_unicode=True,sort_keys=False).encode(),'text/yaml'
NODE_EMBEDDED_PY_EOF

cat > "$STAGE/nodes.js" <<'NODE_EMBEDDED_JS_EOF'
/* Node selector: additive UI only; all native forms and handlers remain intact. */
(() => {
  'use strict';
  const config=window.ALIREZA;
  if (!config || config.dns || typeof PERMS==='undefined' || !PERMS.superAdmin) return;
  const base=config.base;
  const nav=document.querySelector('.bo-rail');
  const component=nav && nav.__vue__;
  if (component && Array.isArray(component.tabs)) {
    if(config.node) {
      const home=nav.querySelector('.bo-rail-brand a');
      if(home) home.href=base+'panel/';
      component.tabs.forEach(t=>{
        if(t.key.startsWith(config.mount) && !/panel\/(inbounds|core)/.test(t.key))
          t.key=base+t.key.slice(config.mount.length);
      });
    }
    if(!component.tabs.some(t=>t.key===base+'panel/nodes'))
      component.tabs.splice(component.tabs.length-1,0,{key:base+'panel/nodes',icon:'cluster',title:'نودها / Nodes'});
    if(location.pathname.replace(/\/$/,'')===base+'panel/nodes') component.requestUri=base+'panel/nodes';
  }
  if(!/\/panel\/(inbounds|core)\/?$/.test(location.pathname)) return;
  const main=document.querySelector('.bo-content');
  if(!main || document.getElementById('alireza-node-picker')) return;
  const bar=document.createElement('div');
  bar.id='alireza-node-picker';
  bar.style.cssText='display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:14px 18px;margin-bottom:18px;border:1px solid #493323;background:#211b17;color:#ffe4cf;border-radius:12px';
  const label=document.createElement('label');label.textContent='سرور / Server';label.htmlFor='alireza-node-select';
  const select=document.createElement('select');select.id='alireza-node-select';
  select.style.cssText='background:#18181c;color:#fff;border:1px solid #795036;border-radius:8px;padding:8px;min-width:190px';
  const link=document.createElement('a');link.href=base+'panel/nodes';link.textContent='مدیریت نودها';link.style.color='#ff963f';
  const status=document.createElement('span');status.style.fontSize='13px';status.setAttribute('role','status');
  select.add(new Option('همین سرور / Local','local'));
  select.disabled=true;
  bar.append(label,select,link,status);main.prepend(bar);
  fetch(base+'_alireza/nodes/list',{credentials:'same-origin',cache:'no-store'})
    .then(async r=>{if(!r.ok) throw Error();return r.json();})
    .then(data=>{
      for(const node of data.nodes) select.add(new Option(node.name,node.id));
      select.value=config.node || 'local';select.disabled=false;
      status.textContent=config.node?'تغییرات این صفحه فقط روی نود انتخاب‌شده ذخیره می‌شوند.':'تغییرات این صفحه روی همین سرور ذخیره می‌شوند.';
    }).catch(()=>{status.textContent='فهرست نودها در دسترس نیست؛ مدیریت محلی همچنان فعال است.';});
  select.addEventListener('change',()=>{
    if(!window.confirm('با تغییر سرور، تغییرات ذخیره‌نشدهٔ فرم کنار گذاشته می‌شوند. ادامه می‌دهی؟')) {
      select.value=config.node || 'local';return;
    }
    window.location.assign(select.value==='local'?base+'panel/inbounds':base+'_alireza/remote/'+encodeURIComponent(select.value)+'/panel/inbounds');
  });
})();
NODE_EMBEDDED_JS_EOF

cat > "$STAGE/nodes.html" <<'NODE_EMBEDDED_HTML_EOF'
<!doctype html>
<html lang="fa" dir="rtl" data-alireza-theme="ember"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>alirezapanel · Nodes</title>
<link rel="stylesheet" href="__BASE_ATTR___alireza/theme.css"><style>
*{box-sizing:border-box}body{margin:0;background:#0e0e11;color:#f5f2ef;font:14px system-ui,sans-serif;line-height:1.9;padding:26px}main{max-width:1160px;margin:auto}h1,h2,p{margin-top:0}h1{font-size:27px;margin-bottom:3px}h2{font-size:18px}.muted{color:#b7b2ad}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}.card{background:#18181c;border:1px solid #303037;border-radius:16px;padding:22px;margin:18px 0}.card .card{margin:10px 0;padding:15px}button,a.btn{background:#ff963f;color:#211208;border:1px solid #ff963f;border-radius:9px;padding:9px 15px;font:inherit;font-weight:600;cursor:pointer;text-decoration:none;display:inline-block}button.secondary{background:#242126;color:#f5f2ef;border-color:#494049}button.danger{background:#372023;color:#ffb0b0;border-color:#603034}button:disabled{opacity:.5;cursor:wait}input,textarea,select{display:block;width:100%;background:#101013;color:#f5f2ef;border:1px solid #494149;border-radius:9px;padding:11px;font:inherit;margin:6px 0 14px}textarea{min-height:110px;resize:vertical;direction:ltr;font:12px monospace}input.code{direction:ltr;font:13px monospace}label{display:block}.row{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.row>*{margin-block:0}#notice{position:sticky;top:0;z-index:2;padding:12px 16px;background:#34271d;border:1px solid #795036;border-radius:9px;white-space:pre-wrap}#notice:empty{display:none}.nodehead{display:flex;justify-content:space-between;gap:12px;align-items:center}.endpoint{direction:ltr;text-align:right;overflow-wrap:anywhere}.source{display:grid;grid-template-columns:1fr 1.5fr auto;gap:10px;align-items:center}.source select{margin:0}.badge{color:#ffb170;font-size:12px}summary{cursor:pointer;color:#ffb170}button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible{outline:2px solid #ffb170;outline-offset:3px}@media(max-width:700px){body{padding:14px}.grid{grid-template-columns:1fr}.source{grid-template-columns:1fr}.nodehead{align-items:start;flex-direction:column}}
a.btn{color:#211208!important}a.btn:hover{color:#211208!important;background:#ffb170}
</style></head><body><main>
<div id="notice" role="status" aria-live="polite"></div>
<h1>نودها و لوکیشن‌ها</h1><p class="muted">سرورهایت را از همین پنل مدیریت کن. هر سرور، اینباندها و تنظیمات مستقل خودش را دارد.</p>
<div class="grid"><section class="card"><h2>افزودن یا اتصال مجدد نود</h2><p class="muted">در پنل سرور مقصد، «مشخصات اتصال این سرور» را باز کن و این دو مقدار را اینجا قرار بده.</p>
<form id="add-form"><label for="certificate">گواهی اتصال</label><textarea id="certificate" required spellcheck="false" placeholder='{"version":1,"endpoint":"https://…","certificate":"…"}'></textarea><label for="token">API Token</label><input class="code" id="token" type="password" required autocomplete="off"><button type="submit">بررسی و افزودن نود</button></form><p class="muted">گواهی اتصال شامل آدرس و گواهی عمومی سرور است. با تعویض گواهی HTTPS، همین دو مقدار را دوباره وارد کن.</p></section>
<section class="card"><h2>مشخصات اتصال این سرور</h2><p class="muted">این مشخصات را در پنل اصلی وارد کن تا این سرور به‌عنوان نود اضافه شود. اتصال نود به HTTPS نیاز دارد.</p><button id="identity">نمایش و کپی مشخصات</button>
<div id="identity-fields" hidden><label for="my-cert">گواهی اتصال این سرور</label><textarea id="my-cert" readonly spellcheck="false"></textarea><button class="secondary" id="copy-cert">کپی گواهی</button><label for="my-token">API Token این سرور</label><input class="code" id="my-token" readonly type="password"><div class="row"><button class="secondary" id="copy-token">کپی توکن</button><button class="secondary" id="show-token">نمایش / پنهان</button></div></div>
<details style="margin-top:18px"><summary>مدیریت دسترسی این نود</summary><p class="muted">با نمایش مشخصات، یک حساب اتصال اختصاصی در بخش ادمین‌ها ساخته می‌شود. توکن اجازهٔ مدیریت اینباندها را می‌دهد؛ آن را خصوصی نگه دار.</p><div class="row"><button class="secondary" id="rotate">ساخت توکن جدید</button><button class="danger" id="disable">قطع دسترسی نود</button></div></details></section></div>
<section class="card"><div class="nodehead"><h2>سرورهای متصل</h2><button class="secondary" id="refresh">بازخوانی فهرست</button></div><div id="nodes-list"></div></section>
<section class="card"><h2>اشتراک چند لوکیشن</h2><p class="muted">اشتراک‌های کاربر را از سرورهای دلخواه انتخاب کن تا یک لینک شامل کانفیگ همهٔ آن‌ها ساخته شود. این کار کاربر جدید نمی‌سازد و سهمیه یا تاریخ انقضای سرورها را تغییر نمی‌دهد.</p>
<form id="profile-form"><label for="profile-name">نام اشتراک</label><input id="profile-name" placeholder="مثلاً اشتراک چند لوکیشن علی" maxlength="120"><div id="sources"></div><div class="row" style="margin:16px 0"><button type="button" class="secondary" id="add-source">افزودن سرور به اشتراک</button><button type="submit">ساخت لینک ترکیبی</button></div></form>
<details><summary>فرمت‌ها و رفتار اشتراک</summary><p class="muted">خروجی Base64، آرایهٔ JSON برای Xray و Clash/Mihomo در دسترس است، به شرط پشتیبانی و فعال‌بودن همان فرمت روی سرورهای انتخاب‌شده. خروجی Clash ترکیبی یک گروه انتخاب سرور دارد؛ قوانین سفارشی هر نود در لینک اصلی آن حفظ می‌شود. فایل‌های اختصاصی OpenVPN و WireGuard از صفحهٔ اینباند همان نود قابل دریافت‌اند. اگر یک منبع قطع باشد، لینک ترکیبی خطا می‌دهد تا لیست ناقص جایگزین کانفیگ‌های کاربر نشود.</p></details>
<div id="profiles-list"></div></section>
</main><script>
'use strict';
const base=__BASE_JSON__;let nodes=[];
const $=id=>document.getElementById(id);
function notice(s){$('notice').textContent=s;}
async function api(op,data){const r=await fetch(base+'_alireza/nodes/'+op,{method:data===undefined?'GET':'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data)});if(!r.ok)throw Error((await r.text()).slice(0,400));return r.json();}
async function busy(button,fn){button.disabled=true;try{await fn();}catch(e){notice(e.message||'عملیات انجام نشد.');}finally{button.disabled=false;}}
async function copy(value){try{await navigator.clipboard.writeText(value);notice('کپی شد.');}catch(_){notice('کپی خودکار در دسترس نیست؛ مقدار را انتخاب و دستی کپی کن.');}}
function button(label,action,danger=false){const b=document.createElement('button');b.type='button';b.className=danger?'danger':'secondary';b.textContent=label;b.onclick=()=>busy(b,action);return b;}
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
async function load(){const data=await api('list');nodes=data.nodes;const list=$('nodes-list');list.replaceChildren();if(!nodes.length)list.append(el('p','هنوز نودی اضافه نشده است.','muted'));for(const n of nodes){const card=el('article',undefined,'card');const head=el('div',undefined,'nodehead');const title=el('div');title.append(el('strong',n.name),el('div',n.endpoint,'endpoint muted'));const actions=el('div',undefined,'row');const link=el('a','اینباندهای این سرور','btn');link.href=base+'_alireza/remote/'+n.id+'/panel/inbounds';link.target='_top';actions.append(link,button('بررسی اتصال',async()=>{await api('check',{id:n.id});notice('اتصال به '+n.name+' برقرار است.');}),button('تغییر نام',async()=>{const name=prompt('نام سرور',n.name);if(name){await api('rename',{id:n.id,name});await load();}}),button('حذف اتصال',async()=>{if(confirm('اتصال '+n.name+' از این پنل حذف شود؟ اینباندهای نود حذف نمی‌شوند.')){await api('delete',{id:n.id});await load();}},true));head.append(title,actions);card.append(head);list.append(card);}const profiles=$('profiles-list');profiles.replaceChildren();for(const p of data.profiles){const card=el('article',undefined,'card');card.append(el('strong',p.name));const input=el('input');input.className='code';input.readOnly=true;input.value=p.url;card.append(input);const row=el('div',undefined,'row');row.append(button('کپی لینک',()=>copy(p.url)),button('کپی JSON',()=>copy(p.url+'/json')),button('کپی Clash',()=>copy(p.url+'/clash')),button('حذف اشتراک ترکیبی',async()=>{if(confirm('این لینک ترکیبی غیرفعال شود؟ اشتراک‌های اصلی حفظ می‌شوند.')){await api('delete-profile',{id:p.id});await load();}},true));card.append(row);profiles.append(card);}}
$('add-form').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{await api('add',{certificate:$('certificate').value,token:$('token').value});$('token').value='';$('certificate').value='';await load();notice('نود متصل شد. از بخش اینباندها سرور را انتخاب کن.');});};
$('identity').onclick=()=>busy($('identity'),async()=>{const d=await api('identity',{});$('my-cert').value=d.certificate;$('my-token').value=d.token||'';$('identity-fields').hidden=false;notice(d.token?'مشخصات آمادهٔ کپی است.':'دسترسی نود قطع است؛ برای فعال‌سازی «ساخت توکن جدید» را بزن.');});
$('copy-cert').onclick=()=>copy($('my-cert').value);$('copy-token').onclick=()=>copy($('my-token').value);
$('show-token').onclick=()=>{$('my-token').type=$('my-token').type==='password'?'text':'password';};
$('rotate').onclick=()=>busy($('rotate'),async()=>{if(confirm('توکن قبلی فوراً غیرفعال می‌شود و باید نود را در پنل‌های اصلی دوباره متصل کنی. ادامه؟')){await api('rotate',{});$('identity').click();notice('توکن جدید ساخته شد.');}});
$('disable').onclick=()=>busy($('disable'),async()=>{if(confirm('دسترسی تمام پنل‌های اصلی به این نود قطع شود؟')){await api('disable',{});$('my-token').value='';notice('دسترسی نود قطع شد؛ اینباندهای محلی همچنان فعال‌اند.');}});
$('refresh').onclick=()=>busy($('refresh'),load);
function sourceRow(){const row=el('div',undefined,'source card');const server=el('select');server.setAttribute('aria-label','سرور منبع');server.add(new Option('انتخاب سرور',''));server.add(new Option('همین سرور','local'));for(const n of nodes)server.add(new Option(n.name,n.id));const client=el('select');client.setAttribute('aria-label','اشتراک کاربر');client.add(new Option('ابتدا سرور را انتخاب کن',''));client.disabled=true;row.append(server,client,button('برداشتن',async()=>row.remove()));server.onchange=async()=>{const selected=server.value;client.replaceChildren(new Option('در حال دریافت…',''));client.disabled=true;if(!selected)return;try{const data=await api('catalog',{id:selected});if(server.value!==selected)return;client.replaceChildren(new Option('انتخاب اشتراک کاربر',''));for(const c of data.clients)client.add(new Option(c.name,c.id));client.disabled=false;if(!data.clients.length)notice('این سرور اشتراک کاربری ندارد؛ ابتدا در اینباندهای آن کاربر بساز.');}catch(e){if(server.value===selected)client.replaceChildren(new Option('دریافت ناموفق؛ سرور را دوباره انتخاب کن',''));notice(e.message);}};$('sources').append(row);}
$('add-source').onclick=sourceRow;
$('profile-form').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{const sources=Array.from($('sources').children).map(row=>({node:row.children[0].value,sub:row.children[1].value}));if(!sources.length||sources.some(s=>!s.node||!s.sub))throw Error('سرور و اشتراک همهٔ ردیف‌ها را انتخاب کن.');const d=await api('profile',{name:$('profile-name').value,sources});await load();await copy(d.url);});};
load().then(sourceRow).catch(e=>notice(e.message));
</script></body></html>
NODE_EMBEDDED_HTML_EOF

cat > "$STAGE/nodes_install.py" <<'NODE_EMBEDDED_INSTALL_EOF'
"""Installer-side additive gateway patch; no changes to native services."""
import os
from pathlib import Path
import shutil
import tempfile
import time

def patch_gateway(text):
    if 'from nodes import Nodes' in text:
        return text
    edits = [
        ('from aiohttp import web\n','from aiohttp import web\nfrom nodes import Nodes\n'),
        ('        self.agh_lock = asyncio.Lock()\n','        self.agh_lock = asyncio.Lock()\n        self.nodes = Nodes(self)\n'),
        ('    async def start(self, app):\n','    async def start(self, app):\n        await self.nodes.start()\n'),
        ('    async def stop(self, app):\n','    async def stop(self, app):\n        await self.nodes.stop()\n'),
        ('    async def dispatch(self, request):\n','    async def dispatch(self, request):\n        node_response = await self.nodes.route(request)\n        if node_response is not None:\n            return node_response\n'),
        ('        return re.sub(r"</head\\s*>", tag + "</head>", text, count=1, flags=re.I)',
         '        if not agh:\n            tag += \'<script defer src="\' + html.escape(base, quote=True) + \'_alireza/nodes.js?v=1.0.0"></script>\'\n        return re.sub(r"</head\\s*>", tag + "</head>", text, count=1, flags=re.I)'),
    ]
    for old,new in edits:
        if text.count(old)!=1:
            raise ValueError('Unsupported gateway layout; no files have been changed.')
        text=text.replace(old,new,1)
    compile(text,'gateway.py','exec')
    return text

def install(root, files):
    root=Path(root)
    gateway=root/'gateway/gateway.py'
    previous=gateway.read_text(encoding='utf-8')
    updated=patch_gateway(previous)
    compile(files['nodes.py'],'nodes.py','exec')
    backup=Path('/var/backups/alirezapanel')/('nodes-'+str(time.time_ns()))
    backup.mkdir(parents=True,mode=0o700)
    paths=[root/'gateway'/name for name in ('gateway.py','nodes.py','nodes.js','nodes.html')]
    for path in paths:
        if path.exists(): shutil.copy2(path,backup/path.name)
    meta=gateway.stat()
    state=Path('/var/lib/alirezapanel-nodes/state.json')
    if state.exists(): shutil.copy2(state,backup/'nodes-state.json')
    cli=Path('/usr/local/bin/alirezapanel')
    cli_update=None
    if cli.is_file():
        cli_text=cli.read_text(encoding='utf-8')
        anchor='cp -a /etc/alirezapanel "$dest/config"'
        if '/var/lib/alirezapanel-nodes "$dest/nodes"' not in cli_text and cli_text.count(anchor)==1:
            cli_update=cli_text.replace(anchor,anchor+'\n        [[ ! -d /var/lib/alirezapanel-nodes ]] || cp -a /var/lib/alirezapanel-nodes "$dest/nodes"',1)
            shutil.copy2(cli,backup/'alirezapanel-cli')
    # Write all optional modules first, gateway activation last. The current
    # process continues serving until the caller restarts only the gateway.
    for name,content in [('nodes.py',files['nodes.py']),('nodes.js',files['nodes.js']),('nodes.html',files['nodes.html']),('gateway.py',updated)]:
        target=root/'gateway'/name
        fd,tmp=tempfile.mkstemp(prefix='.nodes-',dir=target.parent)
        try:
            with os.fdopen(fd,'w',encoding='utf-8') as stream:
                stream.write(content); stream.flush(); os.fsync(stream.fileno())
            os.chown(tmp,meta.st_uid,meta.st_gid); os.chmod(tmp,0o640)
            os.replace(tmp,target)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
    if cli_update is not None:
        meta=cli.stat()
        fd,tmp=tempfile.mkstemp(prefix='.alireza-nodes-',dir=cli.parent)
        try:
            with os.fdopen(fd,'w',encoding='utf-8') as stream:
                stream.write(cli_update); stream.flush(); os.fsync(stream.fileno())
            os.chown(tmp,meta.st_uid,meta.st_gid); os.chmod(tmp,meta.st_mode & 0o7777)
            os.replace(tmp,cli)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
    print('Previous gateway files backed up to:',backup)
NODE_EMBEDDED_INSTALL_EOF

say 'Checking the embedded integration code before changing services.'
python3 -m py_compile "$STAGE/gateway.py" "$STAGE/manage.py" "$STAGE/nodes.py"
python3 -c 'import aiohttp, yaml, bcrypt; print("Runtime dependencies OK")'
if [[ -f "$ETC/owner" ]]; then
    say 'Backing up the existing installation before repair (services pause briefly).'
    systemctl stop alirezapanel alirezapanel-vpn alirezapanel-dns || true
    REPAIR_STOPPED=1
    backup="/var/backups/alirezapanel/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    install -d -m 700 "$backup"
    cp -a "$ETC" "$backup/config"
    cp -a "$ROOT/vpn" "$backup/vpn"
    cp -a "$ROOT/adguard" "$backup/adguard"
    [[ ! -d /var/lib/alirezapanel-nodes ]] || cp -a /var/lib/alirezapanel-nodes "$backup/nodes"
    [[ ! -d "$ROOT/gateway" ]] || cp -a "$ROOT/gateway" "$backup/gateway"
    say "Backup saved at $backup"
fi
CHANGED=1
getent group alirezapanel >/dev/null || groupadd --system alirezapanel
id alirezapanel >/dev/null 2>&1 || useradd --system --gid alirezapanel --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin alirezapanel
install -d -o root -g alirezapanel -m 750 "$ROOT" "$ROOT/vpn" "$ROOT/gateway" "$ETC" "$ETC/tls"
install -d -o root -g root -m 700 "$ROOT/adguard"
printf 'alirezapanel installer v1\n' > "$ETC/owner"
install -m 755 "$STAGE/vpn-ui-amd64" "$ROOT/vpn/vpn-ui-amd64"
install -m 755 "$STAGE/AdGuardHome/AdGuardHome" "$ROOT/adguard/AdGuardHome"
for filename in gateway.py brand.js theme.css manage.py logo.svg nodes.py nodes.js nodes.html; do
    install -o root -g alirezapanel -m 640 "$STAGE/$filename" "$ROOT/gateway/$filename"
done
install -m 644 "$STAGE/README.txt" "$ROOT/README.txt"
install -m 644 "$STAGE/LICENSE-vpn-ui.txt" "$ROOT/LICENSE-vpn-ui.txt"
install -m 644 "$STAGE/AdGuardHome/LICENSE.txt" "$ROOT/LICENSE-AdGuardHome.txt"
cat > "$ROOT/SOURCES.txt" <<'SOURCES'
Upstream source corresponding to the pinned, unmodified executables:
vpn-ui v1.9.4 (8044e0ad45c60149439546ea0fd99371a4d3c03d):
https://github.com/Sir-MmD/vpn-ui/tree/v1.9.4
https://github.com/Sir-MmD/vpn-ui/archive/refs/tags/v1.9.4.tar.gz
AdGuard Home v0.107.79:
https://github.com/AdguardTeam/AdGuardHome/tree/v0.107.79
https://github.com/AdguardTeam/AdGuardHome/archive/refs/tags/v0.107.79.tar.gz
Build instructions and third-party notices are in each corresponding repository.
Integration source is included in install.sh and /opt/alirezapanel/gateway.
alirezapanel is an independent integration, not an official upstream product.
SOURCES

say 'Preparing shared access and DNS defaults.'
python3 "$ROOT/gateway/manage.py" init
# Bind probes happen with owned services stopped and BEFORE anything starts.
# DNS uses port 53 directly on exact addresses; no firewall/NAT redirect is added.
python3 - "$ETC/gateway.json" <<'PORTCHECK'
import json, socket, sys
cfg=json.load(open(sys.argv[1]))
tests=[('0.0.0.0',cfg['port'],socket.SOCK_STREAM),
       ('127.0.0.1',18080,socket.SOCK_STREAM),
       ('127.0.0.1',18081,socket.SOCK_STREAM)]
for dns_host in cfg.get('dns_bind_hosts', []):
    tests.append((dns_host,53,socket.SOCK_STREAM))
    tests.append((dns_host,53,socket.SOCK_DGRAM))
for host,port,kind in tests:
    with socket.socket(socket.AF_INET,kind) as sock:
        try: sock.bind((host,port))
        except OSError as exc: raise SystemExit(f'Port conflict on {host}:{port}: {exc}')
print('Required ports are available')
PORTCHECK
if [[ ! -f "$ETC/vpn-seeded" ]]; then
    (cd "$ROOT/vpn" && ./vpn-ui-amd64 setting -port 18080 -listenIP 127.0.0.1 >/dev/null)
    python3 "$ROOT/gateway/manage.py" seed
fi
chown root:alirezapanel "$ROOT/vpn/vpn-ui.db" "$ETC/gateway.json" "$ETC/tls/cert.pem" "$ETC/tls/key.pem"
chmod 640 "$ROOT/vpn/vpn-ui.db" "$ETC/gateway.json" "$ETC/tls/cert.pem" "$ETC/tls/key.pem"
chmod 600 "$ETC/access.json" "$ROOT/adguard/AdGuardHome.yaml"
"$ROOT/adguard/AdGuardHome" --check-config -c "$ROOT/adguard/AdGuardHome.yaml" -w "$ROOT/adguard"

cat > /etc/systemd/system/alirezapanel-vpn.service <<'VPNUNIT'
[Unit]
Description=alirezapanel VPN service
After=network-online.target alirezapanel-dns.service
Wants=network-online.target alirezapanel-dns.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
Group=alirezapanel
UMask=0027
WorkingDirectory=/opt/alirezapanel/vpn
ExecStart=/opt/alirezapanel/vpn/vpn-ui-amd64 run
Restart=on-failure
RestartSec=5
TimeoutStopSec=45
LimitNOFILE=65536
Environment=GOMEMLIMIT=300MiB
Environment=GOGC=75
Environment=VPNUI_LOG_LEVEL=warning
Environment=VPNUI_DB_FOLDER=/opt/alirezapanel/vpn
LogRateLimitIntervalSec=30s
LogRateLimitBurst=200

[Install]
WantedBy=multi-user.target
VPNUNIT

cat > /etc/systemd/system/alirezapanel-dns.service <<'DNSUNIT'
[Unit]
Description=alirezapanel DNS service (AdGuard Home)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
UMask=0077
WorkingDirectory=/opt/alirezapanel/adguard
# CLI pins the internal HTTP socket even if a future config migration changes it.
ExecStart=/opt/alirezapanel/adguard/AdGuardHome -c /opt/alirezapanel/adguard/AdGuardHome.yaml -w /opt/alirezapanel/adguard --web-addr 127.0.0.1:18081
Restart=on-failure
RestartSec=5
TimeoutStopSec=45
LimitNOFILE=65536
Environment=GOMEMLIMIT=160MiB
Environment=GOGC=80
LogRateLimitIntervalSec=30s
LogRateLimitBurst=200

[Install]
WantedBy=multi-user.target
DNSUNIT

install -d -o alirezapanel -g alirezapanel -m 700 /var/lib/alirezapanel-nodes
install -d -m 755 /etc/systemd/system/alirezapanel.service.d
cat > /etc/systemd/system/alirezapanel.service.d/nodes.conf <<'NODE_UNIT'
[Service]
StateDirectory=alirezapanel-nodes
StateDirectoryMode=0700
ReadWritePaths=/var/lib/alirezapanel-nodes
NODE_UNIT

cat > /etc/systemd/system/alirezapanel.service <<'GATEWAYUNIT'
[Unit]
Description=alirezapanel unified HTTPS interface
After=network-online.target alirezapanel-vpn.service alirezapanel-dns.service
Wants=network-online.target alirezapanel-vpn.service alirezapanel-dns.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=alirezapanel
Group=alirezapanel
WorkingDirectory=/opt/alirezapanel/gateway
ExecStart=/usr/bin/python3 -B /opt/alirezapanel/gateway/gateway.py /etc/alirezapanel/gateway.json
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
LimitNOFILE=8192
LogRateLimitIntervalSec=30s
LogRateLimitBurst=100

[Install]
WantedBy=multi-user.target
GATEWAYUNIT

cat > /usr/local/bin/alirezapanel <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
case "${1:-info}" in
    info) exec python3 /opt/alirezapanel/gateway/manage.py info ;;
    credentials) exec python3 -c 'import json; d=json.load(open("/etc/alirezapanel/access.json")); print("Initial username:",d["username"]); print("Initial password:",d["password"]); print("These are initial credentials; later password changes are not reflected here.")' ;;
    check) exec python3 /opt/alirezapanel/gateway/manage.py check ;;
    status) exec systemctl --no-pager status alirezapanel alirezapanel-vpn alirezapanel-dns ;;
    restart)
        wait_active() {
            local unit="$1"
            for _ in $(seq 1 45); do
                systemctl is-active --quiet "$unit" && return 0
                sleep 1
            done
            echo "ERROR: $unit did not become active." >&2
            journalctl -u "$unit" -n 50 --no-pager >&2 || true
            return 1
        }
        echo 'Restarting alirezapanel safely in dependency order...'
        # Keep the public gateway alive while its backends are restarted.  This
        # avoids turning a backend restart failure into a completely vanished panel.
        systemctl reset-failed alirezapanel.service alirezapanel-vpn.service alirezapanel-dns.service 2>/dev/null || true
        systemctl restart alirezapanel-dns.service || { journalctl -u alirezapanel-dns -n 50 --no-pager >&2; exit 1; }
        wait_active alirezapanel-dns.service
        systemctl restart alirezapanel-vpn.service || { journalctl -u alirezapanel-vpn -n 50 --no-pager >&2; exit 1; }
        wait_active alirezapanel-vpn.service
        systemctl start alirezapanel.service || { journalctl -u alirezapanel -n 50 --no-pager >&2; exit 1; }
        wait_active alirezapanel.service
        ready=0
        for _ in $(seq 1 45); do
            if python3 /opt/alirezapanel/gateway/manage.py probe >/dev/null 2>&1; then ready=1; break; fi
            sleep 1
        done
        if (( ! ready )); then
            echo 'ERROR: services are running but the panel readiness probe failed.' >&2
            journalctl -u alirezapanel -u alirezapanel-vpn -u alirezapanel-dns -n 100 --no-pager >&2 || true
            exit 1
        fi
        python3 /opt/alirezapanel/gateway/manage.py info
        echo 'Restart completed successfully.'
        ;;
    logs) exec journalctl -u alirezapanel -u alirezapanel-vpn -u alirezapanel-dns -n 100 --no-pager ;;
    backup)
        dest="/var/backups/alirezapanel/manual-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        install -d -m 700 "$dest"
        trap 'systemctl start alirezapanel-dns alirezapanel-vpn alirezapanel' EXIT
        systemctl stop alirezapanel alirezapanel-vpn alirezapanel-dns
        cp -a /etc/alirezapanel "$dest/config"
        [[ ! -d /var/lib/alirezapanel-nodes ]] || cp -a /var/lib/alirezapanel-nodes "$dest/nodes"
        cp -a /opt/alirezapanel/vpn "$dest/vpn"
        cp -a /opt/alirezapanel/adguard "$dest/adguard"
        printf 'Backup saved: %s\n' "$dest"
        ;;
    vpn) shift; cd /opt/alirezapanel/vpn; exec ./vpn-ui-amd64 "$@" ;;
    help|--help|-h) cat /opt/alirezapanel/README.txt ;;
    *) echo 'Commands: info credentials check status restart logs backup vpn help' >&2; exit 2 ;;
esac
CLI
chmod 755 /usr/local/bin/alirezapanel

# When automatic domain SSL was selected, keep the project certificate copy in
# sync after Certbot renewals. The hook restarts only the public gateway because
# VPN and DNS do not consume this certificate.
if [[ "$MODE" == install && "${ALIREZA_TLS_MODE:-}" == domain && -n "${ALIREZA_HOST:-}" && -d "/etc/letsencrypt/live/$ALIREZA_HOST" ]]; then
    install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/alirezapanel <<RENEWHOOK
#!/usr/bin/env bash
set -euo pipefail
[[ "\${RENEWED_LINEAGE:-}" == "/etc/letsencrypt/live/$ALIREZA_HOST" ]] || exit 0
install -o root -g alirezapanel -m 640 "\$RENEWED_LINEAGE/fullchain.pem" /etc/alirezapanel/tls/cert.pem
install -o root -g alirezapanel -m 640 "\$RENEWED_LINEAGE/privkey.pem" /etc/alirezapanel/tls/key.pem
systemctl try-restart alirezapanel.service
RENEWHOOK
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/alirezapanel
    systemctl enable --now certbot.timer 2>/dev/null || true
fi

systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/alirezapanel.service \
    /etc/systemd/system/alirezapanel-vpn.service /etc/systemd/system/alirezapanel-dns.service
say 'Starting both services and the integrated HTTPS interface.'
systemctl enable --now alirezapanel-dns alirezapanel-vpn alirezapanel
REPAIR_STOPPED=0
ready=0
for ((attempt=0; attempt<120; attempt++)); do
    if python3 "$ROOT/gateway/manage.py" probe > "$STAGE/readiness.log" 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if (( ! ready )); then
    cat "$STAGE/readiness.log"
    die 'The integrated interface did not become ready. Inspect logs with alirezapanel logs.'
fi
# Retry readiness, not installer mutations. A failed check never prints success.
health=0
for ((attempt=0; attempt<12; attempt++)); do
    if [[ -f "$ETC/installed" ]]; then
        if python3 "$ROOT/gateway/manage.py" check > "$STAGE/health.log" 2>&1; then health=1; break; fi
    else
        if python3 "$ROOT/gateway/manage.py" check --login > "$STAGE/health.log" 2>&1; then health=1; break; fi
    fi
    sleep 3
done
cat "$STAGE/health.log"
(( health )) || die 'A health check failed. The installation is preserved; see alirezapanel logs.'
printf 'integration=1.1.0\nvpn=%s\nadguard=%s\n' "$VPN_VERSION" "$AGH_VERSION" > "$ETC/installed"
say 'Installation and automated health checks completed.'
python3 "$ROOT/gateway/manage.py" info
printf '\nTo display your initial login: sudo alirezapanel credentials\n'
case "${ALIREZA_TLS_MODE:-ip}" in
    domain) printf 'Domain SSL mode is enabled. Certbot renewal is configured when Let\x27s Encrypt was used.\n' ;;
    ip) printf 'IP HTTPS mode is enabled; the default certificate is self-signed unless a certificate was supplied.\n' ;;
    none) printf 'Plain HTTP mode is enabled; traffic to the public panel is not TLS-encrypted.\n' ;;
esac
printf 'No firewall rules or system DNS settings were changed. Permit the selected panel port at the hosting firewall.\n'
