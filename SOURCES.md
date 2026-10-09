# Sources and pinned versions

Integration source: `install.sh`, GPL-3.0-or-later. Tests and documentation are shipped alongside it.

| Component | Version / source | Download SHA-256 |
|---|---|---|
| vpn-ui | [v1.9.4](https://github.com/Sir-MmD/vpn-ui/tree/v1.9.4), source commit `8044e0ad45c60149439546ea0fd99371a4d3c03d` | `18ec321d9074b319bd5756508bbc523ab5d95450b832c406acdd72e987a2da8f` |
| AdGuard Home | [v0.107.79](https://github.com/AdguardTeam/AdGuardHome/tree/v0.107.79) | `c48f4a43000665484c5ec28177de11a004759b620dae8f77b2aabefc9ef3687f` |

The installer downloads unmodified executables over HTTPS and verifies these digests. It does not compile either project or substitute alirezaserver files. Build instructions and third-party licenses are in the corresponding upstream source repositories. Installed licenses and source references are retained under `/opt/alirezapanel`.

The package is an online installer; upstream executables, geodata and system packages are not bundled in the source ZIP. Optional native cores still depend on their original provisioning mechanism and host capabilities.
