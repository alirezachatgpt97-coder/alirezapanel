#!/usr/bin/env bash
# alirezapanel 1.4.0 -- one-file ONLINE installer, 2026-09-16
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
  sudo bash install.sh --ssl        Configure trusted SSL on an installed panel
  sudo bash install.sh --check      Read-only service and connectivity checks
  sudo bash install.sh --fix-restart Apply only the restart-page fix to an existing installation
  sudo bash install.sh --enable-nodes Add/update Nodes without reinstalling VPN or DNS
  bash install.sh --self-test       Check shell and embedded Python syntax without installing
  bash install.sh --help            Show this help

Optional first-install environment variables:
  ALIREZA_HOST       Public IP or domain (no scheme or port)
  ALIREZA_PORT       Public panel port; defaults depend on access mode
  ALIREZA_TLS_MODE   domain | ip-acme | ip | none (interactive installer asks when omitted)
  ALIREZA_ACME_EMAIL Optional Let's Encrypt email for domain mode
  ALIREZA_USER       Initial administrator, default admin
  ALIREZA_PASSWORD   16..72 UTF-8 bytes; randomly generated if omitted
  ALIREZA_CERT       Existing PEM certificate chain (optional)
  ALIREZA_KEY        Matching PEM private key (required with ALIREZA_CERT)

Examples:
  sudo env ALIREZA_TLS_MODE=domain ALIREZA_HOST=panel.example.com bash install.sh
  sudo env ALIREZA_TLS_MODE=ip bash install.sh
  sudo env ALIREZA_TLS_MODE=none bash install.sh

Domain mode can obtain a Let's Encrypt certificate automatically. ip-acme mode obtains a trusted short-lived IP certificate.
Legacy ip mode uses a self-signed HTTPS certificate unless ALIREZA_CERT/ALIREZA_KEY are supplied.
The server must reach GitHub, its package repositories and DNS upstreams.
Allow the selected public panel port and TCP/UDP port 53 in your hosting firewall if
DNS should be reachable from clients. VPN ports depend on the protocols you enable.
Native services are NOT provisioned until selected in UI.
Designed for light use on 1 vCPU; 512 MiB minimum, 1 GiB recommended. Optional native cores need additional memory.
This installer has NOT been validated on a live 1 GiB Linux server.
HELP
}

case "$MODE" in
    --help|-h) help; exit 0 ;;
    --self-test)
        bash -n "$0"
        python3 - "$0" <<'SELF_TEST'
import pathlib,re,sys
source=pathlib.Path(sys.argv[1]).read_text()
count=0
for name,tag,body in re.findall(r'''cat > "\$STAGE/([^"\n]+)" <<'([^']+)'\n(.*?)\n\2''',source,re.S):
    if name.endswith('.py'):
        compile(body,name,'exec');count+=1
if count<6:raise SystemExit('Embedded module extraction failed.')
print('OK: Bash syntax and',count,'embedded Python modules. No installation performed.')
SELF_TEST
        exit 0 ;;

    install|--repair|--check|--fix-restart|--enable-nodes|--ssl) ;;
    *) help; exit 2 ;;
esac
[[ $# -le 1 ]] || die 'Only one operation may be specified.'
[[ $EUID -eq 0 ]] || die 'Run with: sudo bash install.sh'
if [[ "$MODE" == --check ]]; then
    [[ -f "$ROOT/gateway/manage.py" ]] || die 'alirezapanel is not installed.'
    exec python3 "$ROOT/gateway/manage.py" check
fi
if [[ "$MODE" == --ssl ]]; then
    [[ -f "$ROOT/gateway/tls.py" ]] || die 'Upgrade with --repair before using --ssl.'
    exec python3 "$ROOT/gateway/tls.py" configure
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
    printf "  2) Public server IP + trusted SSL (Let's Encrypt)\n"
    printf '  3) Server IP + self-signed HTTPS\n  4) Server IP/domain without SSL (plain HTTP)\n'
    printf '\nSelection [1-4]: '
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
            export ALIREZA_PORT="${ALIREZA_PORT:-8443}"
            printf 'Optional email for Let\x27s Encrypt notices (press Enter to skip): '
            read -r acme_email_input
            [[ -z "$acme_email_input" ]] || export ALIREZA_ACME_EMAIL="$acme_email_input"
            ;;
        2)
            export ALIREZA_TLS_MODE=ip-acme
            export ALIREZA_PORT="${ALIREZA_PORT:-8443}"
            printf 'Public server IP (not private/NAT address): '
            read -r public_ip_input
            [[ -n "$public_ip_input" ]] || die 'A public IP is required for trusted IP SSL.'
            export ALIREZA_HOST="$public_ip_input"
            ;;
        3)
            export ALIREZA_TLS_MODE=ip
            export ALIREZA_PORT="${ALIREZA_PORT:-8443}"
            printf 'Public server IP: '
            read -r public_ip_input
            [[ -z "$public_ip_input" ]] || export ALIREZA_HOST="$public_ip_input"
            ;;
        4)
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
        *) die 'Invalid selection. Run the installer again and choose 1, 2, 3 or 4.' ;;
    esac
fi

# Non-interactive installs preserve the historical secure default.
export ALIREZA_TLS_MODE="${ALIREZA_TLS_MODE:-ip}"
case "$ALIREZA_TLS_MODE" in
    domain|ip-acme|ip|none) ;;
    *) die 'ALIREZA_TLS_MODE must be: domain, ip-acme, ip or none.' ;;
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
(( memory_kb >= 450000 )) || die 'At least 512 MiB RAM is required; protocol capacity depends on workload.'
vpn_memory_mib=$((memory_kb / 1024 * 30 / 100))
(( vpn_memory_mib <= 300 )) || vpn_memory_mib=300
dns_memory_mib=$((memory_kb / 1024 * 12 / 100))
(( dns_memory_mib <= 160 )) || dns_memory_mib=160

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

STAGE=$(mktemp -d /opt/.alirezapanel-install.XXXXXXXX)
chmod 700 "$STAGE"
# Validate access settings before certificate requests, downloads or service writes.
python3 - "$0" "$STAGE/tls.py" <<'EXTRACT_TLS'
import pathlib, sys
source=pathlib.Path(sys.argv[1]).read_text()
delimiter='NODE_EMBEDDED_TLS_PY_EOF'
body=source.split("<<'"+delimiter+"'\n",1)[1].split('\n'+delimiter,1)[0]
pathlib.Path(sys.argv[2]).write_text(body+'\n')
EXTRACT_TLS
if [[ ! -f "$ETC/gateway.json" ]]; then
    python3 - "$STAGE" <<'ACCESS_PREFLIGHT'
import os, sys
sys.path.insert(0,sys.argv[1])
from tls import host_name
mode=os.environ.get('ALIREZA_TLS_MODE','ip')
host=os.environ.get('ALIREZA_HOST','')
if host: host_name(host,mode)
elif mode in ('domain','ip-acme'): raise SystemExit('Set ALIREZA_HOST to your public domain/IP.')
port=int(os.environ.get('ALIREZA_PORT','8080' if mode=='none' else '8443'))
if not 1<=port<=65535 or port in (53,80,2097,18080,18081): raise SystemExit('Panel port is reserved or invalid; use 8443.')
password=os.environ.get('ALIREZA_PASSWORD')
if password and not 16<=len(password.encode())<=72: raise SystemExit('Password must be 16..72 UTF-8 bytes.')
if bool(os.environ.get('ALIREZA_CERT'))!=bool(os.environ.get('ALIREZA_KEY')): raise SystemExit('Supply BOTH certificate and key.')
ACCESS_PREFLIGHT
fi
if [[ ! -f "$ETC/gateway.json" && ( "$ALIREZA_TLS_MODE" == domain || "$ALIREZA_TLS_MODE" == ip-acme ) && -z "${ALIREZA_CERT:-}" ]]; then
    python3 "$STAGE/tls.py" prepare --result "$STAGE/tls-result.json"
    export ALIREZA_CERT="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["cert"])' "$STAGE/tls-result.json")"
    export ALIREZA_KEY="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["key"])' "$STAGE/tls-result.json")"
fi
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
import signal
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
from features import Features
from dns_clients import DNSClients
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
        self.features = Features(self)
        self.dns_clients = DNSClients(self)
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
        self.vpn = aiohttp.ClientSession(timeout=timeout, headers={"Accept-Encoding":"identity"}, cookie_jar=aiohttp.DummyCookieJar(),
                                        auto_decompress=False, connector=aiohttp.TCPConnector(limit=64))
        self.agh = aiohttp.ClientSession(timeout=timeout, headers={"Accept-Encoding":"identity"}, cookie_jar=aiohttp.CookieJar(unsafe=True),
                                        auto_decompress=False, connector=aiohttp.TCPConnector(limit=32))

        await self.dns_clients.start()

    async def stop(self, app):
        await self.dns_clients.stop()
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
            text = text.replace('<a-input v-model.trim="client.email"></a-input>', '<a-input v-model.trim="client.email"></a-input><button type="button" class="alireza-policy-button" data-alireza-policy :data-email="client.email">فیلتر / گیمینگ</button>')
        # Don't replace arbitrary JavaScript/JSON identifiers, protocol names,
        # URLs, user configuration or legal attribution. Branding is DOM-only.
        text = re.sub(r"<title>.*?</title>", "<title>alirezapanel" + (" · DNS" if agh else "") + "</title>",
                      text, count=1, flags=re.I | re.S)
        opts = json.dumps({"base": base, "dns": agh}, ensure_ascii=True).replace("<", "\\u003c")
        # The stylesheet loads after the upstream styles. Mark the document before
        # first paint; don't override saved user theme choices on every visit.
        tag = ('<link rel="stylesheet" href="' + html.escape(base, quote=True) +
               '_alireza/theme.css?v=1.4.0"><script>document.documentElement.setAttribute("data-alireza-theme","ember");'
               'window.ALIREZA=' + opts + ';</script><script defer src="' +
               html.escape(base, quote=True) + '_alireza/brand.js?v=1.1.0"></script>')
        if not agh:
            tag += '<script defer src="' + html.escape(base, quote=True) + '_alireza/nodes.js?v=1.0.0"></script>'
        if not agh:
            tag += '<script defer src="' + html.escape(base, quote=True) + '_alireza/features.js?v=1.5.0"></script>'
        return re.sub(r"</head\s*>", tag + "</head>", text, count=1, flags=re.I)

    def dns_shell(self, upstream_html, base, managed=False):
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
  <main class="bo-content" style="min-width:0">
  <div id="alireza-dns-clients" dir="rtl"></div>
  <iframe id="alireza-dns" title="alirezapanel DNS · تنظیمات پیشرفته" data-src="''' + src + '''" hidden style="width:100%;min-height:480px;border:0" allow="clipboard-write"></iframe>
  </main></div></div>''' + "\n".join(scripts) + '''
