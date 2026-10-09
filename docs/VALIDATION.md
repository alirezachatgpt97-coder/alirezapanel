# Validation — 2.8.0

Source baseline: `b51f7480623cf050debdbb3f39eacd71fbe399cf` in the requested **alirezapanel** repository. Upstream controller/templates inspected at vpn-ui v1.9.4, commit `8044e0ad45c60149439546ea0fd99371a4d3c03d`.

## Executed checks

| Check | Result and scope |
|---|---|
| Installer shell syntax and payload extraction | Passed; Bash syntax and all 9 embedded Python modules compiled without installing |
| Python regression suite | Passed (13 tests); node mount for root/custom base paths, allowlist/traversal, unchanged AdGuard HTML, native-only DNS shell, retired subsystem on fresh state, policy isolation, existing initialization and legacy-state preservation, subscription output, polling, upgrade preservation assertions |
| JavaScript syntax | Passed; integration scripts and node page inline script |
| DOM/control harness | Passed in English and Persian; policy page, account search, node selection, dialog and server-target capture. This uses mocked DOM/fetch, not a browser layout engine |
| Native integration: node base `/` | Passed with two real SHA-verified vpn-ui backends and HTTPS gateways |
| Native integration: node base `/edge/` | Passed with the same test against a custom node path |
| Native node flows | Login/connector promotion, identity, pinned TLS enrollment, catalog/status, native mounted HTML, defaults, create/update/delete inbound, add client, assignable list, multipart body and query parameters, root-node language forwarding, destination isolation, denied admin route, revoked token |
| Native admin flows | Create, wrong password rejection, landing redirect to permitted inbounds page, explicit inbound-grant isolation, denied node API, immediate disabled-account rejection, no-page-permission notice and logout |
| Native shell endpoints | Content page and Nodes page returned the integrated shell; browser mounting remains pending |
| Package | Complete online source installer, tests and docs; no credentials, local databases, private certificates or upstream binaries bundled |

`native-results-root.json` and `native-results-custom.json` are sanitized summaries of the actual native tests. Their `browser: false` field is intentional.

## Root causes and boundaries

For a node using `/`, the former mount regex rewrote every quoted `/panel/…` string, including native Axios arguments. Native `axios.defaults.baseURL` was also mounted. Axios therefore prepended the mount twice. The fix leaves Axios request arguments untouched and rewrites only UI resource/navigation fields. Custom base paths and Core’s separate basePath are covered too.

Native Admins creation starts with an empty permission set. An enabled account can authenticate correctly but have no page permission. The pinned controller deliberately responds with plain-text 403 when no permitted landing exists. The gateway now presents that state as a complete access notice with logout. It does not bypass password/2FA/session validation, invent permissions or replace native per-admin ownership rules. Without a user screenshot, this reproduced case cannot prove every historical incomplete-page report had the same cause.

Old node 401s could trigger native Axios’s global reload behavior. Remote authorization failures now return an explicit gateway failure, preserving rejection and never retrying mutations.

## Tests that could not be completed

- Real Chromium launch was attempted; it exited with **SIGTRAP (133)** before opening a page. The normal Playwright browser download also failed in this environment. No rendered mobile/desktop screenshot or browser success is claimed.
- `tests/browser_checks.js` is provided for actual 1366×900 and 390×844 checks, English/Persian, login/logout, dashboard/admins/nodes/remote inbounds/content, overflow and script errors. It is **not marked passed**.
- Full installation/upgrade via apt/systemd was not run. Sandbox lacks a normal `/proc`, systemd services and kernel network capabilities. Native backend emitted expected sandbox warnings and its Xray core could not start with missing geodata. CRUD/auth tests passed; these are not tunnel/traffic tests.
- No complete AdGuard daemon/production DNS, public certificate/ACME renewal, or live 1 GiB RAM/load benchmark was run.
- No protocol-by-protocol network connectivity, 2FA challenge roundtrip, long-running session expiry, real CA rotation, or production backup/restore rehearsal was performed.
- Source and regression checks verify removal of AdGuard HTML injection and installer YAML rewriting; they do not certify every AdGuard encrypted DNS configuration.

## Reproduction

Required development dependencies: Python 3 with aiohttp and PyYAML; Node for JS tests; OpenSSL; the exact pinned vpn-ui binary. Tests use temporary scratch directories and loopback listeners, and remove child processes on completion. The native binary’s startup may attempt its normal system discovery; run only in a disposable restricted development container/VM, not a live server. No installer or GitHub write is performed by these tests.

```bash
bash install.sh --self-test
python3 tests/test_regressions.py
python3 tests/extract.py /path/to/private/runtime
node tests/ui_harness.js /path/to/private/runtime
python3 tests/native_integration.py /path/to/vpn-ui-amd64 /path/to/root-results
NODE_BASE_PATH=/edge/ python3 tests/native_integration.py /path/to/vpn-ui-amd64 /path/to/custom-results
```

With a working Playwright/Chromium installation:

```bash
RUN_BROWSER=1 python3 tests/native_integration.py /path/to/vpn-ui-amd64 /path/to/browser-results
```

An explicit browser executable can be passed through `CHROMIUM_EXECUTABLE`. Screenshots and browser results are saved only if Chromium actually runs. Developer test dependencies are not installed on the production server by `install.sh`.

Before production rollout, finish browser visual QA, a systemd fresh-install/upgrade/rollback rehearsal and workload-specific memory/traffic tests on a disposable 1 GiB VPS.
