# DACAAM API

PHP 8.2 + MySQL/MariaDB REST API for the DACAAM restaurant POS.

```
Flutter → REST API → PHP → MySQL
```

No Composer, no framework: a PSR-4 autoloader, a small router, PDO, and
controllers. Deployment is copying the folder onto any PHP host.

## Run it

```bash
php bin/migrate.php --fresh --seed
```

```bash
php -S 127.0.0.1:8090 -t public public/index.php
```

```bash
php tests/api_test.php http://127.0.0.1:8090
```

```bash
php bin/migrate.php --fresh --seed && php tests/auth_test.php http://127.0.0.1:8090
```

```bash
php bin/migrate.php --fresh --seed && php tests/operations_test.php http://127.0.0.1:8090
```

Re-seed between suites. `auth_test.php` deliberately locks an account, changes
a password and enables 2FA; `operations_test.php` edits orders and balances.
Each wants a clean database and leaves one the others would not recognise.

Under XAMPP/Apache instead, point a vhost `DocumentRoot` at `backend/public`;
the bundled `.htaccess` handles rewriting and preserves the `Authorization`
header that CGI otherwise strips.

Configuration lives in `config/config.php` and reads environment variables
(`DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `APP_DEBUG`). Drop a
gitignored `config/config.local.php` returning an array to override per machine.

**Seeded logins** (local development only — password `admin123`):

| Code | Phone | Role |
| --- | --- | --- |
| HAMZE | 0634567890 | Admin |
| HAMZE | 0631122334 | Operator |
| HAMZE | 0632233445 | Waiter |
| WARFA | 0637778899 | Admin |

## Tenancy

`restaurant_id` is taken from the authenticated token and never from a request
body or query string. Reads go through `Repository::requireScoped()`, which
requires a restaurant id — there is no `find($id)` without a tenant anywhere in
the codebase.

A row that belongs to another restaurant returns **404, not 403**: confirming
that an id exists elsewhere would itself leak across tenants. The same applies
to login — a wrong restaurant code and a wrong password produce byte-identical
responses, so the endpoint cannot enumerate which restaurants exist.

## Business rules the server owns

The client sends *what* was ordered — item ids and quantities. It never sends
prices or totals, and anything price-shaped in the request body is ignored.

- Prices are re-read from `menu_items` on every quote (`Support/Pricing.php`).
- Discount comes off the subtotal before tax, and is capped at the subtotal.
- Tax applies only when enabled, at the rate stored on the order at the time.
- The packaging fee is one flat charge on a takeaway order containing at least
  one packaging-eligible line.
- Takeaway orders never carry a table — enforced in the controller *and* by a
  schema `CHECK`.
- Dine In requires a table when `require_table_for_dine_in` is on.
- Cancelling requires a reason — controller, schema `CHECK`, and client.
- Completed and cancelled orders are terminal; reopening returns 409.
- Completing or cancelling a dine-in order frees its table.
- Payments post to the matching account and write an `account_transactions`
  row, so Accounts reconciles with takings without a nightly job.
- Drafts are not sales. Nothing in reports, KPIs or account balances reads
  them until `POST /drafts/{id}/convert`, which reprices from the live menu.
- Only open orders can be edited. A completed order records money that moved;
  a cancelled one records money that did not. Editing either after the fact
  would make the day's takings a fiction.
- An order cannot be edited below what has already been paid, and cannot be
  overpaid.
- Correcting an expense reverses its old account posting and makes a new one
  rather than patching it, so the ledger keeps both and the balance stays
  explainable. Deleting one refunds the account it came from.
- The restaurant's plan limits active staff and active tables. Adding one, or
  switching one back on, past the limit returns 422 `plan_limit`. Nothing
  already active is ever switched off by a smaller plan; zero is unlimited.
- An archived restaurant is refused like a suspended one, and keeps every row.

## Audit trail

One `audit_logs` table backs both the global Audit Logs screen and an
individual order's timeline (filter by `module` + `record_id`), so the two can
never diverge. Entries carry user, action, field, old value, new value, reason,
IP and device.

## Authentication

Sign-in is two steps when the account has 2FA:

```
restaurant code + phone + password  →  challenge
challenge + OTP (or recovery code)  →  session token
```

A challenge is not a session. It expires in five minutes, dies after five wrong
codes, is single-use, and grants nothing except the right to present a code.

**TOTP** is RFC 6238 (HMAC-SHA1, 6 digits, 30s, ±1 step of drift), implemented
in `Core/Totp.php` rather than pulled in as a dependency — the algorithm is
forty lines and the deployment target is shared hosting where "just add
Composer" is not always an option. It is verified against the RFC's own test
vectors. Any authenticator app works: Google Authenticator, Authy, Aegis,
1Password.

A correct code is burned on use: it stays valid for roughly ninety seconds, and
without that a code read over someone's shoulder would work twice.

**Recovery codes** — eight, issued once at enrolment, formatted `4F7K-92QX`
with no 0/O/1/I because they get read off paper under kitchen lighting. Stored
hashed; each works once.

**Enrolment cannot lock anyone out.** `two_factor_secret` is set when setup
starts, but `two_factor_confirmed_at` — the flag that actually turns 2FA on —
is only set once the user proves their authenticator produces a correct code.
An abandoned setup changes nothing.

## Password policy and lockout

Both are per-restaurant, in `restaurant_settings`: minimum length, whether an
uppercase letter, number or symbol is required, session length, how many failed
attempts trigger a lockout and for how long, and whether admins must use 2FA.
A single owner-operator and a chain with forty staff should not be forced onto
the same rules — a policy nobody can live with just produces passwords on
sticky notes.

Changing a password revokes every other session for that user. So does an admin
resetting it, and a password an admin set for someone else is flagged
`must_change_password` until that person replaces it.

## Endpoints

All paths are prefixed `/api/v1`. Every route except `health` and
`auth/login` requires `Authorization: Bearer <token>`; the permission listed is
checked before the handler runs.

| Method | Path | Permission |
| --- | --- | --- |
| GET | `/health` | — |
| GET | `/app/version` | — (minimum and latest app version, download link) |
| POST | `/auth/login` | — |
| POST | `/auth/2fa/verify` | — (holds a challenge, not a session) |
| GET | `/auth/me` | authenticated |
| POST | `/auth/logout` | authenticated |
| GET | `/security/overview` | authenticated (own account) |
| POST | `/security/2fa/setup`, `/2fa/confirm`, `/2fa/disable` | authenticated (own account) |
| POST | `/security/2fa/recovery-codes` | authenticated (own account) |
| GET | `/security/sessions`, `/security/login-history` | authenticated (own account) |
| DELETE | `/security/sessions/{id}` | authenticated (own account) |
| POST | `/security/sessions/revoke-others` | authenticated (own account) |
| POST | `/security/password` | authenticated (own account) |
| GET/PUT | `/security/policy` | `settings.view` / `settings.manage` |
| PUT | `/users/{id}/permissions` | `users.edit` |
| POST | `/roles` | `users.create` |
| PUT | `/roles/{id}/permissions` | `users.edit` |
| DELETE | `/roles/{id}` | `users.delete` |
| GET | `/bootstrap` | authenticated |
| GET | `/orders` | `orders.view` |
| POST | `/orders` | `orders.create` |
| GET | `/orders/{id}` | `orders.view` |
| GET | `/orders/{id}/history` | `orders.view` |
| PATCH | `/orders/{id}/status` | `orders.view` (+ `orders.edit` / `orders.cancel`) |
| PUT | `/orders/{id}/items` | `orders.edit` |
| POST | `/orders/{id}/payments` | `orders.edit` |
| GET/POST | `/drafts` | `orders.view` / `orders.create` |
| GET/PUT/DELETE | `/drafts/{id}` | `orders.view` / `orders.create` |
| PUT | `/expenses/{id}` | `expenses.edit` |
| POST/DELETE | `/expense-categories` | `expenses.create` / `expenses.delete` |
| POST | `/drafts/{id}/convert` | `orders.create` |
| GET | `/menu/items`, `/menu/categories` | `menu.view` |
| POST/PUT/DELETE | `/menu/items`, `/menu/categories` | `menu.create` / `menu.edit` / `menu.delete` |
| PATCH | `/menu/items/{id}/availability` | `menu.edit` |
| GET | `/tables` | `tables.view` |
| POST/PUT/DELETE | `/tables` | `tables.manage` |
| GET | `/expenses`, `/expense-categories` | `expenses.view` |
| POST | `/expenses` | `expenses.create` |
| DELETE | `/expenses/{id}` | `expenses.delete` |
| GET | `/accounts`, `/accounts/transactions` | `accounts.view` |
| POST | `/accounts/transfer` | `accounts.manage` |
| GET | `/reports/summary`, `/reports/dashboard` | `reports.view` |
| GET/PUT | `/settings` | `settings.view` / `settings.manage` |
| GET/POST/PUT/DELETE | `/users` | `users.*` |
| GET | `/roles`, `/permissions` | `users.view` |
| GET | `/audit-logs` | `audit.view` |

### Response envelope

```json
{ "data": { } }
{ "error": { "code": "validation_failed", "message": "...", "fields": { "table_id": "..." } } }
```

## Security notes

- Passwords are bcrypt (`password_hash`); tokens, challenges and recovery codes
  are random bytes stored only as SHA-256 hashes, so a database leak yields no
  usable sessions or codes.
- Failed logins lock an account per the tenant's policy; every attempt is
  recorded in `login_attempts` with IP and device.
- Changing a user's password or deactivating them revokes their live tokens.
- Disabling 2FA or regenerating recovery codes costs the account password, even
  though the caller is already authenticated — both are downgrades in account
  security.
- A permission change that would leave the restaurant with nobody able to
  manage users is rejected *inside the transaction*, so the change rolls back
  rather than being reported after the fact.
- Deleting is soft wherever history depends on the row (menu items, categories,
  users, tables) — receipts and audit entries must keep resolving.
- `display_errors` is off; internal errors log server-side and return a generic
  500 unless `APP_DEBUG` is on — and `APP_DEBUG` follows `APP_ENV`, so it is off
  unless you are on `local` or ask for it. Forgetting a flag should not be the
  thing that publishes a stack trace.
- Every response carries `nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer` and `Cache-Control: no-store` — tenant data
  under a bearer token must not sit in a proxy or a browser's back-forward
  cache. HSTS is added only when the request actually arrived over TLS.
- CORS with a named allowlist now *enforces* the allowlist. It previously
  echoed back whatever `Origin` header arrived, which permitted every site on
  the internet while reading like it permitted four.

## Rate limiting

`Core/RateLimiter.php`, fixed windows in a `rate_limits` table — MySQL rather
than memory because the target is shared hosting, where APCu is per-process and
Redis is not on offer.

| Endpoint | Limit per address |
| --- | --- |
| `POST /auth/login` | 20 / 5 min |
| `POST /auth/2fa/verify` | 20 / 5 min |
| `POST /auth/password/forgot` | 5 / 15 min |
| `POST /auth/password/reset` | 10 / 15 min |
| Super Admin sign-in | 30 / hour |

Limits are declared on the route next to the handler, and counted *before*
authentication — a limit applied after the password check still spends the
database's time on every guess.

Two decisions worth knowing:

- **A successful sign-in clears the bucket.** Twenty staff clocking in through
  one restaurant's router are not twenty guesses, and without this the morning
  rush would lock a restaurant out of its own till.
- **Nothing is keyed on the victim's identity.** A per-restaurant-code throttle
  would let anyone lock out an entire restaurant by failing logins at it. The
  per-account lockout already carries that risk deliberately and narrowly;
  widening it to a whole tenant would be handing out a denial-of-service lever.

## Subscriptions at the API boundary

Suspension and expiry are different things and are enforced differently.

**Suspended** is the platform switching a tenant off: `Auth::authenticate()`
refuses everything, reads included, and the Super Admin dashboard revokes live
tokens at the moment of suspension so it bites immediately.

**Expired** is a date passing, which nobody performs and no token revocation can
catch, so it is decided on each request. A lapsed tenant becomes read-only:
every `GET` works, every write returns 403 with code `subscription_expired`,
and `POST /auth/logout` is exempt. They keep their orders, their reports and
their exports; renewing restores writing with nothing lost. Locking a
restaurant out of its own records to collect an invoice would be holding the
data hostage, and it would also make the renewal conversation harder, not
easier.

A restaurant with no subscription row at all is left alone. That is a
provisioning gap on our side, and a working restaurant should not be stopped
over our missing record.

## Index review

Measured on 60,000 orders and 150,000 order items spread over eighteen months,
best of seven runs:

| Query | Before | After |
| --- | --- | --- |
| Report KPI summary | 154 ms | **34 ms** |
| Daily revenue chart | 196 ms | **61 ms** |
| Orders list filtered by status | 12.9 ms | **5.8 ms** |

Two indexes were added: `ix_orders_revenue (restaurant_id, created_at, status,
total)`, which covers every money question so it never touches the table, and
`ix_orders_status_created`, which removes the filesort behind the Orders
screen's status tabs. Insert cost was measured over 3,000 rows and did not
move outside noise.

A third — `(restaurant_id, module, created_at)` on `audit_logs` — was tried and
**rejected**: at 320,000 rows it saved 0.3 ms, and that table is written on
nearly every mutation, so an index that does not earn its keep on reads is a
pure tax on writes.

## Mail and password reset

`Core/Mailer.php` is a small SMTP client (EHLO, optional STARTTLS, AUTH LOGIN,
MIME multipart), written directly rather than pulled in for the same reason as
`Totp` — shared hosting, no Composer, and PHP's `mail()` is unusable on most of
it. Configuration lives in `system_settings` because SMTP credentials are a
platform concern, not a per-restaurant one.

`POST /auth/password/forgot` and `/auth/password/reset` are unauthenticated by
necessity — the caller cannot sign in. Both answer identically whether or not
the account exists, so neither can be used to discover which phone numbers work
at which restaurant. Tokens are single-use, expire in 30 minutes, and using one
revokes every existing session for that user.

With no SMTP host configured the request endpoint still returns its generic
success response and logs the real reason server-side, so a restaurant without
mail keeps working — it just has no self-service reset.

## Going to production

1. Copy `config/config.local.example.php` to `config/config.local.php` and fill
   in the database credentials, or set `DB_*` environment variables instead and
   keep credentials off the filesystem entirely.
2. Set `APP_ENV` to anything other than `local`. That alone turns debug detail
   off; `APP_DEBUG=false` is belt and braces.
3. Give MySQL a dedicated user with rights on `dacaam_db` only — not root.
4. Point the vhost's document root at `backend/public`. Nothing above it should
   be reachable over HTTP; `.htaccess` assumes `mod_rewrite`.
5. Serve over TLS. HSTS turns itself on once requests arrive over HTTPS, and
   the mobile app's network config refuses cleartext to anything but the
   development loopback addresses.
6. If you also serve a Flutter web build, list its origin in `cors.allowed_origins`.
   Leaving `*` there means any site can call the API with a token it has stolen
   by other means.
7. Run `php bin/migrate.php` on the target. It is idempotent and drops nothing.
8. Point the four suites at the deployed URL before letting anyone in.

## Tests

```bash
php bin/migrate.php --fresh --seed
php tests/api_test.php        http://127.0.0.1:8090   # 86
php tests/auth_test.php       http://127.0.0.1:8090   # 79
php tests/operations_test.php http://127.0.0.1:8090   # 57
php tests/security_test.php   http://127.0.0.1:8090   # 33
php tests/plans_test.php      http://127.0.0.1:8090   # 48
```

Or all of them, each on a freshly seeded database, with the host's
restrictions applied: `bash test_server.sh` from the repository root.

`auth_test`, `operations_test` and `security_test` each change state they
cannot put back — locked accounts, expired subscriptions, filled throttle
buckets — so re-seed between them.
