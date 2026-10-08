# Changelog

## 0.1.3 — 2026-10-08

- Add a direct `tgproxy uninstall` command as an alternative to menu option 11.
- Clarify that the current uninstall stops Caddy as well as the proxy services.
- Preserve upstream binaries/configuration and recovery backups for safe manual cleanup.


## 0.1.2 — 2026-10-08

- Wait up to 180 seconds for Telemt to establish real Telegram Middle Proxy routing during initial sponsored setup.
- Avoid treating temporary direct fallback during startup as a permanent sponsor failure.
- Keep manual health checks strict: the sponsored route must actually be in middle mode to pass.


## 0.1.1 — 2026-10-08

- Fix Telemt permissions under `umask 077`: the service user can now traverse `/etc/telemt`.
- Validate Telemt port binding, API and WEB readiness before declaring installation successful.
- Return non-zero exit status for failed HTTPS, FakeTLS and sponsored Middle Proxy health checks.
- Re-running the bootstrap installer resumes a partially installed setup without needless re-cloning.


## 0.1.0 — 2026-10-08

- Initial public release.
- Interactive domain/IP and FakeTLS port setup.
- Telemt FakeTLS deployment with TLS masking.
- Telegram WEB Proxy stack deployment via upstream `tproxy-server` installer.
- Official MTProxy backend integration.
- Sponsor/promoted-channel support with `@MTProxyBot` proxy tags.
- Middle Proxy / TCP 8888 diagnostics.
- Persistent `tgproxy` management menu.
- Secret rotation, port/domain edits, health checks and self-update.
- Persian and English documentation.
