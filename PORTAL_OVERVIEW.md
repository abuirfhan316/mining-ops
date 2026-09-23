# MiningOps Portal — Functionality & Process Overview

## What this is

MiningOps is a single-page web application (one self-contained HTML file) for
tracking and monitoring two Bitcoin mining fleets — **madZ** (the main fleet)
and **Mirfa** (a separate site) — plus their supporting power infrastructure
(PSUs), live pool performance, and network/market context. It's used by an
operations team to know, at a glance and in detail: which miners exist, what
state they're in, whether they're actually hashing on the pool, and what
still needs action (repair, deployment, uploading changes to the master
database).

The app talks to a Supabase project for its database, authentication, and a
pair of Edge Functions that proxy Foundry pool data (so the Foundry API key
never reaches the browser). A handful of free public APIs (CoinGecko,
mempool.space, blockchain.info) feed the live price/network stats shown in
the top bar.

---

## Authentication & accounts

- Sign-in is handled by Supabase Auth (email + password). New sign-ups land
  with `status = 'pending'` and cannot access the app until an admin
  approves them from **Staff Accounts**.
- Every user has a row in the `profiles` table carrying their role
  (`admin` or a lower-privilege staff role), status (`pending` / `active` /
  `disabled`), and a `force_password_change` flag (used to make a new user
  set their own password on first login).
- Session state is Supabase's own (JWT-based); the app checks
  `sb.auth.getSession()` on load and re-derives the current user's profile
  from it rather than trusting anything stored client-side for
  authorization decisions.
- A `bump_own_last_login` database function is called on login so
  **Staff Accounts → Last Login** reflects real activity.

---

## The two sites: madZ and Mirfa

The sidebar has a site dropdown (madZ / Mirfa). Switching it does two
things: it swaps which nav items are visible, **and** it navigates the
content pane to the equivalent page on the newly selected site (e.g. Pool
Monitor → Mirfa Pool Monitor). Pages with no direct equivalent on the other
site (PSU/APSU, which only exist for madZ) or that aren't site-scoped at all
(Master Breakdown, Audit Log, Staff Accounts) fall back to that site's
Inventory page instead of leaving stale content on screen.

Both sites' inventory records live in **one shared `inventory` table**,
distinguished by an `asset_type` field (`'Asic Miner'` for madZ,
`'Mirfa Miner'` for Mirfa, plus `'PSU'` / `'Avalon PSU'` for power supplies).
There is no separate database per site.

---

## Core pages

### Inventory (madZ-Inventory / Mirfa-Inventory)
The main data grid: Serial, Model, Location, Status, Container/Tank/
Position, Updated By, Uploaded flag, Time, and row actions. Supports:
- **Add / Edit / Delete** a single record (modal form).
- **Bulk Add** — paste multiple serials at once, auto-filling
  container/tank/position from the grid location.
- **Import** — paste an Excel export of the "official" database; rows are
  matched by serial and marked `uploaded: true` on import (they're assumed
  already synced).
- **Export** and **DB Import export** — the latter produces a plain-text
  block formatted for pasting directly into the master database, and marks
  the exported rows uploaded once you confirm ("Done — Mark Uploaded").
- **Swap Miner** — replace a faulty unit with a spare in one action,
  updating both records and logging it.
- **Click-and-drag row selection** — click a row and drag up/down to
  select a range in one motion, for bulk actions; works across grouped/
  collapsed rows too (a collapsed group selects every record inside it).
- **Sort** (click a header) and **group** (double-click a header) by any
  column, including a multi-level "Add level..." grouping panel.
- **Duplicate/missing-data detection** — the sidebar's Mining stat card
  surfaces duplicate IPs, duplicate serials, missing IPs (grid positions
  with no matching inventory record), and models missing entirely, each
  opening its own detail list with export.

### PSU Inventory (XP-PSU) and Avalon-PSU Inventory
Same CRUD/search/sort/group/drag-select pattern as the main Inventory, but
scoped to `asset_type = 'psu'` / `'avalon psu'` records. madZ-only — Mirfa
has no PSU tracking.

