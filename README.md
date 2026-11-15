<div align="center">

<img src="mobile/assets/branding/app_icon.png" alt="DACAAM" width="120" />

# DACAAM

**Restaurant POS & Management — multi-restaurant SaaS**

*Nidaamka maamulka maqaayadaha: dalabaad, miisas, kharash, warbixin iyo shaqaale — hal meel.*

![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-8.2+-777BB4?logo=php&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-MariaDB-4479A1?logo=mysql&logoColor=white)
![Android](https://img.shields.io/badge/Android-APK-3DDC84?logo=android&logoColor=white)
![Version](https://img.shields.io/badge/version-1.1.0-orange)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)

</div>

---

## ✨ Features

| | |
| --- | --- |
| 🧾 **Orders & POS** | Dine-in, takeaway, drafts, refunds, wallet payments |
| 🍽️ **Menu & Tables** | Categories, items, images, table management |
| 👥 **Roles** | Restaurant Admin, Operator, Waiter — each with its own permissions |
| 💰 **Books** | Expenses, payment methods, shifts and till counts |
| 📊 **Reports** | Daily digest, period reports, CSV export |
| 🔐 **Security** | Two-factor (TOTP), rate limiting, audit log, password policy |
| 🔔 **Notifications** | Firebase push + email outbox |
| 🏢 **Super Admin** | Web dashboard: restaurants, plans, invoices, subscriptions, backups |

## 🧱 Stack

```
mobile/     Flutter app (Android)        → Admin / Operator / Waiter
backend/    PHP 8.2 REST API + MySQL      → auth, tenants, business rules
admin/      PHP web dashboard            → Super Admin / platform
```

> **License:** This code is public to *view* only. All rights reserved —
> see [LICENSE](LICENSE). No use, copy or redistribution without written permission.

---

## Overview

Multi-restaurant SaaS POS. Every restaurant is a tenant identified by a slug
(`HAMZE`, `WARFA`) and isolated by `restaurant_id`.

```
mobile/     Flutter app for Restaurant Admin / Operator / Waiter   ← Phase 1
backend/    PHP REST API + MySQL                                    ← Phase 2 (this repo state)
admin/      Super Admin web dashboard                               ← Phase 9
```

Flutter never talks to MySQL. All reads and writes go through the REST API,
which owns authentication, authorization, validation, tenant isolation,
business rules and audit logging.

## Running it

**Backend** — needs PHP 8.2+ and MySQL/MariaDB. See [backend/README.md](backend/README.md).

```bash
cd backend && php bin/migrate.php --fresh --seed && php -S 127.0.0.1:8090 -t public public/index.php
```

**Mobile** — runs standalone on the seeded in-memory dataset:

```bash
cd mobile && flutter run
```

Or against the live API (`10.0.2.2` is the Android emulator's route to the host):

```bash
cd mobile && flutter run --dart-define=USE_API=true --dart-define=API_BASE_URL=http://10.0.2.2:8090/api/v1
```

```bash
cd mobile && flutter test
```

Requires Flutter 3.44+ (built against 3.44.8 / Dart 3.12).

**Release APK.** Put a `key.properties` in `mobile/android/` with `storeFile`,
`storePassword`, `keyAlias` and `keyPassword` — it is gitignored, and without it
the release build falls back to the debug key and produces an artifact you
cannot publish. Then:

```bash
cd mobile && flutter build apk --release --dart-define=USE_API=true --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

If the API is on a LAN without TLS, add that address to
`mobile/android/app/src/main/res/xml/network_security_config.xml` first —
Android 9+ blocks cleartext to anything not named there.

**App icon.** Every launcher density, the adaptive icon and the Play Console
512×512 are generated from one source file:

```bash
cd mobile && php tool/generate_icons.php assets/branding/app_icon.png full
```

The last argument is `full` (the whole logo, wordmark included) or `emblem`
(the artwork alone, no wordmark). An adaptive icon is a 108dp canvas of which
Android only ever shows the inner 72dp, so the artwork is sized against 72 —
scaling to the full 108, which is the obvious first guess, throws a third of
the logo away and cuts the wordmark in half.

**Super Admin dashboard** — server-rendered PHP, shares the backend's database
and config. See [admin/README.md](admin/README.md).

```bash
php -S 127.0.0.1:8091 -t admin/public admin/public/index.php
```

**Seeded logins** (local development only, password `admin123`): `HAMZE` /
`0634567890` (admin), `0631122334` (operator), `0632233445` (waiter), and
`WARFA` / `0637778899` (admin of a second tenant). The platform dashboard signs
in with `super@dacaam.test`.

## Deploying

Step by step: **[DEPLOY-HOSTINGER.md](DEPLOY-HOSTINGER.md)** for Hostinger
Cloud Startup (hPanel, SSH, symlinked document roots), or
**[DEPLOY.md](DEPLOY.md)** for cPanel and generic hosts.

```bash
cd backend && php bin/bundle.php
```

builds `dist/` with only what belongs on a server — the test suites, `seed.sql`
and `config.local.php` are left behind. That last pair is why the script
exists: `seed.sql` creates demo restaurants whose every password is `admin123`,
and both have reached production before in projects that FTP'd the whole folder
up because it was quicker.

The schema files name no database of their own, so they import into whichever
one a host has given you — shared hosting picks the name (`someuser_dacaam`)
and grants no rights to create another.

On a fresh install the dashboard has nobody to sign in as, by design. Visiting
it redirects to `/setup`, which creates the first platform administrator and
then closes permanently — there is no second way in.

## Phase 1 — what is built

Foundation and the six primary screens, running on a seeded in-memory dataset
for the `HAMZE` tenant.

**Design system** — orange/amber identity (`#F97316 → #F59E0B`) on `#F8FAFC`,
white cards with 16–20px radii and soft shadows, a single spacing scale, full
light **and** dark themes, staggered entrances, count-up KPIs, skeleton /
empty / error states throughout.

**Somali first** — Somali is the default language, English is a per-key
fallback; switching in Settings re-renders immediately. Currency is SLSH with
a configurable prefix.

**Six sections** (bottom navigation, permission-aware):

| Screen | Contents |
| --- | --- |
| Home | KPIs, quick actions, weekly sales chart with per-day tooltips, top sellers, recent orders |
| POS | Menu grid with search + category chips, cart with steppers and swipe-to-remove, two-step checkout, animated success screen |
| Orders | Status tabs with counts, filter sheet (date/type/waiter/table/payment), order details with money breakdown and audit timeline |
| Menu | Items and Categories tabs, create/edit/view sheet with validation, availability toggle, delete confirmation |
| Reports | Range presets, sales overview, category donut, financial summary, order analytics, payment and waiter breakdowns, top items, hourly trend |
| More | Profile card, Drafts, Tables, Expenses, Accounts, Users & Roles, Settings, About |

**Business rules already enforced client-side** (and mirrored by the API in
Phase 2): discount applies before tax; tax only when enabled; the packaging
fee is a single flat charge on takeaway orders containing at least one
eligible item; takeaway never carries a table; Dine In requires a table when
`Require Table for Dine In` is on; cancelling requires a reason; every status
change writes an audit event with actor, old value, new value and reason.

**Tests** — pricing rules, seed-data integrity, cart and checkout reducers,
table occupancy, order filters, permission sets, plus widget tests that boot
the real app and drive navigation, add-to-cart and language switching, and a
render sweep over every screen and sheet in both themes.

### Deliberate choices worth knowing

- **Tax defaults to OFF** (rate stored at 5%). Every worked example in the
  spec is tax-free arithmetic — a 35,000 burger rings up as 35,000. Enable it
  in Settings and every total recomputes.
- **Menu images are emoji tiles.** `MenuItem.imageUrl` exists and is used when
  present; the tinted emoji fallback means the POS grid looks finished with no
  network. Phase 2 supplies real URLs.
- **Platform UI font**, not a downloaded webfont — the app must render
  identically on a cheap handset with no connectivity mid-service.
- **Offline sign-in accepts any non-empty credentials** and returns the seeded
  admin, and never asks for a second factor. The login screen is still shown
  rather than skipped: it is part of the product, and designing or demoing it
  should not require a running backend. A fake OTP prompt with nothing to
  verify against would teach the wrong thing.
- **The session token lives in `SharedPreferences`**, not the platform
  keychain. It is not a password: it expires, it can be revoked from Security →
  Sessions, and changing the account password kills it. Moving to the keychain
  is a Phase 10 hardening step, listed rather than silently assumed.
- **Security screens need the API.** Offline they say so, instead of miming
  2FA enrolment against local state.
- **Audit Logs and Help & Support** are honest "coming soon" screens
  (Phases 8 and 10). Everything else in More is functional.

## Phase 2 — what is built

A PHP REST API over MySQL, and the Flutter client wired to it.

**Schema** — 28 tables. Every restaurant-owned row carries `restaurant_id`;
money is `DECIMAL(14,2)` throughout; indexes follow the query patterns in the
spec. Constraints encode the rules the API also enforces: a takeaway order
cannot hold a table, a cancelled order cannot have an empty reason, a menu
price cannot be zero.

**API** — bearer-token auth resolving the tenant, 40+ endpoints, module-scoped
permissions declared on each route, one audit table behind both the Audit Logs
screen and each order's timeline. See [backend/README.md](backend/README.md).

**The client sends what was ordered, never what it costs.** Item ids and
quantities go up; the server re-reads prices from `menu_items`, applies the
tenant's tax and packaging settings, and returns the totals. A tampered or
stale client cannot change a price.

**Data source is a seam.** `DacaamRepository` has two implementations —
`MockRepository` (seeded, offline) and `ApiRepository` (live). Reducers,
screens and effects cannot tell which is in use. If the API is unreachable at
launch the app falls back to the offline dataset rather than showing an error
page, because a POS that opens is worth more than one that is correct about
being broken.

**Tests** — 86 API tests against a live server and seeded database, plus 6
Flutter integration tests that drive `ApiRepository` against the same backend.
They exist mainly to keep three things from regressing: tenant isolation,
server-computed pricing, and permission enforcement. Two tenants (`HAMZE`,
`WARFA`) are seeded with deliberately different menus, prices and tax settings,
so isolation is observable — if a HAMZE token ever returns "Camel Suqaar",
isolation is broken.

The Flutter integration suite self-skips when no API is running, so
`flutter test` stays green on a machine with no backend.

## Phase 3 — what is built

Authentication, two-factor, sessions, and permissions you can actually edit.

**Sign-in** — restaurant code, phone, password. The code selects the tenant, so
the same phone can belong to staff at two restaurants. It is remembered between
sessions and upper-cased as it is typed; the password never is. The token
persists, so reopening the app mid-shift does not ask again.

**Two-factor** — RFC 6238 TOTP, verified against the spec's own test vectors,
implemented in ~40 lines rather than pulled in as a dependency. Enrolment shows
a QR code and the key; 2FA only switches on once the user proves their app
produces a correct code, so an abandoned setup cannot lock anyone out. Eight
single-use recovery codes, formatted for reading off paper. A used code is
burned immediately — it stays valid for ~90 seconds, and without that a code
read over someone's shoulder works twice.

**Sessions** — every signed-in device is listed with its IP and last use; any
can be revoked, and the current one is labelled and protected from being cut by
accident. Changing a password ends every *other* session.

**Policy, per restaurant** — password rules, session length, lockout
thresholds, and whether admins must use 2FA. A single owner-operator and a
forty-person chain should not share one policy.

**Granular permissions** — the module tree from the spec, editable per role and
overridable per user, so "this one waiter may cancel orders" needs no new role.
The shell reads the same set, so what the screen says and what the API allows
cannot drift. A change that would leave nobody able to manage users is rolled
back, not merely reported.

**Tests** — 79 API tests covering 2FA (including replay, challenge exhaustion
and recovery codes), lockout, policy, session revocation and the permission
lockout guard; 5 widget tests driving the real login gate; 3 more integration
tests for token restore and rejection.

## Phases 4–6 — what is built

Every mutation in the app is now real. Before this, most screens edited local
Redux state and forgot it on restart; now each one calls the API, and the
server's response replaces the slice.

**Phase 4 — POS, orders, drafts.** A cart can be parked as a draft from beside
the Checkout button and picked up later; converting it reprices from the live
menu, so a draft that sat overnight does not resurrect yesterday's prices, and
only at that moment does it become revenue. An open order's lines can be
edited — every added, removed or requantified line is audited individually,
because "the order changed" tells a manager nothing about why the total moved.
Payments can be taken against an outstanding balance.

Three rules the server holds and the tests pin down: a completed or cancelled
order is frozen, an order cannot shrink below what has already been paid, and
it cannot be overpaid.

**Phase 5 — menu, categories, tables.** Item create/edit/delete now persists,
with a price change carrying a reason into the audit trail. Categories have a
proper editor (emoji and colour are part of the record — they are what makes a
category recognisable in the POS chip row). Tables can be added, renamed,
recapacitied and retired; an occupied table refuses to be removed, and its
status is not hand-editable because an order is what makes it occupied.

**Phase 6 — expenses, accounts.** Expenses create/edit/delete against real
account balances. Correcting an amount or payment method reverses the old
posting and makes a new one rather than patching it, so the ledger keeps both
entries and the balance stays explainable. Deleting an expense refunds the
account it came from. Account-to-account transfers move both legs in one
transaction.

**Tests** — 57 new API tests, and 15 Flutter integration tests driving the same
backend through the repository.

Deleting is soft wherever history depends on the row. A "deleted" menu item
stops being orderable but past receipts still resolve; a "deleted" table is
deactivated because orders point at it. That is why the table count only ever
grows.

## Phases 7–8 — what is built

**Phase 7 — advanced reports.** Every section of the Reports screen now shares
one server-side filter set (waiter, order type, category, table, payment), so
the KPI row, the charts and the breakdowns can never disagree about what is
being reported on. Added sales-by-table (takeaway grouped separately rather
than dropped, so the numbers still add up to total sales), low-selling items,
a custom date-range picker, and CSV export of orders, items or expenses.

One honest limitation: with an order-shaped filter applied, expenses show as
zero rather than being silently attributed. Expenses are restaurant-wide — a
waiter does not "own" a share of the rent — and inventing an attribution would
be worse than showing none. The filter sheet says so.

**Phase 8 — SMTP, password reset, audit.** A small SMTP client (EHLO,
STARTTLS, AUTH LOGIN, MIME multipart) written directly for the same reason as
the TOTP code: shared hosting where Composer is not always available and PHP's
`mail()` is unusable. Self-service password reset by email with single-use,
30-minute tokens that revoke every existing session on use. Both reset
endpoints answer identically whether or not the account exists, so they cannot
be used to discover which phone numbers work at which restaurant.

The Audit Logs screen is now real, with module filters and the full
who/what/old/new/reason/IP/device record.

## Phase 9 — what is built

A Super Admin web dashboard at `admin/`: sign-in, platform KPIs, restaurant
provisioning, subscription lifecycle, global reports, a platform audit trail
and SMTP settings. Server-rendered PHP rather than a second Flutter app — it
is used by a handful of people at a desk, and a page of HTML loads faster and
has fewer moving parts than a SPA would for that audience. It reuses the
backend's `Config`, `Database` and `Mailer` by requiring `backend/bootstrap.php`,
so there is exactly one place that knows how to reach MySQL.

**Provisioning is one transaction.** Creating a restaurant writes the tenant
row, its subscription, its settings, the three built-in roles with their
permission grants, the first admin user, four accounts and the starter menu and
expense categories — or none of it. A half-built tenant that cannot sign in is
worse than a failed create, so a duplicate restaurant code rolls the whole
thing back rather than leaving debris.

**Lapsing restricts, it never destroys.** Suspending or expiring a subscription
revokes every live API token immediately — leaving them valid would let a
suspended restaurant keep trading until it happened to sign out — but touches
no data. Orders, menu, balances and staff survive untouched, and renewal
restores access exactly as it was. Renewing a subscription that already lapsed
counts from today, not from the expired end date, so a restaurant that renews
three months late does not pay for time it could not use.

Three decisions worth knowing:

- **A platform password reset ends every session for that user** and forces a
  change on next sign-in. The operator now knows that password, so it must not
  remain a usable long-term credential.
- **The reset form is scoped to the restaurant being viewed.** Passing another
  tenant's user id is refused, not silently honoured — the page is per-tenant
  and so is its authority.
- **A rejected request answers with its real status.** A bad CSRF token returns
  419 with an explanation, not a 302 to the dashboard; a redirect would report
  success to logs and monitoring. Failed actions bounce back to the page they
  came from, but only when the referer is one of ours.

`admin/tests/admin_test.php` drives the real HTML with a cookie jar, reading
each form's CSRF token before posting it — 77 checks covering the guest
redirect, provisioning and its rollback, suspend/reactivate, cross-tenant
password reset, renewal, the audit trail and sign-out.

## Phase 10 — what is built

The hardening pass. Details and measurements are in
[backend/README.md](backend/README.md); the shape of it:

**Rate limiting.** Fixed windows in a `rate_limits` table, declared per route
next to the handler and counted before authentication. Sign-in and the 2FA
exchange get 20 per five minutes per address; password reset gets 5 per
fifteen, because that endpoint sends mail and an unlimited one is a way to use
us to flood somebody's inbox. A successful sign-in clears the bucket — twenty
staff clocking in through one router are not twenty guesses. Nothing is keyed
on the victim's identity, because a per-restaurant throttle would let anyone
lock out a restaurant by failing logins at it.

**Subscriptions enforced at the API boundary.** Suspension refuses everything
and revokes live tokens at the moment it happens. Expiry cannot work that way —
it is a date passing, not an action — so it is decided per request, and it
makes the tenant read-only rather than locking them out: every `GET` works,
writes return 403 `subscription_expired`, and signing out stays exempt.
Renewing restores writing with nothing lost. Holding a restaurant's own records
hostage to collect an invoice would be wrong on its own terms and would make
the renewal conversation harder.

**Index review, measured rather than guessed.** On 60,000 orders the report KPI
query went 154 → 34 ms and the daily chart 196 → 61 ms behind one covering
index; the orders list halved behind another. A third candidate index was
tried and rejected for saving 0.3 ms on a table that is written constantly.

**Release build.** The Android release manifest was missing
`android.permission.INTERNET` — Flutter's template declares it only in the
debug and profile manifests, so a release build compiles and then cannot reach
the API at all. Fixed, along with the app label, a network security config that
refuses cleartext to anything but the development loopback addresses, R8
minification with resource shrinking, and signing from a gitignored
`key.properties` that falls back to the debug key when absent. Two compiled-in
demo credentials were deleted: a real password inside a shipping APK is a
credential anyone with the file can read.

Four smaller fixes found on the way: CORS with a named allowlist was echoing
back whatever `Origin` arrived, which permitted every site while looking like
it permitted four; `APP_DEBUG` defaulted to on; the admin session cookie missed
its `Secure` flag on any SAPI that reports HTTPS as `1` rather than `on`; and
the CSV export skipped the security headers.

## Phase 11 — what is built

The platform side of running DACAAM as a business: what is sold, what was
paid, who is told before it lapses, and who on the platform may do what.

**Plans are rows, not text.** A plan used to be whatever was typed into the
subscription form. Now it is a code, a monthly price, and two limits — active
staff and active tables — that the API enforces when a restaurant adds one or
switches one back on (`422 plan_limit`). Limits are never applied backwards:
moving a restaurant to a smaller plan stops the list growing and switches
nobody off mid-shift. Zero means unlimited, which is what every plan starts as,
so the upgrade restricts nobody until someone decides it should.

**Every payment has an invoice.** A renewal now records the plan, the months
and the exact period it paid for, so the numbered invoice (`INV-2026-00012`)
still says the right thing after the next renewal moves the dates. It prints
cleanly or saves as PDF from the browser, and can be emailed to the
restaurant's admins through the outbox.

**Renewal reminders.** Seven days out, the day before, and once after it ends —
an in-app notification, a push and an email, in Somali, to the restaurant's
admins only. Each is recorded before it is sent, so the daily cron and the
button on the Subscriptions page can both run on the same morning without
anyone being told twice.

**Platform roles.** *Owner* (everything), *Support* (restaurants, staff
passwords, backups, messages) and *Billing* (renewals, invoices, reminders).
Every role can read what it can open; the ability each route needs is declared
next to it, so a forged POST gets a 403 whatever the page offered. Nobody
changes their own role, and the last active owner cannot be demoted or
disabled. Existing administrators became owners.

**Archive, not delete.** A restaurant that leaves is archived: signed out,
removed from the working lists and reminders, every row kept. Its orders,
lines, payments, menu, customers, expenses and staff export as CSV — what a
leaving restaurant is owed — and each download is in the platform audit.
Restoring brings it back suspended, so switching it on is its own decision.

**CSV everywhere a list is.** Restaurants, subscriptions and global reports,
with a byte-order mark so Excel reads Somali names correctly, and formula
injection defused (a cell starting `=`, `+`, `-` or `@` is prefixed).

**The app knows when it is out of date.** The dashboard sets a minimum and a
latest version with a download link; `GET /api/v1/app/version` publishes them.
Below the minimum the app shows an update screen instead of the till, below
the latest it mentions it once. A failed check never blocks the till. APKs
from before this change do not check — hand them the new one once.

## Architecture

```
mobile/lib/
  core/       theme, i18n, formatters, enums, build-time config
  data/
    models/   domain types
    mock/     seeded offline dataset
    api/      HTTP client, endpoints, JSON mappers
    repository/ DacaamRepository + mock and API implementations
  redux/      AppState, 15 state slices, actions, one root reducer, effects
  widgets/    cards, KPIs, chips, sheets, charts, states, animations
  features/   shell, home, pos, orders, menu, reports, more, management

backend/
  public/     front controller + .htaccess
  src/Core/   router, PDO, auth, audit, validation, request/response
  src/Support/ pricing, periods, JSON presenters
  src/Controllers/, src/Repositories/
  database/   schema.sql, seed.sql
  bin/        migrate.php
  tests/      api_test.php

admin/
  public/     front controller, .htaccess, app.css
  src/Core/   AdminAuth, WebRouter, View, Csrf, Flash, Response, PlatformAudit
  src/Services/ Provisioner
  src/Controllers/, src/Views/
  tests/      admin_test.php
```

State is Redux. One root reducer rather than `combineReducers`, because
checkout legitimately moves several slices at once (append order, occupy
table, reset cart) and that transition must be atomic.

Effects never touch a data source directly — they go through
`DacaamRepository`, which is the only place that knows whether the app is
talking to HTTP or to the seeded dataset.

## Roadmap

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | Foundation + core UI | **done** |
| 2 | Backend, MySQL schema, REST API | **done** |
| 3 | Authentication, roles, granular permissions, 2FA | **done** |
| 4 | Full POS, orders, drafts persistence | **done** |
| 5 | Menu, categories, tables CRUD | **done** |
| 6 | Expenses, accounts, payments | **done** |
| 7 | Advanced reports and exports | **done** |
| 8 | Settings, SMTP, audit log module | **done** |
| 9 | Super Admin web + subscriptions | **done** |
| 10 | Testing, security, optimization, release | **done** |
| 11 | Plans, invoices, reminders, platform roles, archive, CSV, app version | **done** |

## Tests

| Suite | Checks |
| --- | --- |
| `backend/tests/api_test.php` | 86 |
| `backend/tests/auth_test.php` | 79 |
| `backend/tests/operations_test.php` | 57 |
| `backend/tests/security_test.php` | 33 |
| `admin/tests/admin_test.php` | 77 |
| `mobile` — `flutter test` | 57 |

The PHP suites run against a live server and each change state they cannot put
back, so re-seed between them:

```bash
php backend/bin/migrate.php --fresh --seed
```

## 📜 License

**Copyright © 2026 hamzik1100 — All Rights Reserved.**

This repository is public for viewing only. You may not use, copy, modify,
deploy or redistribute any part of it without written permission.
See [LICENSE](LICENSE).