<script>const app=new Vue({el:'#app',data:{themeSwitcher}});</script><script defer src="''' + html.escape(base, quote=True) + '''_alireza/dns-clients.js?v=1.3.0"></script></body>'''
        if not managed:
            body = body.replace('<div id="alireza-dns-clients" dir="rtl"></div>', '')
            body = body.replace('data-src="', 'src="').replace(' hidden style="', ' style="')
            body = re.sub(r'<script defer src="[^"<>]*_alireza/dns-clients\.js[^"<>]*"></script>', '', body)
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
        except web.HTTPException as exc:
            if request.path.startswith("/dns-query/"):
                exc.headers["Cache-Control"] = "no-store"
                exc.headers["Referrer-Policy"] = "no-referrer"
                raise
            if request.headers.get('X-Requested-With') == 'XMLHttpRequest' or '/_alireza/' in request.path or '/panel/api/' in request.path:
                if exc.status >= 400:
                    return web.json_response({'success': False, 'msg': exc.text}, status=exc.status,
                        headers={'Cache-Control':'no-store'})
            raise
        except (aiohttp.ClientError, asyncio.TimeoutError, sqlite3.Error, OSError, ValueError):
            LOG.warning("An upstream service is unavailable", exc_info=True)
            return web.json_response({"success":False,"msg":"سرویس مقصد پاسخ نداد؛ اتصال نود، گواهی و وضعیت هسته را بررسی کن. دستور ترمینال: alirezapanel check"}, status=502, headers={"Cache-Control":"no-store"})

    async def dispatch(self, request):
        dns_response = await self.dns_clients.public(request)
        if dns_response is not None:
            return dns_response
        node_response = await self.nodes.route(request)
        if node_response is not None:
            return node_response
        self.validate_origin(request)
        base, vpn_origin, tls = self.vpn_settings()
        if request.path == "/" and base != "/":
            raise web.HTTPNotFound()
        if not request.path.startswith(base):
            raise web.HTTPNotFound()
        relative = request.path[len(base):]
        dns_response = await self.dns_clients.api(request, relative)
        if dns_response is not None:
            return dns_response
        feature_response = await self.features.route(request, relative)
        if feature_response is not None:
            return feature_response
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
                document = self.dns_shell(await response.text(), base, managed=True)
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
                        if request.scheme == "https" and "secure" not in value.lower():
                            value += "; Secure"
                        if "samesite=" not in value.lower():
                            value += "; SameSite=Lax"
                    out.add("Set-Cookie", value)
            if not agh and relative == 'panel/setting/defaultSettings' and response.status == 200:
                from nodes import bounded
                data = json.loads(await bounded(response))
                data = self.features.defaults(data, request)
                out.popall('ETag', None)
                out.popall('Content-Encoding', None)
                out['Content-Type'] = 'application/json; charset=utf-8'
                out['Cache-Control'] = 'no-store'
                return web.Response(body=json.dumps(data).encode(), headers=out)
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
    app = create_app(config)
    def reload_certificate(signum, frame):
        if context is not None:
            try: context.load_cert_chain(config["tls_cert"], config["tls_key"])
            except (OSError, ssl.SSLError): LOG.exception("Certificate reload failed; existing context retained")
    # Install the handler before startup; an early systemd reload must not take
    # the default SIGHUP action and terminate the public gateway.
    signal.signal(signal.SIGHUP, reload_certificate)
    web.run_app(app, host=config.get("listen", "0.0.0.0"), port=config["port"],
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
    if tls_mode not in ('domain', 'ip-acme', 'ip', 'none'):
        raise SystemExit('ALIREZA_TLS_MODE must be domain, ip-acme, ip or none.')
    default_port = '8080' if tls_mode == 'none' else '8443'
    port = int(os.environ.get('ALIREZA_PORT', default_port))
    if not 1 <= port <= 65535 or port in (53, 80, 2097, 18080, 18081):
        raise SystemExit('ALIREZA_PORT must be 1..65535, excluding 53, 80, 2097, 18080 and 18081.')

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
        if not ipaddress.ip_address(primary_ipv4).is_global:
            raise SystemExit('A private/NAT address was detected. Set ALIREZA_HOST to the public domain/IP explicitly.')
        host = primary_ipv4
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
                     'systemdServiceName': 'alirezapanel-vpn', 'subTitle': 'alirezapanel',
                     'subEnable':'true','subJsonEnable':'true','subClashEnable':'true','subListen':'127.0.0.1','subPort':'2097'}.items():
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
    # The private DoH relay must actually resolve, not merely expose a UI toggle.
    query = b'\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01'
    req = urllib.request.Request(cfg['agh_origin'] + '/dns-query', data=query,
          headers={'Content-Type':'application/dns-message', 'Accept':'application/dns-message'})
    with urllib.request.urlopen(req, timeout=12) as response:
        answer = response.read(65536)
        if response.headers.get_content_type() != 'application/dns-message' or len(answer) < 12 or answer[:2] != query[:2] or not answer[2] & 128 or answer[3] & 15:
            raise SystemExit('Managed DoH backend failed. Run --repair and check DNS upstreams.')
    print('OK actual private DoH backend response')
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

/* 1.2: Scope client polish to Clients; preserve dashboard geometry. */
.alireza-policy-button{display:none}
[data-alireza-admin] .alireza-policy-button{display:inline-block;margin-top:8px;border:1px solid #9b6235;background:transparent;color:#df843d;border-radius:8px;padding:5px 10px;cursor:pointer}
.alireza-client-tools{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:0 0 14px}
.alireza-client-tools button{font:inherit;color:inherit;background:transparent;border:1px solid #8b684b;border-radius:9px;padding:7px 12px;cursor:pointer}
.alireza-policy-dialog{max-width:min(540px,94vw);padding:24px;border:1px solid #85613f;border-radius:16px;background:#18181c;color:#f5f2ef;font:14px/1.9 system-ui}
.alireza-policy-dialog::backdrop{background:#0009}
.alireza-policy-dialog label{display:block;margin:12px 0}.alireza-policy-dialog label input{margin-inline-end:10px}
.alireza-policy-dialog>input{width:100%;padding:10px;background:#101013;color:#eee;border:1px solid #615448;border-radius:8px;direction:ltr}
.alireza-policy-dialog button{padding:8px 14px;margin:12px 0 0 10px;border:1px solid #b57641;border-radius:8px;background:#e99045;color:#18100a;cursor:pointer}
.alireza-policy-dialog button:disabled{opacity:.5;cursor:wait}.alireza-policy-dialog button:focus-visible{outline:2px solid white;outline-offset:3px}
[data-alireza-clients] .ant-table-thead>tr>th{font-weight:600;letter-spacing:0;padding-block:14px}
[data-alireza-clients] .ant-table-tbody>tr>td{padding-block:15px}
[data-alireza-clients] .ant-input,[data-alireza-clients] .ant-select-selection,[data-alireza-clients] .ant-btn{border-radius:8px}
[data-alireza-clients] .ant-table-wrapper{border-radius:12px;overflow:hidden}
@media(prefers-reduced-motion:reduce){[data-alireza-clients] *{transition:none!important;animation:none!important}}

/* 1.3: DNS console and client refinements. Static surfaces; no dashboard changes. */
.ap-dns{font:14px/1.75 system-ui,sans-serif;color:var(--ap-text);max-width:1440px;margin-inline:auto}
.ap-dns [hidden],#alireza-dns[hidden]{display:none!important}
.ap-dns button,.ap-dns input,.ap-dns select,.ap-dns textarea{font:inherit;color:var(--ap-text);border:1px solid var(--ap-border);background:var(--ap-surface);border-radius:10px;padding:9px 13px;max-width:100%}
.ap-dns button{cursor:pointer;white-space:nowrap}.ap-dns button:hover{border-color:var(--ap-orange);background:var(--ap-raised)}
.ap-dns button:disabled{opacity:.5;cursor:wait}.ap-dns .ap-primary{background:var(--ap-orange);border-color:var(--ap-orange);color:var(--ap-on-orange);font-weight:700}
.ap-dns .ap-primary-soft{background:var(--ap-orange-soft);color:var(--ap-orange);border-color:transparent}
.ap-dns p{color:var(--ap-muted);margin:8px 0 18px}.ap-dns h2{font-size:25px;font-weight:750;margin:5px 0 8px;letter-spacing:-.7px}
.ap-dns-tabs{display:flex;gap:5px;border-bottom:1px solid var(--ap-border);padding-bottom:12px;margin-bottom:26px;flex-wrap:wrap}
.ap-dns-tabs button{border-color:transparent;background:transparent;color:var(--ap-muted)}
.ap-dns-tabs .is-selected{background:var(--ap-orange-soft);color:var(--ap-orange);font-weight:650}
.ap-dns-heading{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:22px}
.ap-dns-eyebrow{font-size:11px;letter-spacing:2px;color:var(--ap-orange);font-weight:750;direction:ltr;display:block}
.ap-dns-stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:24px}
.ap-dns-stats>div{padding:18px 22px;border:1px solid var(--ap-border);border-radius:15px;background:var(--ap-surface)}
.ap-dns-stats span{color:var(--ap-muted);font-size:12px}.ap-dns-stats strong{display:block;font-size:27px;margin-top:5px;font-weight:650}
.ap-dns-toolbar,.ap-dns-bulk,.ap-dns-actions,.ap-dns-pager,.ap-dns-dialog-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.ap-dns-toolbar{margin-bottom:14px}.ap-dns-toolbar input{flex:1;min-width:200px}.ap-dns-bulk{padding:12px;margin-bottom:12px;background:var(--ap-orange-soft);border-radius:12px}
.ap-dns-table-wrap{overflow-x:auto;border:1px solid var(--ap-border);border-radius:15px;background:var(--ap-surface)}
.ap-dns table{border-collapse:collapse;width:100%;min-width:880px;text-align:right}
.ap-dns th{font-weight:500;font-size:12px;color:var(--ap-muted);background:var(--ap-raised);padding:12px 15px;white-space:nowrap}
.ap-dns td{padding:16px 15px;border-top:1px solid var(--ap-border);vertical-align:middle}.ap-dns tr:hover td{background:var(--ap-raised)}
.ap-dns td small{display:block;color:var(--ap-muted);font-size:11px;margin-top:4px}.ap-dns input[type=checkbox]{accent-color:var(--ap-orange);width:16px;height:16px;padding:0;flex:none}
.ap-dns-person{display:flex;align-items:center;gap:10px}.ap-dns-person strong{display:block;max-width:200px;overflow-wrap:anywhere;font-weight:600}
.ap-dns-avatar{display:grid;place-items:center;flex:none;width:36px;height:36px;border:1px solid var(--ap-border);border-radius:11px;background:var(--ap-orange-soft);color:var(--ap-orange);font-weight:700}
.ap-dns-badge{font-size:11px;white-space:nowrap;padding:4px 8px;border-radius:7px;background:var(--ap-raised);border:1px solid var(--ap-border);color:var(--ap-muted)}
.ap-dns-badge.active,.ap-dns-badge.waiting{color:#62ce9b;border-color:#345348}.ap-dns-badge.expired,.ap-dns-badge.quota,.ap-dns-badge.error{color:#edaf61;border-color:#715435}
.ap-dns-number{direction:ltr;text-align:right;font-variant-numeric:tabular-nums;font-size:12px}.ap-dns progress{display:block;width:130px;height:5px;border:0;margin-top:8px;accent-color:var(--ap-orange);border-radius:5px;overflow:hidden}
.ap-dns progress::-webkit-progress-bar{background:var(--ap-raised)}.ap-dns progress::-webkit-progress-value{background:var(--ap-orange)}
.ap-dns-actions button{font-size:12px;padding:6px 9px;border-radius:7px}.ap-dns-pager{justify-content:flex-end;margin-top:16px;color:var(--ap-muted);font-size:12px}
.ap-dns-empty{text-align:center;padding:48px 24px;border:1px dashed var(--ap-border);border-radius:15px}.ap-dns-empty h3{font-size:20px}
.ap-dns-note{margin-top:28px;padding:14px 18px;border:1px solid var(--ap-border);border-radius:12px;color:var(--ap-muted);font-size:12px}
.ap-dns summary{cursor:pointer;color:var(--ap-muted)}.ap-dns-note p:last-child{margin-bottom:0}
.ap-dns-message:empty{display:none}.ap-dns-message{border-inline-start:3px solid var(--ap-orange);padding:8px 14px;background:var(--ap-orange-soft);border-radius:8px}.ap-dns-message.is-error{color:#f7b4a4}
.ap-dns-dialog{width:min(690px,94vw);max-height:90dvh;overflow:auto;border:1px solid var(--ap-border);border-radius:20px;background:var(--ap-bg);padding:24px;box-shadow:0 25px 100px #0007;margin:auto}
.ap-dns-dialog::backdrop{background:#0009}.ap-dns-dialog-top{display:flex;justify-content:space-between;align-items:center;gap:16px;margin-bottom:20px}.ap-dns-dialog-top h3{margin:0;font-size:20px}.ap-dns-dialog-top button{font-size:24px;padding:0 11px;background:transparent;border-color:transparent}
.ap-dns-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:0 14px}.ap-dns-field{display:block;margin-bottom:15px}.ap-dns-field>span{display:block;font-size:12px;color:var(--ap-muted);margin-bottom:6px}.ap-dns-field input,.ap-dns-field select,.ap-dns-field textarea{width:100%;box-sizing:border-box}.ap-dns-field textarea{resize:vertical}
.ap-dns fieldset{border:1px solid var(--ap-border);padding:10px 15px;border-radius:12px;margin:18px 0}.ap-dns legend{font-size:12px;color:var(--ap-orange);width:auto;padding:0 8px}.ap-dns-check{display:flex;gap:9px;align-items:center;margin:10px 0}
.ap-dns .ap-dns-hint{font-size:12px;line-height:1.9;color:var(--ap-muted)}.ap-dns-dialog-actions{border-top:1px solid var(--ap-border);padding-top:16px;margin:16px 0}.ap-dns-dialog details{margin-top:20px}.ap-dns-dialog details .ap-dns-actions{margin-top:14px}
.ap-dns-qr{text-align:center;margin:18px 0}.ap-dns-qr canvas{border:12px solid white;border-radius:10px;max-width:100%;height:auto}
[data-alireza-clients] .ant-table-thead>tr>th{font-size:12px;color:var(--ap-muted)!important}
[data-alireza-clients] .ant-table-tbody>tr>td{font-variant-numeric:tabular-nums}
[data-alireza-clients] .ant-tag{border-radius:6px;font-size:11px}
[data-alireza-clients] .ant-progress-inner{height:5px}
[data-alireza-clients] .alireza-client-tools{padding:12px 16px;background:var(--ap-surface);border:1px solid var(--ap-border);border-radius:12px}
@media(max-width:760px){.ap-dns-heading{align-items:flex-start;flex-direction:column}.ap-dns-heading>button{width:100%}.ap-dns h2{font-size:21px}.ap-dns-stats{grid-template-columns:1fr 1fr;gap:8px}.ap-dns-stats>div{padding:14px}.ap-dns-dialog{padding:18px}.ap-dns-form-grid{grid-template-columns:1fr}.ap-dns-pager{justify-content:center}}

/* 1.4: scoped controls only, no idle work. */
.alireza-policy-dialog{max-height:88dvh;overflow:auto;background:var(--ap-surface);color:var(--ap-text)}
.alireza-policy-dialog textarea{width:100%;font:inherit;padding:9px;border:1px solid var(--ap-border);background:var(--ap-bg);color:var(--ap-text);border-radius:8px;resize:vertical}
.alireza-game-box{border:1px solid var(--ap-border);border-radius:12px;padding:14px;margin-top:14px}
.alireza-game-box p{font-size:12px;color:var(--ap-muted);margin-bottom:0}
.alireza-game-box button[aria-pressed=false]{background:var(--ap-raised);color:var(--ap-text);border-color:var(--ap-border)}
/* Per-user native usage + subscription studio: on-demand only, no polling. */
.alireza-usage-dialog,.alireza-sub-dialog{width:min(760px,94vw);max-height:88vh;overflow:auto;border:1px solid var(--ap-border);border-radius:18px;background:var(--ap-surface);color:var(--ap-text);padding:22px;box-shadow:0 24px 80px rgba(0,0,0,.35)}
.alireza-usage-dialog::backdrop,.alireza-sub-dialog::backdrop{background:rgba(0,0,0,.68)}
.alireza-usage-dialog input,.alireza-sub-dialog input{width:min(430px,100%);padding:10px 12px;margin:8px 6px;border:1px solid var(--ap-border);border-radius:10px;background:var(--ap-bg);color:var(--ap-text)}
.alireza-stat-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:16px 0}.alireza-stat-grid section{padding:14px;border:1px solid var(--ap-border);border-radius:14px;background:var(--ap-raised)}.alireza-stat-grid small{display:block;color:var(--ap-muted);margin-bottom:7px}.alireza-stat-grid strong{font-size:18px}.alireza-bars>div{margin:13px 0}.alireza-bars span{display:block;margin-bottom:6px}.alireza-bars i{display:block;height:10px;background:var(--ap-bg);border:1px solid var(--ap-border);border-radius:99px;overflow:hidden}.alireza-bars b{display:block;height:100%;background:var(--ap-orange);border-radius:99px}.alireza-log-list{display:grid;gap:7px}.alireza-log-list>div{display:grid;grid-template-columns:1fr 1.5fr auto;gap:10px;padding:10px 12px;border:1px solid var(--ap-border);border-radius:10px}.alireza-sub-hero{padding:20px;border:1px solid #634027;border-radius:18px;background:linear-gradient(135deg,var(--ap-orange-soft),var(--ap-surface));margin-top:14px}.alireza-ring{--p:0;position:relative;width:150px;height:150px;margin:18px auto;border-radius:50%;display:grid;place-items:center;background:conic-gradient(var(--ap-orange) calc(var(--p)*1%),var(--ap-raised) 0)}.alireza-ring:before{content:'';width:116px;height:116px;border-radius:50%;background:var(--ap-surface);position:absolute}.alireza-ring>div{position:relative;text-align:center}.alireza-ring strong,.alireza-ring small{display:block}.alireza-ring strong{font-size:24px}.alireza-sub-links>div{display:flex;gap:8px;align-items:center;margin:7px 0}.alireza-sub-links code{direction:ltr;overflow:auto;flex:1;padding:9px;border-radius:8px;background:var(--ap-bg);border:1px solid var(--ap-border)}
@media(max-width:650px){.alireza-stat-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.alireza-log-list>div{grid-template-columns:1fr}.alireza-usage-dialog,.alireza-sub-dialog{padding:14px}}

ALIREZAPANEL_EMBEDDED_3_EOF

cat > "$STAGE/logo.svg" <<'ALIREZAPANEL_EMBEDDED_4_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect width="48" height="48" rx="14" fill="#ff963f"/><path d="M24 8 38 14v10c0 8-7 13-14 16C17 37 10 32 10 24V14Z" fill="#211208"/><path d="m17 29 7-14 7 14m-11-5h8" fill="none" stroke="#ffb170" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
ALIREZAPANEL_EMBEDDED_4_EOF

cat > "$STAGE/README.txt" <<'ALIREZAPANEL_EMBEDDED_5_EOF'
alirezapanel 1.4.0
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
512 MiB RAM (1 GiB recommended) and 2 GiB free disk space. GitHub and distribution package
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

TLS / AUTOMATIC RENEWAL
The terminal wizard offers domain + trusted SSL, public IP + trusted SSL,
self-signed HTTPS, or explicit HTTP. HTTPS defaults to 8443, leaving 443 free
for an inbound. Trusted IP certificates use Certbot 5.4.0 when the distro's CLI
is too old. This isolated command-line runtime adds no resident process.
HTTP-01 requires TCP port 80 reachable from the internet during issuance AND
renewal. Domain A/AAAA records must reach this server. If port 80 is already in
use, the installer stops with an explanation and never stops another webserver.
Use the native SSL manager's DNS challenge for that deployment topology.

  sudo alirezapanel ssl             Configure or change trusted public SSL
  sudo alirezapanel ssl status      Certificate expiry, paths and renewal mode
  sudo alirezapanel ssl renew       Check renewal now (does not force reissuance)
  systemctl status alirezapanel-cert-renew.timer
  journalctl -u alirezapanel-cert-renew.service

Renewal is checked every six hours (with jitter), including six-day IP certs.
The stable certificate/key paths are /etc/alirezapanel/tls/cert.pem and key.pem.
The native inbound form offers the alirezapanel certificate and "Default cert".
For new TLS inbounds an empty file-certificate pair is filled automatically
when a trusted alirezapanel certificate is available; a blank domain SNI is
filled with its hostname. Existing or custom certificates are preserved.
Otherwise select the certificate and use a hostname/SNI covered by it.
Existing inbounds, custom certificates, Reality keys and non-TLS protocols are
never silently converted. OpenVPN's client CA and device keys are NOT replaced.
Panel TLS reload keeps node sessions alive. VPN is restarted only if a live
inbound or native web/subscription listener consumes the renewed certificate;
that restart briefly interrupts traffic and preserves all saved protocol data.
Externally supplied certs are not automatically enrolled into ACME.
Self-signed mode is deliberately labelled untrusted; issuance failure never
silently falls back to self-signed. No trust bypass is added to client configs.

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
Development verification for this revision uses local HTTP/HTTPS integration
tests, a native-Vue DOM harness and the SHA-verified vpn-ui executable
(login, connector promotion, node enrollment, inbound creation/edit, client
identity preservation and real category-filter validation/core restart). Full Linux installation, kernel VPN protocols,
all AdGuard settings flows and sustained low-memory performance remain unverified.
The pinned AdGuard binary accepted the exact generated config/schema; its full
service could not start in the test environment because /proc/self/exe is absent.
Live panel TLS rotation was exercised while an existing TLS connection remained
open, and the new certificate was verified on a fresh connection.

SOURCE AND LICENSE
See SOURCES.txt, LICENSE-vpn-ui.txt and LICENSE-AdGuardHome.txt in this directory.
Original GPL licenses and author notices are retained. Integration source is
embedded in install.sh and installed in /opt/alirezapanel/gateway, under GPL-3.0
or later. alirezapanel is an independent integration of the upstream projects.

1.2.0 INTEGRATION CHANGES
- Fixed the HTTP login cookie's inappropriate Secure flag.
- Kept the secret base path private at the public root (404).
- Fixed compressed native login/catalog JSON being read as UTF-8; internal
  sessions now explicitly request identity encoding, matching their streaming
  no-decompression policy. This failure was reproduced against the pinned binary.
- Node UI now includes the native Clients page and its APIs, plus core logs and
  individual core restart/stop. System uninstall/reboot and unrelated settings
  remain local-only. All original inbound forms and protocol generators remain.
- Exact encoded queries, multipart bodies and binary downloads survive both
  gateway hops. Node errors are returned in the native JSON error format.
- Check/add verifies catalog access, not only the node's identity endpoint.
- Service sessions are revalidated before node mutations without replaying writes.
- Public-CA node enrollment verifies chain + hostname on every connection and
  survives ordinary certificate renewal. Existing pins remain strict; reconnect
  legacy entries once to opt into public-CA verification. Self-signed nodes must
  be re-enrolled after certificate replacement.
- New installs enable loopback-only native subscriptions. Links are exposed
  through the panel's HTTPS gateway, including a unified multi-location link.
  Existing subscription enable/port/listen settings and explicit subscription or
  bridge URLs are preserved during repair. Custom native certificate defaults
  are also preserved; the panel certificate remains a separate selectable option.
- Combined subscription memory is bounded at 8 MiB. Unavailable sources fail
  the refresh rather than silently removing a location from a user's profile.
- Optional per-client ad/adult domain filtering uses native Xray user routing
  rules and geosite datasets. Native config validation precedes save; a failed
  core restart restores the previous template where no concurrent edit occurred.
  The recovery checkpoint is in the private node state. MTProto is not supported
  for this per-client feature. Domain blocking cannot identify every adult item,
  IP-only flow or content hidden in encrypted DNS/ECH; DNS UI remains available.
- Choose filters in the client form, then save the client. Account creation and
  filter application are separate operations: if the latter fails, a visible
  message says the client exists but filtering was NOT applied. Retry from the
  Filter Client control. Existing accounts can be filtered from the same toolbar.
- Client page spacing/controls are polished; dashboard layout, branding and
  original navigation/button positions are preserved. No continuous new polling,
  external fonts, large frontend framework or always-on worker was added.
- Go memory targets scale with RAM. They are GC targets, not hard memory caps.
  More protocols, geofiles and traffic need more memory; 512 MiB capacity is not
  certified. Native cores remain opt-in; the installer adds no tunnel/firewall
  redirection. Existing native tunnel options retain their original behavior.

UPGRADE
  sudo bash install.sh --repair
Run the same version on the master and every node. A backup is made first;
repair briefly stops the services. Then recheck nodes in the Nodes page.
For trusted certificates created by an older installer, run `alirezapanel ssl`
once if `ssl status` does not show automatic renewal configured.

VALIDATION SCOPE
The supplied installer is syntax-checked. Integration regression tests use real
local HTTP/HTTPS connections against simulated APIs, with separate tests against
the pinned native vpn-ui binary. Coverage includes:
node enrollment, create/update client/inbound, multipart/query fidelity, binary
exports, WebSocket, TLS defaults, filtering rollback and access revocation.
This does not certify live ACME issuance, traffic for every VPN protocol, every
hosting firewall/tunnel, or capacity on an actual 512 MiB VPS. Real browser
rendering was not available in the build environment. Use `alirezapanel check`
after deployment; inspect any failing service before exposing it to customers.

DESIGN REFERENCES
Nova-Server informed the simple node/client flow and certificate lifecycle ideas:
https://github.com/IRNova/Nova-Server
No Nova binary or background stack is installed. Upstream protocol code remains
vpn-ui v1.9.4, SHA-256 pinned by this installer. Attribution/licenses are retained.
Trusted IP ACME reference:
https://letsencrypt.org/2026/03/11/shorter-certs-certbot


MANAGED DNS CLIENTS (1.3)
Open DNS in the existing sidebar. The Clients tab adds named DoH credentials,
quota in DNS MESSAGE bytes (not HTTP overhead or website/download bandwidth),
query-count limits, validity days, optional start on first successful query,
fixed-IP restriction or first-successful-IP binding, native per-client adult / ad
list / safe-search settings, custom tested upstreams, and saved creation presets.
Bulk enable/disable, extension, counter reset and delete are available. Editing
policy preserves expiry. Extension adds days to max(now, current expiry) and
keeps counters / enable state. Rotate invalidates the old URL immediately.
A failed native policy save leaves that managed client blocked until a successful
save; it is shown as requiring review. No success is claimed after a failed write.

Each managed client gets a separate native ClientID, unrelated to its public
secret token. Its DoH URL is https://HOST:PANEL_PORT/dns-query/SECRET and stays
valid when the panel's secret base path changes. QR and JSON configuration export
are generated locally. The JSON is human-readable connection data, not a VPN
subscription. Use the URL in a DoH-capable client. Android's system Private DNS
box expects a DoT hostname and does not accept this URL. Use a DoH app instead,
or configure native DoT separately without claiming managed quotas on it.
Trusted SSL must match the URL host. The panel certificate and renewal mechanism
also serve managed DoH on the same HTTPS listener. No additional cert service.

LIMITS THAT MATTER
- These quotas/expiry/IP restrictions apply ONLY to managed /dns-query/SECRET.
  Existing plain DNS port 53 and separately enabled native DoT/DoQ remain intact
  and do not use this quota engine. This does not force a device to use your DNS.
- IP is a network address, not a hardware identifier. NAT shares it across devices;
  mobile networks change it. A bearer link can be shared. First-IP binding requires
  explicit unbind when networks change. We do not promise physical-device identity.
- DNS upstream selection is real and tested for DNS responses. A third-party
  Smart DNS / anti-sanction service must support the desired sites and may require
  registration of this server's public IP. DNS alone does not change web egress IP.
  Custom DNS services can see queries. No default third-party anti-sanction service
  is silently added. Existing global fallback settings still belong to AdGuard.
- Ad blocking requires at least one enabled, downloaded native blocklist and global
  DNS protection enabled. The form checks this before saving. Use the Advanced tab
  to configure lists. Adult filtering and Safe Search also require global protection.
  Content filtering operates on domains; apps with independent DNS can bypass it.
- Successful requests debit request + returned response bytes. Failed upstreams
  debit inbound request bytes/count. Over-quota replies are withheld. Expiry and
  first-IP activation start only on a returned valid DNS response. Already cached
  answers on clients cannot be revoked. No user browsing payload passes this relay.

LIGHTWEIGHT OPERATION
No extra daemon, frontend framework, public lookup, remote font, background client
poll or quota scheduler. The advanced native DNS UI loads on demand. DNS concurrency
is capped at 8, each managed credential at 20 queries/sec with a 40-query burst.
Requests are capped at 4 KiB, responses at 65535 bytes. DNS transfers/ANY are refused.
Client search is paginated at 25 rows. Counters use SQLite WAL with NORMAL sync;
process restarts retain committed counters, while unexpected power/storage loss can
lose the last commits. This is not a financial billing ledger. 5000 stored clients
is an administrative ceiling, NOT a capacity guarantee for a 512 MiB VPS. A single
small server's measured workload determines usable capacity. Backups include the
private DNS database within /var/lib/alirezapanel-nodes.

TUNNELS / REVERSE PROXIES
Forward /dns-query/* to the same HTTPS gateway, preserving its path and request
body. TLS terminates at the gateway for this endpoint. Arbitrary X-Forwarded-For
headers are ignored. When a trusted reverse proxy is needed, add only its exact
CIDRs in gateway.json as dns_trusted_proxies, then restart the gateway. That proxy
must overwrite/append actual peer information safely; never trust 0.0.0.0/0 or ::/0.
A raw TCP tunnel can hide original client IP; bearer credentials still work but
per-device IP binding is then not meaningful. Configure it accordingly.

UPGRADE / CHECK
sudo bash install.sh --repair
sudo alirezapanel check
sudo alirezapanel ssl status
The installer enables private HTTP DoH only on AdGuard's loopback management
listener while that service is stopped. The externally exposed managed endpoint
requires HTTPS. --repair preserves existing clients, protocols and certificate
configuration and creates the standard pre-upgrade backup. Existing nodes need the
same repair update for new integration modules; each node's DNS clients are managed
on that node's own panel, independently of VPN node control.

1.3 VALIDATION
Automated HTTPS relay tests cover native API adapters, DNS GET/POST bytes, quota
concurrency, expiry, secret rotation, revoke during in-flight work, IP binding,
forwarded-IP spoof rejection, policy failure recovery and restart persistence.
DOM tests cover creation, exports, bulk revoke, safe text rendering, lazy advanced
UI and dashboard isolation. The pinned native VPN executable is also exercised.
AdGuard configuration is checked with its pinned executable. A complete live
AdGuard run, public ACME issuance and VPS memory/load capacity must be verified on
a real Linux host; this development sandbox does not expose /proc/self/exe.

Inspiration, without copying Nova implementation or changing the panel identity:
https://github.com/IRNova/Nova-Server (quick onboarding, saved plans, bulk actions)
Native DNS API contract: AdGuard Home v0.107.79 openapi/openapi.yaml
https://github.com/AdguardTeam/AdGuardHome/tree/v0.107.79


PER-CLIENT POLICIES AND GAMING (1.4)
The existing filter dialog now adds social-media categories, communication / messenger
categories, YouTube, detectable BitTorrent, and up to 100 custom domain names.
Custom domains include subdomains; wildcard/regex rules, URLs and IP addresses
are deliberately not accepted by this simple editor. Existing ad/adult rules remain.
Only explicitly provided fields change through the API; old clients updating ad/adult
settings do not silently erase newer options. Domain lists use the installed geosite
database and are validated by the native core. Categories can change with data updates.

This dialog is supported for native Xray VLESS, VMess, Trojan and Shadowsocks users.
Before enabling filtering, the integration checks inbound Sniffing: HTTP/TLS must be
on and metadataOnly off. It does not silently change the shared inbound or its protocol.
Unsupported cores / relay accounts are refused rather than displaying fictitious
protection. If the same email is used on multiple inbounds, policy targets all such
instances of that identity. Other clients are untouched. Native core restart may
briefly reconnect active users when applying settings; reads do not restart it.

Filters are real routing rules, not universal content inspection. Encrypted DNS,
ECH, IP-only connections, unrecognized QUIC and encrypted/obfuscated torrents can
limit detection. A domain block does not inspect every image, video or ad inside
an otherwise allowed domain. Do not claim 100 percent coverage. A failing restart
attempt restores the previous template when no concurrent edit has intervened.

Gaming Mode is an explicit OPTIONAL DIRECT UDP EGRESS rule for one user:
- Appends after all existing routes, preserving their precedence. Filters, explicit
  tunnel routes, private-network blocks and other operator rules keep priority.
- Only otherwise-unmatched UDP, excluding destination port 53, uses a small shared
  freedom outbound. TCP stays on its existing route. This covers UDP generally;
  it does not magically identify every game's packets.
- Can avoid an unnecessary default outbound proxy hop. If the normal path is already
  direct, it does not create a shorter path. A prior catch-all rule can prevent it
  from taking effect. The UI explains both limits rather than promising lower ping.
- UDP may leave using the server's own egress IP instead of a default chained proxy.
  Services requiring that proxy's location may work differently. Normal OS-level
  routes/tunnels still apply. The client app and inbound must carry UDP.
- Existing custom outbounds are not modified. No CPU overclock, OS sysctl changes,
  high-memory buffers, packet duplication, background probing, observatory, new
  service, or kernel traffic shaping is added. Last-user disable removes the
  integration's unused gaming outbound. A deny-by-default blackhole setup is refused.

Resource target remains light usage on 1 vCPU / 1 GiB RAM. Each enabled policy adds
only a few native routing entries (and category data already used by Xray); there is
no per-user daemon. Actual concurrent users, protocols, category lists and throughput
determine capacity. A literal guarantee for every cheap VPS or game latency is not
possible without measuring that host and network path.

1.4 VERIFICATION
Actual pinned Xray tests send VLESS/TLS traffic for two separate users. Ad/adult,
social, messenger, YouTube, custom domains (including subdomains), and BitTorrent
handshake blocking are checked alongside an allowed control user. Real UDP echo
checks per-user gaming routing, unchanged TCP/other users, and preservation of a
higher-priority block rule. Test-only loopback exceptions allow local echo fixtures;
no such exception is shipped in the production gaming outbound. Native panel tests
also create/update a node inbound, apply/read back policies, and remove them again.
Automated API/DOM regressions cover partial writes, rollback, tag conflicts,
configuration preservation, checkbox queuing and node selection. No measured
internet ping improvement is claimed.

Routing reference: https://xtls.github.io/en/config/routing.html
Pinned core schema: https://github.com/XTLS/Xray-core/tree/v26.4.17
Upgrade with sudo bash install.sh --repair on master and nodes, then open
Filter / Gaming in the client editor. Turn Gaming off to restore normal UDP routing.

The new policy API advertises version 2. The UI verifies this on the selected node
before writes; an older node cannot silently accept and ignore Gaming controls.
A fresh template comparison also rejects edits detected before the save operation.
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
NATIVE_SUB = '/_alireza/native-sub/'
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
    if data.get('trust','pinned') not in ('pinned','public'):
        raise ValueError('Invalid TLS trust mode.')
    return {'endpoint':endpoint,'certificate':pem,'fingerprint':hashlib.sha256(der).hexdigest(),'trust':data.get('trust','pinned')}

def permitted(method, tail):
    # URL decoding has already happened in aiohttp. Reject traversal/ambiguous
    # path separators before matching, rather than trying to normalize them.
    path = tail.split('?',1)[0]
    if '\\' in path or any(p in ('.','..') for p in path.split('/')) or path.startswith('/'):
        return False
    if method in ('GET','HEAD') and (path.startswith('assets/') or path in ('panel/inbounds','panel/inbounds/','panel/clients','panel/clients/','ws','panel/core','panel/core/')):
        return True
    if method == 'GET' and path in ('panel/api/clients/list','panel/api/clients/assignable','_alireza/features/tls'):
        return True
    if method == 'POST' and path == '_alireza/features/policy':
        return True
    if method == 'GET' and re.fullmatch(r'panel/core/(logs|config)/[a-z0-9_-]+', path):
        return True
    if method == 'POST' and re.fullmatch(r'panel/core/(restart|stop)/[a-z0-9_-]+', path):
        return True
    if method in ('GET','POST') and path.startswith('panel/api/inbounds/'):
        return True
    if method == 'GET' and path in ('panel/core/status','panel/core/catalog','panel/core/provision-status'):
        return True
    if method == 'POST' and path == 'panel/core/provision':
        return True
    if method == 'POST' and path in ('panel/setting/defaultSettings','panel/setting/inboundForm'):
        return True
    if method == 'GET' and path in tuple('panel/api/server/'+p for p in ('status','userStats','serverName','panelLocation','getNewUUID','getNewX25519Cert','getNewmldsa65','getNewmlkem768','getNewVlessEnc','getXrayVersion')):
        return True
    if method == 'POST' and path=='panel/api/server/getNewEchCert':
        return True
    return False

def node_tls(node):
    if node.get('trust') == 'public':
        return True
    return aiohttp.Fingerprint(bytes.fromhex(node['fingerprint']))

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
        self.remote = aiohttp.ClientSession(headers={"Accept-Encoding":"identity"},cookie_jar=aiohttp.DummyCookieJar(),
            timeout=aiohttp.ClientTimeout(total=None,connect=8,sock_read=180),
            connector=aiohttp.TCPConnector(limit=32),auto_decompress=False)

    async def stop(self):
        tasks = {t for group in self.channels.values() for t in group}
        for task in tasks: task.cancel()
        if tasks: await asyncio.gather(*tasks, return_exceptions=True)
        await self.remote.close()

    async def channel(self, key, operation):
        task=asyncio.current_task()
        tasks=self.channels.setdefault(key,set()); tasks.add(task)
        try:
            return await operation
        finally:
            tasks.discard(task)
            if not tasks: self.channels.pop(key, None)

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
        # Node integration only. Use the native Admins API and never write the VPN
        # database, inbound/protocol tables, clients or core settings directly.
        # vpn-ui v1.9.4 deliberately ignores isSuperAdmin on /admins/add; promotion
        # is a separate /admins/update/:id operation.  The old code therefore made
        # a connector which could log in but had no privilege to list/manage node
        # inbounds.  Reconcile the dedicated connector on every identity request so
        # existing installations made by the buggy version repair themselves too.
        async with self.lock:
            base,origin,tls = self.g.vpn_settings()
            common = {'Cookie':request.headers.get('Cookie',''),'Host':request.host,
                      'Accept':'application/json','Accept-Encoding':'identity'}

            async def admin_json(method, path, data=None):
                async with self.g.vpn.request(method, origin+base+'panel/admins/'+path,
                    data=data, ssl=tls, headers=common, allow_redirects=False,
                    timeout=aiohttp.ClientTimeout(total=12)) as response:
                    raw = await bounded(response)
                    try:
                        result = json.loads(raw)
                    except (TypeError, ValueError):
                        raise web.HTTPBadGateway(text='Node connector Admin API returned an invalid response.')
                    if response.status != 200 or result.get('success') is not True:
                        message = str(result.get('msg') or 'Admin API request failed.')[:240]
                        raise web.HTTPBadGateway(text='Unable to prepare the node connector account: '+message)
                    return result

            credentials = self.state.get('service')
            if not isinstance(credentials,dict) or not credentials.get('username') or not credentials.get('password'):
                credentials = {'username':'alireza-node-'+secrets.token_hex(6),
                               'password':secrets.token_urlsafe(40)}
                await admin_json('POST','add',dict(credentials,
                    nickname='alirezapanel node connector',enable='true'))

            # Find the dedicated account through the supported native API.  If an
            # operator deleted it, recreate it rather than leaving state.json stale.
            listing = await admin_json('GET','list')
            admins = listing.get('obj') or []
            account = next((item for item in admins if item.get('username') == credentials['username']), None)
            if account is None:
                credentials = {'username':'alireza-node-'+secrets.token_hex(6),
                               'password':secrets.token_urlsafe(40)}
                await admin_json('POST','add',dict(credentials,
                    nickname='alirezapanel node connector',enable='true'))
                listing = await admin_json('GET','list')
                admins = listing.get('obj') or []
                account = next((item for item in admins if item.get('username') == credentials['username']), None)
                if account is None:
                    raise web.HTTPBadGateway(text='Node connector account was created but could not be found.')

            # Promotion is intentionally a separate native operation in vpn-ui
            # v1.9.4. Reset only this connector's private password so state.json and
            # the login credential cannot drift apart. No inbound or protocol data
            # is touched by this request.
            ident = account.get('id')
            if not isinstance(ident,int) or ident <= 0:
                raise web.HTTPBadGateway(text='Node connector account has an invalid id.')
            await admin_json('POST','update/'+str(ident),{
                'username':credentials['username'],
                'password':credentials['password'],
                'nickname':'alirezapanel node connector',
                'enable':'true',
                'isSuperAdmin':'true',
            })

            # Confirm the promotion before handing out a token/certificate. This
            # prevents a node from looking configured while its relay API is unusable.
            listing = await admin_json('GET','list')
            admins = listing.get('obj') or []
            account = next((item for item in admins if item.get('username') == credentials['username']), None)
            if not account or account.get('isSuperAdmin') is not True or account.get('enable') is not True:
                raise web.HTTPBadGateway(text='Node connector account could not be promoted to an enabled super-admin.')

            changed = self.state.get('service') != credentials
            self.state['service'] = credentials
            if not self.state.get('token'):
                self.state['token'] = secrets.token_urlsafe(48)
                changed = True
            if changed:
                self.save()
            self.cookie = ''
            self.cookie_at = 0

    async def session(self, host, verify=False):
        async with self.login_lock:
            if self.cookie and time.monotonic()-self.cookie_at<60:
                if not verify: return self.cookie
                base,origin,tls=self.g.vpn_settings()
                async with self.g.vpn.get(origin+base+'panel/admins/permissions',ssl=tls,
                    headers={'Cookie':self.cookie,'Host':host,'Accept-Encoding':'identity'},allow_redirects=False,
                    timeout=aiohttp.ClientTimeout(total=10)) as response:
                    try: result=json.loads(await bounded(response))
                    except ValueError: result={}
                    if response.status==200 and result.get('success') is True and result.get('obj'):
                        return self.cookie
                self.cookie=''
                self.cookie_at=0
            if not self.state['service']:
                raise web.HTTPServiceUnavailable(text='Open Nodes and enable this node first.')
            base,origin,tls = self.g.vpn_settings()
            async with self.g.vpn.post(origin+base+'login',data=self.state['service'],ssl=tls,
                headers={'Host':host,'Accept-Encoding':'identity'},allow_redirects=False) as response:
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
            headers={'Cookie':await self.session(host),'Host':host,'Accept-Encoding':'identity'},allow_redirects=False) as response:
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
                ssl=node_tls(node),
                headers={'Authorization':'Bearer '+node['token'],'X-Alirezapanel-Request':'1'},
                allow_redirects=False,timeout=aiohttp.ClientTimeout(total=15)) as response:
                raw=await bounded(response)
                if response.status!=200: raise web.HTTPBadGateway(text='Node API returned '+str(response.status)+': '+raw.decode(errors='replace')[:240])
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
                headers['Cookie']=await self.session(request.host,verify=request.method not in ('GET','HEAD'))
                headers['X-Alirezapanel-Request']='1'
                clone=request.clone(rel_url=URL(base+request.rel_url.raw_path[len(AGENT+'relay/'):]+('?' + request.rel_url.raw_query_string if request.rel_url.raw_query_string else ''),encoded=True),headers=headers)
                return await self.channel('agent', self.g.dispatch(clone))
            raise web.HTTPNotFound()
        if request.path.startswith(NATIVE_SUB):
            if request.method not in ('GET','HEAD'): raise web.HTTPMethodNotAllowed(request.method,['GET','HEAD'])
            try: await asyncio.wait_for(self.subscription_pool.acquire(), timeout=1)
            except asyncio.TimeoutError: raise web.HTTPTooManyRequests(headers={'Retry-After':'5'})
            try:
                return await self.local_sub_response(request, request.path[len(NATIVE_SUB):])
            finally: self.subscription_pool.release()
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
            if request.headers.get('Upgrade','').lower() == 'websocket':
                return await self.proxy(request,parts[0],parts[1],base)
            try: await asyncio.wait_for(self.pool.acquire(),timeout=5)
            except asyncio.TimeoutError: raise web.HTTPTooManyRequests(headers={'Retry-After':'3'})
            try:
                return await self.channel(parts[0],self.proxy(request,parts[0],parts[1],base))
            finally: self.pool.release()
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
            except aiohttp.ClientConnectorCertificateError:
                raise web.HTTPBadGateway(text='Public TLS validation failed: check the node hostname, certificate chain and expiry. No insecure fallback was used.')
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
            package=json.dumps({'version':1,'endpoint':request.scheme+'://'+request.host,'certificate':pem,
                'trust':'public' if self.g.config.get('tls_mode') in ('domain','ip-acme') else 'pinned'},indent=2)
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
            await self.remote_data(node,'catalog')
            if info.get('version')!=1 or str(uuid.UUID(info['id']))!=info['id']: raise ValueError('Unsupported node.')
            if info['id']==self.state['id']: raise ValueError('This is the local server; choose Local in Inbounds.')
            if not isinstance(info.get('base'),str) or not re.fullmatch(r'/[A-Za-z0-9_./-]*',info['base']): raise ValueError('Invalid node base path.')
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
                catalog=await self.remote_data(node,'catalog')
                return no_store({'success':True,'inbounds':catalog['inbounds'],'clients':len(catalog['clients'])})
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
        path=request.rel_url.raw_path[len(URL(base+'_alireza/remote/'+ident+'/').raw_path) :]+('?' + request.rel_url.raw_query_string if request.rel_url.raw_query_string else '')
        target=URL(node['endpoint']+AGENT+'relay/'+path,encoded=True)
        headers=headers_clean(request.headers)
        for name in ('Host','Cookie','Origin','Referer','Authorization','X-Forwarded-Proto','X-Forwarded-Host','X-Forwarded-For','X-Real-IP','Forwarded'):
            headers.popall(name,None)
        headers['Authorization']='Bearer '+node['token']
        headers['X-Alirezapanel-Request']='1'
        headers['Accept-Encoding']='identity'
        tls=node_tls(node)
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
        for asset in ('brand.js','theme.css','logo.svg','nodes.js','features.js'):
            body=body.replace(mount+'_alireza/'+asset,master+'_alireza/'+asset)
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
            async with self.remote.get(target,ssl=node_tls(node),
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
        results=[]; size=0
        for start in range(0,len(profile['sources']),4):
            batch=await asyncio.gather(*(self.source_bytes(s,kind,request.host) for s in profile['sources'][start:start+4]))
            size+=sum(len(r[0]) for r in batch)
            if size>LIMIT: raise web.HTTPBadGateway(text='Combined subscription exceeds 8 MiB; split the profile.')
            results.extend(batch)
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
                text=base64.b64decode(text + '=' * (-len(text) % 4),validate=True).decode()
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
        if(t.key.startsWith(config.mount) && !/panel\/(inbounds|clients|core)/.test(t.key))
          t.key=base+t.key.slice(config.mount.length);
      });
    }
    if(!component.tabs.some(t=>t.key===base+'panel/nodes'))
      component.tabs.splice(component.tabs.length-1,0,{key:base+'panel/nodes',icon:'cluster',title:'نودها / Nodes'});
    if(location.pathname.replace(/\/$/,'')===base+'panel/nodes') component.requestUri=base+'panel/nodes';
  }
  if(!/\/panel\/(inbounds|clients|core)\/?$/.test(location.pathname)) return;
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
    window.location.assign(select.value==='local'?base+'panel/'+location.pathname.split('/').filter(Boolean).pop():base+'_alireza/remote/'+encodeURIComponent(select.value)+'/panel/'+location.pathname.split('/').filter(Boolean).pop());
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
<form id="add-form"><label for="certificate">گواهی اتصال</label><textarea id="certificate" required spellcheck="false" placeholder='{"version":1,"endpoint":"https://…","certificate":"…"}'></textarea><label for="token">API Token</label><input class="code" id="token" type="password" required autocomplete="off"><button type="submit">بررسی و افزودن نود</button></form><p class="muted">گواهی اتصال شامل آدرس و گواهی عمومی سرور است. گواهی معتبر عمومی با تمدید خودکار متصل می‌ماند. برای گواهی خودامضا، پس از تعویض گواهی اتصال را دوباره ثبت کن.</p></section>
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
async function api(op,data){const r=await fetch(base+'_alireza/nodes/'+op,{method:data===undefined?'GET':'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json','X-Alirezapanel-Request':'1'},body:data===undefined?undefined:JSON.stringify(data)});if(!r.ok){let t=await r.text();try{t=JSON.parse(t).msg||t;}catch(_){}throw Error(t.slice(0,400));}return r.json();}
async function busy(button,fn){button.disabled=true;try{await fn();}catch(e){notice(e.message||'عملیات انجام نشد.');}finally{button.disabled=false;}}
async function copy(value){try{await navigator.clipboard.writeText(value);notice('کپی شد.');}catch(_){notice('کپی خودکار در دسترس نیست؛ مقدار را انتخاب و دستی کپی کن.');}}
function button(label,action,danger=false){const b=document.createElement('button');b.type='button';b.className=danger?'danger':'secondary';b.textContent=label;b.onclick=()=>busy(b,action);return b;}
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
async function load(){const data=await api('list');nodes=data.nodes;const list=$('nodes-list');list.replaceChildren();if(!nodes.length)list.append(el('p','هنوز نودی اضافه نشده است.','muted'));for(const n of nodes){const card=el('article',undefined,'card');const head=el('div',undefined,'nodehead');const title=el('div');title.append(el('strong',n.name),el('div',n.endpoint,'endpoint muted'));const actions=el('div',undefined,'row');const link=el('a','اینباندهای این سرور','btn');link.href=base+'_alireza/remote/'+n.id+'/panel/inbounds';link.target='_top';const clients=el('a','کلاینت‌ها','btn');clients.href=base+'_alireza/remote/'+n.id+'/panel/clients';clients.target='_top';actions.append(link,clients,button('بررسی اتصال',async()=>{const d=await api('check',{id:n.id});notice('اتصال و دسترسی به '+n.name+' برقرار است؛ '+d.inbounds+' اینباند، '+d.clients+' اشتراک.');}),button('تغییر نام',async()=>{const name=prompt('نام سرور',n.name);if(name){await api('rename',{id:n.id,name});await load();}}),button('حذف اتصال',async()=>{if(confirm('اتصال '+n.name+' از این پنل حذف شود؟ اینباندهای نود حذف نمی‌شوند.')){await api('delete',{id:n.id});await load();}},true));head.append(title,actions);card.append(head);list.append(card);}const profiles=$('profiles-list');profiles.replaceChildren();for(const p of data.profiles){const card=el('article',undefined,'card');card.append(el('strong',p.name));const input=el('input');input.className='code';input.readOnly=true;input.value=p.url;card.append(input);const row=el('div',undefined,'row');row.append(button('کپی لینک',()=>copy(p.url)),button('کپی JSON',()=>copy(p.url+'/json')),button('کپی Clash',()=>copy(p.url+'/clash')),button('حذف اشتراک ترکیبی',async()=>{if(confirm('این لینک ترکیبی غیرفعال شود؟ اشتراک‌های اصلی حفظ می‌شوند.')){await api('delete-profile',{id:p.id});await load();}},true));card.append(row);profiles.append(card);}}
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


cat > "$STAGE/dns_clients.py" <<'NODE_EMBEDDED_DNS_CLIENTS_PY_EOF'
"""Managed DoH clients: bounded relay, durable quotas, native AdGuard policies.

No extra daemon. Plain DNS and native DoT/DoQ remain independent legacy services.
Only the secret managed DoH endpoint enforces these quotas and IP bindings.
"""
import asyncio
import base64
import ipaddress
import json
import re
import secrets
import sqlite3
import struct
import time
from urllib.parse import urlsplit

import aiohttp
from aiohttp import web

PUBLIC = '/dns-query/'
API = '_alireza/dns-clients/'
HEADERS = {'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff'}
MAX_CLIENTS = 5000


def reply(data):
    return web.json_response(data, headers=HEADERS)


def number(value, minimum=0, maximum=10**12):
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ValueError('عدد خارج از محدوده است.')
    return value


def normalize_ip(value):
    ip = ipaddress.ip_address(value)
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return str(ip)


def upstreams(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 3:
        raise ValueError('یک تا سه DNS بالادستی وارد کن.')
    result = []
    for item in value:
        if not isinstance(item, str) or not item or len(item) > 512 or re.search(r'\s', item):
            raise ValueError('آدرس DNS نامعتبر است.')
        try:
            item = str(ipaddress.ip_address(item))
        except ValueError:
            u = urlsplit(item)
            if u.scheme not in ('https', 'tls', 'quic') or not u.hostname or u.username or u.password or u.fragment or u.query:
                raise ValueError('DNS باید IP یا آدرس https://، tls:// یا quic:// باشد.')
            if u.port is not None and not 1 <= u.port <= 65535:
                raise ValueError('پورت DNS نامعتبر است.')
            if u.scheme != 'https' and u.path not in ('', '/'):
                raise ValueError('مسیر فقط برای HTTPS مجاز است.')
        result.append(item)
    return result


def client_config(data):
    name = data.get('name', '')
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80 or any(ord(c) < 32 for c in name):
        raise ValueError('نام کلاینت باید بین ۱ تا ۸۰ حرف باشد.')
    mode = data.get('ip_mode', 'any')
    if mode not in ('any', 'fixed', 'first'):
        raise ValueError('حالت محدودیت IP نامعتبر است.')
    ip = normalize_ip(str(data.get('allowed_ip', '')).strip()) if mode == 'fixed' else ''
    custom = data.get('resolver', 'default')
    if custom not in ('default', 'custom'):
        raise ValueError('نوع DNS نامعتبر است.')
    out = dict(name=name.strip(), ip_mode=mode, allowed_ip=ip,
               quota_bytes=number(data.get('quota_bytes', 0), maximum=10**15),
               query_limit=number(data.get('query_limit', 0)),
               days=number(data.get('days', 30), maximum=3650),
               resolver=custom, upstreams=upstreams(data.get('upstreams')) if custom == 'custom' else [])
    for key in ('ads', 'adult', 'safe_search', 'start_on_first'):
        if not isinstance(data.get(key, False), bool):
            raise ValueError('مقدار گزینه نامعتبر است.')
        out[key] = data.get(key, False)
    return out


async def limited_body(content, limit):
    chunks, size = [], 0
    async for chunk in content.iter_chunked(8192):
        size += len(chunk)
        if size > limit:
            raise web.HTTPRequestEntityTooLarge(max_size=limit, actual_size=size)
        chunks.append(chunk)
    return b''.join(chunks)


def question(packet):
    if not 17 <= len(packet) <= 4096:
        raise ValueError('Invalid DNS query size.')
    ident, flags, qd, an, ns, ar = struct.unpack('!6H', packet[:12])
    if flags & 0xf800 or qd != 1 or an or ns:
        raise ValueError('Only standard single-question DNS queries are supported.')
    offset = 12
    while True:
        if offset >= len(packet):
            raise ValueError('Incomplete DNS question.')
        length = packet[offset]; offset += 1
        if length == 0:
            break
        if length > 63 or offset + length > len(packet) or offset + length > 267:
            raise ValueError('Invalid DNS name.')
        offset += length
    if offset + 4 > len(packet):
        raise ValueError('Incomplete DNS question.')
    qtype, qclass = struct.unpack('!HH', packet[offset:offset+4])
    if qtype in (251, 252, 255) or qclass != 1:
        raise ValueError('DNS transfers and ANY queries are not supported.')
    return packet[12:offset+4]


class DNSClients:
    def __init__(self, gateway):
        self.g = gateway
        self.db = None
        self.admin_lock = asyncio.Lock()
        self.pool = asyncio.Semaphore(8)
        self.rates = {}
        self.trusted = [ipaddress.ip_network(s) for s in gateway.config.get('dns_trusted_proxies', [])]

    async def start(self):
        path = self.g.nodes.folder / 'dns-clients.sqlite3'
        self.db = sqlite3.connect(path, timeout=2)
        path.chmod(0o600)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=NORMAL')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS clients (
          id TEXT PRIMARY KEY, token TEXT UNIQUE NOT NULL, agh_id TEXT UNIQUE NOT NULL,
          config TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
          state TEXT NOT NULL DEFAULT 'pending', created INTEGER NOT NULL,
          started INTEGER NOT NULL DEFAULT 0, expires INTEGER NOT NULL DEFAULT 0,
          used INTEGER NOT NULL DEFAULT 0, queries INTEGER NOT NULL DEFAULT 0,
          bound_ip TEXT NOT NULL DEFAULT '', last_ip TEXT NOT NULL DEFAULT '',
          last_seen INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS plans (id TEXT PRIMARY KEY, name TEXT NOT NULL, config TEXT NOT NULL);
        ''')
        self.session = aiohttp.ClientSession(cookie_jar=aiohttp.DummyCookieJar(),
            headers={'Accept-Encoding': 'identity'}, auto_decompress=False,
            timeout=aiohttp.ClientTimeout(total=8, connect=2), connector=aiohttp.TCPConnector(limit=8))

    async def stop(self):
        await self.session.close()
        if self.db:
            self.db.close()

    def row(self, ident):
        row = self.db.execute('SELECT * FROM clients WHERE id=?', (ident,)).fetchone()
        if row is None:
            raise web.HTTPNotFound(text='کلاینت پیدا نشد.')
        return dict(row)

    def view(self, row, include_secret=False):
        r = dict(row); cfg = json.loads(r.pop('config'))
        r.pop('agh_id')
        if not include_secret:
            r.pop('token')
        r['config'] = cfg
        r['status'] = ('error' if r['state'] != 'ready' else 'disabled' if not r['enabled']
                       else 'expired' if r['expires'] and r['expires'] <= time.time()
                       else 'quota' if (cfg['quota_bytes'] and r['used'] >= cfg['quota_bytes']) or
                       (cfg['query_limit'] and r['queries'] >= cfg['query_limit'])
                       else 'waiting' if not r['started'] else 'active')
        return r

    async def agh(self, path, data=None):
        # Login before a write. Never replay writes after an ambiguous failure.
        await self.g.agh_login(force=True)
        async with self.g.agh.request('POST' if data is not None else 'GET',
              self.g.config['agh_origin'] + '/control/' + path, json=data,
              allow_redirects=False, timeout=aiohttp.ClientTimeout(total=25)) as response:
            body = await limited_body(response.content, 8*1024*1024)
            if response.status != 200:
                raise web.HTTPBadGateway(text='سرویس DNS تنظیم را نپذیرفت: ' + body.decode('utf-8', 'replace')[:240])
            return json.loads(body) if body.strip() else {}

    def native(self, row, cfg):
        return dict(name='alireza-managed-' + row['id'], ids=[row['agh_id']], tags=[],
                    use_global_settings=False, filtering_enabled=cfg['ads'],
                    parental_enabled=cfg['adult'], safebrowsing_enabled=True,
                    safe_search=dict(enabled=cfg['safe_search'], **{k: True for k in
                         ('bing','duckduckgo','ecosia','google','pixabay','yandex','youtube')}),
                    use_global_blocked_services=True, upstreams=cfg['upstreams'],
                    upstreams_cache_enabled=False, ignore_querylog=False, ignore_statistics=False)

    async def check_config(self, cfg):
        if cfg['upstreams']:
            tested = await self.agh('test_upstream_dns', {'upstream_dns': cfg['upstreams']})
            if any(tested.get(u) != 'OK' for u in cfg['upstreams']):
                raise web.HTTPBadRequest(text='تست DNS بالادستی موفق نبود: '+str(tested)[:300])
        if cfg['ads'] or cfg['adult'] or cfg['safe_search']:
            status = await self.agh('status')
            if not status.get('protection_enabled'):
                raise web.HTTPConflict(text='محافظت DNS خاموش است؛ در تنظیمات پیشرفته آن را روشن کن.')
        if cfg['ads']:
            status = await self.agh('filtering/status')
            if not status.get('enabled') or not any(f.get('enabled') and f.get('rules_count', 0) for f in status.get('filters', [])):
                raise web.HTTPConflict(text='برای فیلتر تبلیغات، ابتدا یک فهرست مسدودسازی فعال و دانلودشده در تنظیمات پیشرفته DNS اضافه کن.')

    async def save_client(self, data):
        cfg = client_config(data)
        if not self.g.config.get('tls_enabled', True):
            raise web.HTTPConflict(text='ابتدا HTTPS پنل را با دستور alirezapanel ssl فعال کن.')
        ident = data.get('id')
        old = self.row(ident) if ident else None
        if old and number(data.get('revision', 0)) != old['revision']:
            raise web.HTTPConflict(text='کلاینت تغییر کرده است؛ فهرست را تازه کن.')
        if not old and self.db.execute('SELECT count(*) FROM clients').fetchone()[0] >= MAX_CLIENTS:
            raise web.HTTPConflict(text='سقف ۵۰۰۰ کلاینت مدیریت‌شده رسیده است.')
        await self.check_config(cfg)
        # A local probe catches unavailable DoH before publishing a usable credential.
        await self.probe_backend()
        now = int(time.time())
        if not old:
            ident = secrets.token_hex(12)
            started = 0 if cfg['start_on_first'] else now
            expires = started + cfg['days']*86400 if started and cfg['days'] else 0
            with self.db:
                self.db.execute('INSERT INTO clients(id,token,agh_id,config,created,started,expires) VALUES(?,?,?,?,?,?,?)',
                    (ident, secrets.token_urlsafe(32), 'ap-'+secrets.token_hex(16), json.dumps(cfg), now, started, expires))
        else:
            with self.db:
                self.db.execute("UPDATE clients SET state='pending',revision=revision+1 WHERE id=?", (ident,))
        row = self.row(ident)
        try:
            native = self.native(row, cfg)
            # Reconcile interrupted saves against the native API, without touching other clients.
            listing = await self.agh('clients')
            present = any(c.get('name') == native['name'] for c in listing.get('clients', []))
            await self.agh('clients/update' if present else 'clients/add',
                           {'name': native['name'], 'data': native} if present else native)
            with self.db:
                bound = row['bound_ip'] if cfg['ip_mode'] == 'first' else ''
                # Editing policies preserves existing expiry; renew is a separate explicit action.
                self.db.execute("UPDATE clients SET config=?,state='ready',bound_ip=? WHERE id=?",
                                (json.dumps(cfg), bound, ident))
        except BaseException:
            with self.db:
                self.db.execute("UPDATE clients SET state='error' WHERE id=?", (ident,))
            raise
        return self.view(self.row(ident), True)

    async def action(self, data):
        action = data.get('action')
        ids = data.get('ids')
        if not isinstance(ids, list) or not 1 <= len(ids) <= 100 or any(not isinstance(i, str) for i in ids):
            raise ValueError('بین ۱ تا ۱۰۰ کلاینت انتخاب کن.')
        ids = list(dict.fromkeys(ids))
        for ident in ids: self.row(ident)
        if action not in ('enable','disable','reset','renew','unbind','rotate','delete'):
            raise ValueError('عملیات نامعتبر است.')
        days = number(data.get('days', 30), 1, 3650) if action == 'renew' else 0
        for ident in ids:
            with self.db:
                if action in ('enable','disable'):
                    self.db.execute('UPDATE clients SET enabled=?,revision=revision+1 WHERE id=?', (int(action=='enable'), ident))
                elif action == 'reset':
                    self.db.execute('UPDATE clients SET used=0,queries=0,revision=revision+1 WHERE id=?', (ident,))
                elif action == 'renew':
                    self.db.execute('UPDATE clients SET started=CASE WHEN started=0 THEN ? ELSE started END,expires=max(expires,?)+?,revision=revision+1 WHERE id=?',
                                    (int(time.time()), int(time.time()), days*86400, ident))
                elif action == 'unbind':
                    self.db.execute("UPDATE clients SET bound_ip='',revision=revision+1 WHERE id=?", (ident,))
                elif action == 'rotate':
                    self.db.execute('UPDATE clients SET token=?,revision=revision+1 WHERE id=?', (secrets.token_urlsafe(32), ident))
                elif action == 'delete':
                    self.db.execute('UPDATE clients SET enabled=0,revision=revision+1 WHERE id=?', (ident,))
            if action == 'delete':
                # Revocation is immediate even if the native delete fails.
                name = 'alireza-managed-' + ident
                listing = await self.agh('clients')
                if any(c.get('name') == name for c in listing.get('clients', [])):
                    await self.agh('clients/delete', {'name': name})
                with self.db: self.db.execute('DELETE FROM clients WHERE id=?', (ident,))
            self.rates.pop(ident, None)
        return {'success': True}

    async def api(self, request, relative):
        if relative == '_alireza/dns-clients.js':
            return web.FileResponse(self.g.root/'dns_clients.js', headers={'Cache-Control': 'no-cache'})
        if not relative.startswith(API): return None
        if not await self.g.is_admin(request):
            raise web.HTTPForbidden(text='دسترسی مدیر اصلی لازم است.')
        op = relative[len(API):]
        if request.method == 'GET' and op == 'list':
            try: page = max(1, min(100000, int(request.query.get('page', '1'))))
            except ValueError: raise web.HTTPBadRequest(text='شماره صفحه نامعتبر است.')
            search = request.query.get('q', '')[:80].lower()
            rows = [self.view(r) for r in self.db.execute('SELECT * FROM clients ORDER BY created DESC,id')]
            counts = {s: sum(r['status']==s for r in rows) for s in ('active','waiting','expired','quota','disabled','error')}
            rows = [r for r in rows if search in (r['config']['name']+' '+r['last_ip']+' '+r['config']['allowed_ip']+' '+r['id']).lower()]
            return reply(dict(clients=rows[(page-1)*25:page*25], total=len(rows), page=page, counts=counts,
                              plans=[dict(id=r['id'], name=r['name'], config=json.loads(r['config'])) for r in self.db.execute('SELECT * FROM plans ORDER BY name')],
                              tls=self.g.config.get('tls_enabled', True), tls_mode=self.g.config.get('tls_mode', 'ip')))
        if request.method != 'POST': raise web.HTTPMethodNotAllowed(request.method, ['POST'])
        try:
            raw = await asyncio.wait_for(limited_body(request.content, 16384), 5)
            data = json.loads(raw)
            if not isinstance(data, dict): raise ValueError('درخواست باید یک شیء JSON باشد.')
            async with self.admin_lock:
                if op == 'save': result = await self.save_client(data)
                elif op == 'action': result = await self.action(data)
                elif op == 'detail': result = self.view(self.row(str(data.get('id', ''))), True)
                elif op == 'test':
                    cfg = client_config(data); await self.check_config(cfg); await self.probe_backend()
                    result = {'success': True, 'message': 'DNS پاسخ داد؛ این تست دسترسی به سایت‌های تحریمی را تضمین نمی‌کند.'}
                elif op == 'plan':
                    ident = str(data.get('id') or secrets.token_hex(8))
                    if data.get('delete'):
                        with self.db: self.db.execute('DELETE FROM plans WHERE id=?', (ident,))
                    else:
                        cfg = client_config(data)
                        cfg['allowed_ip'] = ''; cfg['ip_mode'] = 'any'
                        if self.db.execute('SELECT count(*) FROM plans').fetchone()[0] >= 30 and not self.db.execute('SELECT 1 FROM plans WHERE id=?', (ident,)).fetchone():
                            raise ValueError('حداکثر ۳۰ پلن ذخیره می‌شود.')
                        with self.db: self.db.execute('INSERT OR REPLACE INTO plans VALUES(?,?,?)', (ident, cfg['name'], json.dumps(cfg)))
                    result = {'success': True}
                else: raise web.HTTPNotFound()
            return reply(result)
        except (ValueError, TypeError, UnicodeError) as exc:
            raise web.HTTPBadRequest(text=str(exc)[:300])

    def peer(self, request):
        peer = normalize_ip(request.remote or '')
        # Never trust arbitrary forwarded headers. Operator must opt in exact proxy CIDRs.
        def trusted(value):
            ip = ipaddress.ip_address(value)
            return any(ip in net for net in self.trusted)
        if self.trusted and trusted(peer):
            chain = request.headers.get('X-Forwarded-For', '').split(',')
            if len(chain) > 10: raise web.HTTPBadRequest(text='Invalid proxy chain.')
            for value in reversed(chain):
                if not trusted(peer): break
                if value.strip(): peer = normalize_ip(value.strip())
        return peer

    def allowed(self, row, peer):
        cfg = json.loads(row['config'])
        if row['state'] != 'ready' or not row['enabled']:
            raise web.HTTPForbidden(text='DNS client is disabled or requires repair.')
        if row['expires'] and row['expires'] <= time.time():
            raise web.HTTPForbidden(text='DNS client expired.')
        expected = cfg['allowed_ip'] if cfg['ip_mode']=='fixed' else row['bound_ip'] if cfg['ip_mode']=='first' else ''
        if expected and expected != peer:
            raise web.HTTPForbidden(text='Client IP is not allowed.')
        if cfg['quota_bytes'] and row['used'] >= cfg['quota_bytes'] or cfg['query_limit'] and row['queries'] >= cfg['query_limit']:
            raise web.HTTPForbidden(text='DNS quota exhausted.')
        return cfg

    async def exchange(self, packet, client_id='', peer='127.0.0.1'):
        async with self.session.post(self.g.config['agh_origin']+'/dns-query'+('/'+client_id if client_id else ''),
                data=packet, headers={'Content-Type':'application/dns-message', 'Accept':'application/dns-message', 'X-Forwarded-For':peer},
                allow_redirects=False) as r:
            if r.status != 200 or r.content_type != 'application/dns-message':
                raise web.HTTPBadGateway(text='DNS backend unavailable; run alirezapanel check / --repair.')
            body = await limited_body(r.content, 65535)
            if len(body) < 12 or body[:2] != packet[:2] or not body[2]&0x80:
                raise web.HTTPBadGateway(text='Invalid DNS backend response.')
            return body

    async def probe_backend(self):
        packet = secrets.token_bytes(2)+b'\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00'+b'\x07example\x03com\x00\x00\x01\x00\x01'
        async with self.pool:
            response = await self.exchange(packet)
        if response[3] & 15 not in (0, 3):
            raise web.HTTPBadGateway(text='DNS بالادستی خطای پاسخ دارد؛ وضعیت resolver را بررسی کن.')

    async def public(self, request):
        if not request.path.startswith(PUBLIC): return None
        if request.method not in ('GET','POST'):
            raise web.HTTPMethodNotAllowed(request.method, ['GET','POST'])
        if not request.secure:
            raise web.HTTPForbidden(text='HTTPS is required for managed DNS.')
        token = request.path[len(PUBLIC):]
        if not re.fullmatch(r'[A-Za-z0-9_-]{43}', token): raise web.HTTPNotFound()
        row = self.db.execute('SELECT * FROM clients WHERE token=?', (token,)).fetchone()
        if row is None: raise web.HTTPNotFound()
        row = dict(row)
        try: peer = self.peer(request)
        except ValueError: raise web.HTTPBadRequest(text='Invalid client IP.')
        self.allowed(row, peer)
        now = time.monotonic(); credits, at = self.rates.get(row['id'], (40., now))
        credits = min(40., credits+(now-at)*20.)
        self.rates[row['id']] = (max(0., credits-1), now)
        if credits < 1: raise web.HTTPTooManyRequests(headers={'Retry-After':'1'})
        try:
            if request.method == 'GET':
                encoded = request.query.get('dns','')
                if not re.fullmatch(r'[A-Za-z0-9_-]{1,5462}', encoded): raise ValueError('Invalid DNS encoding.')
                packet = base64.urlsafe_b64decode(encoded+'='*(-len(encoded)%4))
            else:
                if request.content_type != 'application/dns-message': raise web.HTTPUnsupportedMediaType()
                packet = await asyncio.wait_for(limited_body(request.content,4096),3)
            question(packet)
        except ValueError as exc: raise web.HTTPBadRequest(text=str(exc))
        except asyncio.TimeoutError: raise web.HTTPRequestTimeout(text='DNS body timed out.')
        try: await asyncio.wait_for(self.pool.acquire(), 0.1)
        except asyncio.TimeoutError: raise web.HTTPServiceUnavailable(headers={'Retry-After':'1'})
        try:
            # Reserve request bytes atomically before forwarding; a failed upstream
            # still used these inbound DNS bytes. No IP lock/expiry starts on a failed probe.
            row = self.row(row['id']); cfg = self.allowed(row,peer)
            if row['token'] != token: raise web.HTTPForbidden(text='Credential rotated.')
            if cfg['quota_bytes'] and row['used']+len(packet) > cfg['quota_bytes']:
                raise web.HTTPForbidden(text='DNS quota exhausted.')
            revision = row['revision']
            with self.db:
                self.db.execute('UPDATE clients SET used=used+?,queries=queries+1 WHERE id=?', (len(packet),row['id']))
            answer = await self.exchange(packet,row['agh_id'],peer)
            current = self.row(row['id'])
            # Reject responses if policy/credential changed while the query was in flight.
            if current['revision'] != revision: raise web.HTTPForbidden(text='Client settings changed; retry.')
            if current['expires'] and current['expires'] <= time.time(): raise web.HTTPForbidden(text='DNS client expired.')
            if cfg['ip_mode']=='first' and current['bound_ip'] and current['bound_ip']!=peer:
                raise web.HTTPForbidden(text='Client IP is not allowed.')
            if cfg['quota_bytes'] and current['used']+len(answer) > cfg['quota_bytes']:
                raise web.HTTPForbidden(text='DNS quota exhausted.')
            now = int(time.time()); started = current['started'] or now
            expires = current['expires'] or (started+cfg['days']*86400 if cfg['days'] else 0)
            bound = peer if cfg['ip_mode']=='first' else ''
            with self.db:
                self.db.execute('UPDATE clients SET used=used+?,started=?,expires=?,bound_ip=?,last_ip=?,last_seen=? WHERE id=?',
                                (len(answer),started,expires,bound,peer,now,row['id']))
            return web.Response(body=answer, content_type='application/dns-message', headers=HEADERS)
        finally:
            self.pool.release()