### Breakdown (madZ-Breakdown / Mirfa-Breakdown)
Groups inventory by miner family (e.g. Antminer XP, Avalon, Bitmain Hydro)
into collapsible sections — each starts collapsed, showing only that
family's Total row, and expands to show individual models on click. Each
family also gets a donut-chart summary card (Mining/Ready/Diagnosis/Repair
proportions). A further breakdown distinguishes Unrepairable / Advance
Repair at Masdar / 3 Faulty Boards as a closer look inside the Repair
count (for one family on the Mirfa side — "Antminer XP" — Repair is instead
*defined as* the sum of those three, rather than the other way around).

### Antsentry Report (Hosting Report)
Compares the manually-tracked inventory against a **master IP list**
(`hydro_fleet` for madZ, `mirfa_hydro_fleet` for Mirfa) to show live hosting
vs. maintenance capacity for the Hydro fleet — any master IP not showing as
"Mining" in inventory is flagged. Exports to Excel and a formatted PDF
report. Only reloads data when its own **Refresh** button is clicked —
simply navigating to the page renders from whatever's already loaded.

### Pool Monitor (madZ-Pool Monitor / Mirfa-Pool Monitor)
Live worker-level data pulled from Foundry via the Supabase Edge Function
proxies — total/online/offline counts, per-worker hashrate (5m/15m/1h),
stale/reject %, and last-share time. Supports search, status filtering,
sort, double-click grouping, auto-refresh every 60 seconds, and export
(including a "DB Import"-style export for pasting worker data alongside
inventory).

### Miner Monitoring (madZ-Miner Monitoring / Mirfa-Miner Monitoring)
A container/tank/position grid view (card layout) built from the same Pool
Monitor worker data: every container as a card, each with clickable tank
dots (red = at least one miner offline). Clicking a tank drills into its
individual positions; an "Offline > 10 min" stat opens a sortable,
exportable list of exactly which IPs are down.

### Master Breakdown
A combined view of both sites' breakdown data together, for a single
top-level picture across the whole operation.

### Audit Log
A running history of every field change made anywhere in the app (who
changed what, from what value to what, and when), with date-range export,
per-serial history lookup, and bulk delete (admin only).

### Staff Accounts (admin only)
Approve or reject pending sign-ups, change roles, disable/enable accounts,
and see each user's last-login date and time.

---

## Live market & mining stats (top bar)

A row of small chips, refreshed every 60 seconds, showing (left to right):
a "Bitcoin is Money" brand chip, sats-per-$1, BTC price, current block
height, global network hashrate, the next-block recommended fee, an
estimated hashprice ($/PH/s/day), a halving countdown, and mempool
congestion (unconfirmed transaction count). These come entirely from free,
keyless public APIs — see `API_ENDPOINTS.md` for exact sources.

---

## Security notes

- The Foundry pool API key lives only inside the `pool-proxy` /
  `pool-proxy-mirfa` Supabase Edge Functions — it is never present in this
  file or sent to the browser.
- A strict Content-Security-Policy restricts which external domains the
  page may ever connect to.
- Row-Level Security on `profiles` (and related tables) is enforced
  server-side using the caller's real Supabase Auth identity, not a value
  the client claims about itself.
- Every meaningful change is written to `audit_log` for accountability.

## Data loading behavior

All inventory-related data (`inventory`, `hydro_fleet`, `mirfa_hydro_fleet`)
is loaded into browser memory once per session (on login, or after any save/
edit/import/swap) — it is **not** cached to `localStorage` and does not
persist across a page refresh or between browser tabs. The three tables
load concurrently rather than one after another. Simply navigating between
pages does not trigger a reload; only an actual data change (or a page's
explicit "Refresh" button) does.

## Theming

The whole app supports dark and light mode (a toggle in the top bar),
persisted via `localStorage`, with color and contrast handled through CSS
custom properties rather than hardcoded values throughout.
