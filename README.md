# MiningOps

A single-page web app for tracking and monitoring two Bitcoin mining
fleets — **madZ** and **Mirfa** — plus their power infrastructure, live
pool performance, and network/market context.

**Live:** [mining-ops-one.vercel.app](https://mining-ops-one.vercel.app)

## Documentation

- **[Portal overview](./PORTAL_OVERVIEW.md)** — what the app does, page by
  page: inventory management, breakdown reports, the Antsentry/Hosting
  Report, Pool Monitor, Miner Monitoring, audit logging, staff accounts,
  and how authentication and site-switching work.
- **[API endpoints](./API_ENDPOINTS.md)** — every endpoint the app talks
  to (Supabase Auth, REST tables, Edge Functions, and the external market/
  mining data APIs), including flowcharts of how it all connects.

## Stack

- **Frontend** — a single self-contained `index.html` (no build step).
- **Backend** — [Supabase](https://supabase.com): Postgres (via the REST
  API), Auth, and Edge Functions. The Edge Functions proxy the Foundry
  pool API so that key never reaches the browser.
- **Hosting** — deployed on [Vercel](https://vercel.com).

## Repo layout

```
index.html              the whole app
PORTAL_OVERVIEW.md       functionality & process summary
API_ENDPOINTS.md         endpoint reference + flowcharts
.github/workflows/       nightly backup automation
backups/                 nightly backup snapshots
backup-export.sh         backup script
```