NODE_EMBEDDED_DNS_CLIENTS_PY_EOF

cat > "$STAGE/dns_clients.js" <<'NODE_EMBEDDED_DNS_CLIENTS_JS_EOF'
/* alirezapanel 1.3: on-demand DNS client console; no polling or extra framework. */
(() => {
  'use strict';
  const root=document.getElementById('alireza-dns-clients'), cfg=window.ALIREZA;
  if(!root || !cfg) return;
  const base=cfg.base, selected=new Set();
  let state={clients:[],plans:[],counts:{},total:0,page:1}, generation=0, searchTimer;
  const labels={active:'فعال',waiting:'منتظر اتصال',expired:'منقضی',quota:'سهمیه تمام شده',disabled:'غیرفعال',error:'نیاز به بررسی'};
  const n=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};
  const button=(text,fn,cls)=>{const el=n('button',text,cls);el.type='button';el.onclick=fn;return el;};
  const date=value=>value?new Date(value*1000).toLocaleString('fa-IR',{dateStyle:'medium',timeStyle:'short'}):'—';
  const bytes=value=>value>=1073741824?(value/1073741824).toFixed(2)+' GiB':value>=1048576?(value/1048576).toFixed(1)+' MiB':value>=1024?(value/1024).toFixed(1)+' KiB':value+' B';
  const defaults={name:'',days:30,quota_bytes:0,query_limit:0,start_on_first:true,ip_mode:'any',allowed_ip:'',resolver:'default',upstreams:[],ads:false,adult:false,safe_search:false};
  root.className='ap-dns';
  const tabs=n('nav',undefined,'ap-dns-tabs');tabs.setAttribute('aria-label','بخش‌های DNS');
  const clientTab=button('کلاینت‌ها',()=>tab(false),'is-selected'), advancedTab=button('تنظیمات پیشرفته DNS',()=>tab(true));
  tabs.append(clientTab,advancedTab);
  const consoleEl=n('section'), message=n('p',undefined,'ap-dns-message');message.setAttribute('role','status');message.setAttribute('aria-live','polite');
  root.append(tabs,message,consoleEl);
  function tab(advanced){
    const frame=document.getElementById('alireza-dns');
    consoleEl.hidden=advanced;frame.hidden=!advanced;
    clientTab.classList.toggle('is-selected',!advanced);advancedTab.classList.toggle('is-selected',advanced);
    if(advanced && !frame.getAttribute('src'))frame.src=frame.dataset.src;
  }
  const title=n('div',undefined,'ap-dns-heading'), titleText=n('div');
  titleText.append(n('span','DNS / CLIENTS','ap-dns-eyebrow'),n('h2','دسترسی روشن، مدیریت ساده'),n('p','کلاینت بساز، زمان و سهمیه بده، لینک اختصاصی را تحویل بده.'));
  const add=button('+ افزودن کلاینت',()=>editor(), 'ap-primary');title.append(titleText,add);
  const stats=n('div',undefined,'ap-dns-stats'), toolbar=n('div',undefined,'ap-dns-toolbar');
  const search=n('input');search.type='search';search.placeholder='جستجوی نام، شناسه یا IP کاربر';search.setAttribute('aria-label',search.placeholder);
  const refresh=button('تازه‌سازی',()=>load(1));
  const help=button('راهنمای اتصال',guide);
  toolbar.append(search,refresh,help);
  search.oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>load(1),250);};
  const bulk=n('div',undefined,'ap-dns-bulk'), bulkCount=n('span','۰ انتخاب'), bulkSelect=n('select');bulkSelect.setAttribute('aria-label','عملیات گروهی');
  for(const [value,label] of [['enable','فعال‌سازی'],['disable','قطع دسترسی'],['renew','تمدید روز'],['reset','بازنشانی مصرف'],['delete','حذف']]){const o=n('option',label);o.value=value;bulkSelect.append(o);}
  bulk.append(bulkCount,bulkSelect,button('اعمال روی انتخاب‌ها',()=>runAction([...selected],bulkSelect.value)));
  bulk.hidden=true;
  const tableWrap=n('div',undefined,'ap-dns-table-wrap'), table=n('table'), thead=n('thead'), header=n('tr');
  const all=n('input');all.type='checkbox';all.setAttribute('aria-label','انتخاب همین صفحه');const allCell=n('th');allCell.append(all);header.append(allCell);
  for(const title of ['کلاینت','وضعیت','مصرف DNS','انقضا','آخرین IP','مدیریت'])header.append(n('th',title));
  thead.append(header);const tbody=n('tbody');table.append(thead,tbody);tableWrap.append(table);
  all.onchange=()=>{for(const c of state.clients)all.checked?selected.add(c.id):selected.delete(c.id);renderRows();};
  const empty=n('div',undefined,'ap-dns-empty'), pager=n('div',undefined,'ap-dns-pager'), pageInfo=n('span');
  const previous=button('قبلی',()=>load(state.page-1)),next=button('بعدی',()=>load(state.page+1));pager.append(previous,pageInfo,next);
  const notice=n('details',undefined,'ap-dns-note');notice.append(n('summary','محدودهٔ اعمال سهمیه و شناسایی دستگاه'));
  notice.append(n('p','این محدودیت‌ها روی لینک اختصاصی DoH اعمال می‌شوند. DNS معمولی روی پورت ۵۳ و DoT/DoQ تنظیمات پیشرفته، سهمیهٔ این بخش را ندارند. حجم، مجموع بایت پیام‌های DNS است؛ حجم دانلود سایت‌ها نیست.'));
  notice.append(n('p','لینک اختصاصی یک رمز دسترسی است. IP فقط اتصال شبکه را مشخص می‌کند؛ چند دستگاه پشت مودم یک IP دارند و شبکهٔ موبایل می‌تواند IP را عوض کند. برای محدودیت بیشتر، لینک را محرمانه نگه دار و IP ثابت یا قفل اولین IP را انتخاب کن.'));
  consoleEl.append(title,stats,toolbar,bulk,tableWrap,empty,pager,notice);
  async function api(op,data){
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),90000);
    try{
      const res=await fetch(base+'_alireza/dns-clients/'+op,{method:data?'POST':'GET',credentials:'same-origin',cache:'no-store',signal:controller.signal,
        headers:{'Content-Type':'application/json','X-Alirezapanel-Request':'1'},body:data?JSON.stringify(data):undefined});
      const text=await res.text();let result;try{result=JSON.parse(text);}catch(_){throw Error('پاسخ نامعتبر؛ ورود و وضعیت سرویس DNS را بررسی کن.');}
      if(!res.ok)throw Error(result.msg||result.message||'درخواست انجام نشد.');return result;
    }finally{clearTimeout(timer);}
  }
  const error=e=>{message.textContent=e.name==='AbortError'?'پاسخ طول کشید؛ قبل از تکرار، فهرست را تازه کن.':e.message;message.classList.add('is-error');};
  async function load(page=state.page){
    const own=++generation;refresh.disabled=true;
    try{
      const result=await api('list?page='+Math.max(1,page)+'&q='+encodeURIComponent(search.value));if(own!==generation)return;
      state=result;selected.clear();message.classList.remove('is-error');message.textContent=!state.tls?'برای استفاده از DoH ابتدا HTTPS را با alirezapanel ssl فعال کن.':state.tls_mode==='ip'?'گواهی فعلی خودامضاست؛ برای اتصال معمولِ کلاینت‌ها، گواهی معتبر را با alirezapanel ssl فعال کن.':'';
      render();
    }catch(e){if(own===generation)error(e);}finally{if(own===generation)refresh.disabled=false;}
  }
  function render(){
    stats.replaceChildren();
    for(const [label,value] of [['کل کلاینت‌ها',Object.values(state.counts).reduce((a,b)=>a+b,0)],['فعال / آماده',(state.counts.active||0)+(state.counts.waiting||0)],['نیازمند تمدید',(state.counts.expired||0)+(state.counts.quota||0)],['قطع / نیاز به بررسی',(state.counts.disabled||0)+(state.counts.error||0)]]){
      const card=n('div');card.append(n('span',label),n('strong',Number(value).toLocaleString('fa-IR')));stats.append(card);
    }
    renderRows();pageInfo.textContent='صفحه '+state.page.toLocaleString('fa-IR')+' · '+state.total.toLocaleString('fa-IR')+' نتیجه';
    previous.disabled=state.page<=1;next.disabled=state.page*25>=state.total;
    empty.hidden=state.clients.length>0;tableWrap.hidden=!state.clients.length;
    empty.replaceChildren(n('h3',search.value?'کلاینتی پیدا نشد':'اولین کلاینت DNS را بساز'),n('p',search.value?'نام یا IP دیگری جستجو کن.':'مدت، سهمیه و روش محدودیت را انتخاب کن؛ لینک آمادهٔ اتصال تحویل می‌گیری.'));
  }
  function renderRows(){
    tbody.replaceChildren();
    for(const c of state.clients){
      const row=n('tr'),check=n('input');check.type='checkbox';check.checked=selected.has(c.id);check.setAttribute('aria-label','انتخاب '+c.config.name);
      check.onchange=()=>{check.checked?selected.add(c.id):selected.delete(c.id);selection();};
      const selectCell=n('td');selectCell.append(check);row.append(selectCell);
      const name=n('td'),who=n('div',undefined,'ap-dns-person'),avatar=n('span',c.config.name.slice(0,1),'ap-dns-avatar'),text=n('div');
      text.append(n('strong',c.config.name),n('small',c.config.resolver==='custom'?'DoH · DNS سفارشی':'DoH · DNS پیش‌فرض'));who.append(avatar,text);name.append(who);row.append(name);
      const status=n('td');status.append(n('span',labels[c.status]||c.status,'ap-dns-badge '+c.status));row.append(status);
      const usage=n('td'),progress=n('progress');progress.max=c.config.quota_bytes||1;progress.value=c.config.quota_bytes?Math.min(c.used,c.config.quota_bytes):0;progress.setAttribute('aria-label','مصرف سهمیه '+c.config.name);
      usage.append(n('div',bytes(c.used)+' / '+(c.config.quota_bytes?bytes(c.config.quota_bytes):'نامحدود'),'ap-dns-number'),progress,n('small',c.queries.toLocaleString('fa-IR')+' درخواست'+(c.config.query_limit?' / '+c.config.query_limit.toLocaleString('fa-IR'):'')));row.append(usage);
      row.append(n('td',c.expires?date(c.expires):!c.started&&c.config.days?c.config.days+' روز از اولین اتصال':'بدون انقضا'));
      const ip=n('td');ip.append(n('div',c.last_ip||'هنوز متصل نشده','ap-dns-number'),n('small',c.bound_ip?'قفل‌شده روی '+c.bound_ip:c.config.ip_mode==='fixed'?'مجاز: '+c.config.allowed_ip:date(c.last_seen)));row.append(ip);
      const actions=n('td'),group=n('div',undefined,'ap-dns-actions');group.append(button('اتصال',()=>connection(c.id),'ap-primary-soft'),button('ویرایش',()=>editor(c)),button('تمدید',()=>runAction([c.id],'renew')));actions.append(group);row.append(actions);tbody.append(row);
    }
    selection();
  }
  function selection(){bulk.hidden=!selected.size;bulkCount.textContent=selected.size.toLocaleString('fa-IR')+' انتخاب';all.checked=!!state.clients.length&&state.clients.every(c=>selected.has(c.id));all.indeterminate=selected.size>0&&!all.checked;}
  function dialog(title){
    const d=n('dialog',undefined,'ap-dns ap-dns-dialog');d.dir='rtl';const top=n('div',undefined,'ap-dns-dialog-top');const close=button('×',()=>d.close());close.setAttribute('aria-label','بستن');top.append(n('h3',title),close);d.append(top);
    d.addEventListener('close',()=>d.remove());document.body.append(d);d.showModal();return d;
  }
  function field(parent,label,type='text',value=''){
    const wrap=n('label',undefined,'ap-dns-field'),input=n(type==='select'?'select':type==='textarea'?'textarea':'input');
    if(type!=='select'&&type!=='textarea')input.type=type;
    input.value=value;wrap.append(n('span',label),input);parent.append(wrap);return input;
  }
  function options(el,items,value){for(const [v,t] of items){const o=n('option',t);o.value=v;el.append(o);}el.value=value;}
  function checkbox(parent,label,checked){const wrap=n('label',undefined,'ap-dns-check'),input=n('input');input.type='checkbox';input.checked=!!checked;wrap.append(input,n('span',label));parent.append(wrap);return input;}
  function editor(existing){
    const initial={...defaults,...existing?.config},d=dialog(existing?'ویرایش کلاینت DNS':'کلاینت جدید DNS'),form=n('form');d.append(form);
    const plan=field(form,'شروع از پلن آماده','select');options(plan,[['','تنظیم دلخواه'],['trial','آزمایشی · ۱ روز'],['month','ماهانه · ۳۰ روز'],...state.plans.map(p=>[p.id,p.name])],'');
    const grid=n('div',undefined,'ap-dns-form-grid');form.append(grid);
    const name=field(grid,'نام کلاینت','text',initial.name);name.required=true;name.maxLength=80;
    const days=field(grid,'مدت پلن (روز؛ صفر = بدون انقضا)','number',initial.days);days.min=0;days.max=3650;days.required=true;
    const quota=field(grid,'حجم پیام‌های DNS (MiB؛ صفر = نامحدود)','number',initial.quota_bytes/1048576);quota.min=0;quota.max=1000000;quota.step='0.001';quota.required=true;
    const queries=field(grid,'سقف تعداد درخواست (صفر = نامحدود)','number',initial.query_limit);queries.min=0;queries.max=1e12;queries.required=true;
    const ipMode=field(grid,'محدودیت دسترسی','select');options(ipMode,[['any','فقط لینک محرمانه'],['fixed','لینک + یک IP مشخص'],['first','لینک + قفل اولین IP موفق']],initial.ip_mode);
    const ip=field(grid,'IP عمومی مجاز (IPv4 / IPv6)','text',initial.allowed_ip);ip.dir='ltr';ip.placeholder='مثلاً 203.0.113.10';
    const start=checkbox(form,'شروع مدت از اولین اتصال موفق',initial.start_on_first);
    if(existing){start.disabled=true;days.disabled=true;form.append(n('p','ویرایش فیلتر و سهمیه، تاریخ فعلی را عوض نمی‌کند. برای تغییر مدت از دکمهٔ تمدید استفاده کن.','ap-dns-hint'));}
    const privacy=n('fieldset');privacy.append(n('legend','حفاظت محتوا'));
    const ads=checkbox(privacy,'فیلتر فهرست‌های تبلیغات و ردیابی',initial.ads),adult=checkbox(privacy,'فیلتر دامنه‌های بزرگسال',initial.adult),safe=checkbox(privacy,'جستجوی امن',initial.safe_search);
    privacy.append(n('p','تبلیغات به فهرست فعال در تنظیمات پیشرفته نیاز دارد. فیلتر DNS دامنه را مسدود می‌کند؛ پوشش تمام محتوای داخل برنامه‌ها تضمین نمی‌شود.','ap-dns-hint'));form.append(privacy);
    const resolver=field(form,'روش حل DNS','select');options(resolver,[['default','پیش‌فرض سرور'],['custom','DNS سفارشی / سرویس تحریم‌شکن']],initial.resolver);
    const upstream=field(form,'DNS سرویس انتخاب‌شده؛ هر خط یک IP یا آدرس DoH / DoT / DoQ','textarea',initial.upstreams.join('\n'));upstream.dir='ltr';upstream.rows=3;upstream.placeholder='https://resolver.example/dns-query';
    const hint=n('p','DNS سفارشی واقعاً به بالادستی انتخاب‌شده فرستاده و قبل از ذخیره تست می‌شود. رفع تحریم به پوشش و مجوز آن سرویس بستگی دارد؛ IP اتصال وب کاربر با DNS عوض نمی‌شود.','ap-dns-hint');form.append(hint);
    const restrictions=n('p','IP هویت سخت‌افزاری نیست. قفل اولین IP با تغییر شبکه نیاز به آزادسازی دارد؛ تمام دستگاه‌های پشت یک مودم می‌توانند یک IP داشته باشند.','ap-dns-hint');form.append(restrictions);
    const feedback=n('p');feedback.setAttribute('role','status');form.append(feedback);
    const actions=n('div',undefined,'ap-dns-dialog-actions');const save=button(existing?'ذخیره تغییرات':'ساخت و دریافت اتصال',null,'ap-primary');save.type='submit';
    const read=()=>({name:name.value.trim(),days:Number(days.value),quota_bytes:Math.round(Number(quota.value)*1048576),query_limit:Number(queries.value),start_on_first:start.checked,
      ip_mode:ipMode.value,allowed_ip:ip.value.trim(),ads:ads.checked,adult:adult.checked,safe_search:safe.checked,resolver:resolver.value,upstreams:upstream.value.split('\n').map(x=>x.trim()).filter(Boolean)});
    const test=button('تست DNS',async()=>{test.disabled=true;feedback.textContent='در حال تست…';try{feedback.textContent=(await api('test',read())).message;}catch(e){feedback.textContent=e.message;}finally{test.disabled=false;}});
    const storePlan=button('ذخیره به‌عنوان پلن',async()=>{if(!form.reportValidity())return;storePlan.disabled=true;try{await api('plan',read());feedback.textContent='پلن ذخیره شد؛ IP شخصی در پلن نگهداری نمی‌شود.';await load();}catch(e){feedback.textContent=e.message;}finally{storePlan.disabled=false;}});
    actions.append(save,test,storePlan);form.append(actions);
    if(existing){
      const more=n('details');more.append(n('summary','مدیریت دسترسی و مصرف'));
      const controls=n('div',undefined,'ap-dns-actions');
      for(const [action,label] of [[existing.enabled?'disable':'enable',existing.enabled?'قطع دسترسی':'فعال‌سازی'],['reset','بازنشانی مصرف'],['unbind','آزادسازی IP قفل‌شده'],['rotate','تعویض لینک محرمانه'],['delete','حذف کلاینت']])controls.append(button(label,()=>{d.close();runAction([existing.id],action);}));
      more.append(controls);d.append(more);
    }
    const dependencies=()=>{ip.parentElement.hidden=ipMode.value!=='fixed';ip.required=ipMode.value==='fixed';upstream.parentElement.hidden=resolver.value!=='custom';upstream.required=resolver.value==='custom';hint.hidden=resolver.value!=='custom';};
    ipMode.onchange=resolver.onchange=dependencies;dependencies();
    plan.onchange=()=>{
      const preset=state.plans.find(p=>p.id===plan.value)?.config || (plan.value==='trial'?{...defaults,days:1,query_limit:10000}:plan.value==='month'?{...defaults,days:30}:null);if(!preset)return;
      if(!existing){days.value=preset.days;start.checked=preset.start_on_first;}
      quota.value=preset.quota_bytes/1048576;queries.value=preset.query_limit;ads.checked=preset.ads;adult.checked=preset.adult;safe.checked=preset.safe_search;resolver.value=preset.resolver;upstream.value=preset.upstreams.join('\n');dependencies();
    };
    form.onsubmit=async e=>{e.preventDefault();save.disabled=true;feedback.textContent='در حال تست و ذخیره…';
      try{const result=await api('save',{...read(),...(existing?{id:existing.id,revision:existing.revision}:{})});d.close();await load();await connection(result.id,result);}
      catch(e){feedback.textContent=e.message+' اگر ذخیره نیمه‌تمام شد، فهرست را تازه و کلاینتِ نیازمند بررسی را دوباره ذخیره کن.';}finally{save.disabled=false;}};
    name.focus();
  }
  function runAction(ids,action){
    if(!ids.length)return;
    const names={enable:'فعال‌سازی',disable:'قطع دسترسی',renew:'تمدید',reset:'بازنشانی مصرف',unbind:'آزادسازی IP',rotate:'تعویض لینک',delete:'حذف'};
    const d=dialog(names[action]+' · '+ids.length+' کلاینت');
    d.append(n('p',action==='rotate'?'لینک قبلی فوراً غیرفعال می‌شود و باید لینک جدید را به کاربر بدهی.':action==='unbind'?'در حالت قفل اولین IP، درخواست موفق بعدی IP جدید را ثبت می‌کند.':action==='delete'?'دسترسی قطع و کلاینت حذف می‌شود.':action==='renew'?'روزها به زمان باقی‌مانده افزوده می‌شوند؛ برای کلاینت منقضی از امروز حساب می‌شود. سهمیه و وضعیت فعال‌بودن تغییر نمی‌کنند.':'این عملیات روی کلاینت‌های انتخاب‌شده اعمال می‌شود.'));
    let days;if(action==='renew'){days=field(d,'روز اضافه','number',30);days.min=1;days.max=3650;}
    const status=n('p');status.setAttribute('role','status');const submit=button('تأیید '+names[action],async()=>{
      if(days&&(!Number.isInteger(Number(days.value))||Number(days.value)<1||Number(days.value)>3650)){status.textContent='روز باید بین ۱ تا ۳۶۵۰ باشد.';return;}
      submit.disabled=true;
      try{await api('action',{ids,action,days:days?Number(days.value):30});d.close();await load();if(action==='rotate'&&ids.length===1)await connection(ids[0]);}
      catch(e){status.textContent=e.message+'؛ ممکن است بخشی از عملیات انجام شده باشد. فهرست را تازه کن.';await load();}finally{submit.disabled=false;}
    },'ap-primary');d.append(status,submit);
  }
  async function copy(text,feedback){try{await navigator.clipboard.writeText(text);feedback.textContent='کپی شد.';}catch(_){feedback.textContent='کپی خودکار در دسترس نیست؛ متن را انتخاب و کپی کن.';}}
  async function connection(id,known){
    const d=dialog('اتصال اختصاصی DNS');const status=n('p','در حال دریافت…');status.setAttribute('role','status');d.append(status);
    try{
      const c=known||await api('detail',{id});if(!d.isConnected)return;
      const url=location.origin+'/dns-query/'+c.token;
      status.textContent=c.config.name+' · '+labels[c.status];
      d.append(n('p','نوع اتصال: DNS-over-HTTPS · این لینک محرمانه است.'));
      const input=field(d,'لینک DoH','textarea',url);input.readOnly=true;input.dir='ltr';input.rows=3;
      const buttons=n('div',undefined,'ap-dns-actions');
      buttons.append(button('کپی لینک',()=>copy(url,status),'ap-primary'),button('دریافت کد تنظیمات',()=>{
        const content={name:c.config.name,protocol:'dns-over-https',url,note:'Use this URL in a DNS-over-HTTPS client. This JSON is a reference, not a universal VPN subscription.'};
        const object=URL.createObjectURL(new Blob([JSON.stringify(content,null,2)],{type:'application/json'})),link=n('a');link.href=object;link.download='alirezapanel-dns-'+c.id+'.json';link.click();setTimeout(()=>URL.revokeObjectURL(object),1000);
      }),button('کد QR',async()=>{
        try{if(!window.QRious){await new Promise((resolve,reject)=>{const script=n('script');script.src=base+'assets/qrcode/qrious2.min.js';script.onload=resolve;script.onerror=()=>reject(Error('بارگذاری QR ناموفق بود؛ از کپی لینک استفاده کن.'));document.head.append(script);});}
          qr.replaceChildren();const canvas=n('canvas');canvas.setAttribute('aria-label','QR لینک DNS محرمانه');qr.append(canvas);new QRious({element:canvas,value:url,size:240,level:'M'});
        }catch(e){status.textContent=e.message;}
      }));
      const qr=n('div',undefined,'ap-dns-qr');d.append(buttons,qr);
      d.append(n('p','لینک را در برنامه یا مرورگر پشتیبان DoH وارد کن. بخش Private DNS خودِ اندروید، نام میزبان DoT می‌خواهد و این لینک را نمی‌پذیرد. فایل JSON برای مشاهدهٔ تنظیمات است؛ لینک اشتراک VPN نیست.','ap-dns-hint'));
      d.append(n('p','گواهی HTTPS باید معتبر و مورد اعتماد دستگاه باشد. اگر پنل از پشت تونل باز می‌شود، همین مسیر /dns-query/ نیز باید به درگاه پنل برسد.','ap-dns-hint'));
    }catch(e){status.textContent=e.message;}
  }
  function guide(){const d=dialog('راهنمای کلاینت DNS');
    for(const text of ['۱. افزودن کلاینت را بزن؛ نام، روز و سهمیهٔ DNS را وارد کن. صفر یعنی بدون محدودیت.','۲. در صورت نیاز فیلتر و IP را انتخاب کن. IP ثابت باید IP عمومی کاربر باشد.','۳. از دکمهٔ اتصال، لینک یا QR را بگیر و در برنامهٔ دارای پشتیبانی DoH وارد کن.','۴. آخرین IP، مصرف و انقضا پس از درخواست واقعی نمایش داده می‌شوند. برای تمدید، انتخاب گروهی هم در دسترس است.','۵. برای تبلیغات، در تنظیمات پیشرفته یک فهرست مسدودسازی فعال کن. هر تغییر سراسری محافظت در همان بخش بر نتیجهٔ فیلترها اثر دارد.','۶. لینک محرمانه هویت سخت‌افزاری نیست و قابل اشتراک است. محدودیت این بخش به مسیر مدیریت‌شدهٔ DoH تعلق دارد.'])d.append(n('p',text));
    if(state.plans.length){d.append(n('h4','پلن‌های ذخیره‌شده'));for(const p of state.plans){const row=n('div',undefined,'ap-dns-actions');row.append(n('span',p.name),button('حذف پلن',async()=>{try{await api('plan',{id:p.id,delete:true});row.remove();await load();}catch(e){error(e);}}));d.append(row);}}
  }
  load(1);
})();
NODE_EMBEDDED_DNS_CLIENTS_JS_EOF

