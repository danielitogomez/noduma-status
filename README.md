# Noduma status

Outside uptime check for the [Noduma](https://github.com/danielitogomez/Noduma) coordinator, built on [Upptime](https://github.com/upptime/upptime). It runs on GitHub Actions, not in the Civo cluster, so it still reports when the whole cluster is down (Noduma SPEC-047).

- **What:** `GET https://74-220-25-65.sslip.io/healthz` every 5 minutes; down unless it answers 200; degraded above 5 s.
- **Alerts:** down and back-up messages to the operators' Telegram group "NodumaOps" (secrets `NOTIFICATION_TELEGRAM`, `NOTIFICATION_TELEGRAM_BOT_KEY`, `NOTIFICATION_TELEGRAM_CHAT_ID`), plus an issue in this repository for each outage.
- **Status page:** https://danielitogomez.github.io/noduma-status/
- **Configuration:** `.upptimerc.yml`. The workflows use the default `GITHUB_TOKEN` (no personal token, no GitHub App), each with only the permissions it needs (repository default: read); every action is pinned by commit SHA, checked by Noduma's `scripts/check_workflow_pins.py`; only the three Telegram secrets reach the Upptime action. Upptime's `setup` and template-update workflows were removed: they rewrite the workflow files, which needs a token with the workflows scope, and the update ones track `@master`. To change a schedule or upgrade Upptime, edit `.github/workflows/` by hand.
