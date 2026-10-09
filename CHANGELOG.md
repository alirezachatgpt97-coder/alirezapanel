# 2.8.0 — 2026-10-09

Based on alirezapanel main `b51f7480623cf050debdbb3f39eacd71fbe399cf`.
No GitHub publication or production server execution was performed.

- Fixed the node UI mount rewriting quoted `/panel/…` Axios arguments when a node uses the root base path. Axios would combine the already-mounted argument with its mounted baseURL again. Rewrites now target HTML resource/navigation attributes and named UI navigation/base fields; API literals stay native. Also corrected Core’s per-instance basePath.
- Converted remote authorization failures to explicit gateway errors instead of feeding 401 into native Axios’s automatic page reload. Authentication still fails closed; writes are not retried.
- Preserved the existing native connector reconciliation/promotion, token version, TLS trust model, API allowlist, stream forwarding, subscriptions and protocol binaries.
- Added a proper authenticated no-page-access document with logout for the native controller’s plain-text 403. The native admin form starts with no permissions; action permissions alone cannot open a page. No new permissions are granted implicitly. Added an admin access guide and canonical sign-in link.
- Added Aurora surfaces for the native login, dashboard, cards, tables, inputs, dialogs and node management. Added language/direction metadata from the existing language cookie and translated integration controls.
- Added a standalone Content filters page backed by the existing policy API, saved account identities and destination selection. Dialogs capture their target server to avoid applying a policy to a newly selected server while a dialog is open.
- Removed the panel’s separate DNS client UI, retaining legacy managed DoH state and existing links. Fresh installations do not open that retired database/session.
- AdGuard HTML is passed through unchanged, with no branding, style or script injection. Repair no longer rewrites its YAML to enable the retired managed DoH subsystem. Health checks use native AdGuard HTML and current configured DNS listeners.
- Removed the integration’s top SSL/filter toolbar. Native TLS forms, certificate publication/reload/renewal and CLI remain.
- Deduplicated dashboard fallback polling, paused it for hidden pages and prevented overlapping calls. Versioned integration assets are cached; no extra daemon, build chain or remote font is introduced.
- Added unit/CLI files to upgrade/manual backups. Repair refuses to continue if services cannot be stopped for a consistent snapshot.
- Included reproducible Python, DOM/control and optional native/Playwright tests. Browser execution and real 1 GiB/systemd/ACME/kernel deployment validation remain pending; see docs/VALIDATION.md.