cat > "$STAGE/features.py" <<'NODE_EMBEDDED_FEATURES_PY_EOF'
"""Small, on-demand integrations. All traffic settings use the native API."""
import asyncio
import contextlib
import copy
import hashlib
import json
import re
from pathlib import Path
import ssl
import sqlite3
import time
import aiohttp
from aiohttp import web

FILTER_TAG = 'alirezapanel-content-block'
GAME_TAG = 'alirezapanel-game-direct'
GAME_OUTBOUND = {'tag': GAME_TAG, 'protocol': 'freedom', 'settings': {}}
CATEGORIES = {'ads': ('geosite:category-ads-all',), 'adult': ('geosite:category-porn',),
              'social': ('geosite:category-social-media-!cn', 'geosite:category-social-media-cn', 'geosite:category-social-media-ir'),
              'messengers': ('geosite:category-communication',), 'youtube': ('geosite:youtube',)}
FLAGS = tuple(CATEGORIES) + ('torrent', 'gaming')
SUPPORTED = {'vless', 'vmess', 'trojan', 'shadowsocks'}

def policy_key(email):
    return 'alireza-policy-' + hashlib.sha256(email.encode()).hexdigest()[:24]

def domains_list(value):
    if not isinstance(value, list) or len(value) > 100:
        raise ValueError('حداکثر ۱۰۰ دامنه می‌توان وارد کرد.')
    result = []
    for domain in value:
        if not isinstance(domain, str): raise ValueError('دامنه نامعتبر است.')
        domain = domain.strip().rstrip('.').lower().encode('idna').decode('ascii')
        if len(domain) > 253 or '.' not in domain or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', part) for part in domain.split('.')):
            raise ValueError('فقط نام دامنه وارد کن؛ بدون آدرس صفحه، wildcard یا عبارت منظم.')
        import ipaddress
        try: ipaddress.ip_address(domain)
        except ValueError: pass
        else: raise ValueError('در فهرست دامنه، IP وارد نکن.')
        if domain not in result: result.append(domain)
    return result

