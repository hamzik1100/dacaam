# DACAAM — Super Admin dashboard

The platform operator's view: every restaurant on the system, their
subscriptions, global trading figures, and the audit trail of what the operator
did. Server-rendered PHP, no build step, no JavaScript framework.

It is not a second copy of the backend. `bootstrap.php` requires
`../backend/bootstrap.php`, so `Config`, `Database` and `Mailer` are the same
classes the API uses and there is exactly one place that knows how to reach
MySQL.

## Running it

```bash
php -S 127.0.0.1:8091 -t admin/public admin/public/index.php
```

Under Apache, point a vhost or alias at `admin/public`; `.htaccess` sends
everything that is not a real file to `index.php`, and `Response::url()` copes
with the dashboard living under a subdirectory.

Sign in with `super@dacaam.test` / `admin123` from the seed. Five failed
attempts lock the account for fifteen minutes.

**On a server there is no seed**, and so nobody to sign in as. The dashboard
redirects to `/setup`, which creates the first platform administrator and then
closes for good — a second visit goes to `/login`, and the guard is re-checked
inside the transaction so two people opening the page at once cannot both
become administrator. That is the entire access control on that page, and it
has to be: there is no credential to check before the first one exists.

## Tests

```bash
php admin/tests/admin_test.php http://127.0.0.1:8091
```

292 checks against a live server, driven through the real HTML with a cookie
jar — the role checks sign in as each role with a jar of its own. Every POST fetches its form first to read the CSRF token, so a broken CSRF
pipeline fails the suite instead of quietly passing. Run
`php backend/bin/migrate.php --fresh --seed` first — the suite expects the two
seeded tenants.

## What it does

| Page | What it is for |
| --- | --- |
| Dashboard | Tenant counts, subscription revenue, busiest restaurants, renewals due, recent platform activity |
| Restaurants | Search and filter tenants; create, edit, suspend, reactivate; reset a staff password; archive and restore; export their data as CSV |
| Subscriptions | Plan, status, end date and money collected; renew or adjust; renewal reminders; CSV export |
| Plans | Monthly price and staff/table limits per plan; retire a plan without touching who is on it |
| Invoices | A numbered, printable invoice for every subscription payment; email it to the restaurant |
| Global reports | Platform volume over 7/30/90/365 days, daily chart, breakdown by restaurant, tenant growth; CSV export |
| Platform audit | Every operator action, filterable, append-only |
| Administrators | Add, disable, and set roles — owner, support, billing |
| Settings | SMTP, invoice details, the mobile app's minimum and latest version, system values |

## Roles

| Role | Can act on |
| --- | --- |
| Owner | Everything, including administrators, settings, plans and archiving |
| Support | Restaurants (edit, suspend, staff passwords, create), backups, notifications, data export, health, tills, audit |
| Billing | Renewals, subscription adjustments, invoices, reminders |

Every role reads every page it can open. The ability a route needs is declared
next to it in `public/index.php` and checked by `WebRouter` before the handler
runs, so a forged request gets a 403 whatever the page offered. Nobody changes
their own role, and the last active owner cannot be demoted or disabled.

## How it behaves

**Provisioning is all-or-nothing.** `Provisioner::create()` writes the tenant,
its subscription, its settings, three built-in roles with permission grants, the
first admin user, four accounts, and starter menu and expense categories inside
one transaction. A restaurant that exists but cannot sign in is worse than a
create that failed, so a duplicate code rolls everything back.

**Suspension restricts; it never deletes.** Suspending revokes every live API
token immediately — otherwise a suspended restaurant keeps trading until it
happens to sign out — and changes nothing else. Orders, menu, balances and
staff are untouched, and reactivating restores access exactly as it was.

**Renewal counts from today when a subscription has already lapsed**, not from
the expired end date. A restaurant renewing three months late should not pay
for time it could not use.

**A password reset ends every session for that user** and forces a change on
next sign-in. The operator now knows that password; it must not stay a usable
long-term credential. The form is scoped to the restaurant on screen — passing
another tenant's user id is refused, not silently honoured.

**A rejected request answers with its real status.** A bad or missing CSRF
token returns 419 with an explanation rather than redirecting to the dashboard;
a 302 would report success to logs and monitoring. Failed actions do bounce
back to the page they came from, but only when the referer is one of ours —
following an attacker-supplied referer would make every failed POST an open
redirect.

**Sign-in is limited two ways.** Five failures lock the account for fifteen
minutes, and one address gets thirty attempts an hour whatever addresses it
tries — the account lockout alone does nothing against someone working through
a list of emails. A successful sign-in clears the address count.

**The dashboard ships no JavaScript**, so its CSP is `default-src 'none'` with
`script-src` unset — any script injected into a page is a blocked request
rather than a working one. Inline styles are allowed because the views use
style attributes for one-off spacing. Nothing may frame it, and the session
cookie is HttpOnly, SameSite=Lax, and Secure whenever the request arrived over
TLS.

## Layout

```
public/     index.php (front controller), .htaccess, assets/app.css
src/Core/   AdminAuth, Access, WebRouter, View, Csrf, Csv, Flash, Response, PlatformAudit
src/Services/  Provisioner
src/Controllers/  Auth, Dashboard, Restaurant, Subscription, Plan, Invoice, Platform, ...
src/Views/  layout.php, login.php, and one file per page
tests/      admin_test.php
```

`WebRouter` requires a session for every non-guest route and verifies CSRF on
every POST, so a controller cannot forget either. `View` renders into the
layout and exposes `e()`, `money()`, `shortDate()` and `dateTime()` in the
`DacaamAdmin\Core` namespace — views import them with
`use function DacaamAdmin\Core\e;`.