def policies(config, email):
    result = {key: False for key in FLAGS}; result['domains'] = []
    key = policy_key(email)
    for rule in config.get('routing', {}).get('rules', []):
        if rule.get('user') != [email]: continue
        tag = rule.get('ruleTag')
        if tag == key and rule.get('outboundTag') == FILTER_TAG:
            for flag, domains in CATEGORIES.items():
                result[flag] = all(d in rule.get('domain', []) for d in domains)
            result['domains'] = [d[7:] for d in rule.get('domain', []) if d.startswith('domain:')]
        elif tag == key+'-torrent' and rule.get('outboundTag') == FILTER_TAG:
            result['torrent'] = rule.get('protocol') == ['bittorrent']
        elif tag == key+'-gaming' and rule.get('outboundTag') == GAME_TAG:
            result['gaming'] = rule.get('network') == 'udp'
    return result

def apply_policy(config, email, choices):
    result = copy.deepcopy(config); current = policies(config,email)
    current.update(choices); choices = current
    routing = result.setdefault('routing', {}); rules = routing.setdefault('rules', [])
    key = policy_key(email); owned = {key,key+'-torrent',key+'-gaming'}
    # Only remove rules for this exact identity, never an operator's unrelated rule.
    routing['rules'] = [r for r in rules if not (r.get('ruleTag') in owned and r.get('user') == [email])]
    domains = [domain for flag, group in CATEGORIES.items() if choices.get(flag) for domain in group]
    domains += ['domain:'+d for d in domains_list(choices.get('domains', []))]
    outbounds = result.setdefault('outbounds', [])
    if not outbounds and (domains or choices.get('torrent') or choices.get('gaming')):
        raise ValueError('ابتدا یک خروجی پیش‌فرض معتبر در تنظیمات Xray تعریف کن؛ ترتیب خروجی‌ها خودکار تغییر نمی‌کند.')
    if domains or choices.get('torrent'):
        existing = next((o for o in outbounds if o.get('tag') == FILTER_TAG), None)
        if existing and existing.get('protocol') != 'blackhole':
            raise ValueError('The content-filter outbound tag is already in use.')
        if existing is None: outbounds.append({'tag': FILTER_TAG, 'protocol': 'blackhole', 'settings': {}})
        if choices.get('torrent'):
            routing['rules'].insert(0, {'type':'field','ruleTag':key+'-torrent','user':[email],
                                       'protocol':['bittorrent'],'outboundTag':FILTER_TAG})
        if domains:
            routing['rules'].insert(0, {'type':'field','ruleTag':key,'user':[email],'domain':domains,'outboundTag':FILTER_TAG})
    if choices.get('gaming'):
        existing = next((o for o in outbounds if o.get('tag') == GAME_TAG), None)
        if existing is not None and existing != GAME_OUTBOUND:
            raise ValueError('Gaming outbound tag conflicts with an existing custom configuration.')
        if existing is None: outbounds.append(copy.deepcopy(GAME_OUTBOUND))
        # Existing rules retain priority, including security, tunnel and DNS routes.
        # Only otherwise-unmatched UDP gets this optional direct egress. Exclude DNS.
        routing['rules'].append({'type':'field','ruleTag':key+'-gaming','user':[email],
                                'network':'udp','port':'1-52,54-65535','outboundTag':GAME_TAG})
    elif not any(r.get('outboundTag') == GAME_TAG for r in routing['rules']):
        # Leave manually customized or referenced outbounds alone.
        serialized = json.dumps({k:v for k,v in result.items() if k not in ('outbounds','routing')})
        references = json.dumps([o for o in outbounds if o != GAME_OUTBOUND]) + serialized
        if GAME_TAG not in references and GAME_TAG not in json.dumps(routing.get('balancers', [])):
            result['outbounds'] = [o for o in outbounds if o != GAME_OUTBOUND]
    return result

class Features:
    def __init__(self, gateway):
        self.g = gateway
        self.lock = asyncio.Lock()

    async def native(self, request, method, path, data=None):
        from nodes import bounded
        base, origin, tls = self.g.vpn_settings()
        async with self.g.vpn.request(method, origin+base+path, data=data, ssl=tls,
            headers={'Cookie': request.headers.get('Cookie', ''), 'Host': request.host,
                     'Accept-Encoding': 'identity', 'X-Requested-With': 'XMLHttpRequest'},
            allow_redirects=False, timeout=aiohttp.ClientTimeout(total=120)) as response:
            raw = await bounded(response)
            try:
                obj = json.loads(raw)
            except ValueError:
                raise web.HTTPBadGateway(text='Native API returned an invalid response.')
            if response.status != 200 or obj.get('success') is not True:
                raise web.HTTPBadGateway(text=str(obj.get('msg') or 'Native API failed.')[:400])
            return obj.get('obj')

    async def configuration(self, request):
        obj = await self.native(request, 'POST', 'panel/xray/')
        if isinstance(obj, str): obj = json.loads(obj)
        config = obj['xraySetting']
        if isinstance(config, str): config = json.loads(config)
        return config, obj.get('outboundTestUrl', '')

    async def route(self, request, relative):
        if relative == '_alireza/features.js':
            return web.FileResponse(self.g.root/'features.js', headers={'Cache-Control':'no-cache'})
        if not relative.startswith('_alireza/features/'):
            return None
        await self.g.nodes.admin(request)
        operation = relative.rsplit('/', 1)[-1]
        if request.method == 'GET' and operation == 'tls':
            cert = ssl._ssl._test_decode_cert(self.g.config['tls_cert'])
            return web.json_response({'host': self.g.config['host'],
                'enabled': self.g.config.get('tls_enabled', True),
                'mode': self.g.config.get('tls_mode', 'ip'),
                'expires': cert['notAfter'], 'cert': self.g.config['tls_cert'],
                'key': self.g.config['tls_key']}, headers={'Cache-Control':'no-store'})
        if operation == 'client-usage' and request.method == 'POST':
            data = await self.g.nodes.body(request)
            email = data.get('email')
            if not isinstance(email, str) or not email or len(email) > 254:
                raise web.HTTPBadRequest(text='شناسه / ایمیل کلاینت را وارد کن.')
            uri = Path(self.g.config['vpn_db']).resolve().as_uri()+'?mode=ro'
            rows=[]
            with contextlib.closing(sqlite3.connect(uri,uri=True,timeout=2)) as db:
                db.row_factory=sqlite3.Row
                tables={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if 'client_traffics' in tables:
                    cols={r[1] for r in db.execute('PRAGMA table_info(client_traffics)')}
                    wanted=[c for c in ('id','inbound_id','enable','email','up','down','expiry_time','total','reset') if c in cols]
                    if 'email' in cols:
                        q='SELECT '+','.join(wanted)+' FROM client_traffics WHERE email=? ORDER BY '+('inbound_id' if 'inbound_id' in cols else 'email')
                        rows=[dict(r) for r in db.execute(q,(email,))]
            inbounds = await self.native(request, 'GET', 'panel/api/inbounds/list')
            memberships=[]; client_meta=[]
            for inbound in inbounds or []:
                settings=inbound.get('settings') or '{}'; settings=json.loads(settings) if isinstance(settings,str) else settings
                for c in settings.get('clients',[]):
                    if c.get('email')==email:
                        memberships.append({'id':inbound.get('id'),'remark':inbound.get('remark') or ('Inbound '+str(inbound.get('id'))),'protocol':inbound.get('protocol')})
                        client_meta.append({k:c.get(k) for k in ('email','enable','expiryTime','totalGB','subId','limitIp') if k in c})
            if not memberships and not rows: raise web.HTTPNotFound(text='کلاینت پیدا نشد.')
            up=sum(max(0,int(r.get('up') or 0)) for r in rows); down=sum(max(0,int(r.get('down') or 0)) for r in rows)
            limit=max([int(r.get('total') or 0) for r in rows]+[int(c.get('totalGB') or 0) for c in client_meta]+[0])
            expiry=max([int(r.get('expiry_time') or 0) for r in rows]+[int(c.get('expiryTime') or 0) for c in client_meta]+[0])
            return web.json_response({'success':True,'source':'vpn-ui native client_traffics','email':email,'up':up,'down':down,'used':up+down,
                'total':limit,'expiry':expiry,'memberships':memberships,'records':rows,'clients':client_meta},headers={'Cache-Control':'no-store'})
        if operation != 'policy' or request.method != 'POST':
            raise web.HTTPNotFound()
        data = await self.g.nodes.body(request)
        email = data.get('email')
        if not isinstance(email, str) or not email or len(email) > 254 or email.startswith('regexp:') or any(ord(c)<32 for c in email):
            raise web.HTTPBadRequest(text='Choose a saved client first.')
        async with self.lock:
            original, test_url = await self.configuration(request)
            if data.get('read') is True:
                return web.json_response(dict(policies(original, email), policy_version=2), headers={'Cache-Control':'no-store'})
            choices = policies(original,email)
            for key in FLAGS:
                if key in data:
                    if type(data[key]) is not bool: raise web.HTTPBadRequest(text='Policy choices must be boolean.')
                    choices[key] = data[key]
            try: choices['domains'] = domains_list(data.get('domains',choices['domains']))
            except (ValueError, UnicodeError) as exc: raise web.HTTPBadRequest(text=str(exc))
            enabled = any(choices[k] for k in FLAGS) or bool(choices['domains'])
            inbounds = await self.native(request, 'GET', 'panel/api/inbounds/list')
            found = []
            for inbound in inbounds or []:
                settings = inbound.get('settings') or '{}'
                if isinstance(settings, str): settings = json.loads(settings)
                if any(c.get('email') == email for c in settings.get('clients', [])):
                    found.append(inbound)
            if not found and enabled:
                raise web.HTTPBadRequest(text='Save the client on an inbound before applying filters.')
            if any(i.get('protocol') not in SUPPORTED for i in found) and enabled:
                raise web.HTTPBadRequest(text='این کنترل‌ها فقط برای کلاینت Xray در VLESS، VMess، Trojan و Shadowsocks تأیید شده‌اند. پروتکل دیگر تغییر نکرد.')
            needs_sniff = any(choices[k] for k in CATEGORIES) or choices['domains'] or choices['torrent']
            if needs_sniff:
                for inbound in found:
                    sniff = inbound.get('sniffing') or {}
                    if isinstance(sniff,str): sniff = json.loads(sniff)
                    if not sniff.get('enabled') or not {'http','tls'} <= set(sniff.get('destOverride', [])) or sniff.get('metadataOnly'):
                        raise web.HTTPBadRequest(text='برای فیلتر واقعی، Sniffing اینباند را با HTTP و TLS روشن و metadataOnly را خاموش کن؛ سپس دوباره اعمال کن. تشخیص QUIC و تورنت رمزگذاری‌شده محدود است.')
            if choices['gaming'] and original.get('outbounds') and original['outbounds'][0].get('protocol') == 'blackhole':
                raise web.HTTPBadRequest(text='خروجی پیش‌فرض مسدود است؛ Gaming مسیر مسدود پیش‌فرض را دور نمی‌زند.')
            try: updated = apply_policy(original, email, choices)
            except ValueError as exc: raise web.HTTPBadRequest(text=str(exc))
            if updated == original:
                return web.json_response({'success': True, 'changed': False, 'policy_version': 2})
            latest, _ = await self.configuration(request)
            if latest != original:
                raise web.HTTPConflict(text='تنظیمات Xray هم‌زمان تغییر کرد؛ دوباره بخوان و اعمال کن.')
            # Persist a recovery checkpoint before calling the native validator.
            self.g.nodes.state['policy_backup'] = {'time': int(time.time()), 'config': original}
            self.g.nodes.save()
            await self.native(request, 'POST', 'panel/xray/update',
                              {'xraySetting': json.dumps(updated), 'outboundTestUrl': test_url})
            try:
                await self.native(request, 'POST', 'panel/api/server/restartXrayService')
            except (web.HTTPException, aiohttp.ClientError, asyncio.TimeoutError):
                # Do not overwrite an intervening edit from the native settings page.
                current, _ = await self.configuration(request)
                if current != updated:
                    raise web.HTTPConflict(text='Settings changed concurrently; inspect Xray settings. Recovery checkpoint retained.')
                await self.native(request, 'POST', 'panel/xray/update',
                                  {'xraySetting': json.dumps(original), 'outboundTestUrl': test_url})
                await self.native(request, 'POST', 'panel/api/server/restartXrayService')
                raise web.HTTPBadGateway(text='Filter could not start; previous configuration restored.')
            warnings = []
            if choices['gaming']:
                warnings.append('Gaming فقط خروج UDP بدون قانون قبلی را مستقیم می‌کند؛ UDP پورت ۵۳ و مسیرهای صریح حفظ می‌شوند. کاهش پینگ تضمینی نیست.')
                if original.get('outbounds') and original['outbounds'][0].get('protocol') == 'freedom':
                    warnings.append('خروجی پیش‌فرض از قبل freedom است؛ اگر مسیر اضافه‌ای ندارد، این حالت مسیر کوتاه‌تری ایجاد نمی‌کند.')
            return web.json_response({'success': True, 'changed': True, 'warnings': warnings, 'policy_version': 2})

    def defaults(self, data, request):
        """Offer the public gateway certificate to the original native form."""
        obj = data.get('obj')
        if data.get('success') is not True or not isinstance(obj, dict): return data
        if 'defaultCert' in obj and self.g.config.get('tls_enabled', True):
            cert_path, key_path = self.g.config['tls_cert'], self.g.config['tls_key']
            if not obj.get('defaultCert') and not obj.get('defaultKey'):
                obj['defaultCert'], obj['defaultKey'] = cert_path, key_path
            cert = ssl._ssl._test_decode_cert(cert_path)
            choices = obj.setdefault('sslCertificates', [])
            if not any(c.get('profile') == 'alirezapanel' for c in choices):
                choices.insert(0, {'profile': 'alirezapanel', 'label': 'alirezapanel · '+self.g.config['host'],
                    'covers': [self.g.config['host']], 'expired': ssl.cert_time_to_seconds(cert['notAfter']) <= time.time(),
                    'selfSigned': cert.get('issuer') == cert.get('subject'), 'certPath': cert_path, 'keyPath': key_path})
        # Serve supported subscriptions over the SAME TLS gateway as the panel.
        # An explicitly configured subscription/bridge origin is the operator's
        # choice and must survive repair and ordinary page loads.
        uri = Path(self.g.config['vpn_db']).resolve().as_uri()+'?mode=ro'
        with contextlib.closing(sqlite3.connect(uri,uri=True,timeout=2)) as db:
            configured = dict(db.execute("SELECT key,value FROM settings WHERE key IN ('subURI','subJsonURI','subClashURI')"))
        origin = request.scheme+'://'+request.host
        for key, kind in (('subURI','links'), ('subJsonURI','json'), ('subClashURI','clash')):
            if not configured.get(key): obj[key] = origin+'/_alireza/native-sub/'+kind+'/'
        return data
NODE_EMBEDDED_FEATURES_PY_EOF

cat > "$STAGE/features.js" <<'NODE_EMBEDDED_FEATURES_JS_EOF'
/* On-demand client controls. No framework, timer or dashboard changes. */
(() => {
  'use strict';
  const cfg=window.ALIREZA;
  if(!cfg || cfg.dns) return;
  if(/\/panel\/clients\/?$/.test(location.pathname)) document.documentElement.setAttribute('data-alireza-clients','');
  if(typeof PERMS==='undefined' || !PERMS.superAdmin) return;
  document.documentElement.setAttribute('data-alireza-admin','');
  const base=cfg.mount || cfg.base;
  const pending=new Map();
  const message=(s,error=false)=>{if(typeof Vue!=='undefined') Vue.prototype.$message[error?'error':'success'](s,8);else alert(s);};
  async function api(op,data){
    if(op==='policy' && data && !data.read)await api('policy',{email:data.email,read:true});
    const r=await fetch(base+'_alireza/features/'+op,{method:data?'POST':'GET',credentials:'same-origin',cache:'no-store',
      headers:{'Content-Type':'application/json','X-Alirezapanel-Request':'1'},body:data?JSON.stringify(data):undefined});
    if(!r.ok){let t=await r.text();try{const j=JSON.parse(t);t=j.msg||j.message||t;}catch(_){}throw Error(t.slice(0,400));}
    const result=await r.json();
    if(op==='policy' && result.policy_version!==2)throw Error('این سرور کنترل‌های جدید را پشتیبانی نمی‌کند؛ install.sh --repair را روی همان نود هم اجرا کن.');
    return result;
  }
  // Fill ONLY an empty certificate on a NEW inbound after the operator selects
  // TLS. Existing certificates, inline PEM, Reality and protocol choice stay native.
  if(typeof inboundModalVueInstance!=='undefined' && inboundModalVueInstance && typeof app!=='undefined'){
    const vm=inboundModalVueInstance;
    vm.$watch(()=>{
      const stream=vm.inbound?.stream;
      return (stream?.security||'')+'|'+!!vm.inModal?.isEdit+'|'+(app.defaultCert||'');
    },()=>{
      const stream=vm.inbound?.stream;
      if(vm.inModal?.isEdit || stream?.security!=='tls')return;
      const choice=(app.sslCertificates||[]).find(c=>c.profile==='alirezapanel'&&!c.selfSigned&&!c.expired);
      const cert=stream.tls?.certs?.[0];
      if(!choice || !cert || !cert.useFile || cert.certFile || cert.keyFile || cert.cert || cert.key)return;
      cert.certFile=choice.certPath;cert.keyFile=choice.keyPath;cert.oneTimeLoading=false;
      const host=choice.covers?.[0]||'';
      if(!stream.tls.sni && host && !/^\d{1,3}(\.\d{1,3}){3}$/.test(host))stream.tls.sni=host;
    },{immediate:true});
  }
  function node(tag,text){const n=document.createElement(tag);if(text)n.textContent=text;return n;}
  async function editor(email,queue){
    const dialog=node('dialog');dialog.className='alireza-policy-dialog';dialog.dir='rtl';
    const title=node('h3','فیلتر و حالت گیمینگ کلاینت');const who=node('input');who.value=email||'';who.placeholder='شناسه / ایمیل کلاینت';who.readOnly=!!email;who.setAttribute('aria-label','شناسه کلاینت');
    const status=node('p');status.setAttribute('role','status');
    const info=node('p','فیلتر دامنه برای همین کاربر روی سرور انتخاب‌شده اعمال می‌شود. نیاز به دیتای geosite دارد؛ پوشش همهٔ محتوا یا ترافیک رمزگذاری‌شده تضمین نمی‌شود. فقط VLESS / VMess / Trojan / Shadowsocks هستهٔ Xray پشتیبانی می‌شوند. Sniffing HTTP/TLS باید روشن باشد. تغییر تنظیمات هسته ممکن است اتصال‌ها را کوتاه قطع کند.');
    const inputs={};dialog.append(title,who,info);
    for(const [key,label] of [['adult','مسدودسازی محتوای بزرگسال'],['ads','مسدودسازی تبلیغات'],['social','مسدودسازی شبکه‌های اجتماعی'],['messengers','مسدودسازی پیام‌رسان‌ها / ارتباطات'],['youtube','مسدودسازی یوتیوب'],['torrent','مسدودسازی تورنت قابل تشخیص']]){
      const row=node('label');const input=node('input');input.type='checkbox';inputs[key]=input;row.append(input,document.createTextNode(label));dialog.append(row);
    }
    const customLabel=node('label','دامنه‌های مسدود دلخواه؛ هر خط یک دامنه (همراه زیردامنه‌ها)');
    const custom=node('textarea');custom.rows=3;custom.dir='ltr';custom.placeholder='example.com';custom.setAttribute('aria-label','دامنه‌های مسدود دلخواه');customLabel.append(custom);dialog.append(customLabel);
    const gameBox=node('section');gameBox.className='alireza-game-box';
    const game=node('button','Gaming Mode · خاموش');game.type='button';game.setAttribute('aria-pressed','false');
    let gaming=false;
    const setGaming=value=>{gaming=!!value;game.setAttribute('aria-pressed',String(gaming));game.textContent='Gaming Mode · '+(gaming?'روشن':'خاموش');};
    game.onclick=()=>setGaming(!gaming);
    gameBox.append(game,node('p','خروج مستقیم UDP فقط برای این کاربر، پس از قوانین موجود. می‌تواند مسیر اضافهٔ خروجی سرور را حذف کند؛ روی مسیر از قبل مستقیم لزوماً اثری ندارد. پینگ تضمینی نیست. IP خروج UDP می‌تواند عوض شود. UDP پورت ۵۳، تونل و قوانین صریح دست‌نخورده می‌مانند؛ پشتیبانی UDP در برنامهٔ کاربر لازم است. بدون سرویس اضافه یا افزایش بافر.'));
    dialog.append(gameBox);
    const save=node('button',queue?'ذخیره همراه کلاینت':'اعمال فیلتر');save.type='button';
    const cancel=node('button','بستن');cancel.type='button';cancel.onclick=()=>dialog.close();
    const read=async()=>{save.disabled=true;status.textContent='در حال خواندن تنظیمات…';try{
      const p=pending.get(who.value.trim()) || await api('policy',{email:who.value.trim(),read:true});
      Object.keys(inputs).forEach(k=>{inputs[k].checked=!!p[k];});custom.value=(p.domains||[]).join('\n');setGaming(p.gaming);status.textContent='';
    }catch(e){status.textContent=e.message;}finally{save.disabled=false;}};
    who.onchange=read;
    save.onclick=async()=>{const name=who.value.trim();if(!name){status.textContent='شناسه کلاینت را وارد کن.';return;}
      const choice={email:name,...Object.fromEntries(Object.entries(inputs).map(([k,v])=>[k,v.checked])),domains:custom.value.split('\n').map(v=>v.trim()).filter(Boolean),gaming};save.disabled=true;
      try{if(queue){pending.set(name,choice);message('انتخاب شد؛ برای اعمال فیلتر دکمهٔ ذخیرهٔ کلاینت را بزن.');}
        else{status.textContent='در حال اعتبارسنجی و اعمال؛ ممکن است دانلود دیتای فیلتر زمان ببرد…';const result=await api('policy',choice);pending.delete(name);message('تنظیمات روی سرور اعمال شد.'+(result.warnings?.length?' '+result.warnings.join(' '):''));}
        dialog.close();
      }catch(e){status.textContent=e.message;}finally{save.disabled=false;}};
    dialog.append(status,save,cancel);dialog.addEventListener('close',()=>dialog.remove());document.body.append(dialog);dialog.showModal();if(email)await read();
  }
  document.addEventListener('click',e=>{const b=e.target.closest('[data-alireza-policy]');if(b){e.preventDefault();editor(b.dataset.email||'',true);}});
  // Native account writes remain native; apply only explicitly queued choices
  // after a successful save. A failed second operation is reported separately.
  if(typeof axios!=='undefined') axios.interceptors.response.use(async response=>{
    const url=String(response.config.url||'');
    if(!response.data || response.data.success!==true || !/\/inbounds\/(addClient|updateClient\/|add$|update\/|saveAccount)/.test(url) || !pending.size) return response;
    let form=response.config.data;
    if(typeof form==='string') form=Object.fromEntries(new URLSearchParams(form));
    else if(form instanceof FormData) form=Object.fromEntries(form.entries());
    const emails=new Set();
    if(form && form.email) emails.add(form.email);
    try{const s=typeof form.settings==='string'?JSON.parse(form.settings):form.settings;for(const c of s?.clients||[])if(c.email)emails.add(c.email);}catch(_){}
    for(const email of emails){const choice=pending.get(email);if(!choice)continue;
      try{const result=await api('policy',choice);pending.delete(email);message('کلاینت و تنظیمات آن ذخیره شدند.'+(result.warnings?.length?' '+result.warnings.join(' '):''));}
      catch(e){message('کلاینت ذخیره شد، ولی فیلتر فعال نشد: '+e.message+' — از دکمهٔ فیلتر کلاینت دوباره اقدام کن.',true);}
    }
    return response;
  });
  const fmt=n=>{n=Number(n||0);const u=['B','KB','MB','GB','TB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return (n<10&&i?n.toFixed(2):n<100&&i?n.toFixed(1):Math.round(n))+' '+u[i];};
  async function usageDialog(){const d=node('dialog');d.className='alireza-usage-dialog';d.dir='rtl';const q=node('input');q.placeholder='شناسه / ایمیل کلاینت';q.dir='ltr';const go=node('button','نمایش گزارش');const close=node('button','بستن');close.onclick=()=>d.close();const out=node('div');d.append(node('h3','گزارش واقعی مصرف هر کاربر'),q,go,out,close);document.body.append(d);d.addEventListener('close',()=>d.remove());d.showModal();go.onclick=async()=>{go.disabled=true;out.textContent='در حال خواندن شمارنده‌های واقعی vpn-ui…';try{const x=await api('client-usage',{email:q.value.trim()});out.textContent='';const cards=node('div');cards.className='alireza-stat-grid';for(const [a,b] of [['دانلود',fmt(x.down)],['آپلود',fmt(x.up)],['مصرف کل',fmt(x.used)],['سقف',x.total?fmt(x.total):'نامحدود']]){const c=node('section');c.append(node('small',a),node('strong',b));cards.append(c);}out.append(cards);const max=Math.max(x.down,x.up,1),chart=node('div');chart.className='alireza-bars';for(const [label,val] of [['دانلود',x.down],['آپلود',x.up]]){const r=node('div'),track=node('i'),fill=node('b');fill.style.width=(val/max*100).toFixed(1)+'%';track.append(fill);r.append(node('span',label+' · '+fmt(val)),track);chart.append(r);}out.append(chart,node('p','منبع: جدول native client_traffics خود vpn-ui؛ عدد ساختگی یا packet capture اضافه وجود ندارد.'));const list=node('div');list.className='alireza-log-list';for(const r of x.records||[]){const row=node('div');row.append(node('strong','Inbound '+(r.inbound_id??'—')),node('span','↓ '+fmt(r.down)+'  ↑ '+fmt(r.up)),node('span',r.enable===false?'غیرفعال':'فعال'));list.append(row);}out.append(list);}catch(e){out.textContent=e.message;}finally{go.disabled=false;}};}
  async function subStudio(){const d=node('dialog');d.className='alireza-sub-dialog';d.dir='rtl';const q=node('input');q.placeholder='شناسه / ایمیل کلاینت';q.dir='ltr';const go=node('button','ساخت نمای اشتراک'),body=node('div'),close=node('button','بستن');close.onclick=()=>d.close();d.append(node('h3','Subscription Studio'),node('p','نمای حرفه‌ای اشتراک و مصرف، بدون تغییر فرمت native subscription.'),q,go,body,close);document.body.append(d);d.addEventListener('close',()=>d.remove());d.showModal();go.onclick=async()=>{go.disabled=true;body.textContent='در حال آماده‌سازی…';try{const x=await api('client-usage',{email:q.value.trim()});body.textContent='';const hero=node('section');hero.className='alireza-sub-hero';hero.append(node('small','ALIREZAPANEL SUBSCRIPTION'),node('h2',x.email),node('p',x.expiry?'اعتبار تا '+new Date(x.expiry).toLocaleDateString('fa-IR'):'بدون تاریخ انقضای ثبت‌شده'));body.append(hero);const pct=x.total?Math.min(100,x.used/x.total*100):0,ring=node('div');ring.className='alireza-ring';ring.style.setProperty('--p',pct.toFixed(1));ring.innerHTML='<div><strong>'+(x.total?pct.toFixed(1)+'٪':'∞')+'</strong><small>مصرف</small></div>';body.append(ring);const stats=node('div');stats.className='alireza-stat-grid';for(const [a,b] of [['مصرف',fmt(x.used)],['باقی‌مانده',x.total?fmt(Math.max(0,x.total-x.used)):'نامحدود'],['دانلود',fmt(x.down)],['آپلود',fmt(x.up)]]){const c=node('section');c.append(node('small',a),node('strong',b));stats.append(c);}body.append(stats);const ids=[...new Set((x.clients||[]).map(c=>c.subId).filter(Boolean))];if(ids.length){const box=node('section');box.className='alireza-sub-links';box.append(node('h4','شناسه‌های Subscription'));for(const id of ids){const line=node('div'),code=node('code',id),cp=node('button','کپی');cp.onclick=()=>navigator.clipboard.writeText(id).then(()=>message('کپی شد'));line.append(code,cp);box.append(line);}body.append(box);}}catch(e){body.textContent=e.message;}finally{go.disabled=false;}};}
  if(!/\/panel\/(clients|inbounds|core)\/?$/.test(location.pathname))return;
  const main=document.querySelector('.bo-content');if(!main)return;
  const bar=node('div');bar.className='alireza-client-tools';
  const policy=node('button','فیلتر / گیمینگ');policy.type='button';policy.onclick=()=>editor('',false);
  const tls=node('button','گواهی و اتصال');tls.type='button';tls.onclick=async()=>{tls.disabled=true;try{
    const d=await api('tls');alert('alirezapanel\n'+d.host+'\n'+(d.enabled?'HTTPS':'HTTP')+' · '+d.mode+'\nانقضا: '+d.expires+'\nدر فرم TLS اینباند، گواهی alirezapanel را انتخاب کن. دامنه/SNI باید با گواهی مطابقت داشته باشد.\nمدیریت از ترمینال: sudo alirezapanel ssl');
  }catch(e){message(e.message,true);}finally{tls.disabled=false;}};
  const usage=node('button','لاگ / مصرف کاربر');usage.type='button';usage.onclick=usageDialog;const sub=node('button','Subscription Studio');sub.type='button';sub.onclick=subStudio;
  const dns=node('a','مدیریت DNS');dns.href=cfg.base+'panel/dns';bar.append(policy,usage,sub,tls,dns);main.prepend(bar);
})();
NODE_EMBEDDED_FEATURES_JS_EOF

cat > "$STAGE/tls.py" <<'NODE_EMBEDDED_TLS_PY_EOF'
#!/usr/bin/env python3
"""Root-only certificate lifecycle; no resident ACME process."""
import argparse
import contextlib
import fcntl
import grp
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import time

ETC = Path('/etc/alirezapanel')
ROOT = Path('/opt/alirezapanel')

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def atomic_json(path, obj, mode=0o640):
    fd, tmp = tempfile.mkstemp(prefix='.tls-', dir=path.parent)
    try:
        with os.fdopen(fd,'w') as out:
            json.dump(obj,out,indent=2); out.flush(); os.fsync(out.fileno())
        os.chmod(tmp,mode)
        if path.exists():
            st=path.stat(); os.chown(tmp,st.st_uid,st.st_gid)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def host_name(value, mode):
    value=value.strip().rstrip('.').lower()
    if not value or '://' in value or '/' in value or '\n' in value:
        raise ValueError('Enter a domain or public IP only; no scheme, path or port.')
    try: address=ipaddress.ip_address(value)
    except ValueError: address=None
    if mode=='domain':
        if address is not None or len(value)>253 or '.' not in value or any(
            not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',s) for s in value.split('.')):
            raise ValueError('Enter a valid DNS domain, for example panel.example.com.')
    elif mode=='ip-acme':
        if address is None or address.version != 4 or not address.is_global:
            raise ValueError('IP certificates require a globally reachable public IPv4 address on this installer.')
    elif address is None:
        host_name(value,'domain')
    return value

def certbot(ip=False):
    binary=shutil.which('certbot')
    if binary:
        help_text=subprocess.check_output([binary,'--help','all'],text=True)
        if not ip or '--ip-address' in help_text: return binary
    if not ip:
        run(['apt-get','install','-y','--no-install-recommends','certbot'])
        return shutil.which('certbot')
    # Debian/Ubuntu's older Certbot cannot issue IP certificates. An isolated,
    # versioned CLI adds no running daemon and does not alter system Python.
    run(['apt-get','install','-y','--no-install-recommends','python3-venv'])
    folder=Path('/opt/alirezapanel-certbot')
    if not (folder/'bin/python').exists(): run(['python3','-m','venv',str(folder)])
    run([str(folder/'bin/python'),'-m','pip','install','--disable-pip-version-check','certbot==5.4.0'])
    return str(folder/'bin/certbot')

def prepare(mode, host, email=''):
    host=host_name(host,mode)
    if mode not in ('domain','ip-acme'): raise ValueError('ACME mode must be domain or ip-acme.')
    if mode=='domain':
        socket.getaddrinfo(host,80,type=socket.SOCK_STREAM)
    # Standalone HTTP-01 must own port 80 on each issuance/renewal. Never stop
    # an unrelated webserver or silently fall back to an untrusted certificate.
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as probe:
        try: probe.bind(('0.0.0.0',80))
        except OSError as exc: raise ValueError('TCP port 80 is busy. Use the native DNS challenge certificate manager or free port 80: '+str(exc))
    binary=certbot(mode=='ip-acme')
    name='alirezapanel-'+hashlib.sha256(host.encode()).hexdigest()[:16]
    args=[binary,'certonly','--standalone','--non-interactive','--agree-tos',
          '--preferred-challenges','http','--cert-name',name,'--keep-until-expiring']
    args+=['--email',email] if email else ['--register-unsafely-without-email']
    if mode=='ip-acme': args+=['--preferred-profile','shortlived','--ip-address',host]
    else: args+=['-d',host]
    print('HTTP-01 requires public TCP port 80. Domain A/AAAA records must reach this server.',flush=True)
    run(args)
    lineage=Path('/etc/letsencrypt/live')/name
    validate(lineage/'fullchain.pem',lineage/'privkey.pem',host)
    return {'cert':str(lineage/'fullchain.pem'),'key':str(lineage/'privkey.pem'),
            'lineage':str(lineage),'binary':binary,'host':host,'mode':mode}

def validate(cert, key, host):
    ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(str(cert),str(key))
    info=ssl._ssl._test_decode_cert(str(cert))
    try: address=ipaddress.ip_address(host)
    except ValueError: address=None
    matched=False
    for kind, name in info.get('subjectAltName', ()):
        if address is not None and kind=='IP Address':
            try: matched = matched or ipaddress.ip_address(name)==address
            except ValueError: pass
        elif address is None and kind=='DNS':
            name=name.lower().rstrip('.')
            matched = matched or host.lower()==name or (name.startswith('*.') and host.lower().endswith(name[1:]) and host.count('.')==name.count('.'))
    if not matched: raise ValueError('Certificate does not cover the requested domain/IP.')
    if ssl.cert_time_to_seconds(info['notAfter'])<=time.time()+300:
        raise ValueError('Certificate is expired or too close to expiry.')
    return info

def publish(cert,key,host):
    validate(cert,key,host)
    folder=ETC/'tls'; folder.mkdir(exist_ok=True,mode=0o750)
    group=grp.getgrnam('alirezapanel').gr_gid
    if not (folder/'current').is_symlink() and (folder/'cert.pem').is_file() and (folder/'key.pem').is_file():
        old=Path(tempfile.mkdtemp(prefix='version-',dir=folder));os.chmod(old,0o750);os.chown(old,0,group)
        for name in ('cert.pem','key.pem'):
            shutil.copyfile(folder/name,old/name);os.chmod(old/name,0o640);os.chown(old/name,0,group)
        (folder/'current').symlink_to(old.name)
    version=Path(tempfile.mkdtemp(prefix='version-',dir=folder)); os.chmod(version,0o750); os.chown(version,0,group)
    for source,name in ((cert,'cert.pem'),(key,'key.pem')):
        target=version/name; shutil.copyfile(source,target); os.chmod(target,0o640); os.chown(target,0,group)
    previous=os.readlink(folder/'current') if (folder/'current').is_symlink() else None
    temporary=folder/'.current-new'; temporary.unlink(missing_ok=True); temporary.symlink_to(version.name)
    os.replace(temporary,folder/'current')
    # Stable pair of paths resolves through ONE atomically swapped directory.
    for name in ('cert.pem','key.pem'):
        link=folder/('.'+name); link.unlink(missing_ok=True); link.symlink_to('current/'+name); os.replace(link,folder/name)
    return previous

def install_renewal(meta):
    atomic_json(ETC/'acme.json',meta,0o600)
    hook=Path('/etc/letsencrypt/renewal-hooks/deploy/alirezapanel')
    hook.parent.mkdir(parents=True,exist_ok=True)
    hook.write_text('#!/bin/sh\nexec /usr/bin/python3 /opt/alirezapanel/gateway/tls.py deploy\n')
    hook.chmod(0o750)
    Path('/etc/systemd/system/alirezapanel-cert-renew.service').write_text('''[Unit]
Description=alirezapanel certificate renewal
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/alirezapanel/gateway/tls.py renew
Nice=15
IOSchedulingClass=idle
TimeoutStartSec=15min
''')
    Path('/etc/systemd/system/alirezapanel-cert-renew.timer').write_text('''[Unit]
Description=Check alirezapanel certificates every 6 hours
[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
''')
    run(['systemctl','daemon-reload'])
    run(['systemctl','enable','--now','alirezapanel-cert-renew.timer'])

def consumers():
    cfg=json.loads((ETC/'gateway.json').read_text())
    paths=(cfg['tls_cert'],cfg['tls_key'])
    uri=Path(cfg['vpn_db']).resolve().as_uri()+'?mode=ro'
    with contextlib.closing(sqlite3.connect(uri,uri=True,timeout=5)) as db:
        for settings,stream in db.execute('SELECT settings,stream_settings FROM inbounds WHERE enable=1'):
            if any(p in (settings or '') or p in (stream or '') for p in paths): return True
        for key,value in db.execute("SELECT key,value FROM settings WHERE key IN ('webCertFile','subCertFile')"):
            if value in paths: return True
    return False

def verify_live(cfg, cert):
    pem=Path(cert).read_text()
    leaf=re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',pem,re.S).group(0)
    expected=hashlib.sha256(ssl.PEM_cert_to_DER_cert(leaf)).digest()
    ctx=ssl.create_default_context(cafile=str(cert));ctx.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
    error=None
    for _ in range(10):
        try:
            with socket.create_connection(('127.0.0.1',cfg['port']),timeout=2) as sock:
                with ctx.wrap_socket(sock,server_hostname=cfg['host']) as secured:
                    if hashlib.sha256(secured.getpeercert(binary_form=True)).digest()!=expected:
                        raise ValueError('The gateway is still serving the previous certificate.')
                    return
        except (OSError,ValueError) as exc:
            error=exc;time.sleep(.2)
    raise ValueError('Live gateway certificate check failed: '+str(error))

def deploy():
    if not (ETC/'acme.json').exists(): return
    meta=json.loads((ETC/'acme.json').read_text())
    if os.environ.get('RENEWED_LINEAGE') != meta['lineage']: return
    cfg=json.loads((ETC/'gateway.json').read_text())
    if cfg.get('tls_mode') not in ('domain','ip-acme'): return
    cert=Path(meta['lineage'])/'fullchain.pem'; key=Path(meta['lineage'])/'privkey.pem'
    validate(cert,key,cfg['host'])
    if cert.read_bytes()==Path(cfg['tls_cert']).read_bytes() and key.read_bytes()==Path(cfg['tls_key']).read_bytes(): return
    previous=publish(cert,key,cfg['host'])
    try:
        # SIGHUP reloads the TLS context without dropping node sessions.
        run(['systemctl','reload','alirezapanel.service'])
        verify_live(cfg,cert)
        if consumers(): run(['systemctl','try-restart','alirezapanel-vpn.service'])
    except (subprocess.CalledProcessError,OSError,ValueError):
        if previous:
            tmp=ETC/'tls/.rollback'; tmp.unlink(missing_ok=True); tmp.symlink_to(previous); os.replace(tmp,ETC/'tls/current')
            subprocess.run(['systemctl','reload','alirezapanel.service'])
            subprocess.run(['systemctl','try-restart','alirezapanel-vpn.service'])
        raise
    # Keep current and one rollback version; repeated short-lived renewals must
    # not leave an unbounded number of private keys on a small VPS.
    keep={os.readlink(ETC/'tls/current'),previous}
    for folder in (ETC/'tls').glob('version-*'):
        if folder.is_dir() and folder.name not in keep: shutil.rmtree(folder)
    print('Certificate renewed; panel reloaded and certificate consumers refreshed.')

def status():
    cfg=json.loads((ETC/'gateway.json').read_text())
    info=ssl._ssl._test_decode_cert(cfg['tls_cert'])
    print('alirezapanel | '+cfg['host']+' | '+cfg.get('tls_mode','ip'))
    print('Certificate expires: '+info['notAfter'])
    print('Inbound certificate: '+cfg['tls_cert']+'\nInbound key: '+cfg['tls_key'])
    print('Automatic ACME renewal: '+('configured' if (ETC/'acme.json').exists() and cfg.get('tls_mode') in ('domain','ip-acme') else 'not configured'))

def configure():
    cfg=json.loads((ETC/'gateway.json').read_text())
    print('alirezapanel SSL\n1) Domain + trusted SSL\n2) Public IP + trusted SSL\n3) Show current status')
    choice=input('Selection [1-3]: ').strip()
    if choice=='3': status(); return
    mode={'1':'domain','2':'ip-acme'}.get(choice)
    if not mode: raise ValueError('Invalid selection.')
    host=host_name(input('Public domain/IP: '),mode)
    email=input('ACME email (optional): ').strip()
    if cfg.get('host') != host and consumers():
        raise ValueError('Active inbounds use the current certificate. Add the new hostname through the native SSL manager first; update SNI before switching panel identity.')
    meta=prepare(mode,host,email)
    backup=ETC/('gateway.before-ssl-'+str(time.time_ns())+'.json'); shutil.copy2(ETC/'gateway.json',backup)
    previous=publish(meta['cert'],meta['key'],host)
    old_cfg=dict(cfg)
    cfg.update(host=host,tls_mode=mode,tls_enabled=True)
    atomic_json(ETC/'gateway.json',cfg)
    old_meta=(ETC/'acme.json').read_bytes() if (ETC/'acme.json').exists() else None
    try:
        install_renewal(meta)
        run(['systemctl','restart','alirezapanel.service'])
        run(['systemctl','is-active','--quiet','alirezapanel.service'])
        verify_live(cfg,meta['cert'])
        if consumers(): run(['systemctl','try-restart','alirezapanel-vpn.service'])
    except (subprocess.CalledProcessError,OSError,ValueError):
        atomic_json(ETC/'gateway.json',old_cfg)
        if old_meta: atomic_json(ETC/'acme.json',json.loads(old_meta),0o600)
        else: (ETC/'acme.json').unlink(missing_ok=True)
        if previous:
            tmp=ETC/'tls/.rollback'; tmp.unlink(missing_ok=True); tmp.symlink_to(previous); os.replace(tmp,ETC/'tls/current')
        subprocess.run(['systemctl','restart','alirezapanel.service'])
        raise
    status()

def migrate():
    """Recognize only the exact Certbot layout used by the previous installer."""
    if (ETC/'acme.json').exists(): return
    cfg=json.loads((ETC/'gateway.json').read_text())
    if cfg.get('tls_mode')!='domain': return
    host=host_name(cfg['host'],'domain')
    lineage=Path('/etc/letsencrypt/live')/host
    binary=shutil.which('certbot')
    if not binary or not (lineage/'fullchain.pem').is_file(): return
    if (lineage/'fullchain.pem').read_bytes()!=Path(cfg['tls_cert']).read_bytes(): return
    validate(lineage/'fullchain.pem',lineage/'privkey.pem',host)
    atomic_json(ETC/'acme.json',{'cert':str(lineage/'fullchain.pem'),'key':str(lineage/'privkey.pem'),
        'lineage':str(lineage),'binary':binary,'host':host,'mode':'domain'},0o600)
    print('Existing installer-managed Certbot certificate adopted for renewal.')

def main():
    if os.geteuid()!=0: raise SystemExit('Run with sudo.')
    parser=argparse.ArgumentParser();parser.add_argument('operation',choices=['prepare','adopt','deploy','renew','status','configure','migrate']);parser.add_argument('--result')
    args=parser.parse_args()
    if args.operation=='prepare':
        meta=prepare(os.environ['ALIREZA_TLS_MODE'],os.environ.get('ALIREZA_HOST',''),os.environ.get('ALIREZA_ACME_EMAIL',''))
        atomic_json(Path(args.result),meta,0o600)
    elif args.operation=='adopt':
        meta=json.loads(Path(args.result).read_text());publish(meta['cert'],meta['key'],meta['host']);install_renewal(meta)
    elif args.operation=='renew':
        if not (ETC/'acme.json').exists(): return
        meta=json.loads((ETC/'acme.json').read_text())
        with open('/run/lock/alirezapanel-renew.lock','w') as lock:
            try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError: return
            run([meta['binary'],'renew','--quiet','--cert-name',Path(meta['lineage']).name])
            # Reconcile after a previous hook failure even when no renewal is due.
            os.environ['RENEWED_LINEAGE']=meta['lineage'];deploy()
    elif args.operation=='configure':
        with open('/run/lock/alirezapanel-install.lock','w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);configure()
    else: globals()[args.operation]()

if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError) as exc:
        raise SystemExit('SSL operation failed: '+str(exc))
NODE_EMBEDDED_TLS_PY_EOF

say 'Checking the embedded integration code before changing services.'
python3 -m py_compile "$STAGE/gateway.py" "$STAGE/manage.py" "$STAGE/nodes.py" "$STAGE/features.py" "$STAGE/tls.py" "$STAGE/dns_clients.py"
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
for filename in gateway.py brand.js theme.css manage.py logo.svg nodes.py nodes.js nodes.html features.py features.js tls.py dns_clients.py dns_clients.js; do
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
python3 - "$ROOT/adguard/AdGuardHome.yaml" <<'MANAGED_DOH'
import ipaddress, pathlib, sys, yaml
p=pathlib.Path(sys.argv[1]); cfg=yaml.safe_load(p.read_text())
http=cfg.setdefault('http', {})
host=http.get('address','127.0.0.1:18081').rsplit(':',1)[0].strip('[]')
if not ipaddress.ip_address(host).is_loopback:
    raise SystemExit('Managed DNS requires a loopback-only AdGuard HTTP listener. Restore 127.0.0.1:18081 before repair.')
doh=http.setdefault('doh', {}); doh['insecure_enabled']=True
# Gateway has its own per-client limiter; don't aggregate every local relay under one IP.
white=cfg.setdefault('dns', {}).setdefault('ratelimit_whitelist', [])
for addr in ('127.0.0.1','::1'):
    if addr not in white: white.append(addr)
if doh.get('routes'):
    for route in ('GET /dns-query','POST /dns-query','GET /dns-query/{ClientID}','POST /dns-query/{ClientID}'):
        if route not in doh['routes']: doh['routes'].append(route)
tmp=p.with_suffix('.yaml.new'); tmp.write_text(yaml.safe_dump(cfg,sort_keys=False)); tmp.chmod(0o600); tmp.replace(p)
MANAGED_DOH
if [[ -f "$STAGE/tls-result.json" ]]; then
    install -o root -g root -m 600 "$STAGE/tls-result.json" "$ETC/acme.json"
fi
# Bind probes happen with owned services stopped and BEFORE anything starts.
# DNS uses port 53 directly on exact addresses; no firewall/NAT redirect is added.
python3 - "$ETC/gateway.json" <<'PORTCHECK'
import json, socket, sqlite3, sys
cfg=json.load(open(sys.argv[1]))
from pathlib import Path
settings={}
if Path(cfg['vpn_db']).exists():
    with sqlite3.connect(Path(cfg['vpn_db']).resolve().as_uri()+'?mode=ro',uri=True) as db:
        settings=dict(db.execute('SELECT key,value FROM settings'))
tests=[(cfg.get('listen','0.0.0.0'),cfg['port'],socket.SOCK_STREAM),
       (settings.get('webListen') or '127.0.0.1',int(settings.get('webPort','18080')),socket.SOCK_STREAM),
       ('127.0.0.1',18081,socket.SOCK_STREAM)]
for dns_host in cfg.get('dns_bind_hosts', []):
    tests.append((dns_host,53,socket.SOCK_STREAM))
    tests.append((dns_host,53,socket.SOCK_DGRAM))
for host,port,kind in tests:
    with socket.socket(socket.AF_INET6 if ':' in host else socket.AF_INET,kind) as sock:
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

cat > /etc/systemd/system/alirezapanel-vpn.service <<VPNUNIT
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
Environment=GOMEMLIMIT=${vpn_memory_mib}MiB
Environment=GOGC=75
Environment=VPNUI_LOG_LEVEL=warning
Environment=VPNUI_DB_FOLDER=/opt/alirezapanel/vpn
LogRateLimitIntervalSec=30s
LogRateLimitBurst=200

[Install]
WantedBy=multi-user.target
VPNUNIT

cat > /etc/systemd/system/alirezapanel-dns.service <<DNSUNIT
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
Environment=GOMEMLIMIT=${dns_memory_mib}MiB
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
ExecReload=/bin/kill -HUP $MAINPID
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
    ssl) shift; exec python3 /opt/alirezapanel/gateway/tls.py "${1:-configure}" ;;
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
        systemctl restart alirezapanel.service || { journalctl -u alirezapanel -n 50 --no-pager >&2; exit 1; }
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
        cp -a /opt/alirezapanel/gateway "$dest/gateway"
        printf 'Backup saved: %s\n' "$dest"
        ;;
    vpn) shift; cd /opt/alirezapanel/vpn; exec ./vpn-ui-amd64 "$@" ;;
    help|--help|-h) cat /opt/alirezapanel/README.txt ;;
    *) echo 'Commands: ssl info credentials check status restart logs backup vpn help' >&2; exit 2 ;;
esac
CLI
chmod 755 /usr/local/bin/alirezapanel

# Adopt the issued certificate after installing all integration modules.
python3 "$ROOT/gateway/tls.py" migrate
if [[ -f "$ETC/acme.json" ]]; then
    python3 "$ROOT/gateway/tls.py" adopt --result "$ETC/acme.json"
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
printf 'integration=1.4.0\nvpn=%s\nadguard=%s\n' "$VPN_VERSION" "$AGH_VERSION" > "$ETC/installed"
say 'Installation and automated health checks completed.'
python3 "$ROOT/gateway/manage.py" info
printf '\nTo display your initial login: sudo alirezapanel credentials\n'
ALIREZA_TLS_MODE="$(python3 -c 'import json;print(json.load(open("/etc/alirezapanel/gateway.json")).get("tls_mode","ip"))')"
case "$ALIREZA_TLS_MODE" in
    domain) printf 'Domain SSL mode is enabled. Automatic renewal is configured when this installer obtained the certificate.\n' ;;
    ip-acme) printf 'Trusted IP SSL is enabled. Renewal is checked every six hours; TCP port 80 must remain reachable.\n' ;;
    ip) printf 'IP HTTPS mode is enabled; the default certificate is self-signed unless a certificate was supplied.\n' ;;
    none) printf 'Plain HTTP mode is enabled; traffic to the public panel is not TLS-encrypted.\n' ;;
esac
printf 'No firewall rules or system DNS settings were changed. Permit the selected panel port at the hosting firewall.\n'
