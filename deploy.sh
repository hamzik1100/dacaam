#!/usr/bin/env bash
#
# Deploys the backend and the Super Admin dashboard to dhuuh.shop.
#
#   bash deploy.sh
#
# One SSH connection does the whole job — back up, upload, migrate — so you
# type your password once rather than four times. The bundle step leaves out
# config.local.php and seed.sql, which is why your credentials on the server
# survive being written over and why the demo tenants never land on production.
#
# Nothing here touches the mobile app: that ships as an APK, not over SSH.

set -euo pipefail

# ---------------------------------------------------------------- settings

# The IP, not uk-fast-web702: that name only exists inside Hostinger's network
# and means nothing to DNS out here.
SSH_HOST="u511759483@72.60.22.236"
SSH_PORT="65002"
REMOTE_BASE="/home/u511759483/domains/dhuuh.shop"
PHP="/d/xampp/php/php.exe"

# Where the web server actually looks. This is NOT dacaam/backend/public —
# that directory is never served. api.dhuuh.shop is rooted at public_html/api,
# which holds its own copy of the front controller pointing back at the code in
# dacaam/. Uploading to dacaam/ alone updates every class while leaving that
# copy stale, and the first renamed method takes the whole API down with a
# fatal on every route.
WEB_ROOT="$REMOTE_BASE/public_html/api"

# The Super Admin dashboard, served at dhuuh.shop/admin, with its own copy of
# its own front controller for exactly the same reason.
ADMIN_ROOT="$REMOTE_BASE/public_html/admin"

# Shared hosting drops a connection that goes quiet, and the quiet stretch here
# is migrate.php doing its work. These keep the link alive through it instead of
# leaving you disconnected halfway with the files half-written.
SSH_OPTS=(-o ServerAliveInterval=20 -o ServerAliveCountMax=6 -o ConnectTimeout=20)

# --------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "1/3  Bundle-ka la samaynayo..."
rm -rf "$ROOT/dist"
"$PHP" "$ROOT/backend/bin/bundle.php" >/dev/null
echo "     $(find "$ROOT/dist" -type f | wc -l | tr -d ' ') fayl"

if [ ! -d "$ROOT/dist/backend" ]; then
    echo "Bundle-ku waa fashilmay — dist/backend ma jiro." >&2
    exit 1
fi

echo "2/3  Kor u dhigid + keyd + migration (hal xidhiidh)..."

# The tarball goes down the pipe into the remote tar. The backup runs first,
# before anything is overwritten, and the whole thing stops on the first
# failure rather than half-applying.
tar -czf - -C "$ROOT/dist" . | ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$SSH_HOST" '
    set -e

    cd '"$REMOTE_BASE"'

    BACKUP=~/dacaam-backup-$(date +%F-%H%M%S).tar.gz
    tar -czf "$BACKUP" dacaam/
    echo "     keyd: $BACKUP"

    cd dacaam
    tar -xzf -

    if [ ! -f backend/config/config.local.php ]; then
        echo "config.local.php WAA MAQAN — keydka ka soo celi, ha sii socon" >&2
        exit 1
    fi

    # The tarball is built on Windows, which has no POSIX modes, so extraction
    # can leave files group- or world-writable. LiteSpeed with suEXEC refuses
    # to execute a PHP file in that state and answers 500 — on every route, with
    # nothing in the PHP log, while the CLI runs the same file happily. That
    # combination cost an outage once; this is two seconds of insurance.
    find . -type f -exec chmod 644 {} +
    find . -type d -exec chmod 755 {} +
    echo "     rukhsadaha: 644 / 755"

    # Publish the front controller to the directory the web server serves.
    # The only difference between the two copies is the bootstrap path: the
    # served one sits outside the project, so its relative require would resolve
    # into public_html and find nothing.
    sed "s|^require dirname(__DIR__) . .*bootstrap.php.;|require \x27'"$REMOTE_BASE"'/dacaam/backend/bootstrap.php\x27;|" \
        backend/public/index.php > '"$WEB_ROOT"'/index.php
    chmod 644 '"$WEB_ROOT"'/index.php

    if ! grep -q "^require .'"$REMOTE_BASE"'/dacaam/backend/bootstrap.php.;" '"$WEB_ROOT"'/index.php; then
        echo "index.php-ka web-ka waddadiisu ma saxna — JOOJI" >&2
        exit 1
    fi
    echo "     web root: index.php la cusboonaysiiyay"

    # The dashboard has the same arrangement and had the same bug: files went to
    # dacaam/admin while public_html/admin kept serving whatever front controller
    # was installed by hand the first time. A route added here simply never
    # appeared and the page answered its own 404, which reads as a missing
    # feature rather than as a stale file.
    if [ -d '"$ADMIN_ROOT"' ]; then
        sed "s|^require dirname(__DIR__) . .*bootstrap.php.;|require \x27'"$REMOTE_BASE"'/dacaam/admin/bootstrap.php\x27;|" \
            admin/public/index.php > '"$ADMIN_ROOT"'/index.php
        chmod 644 '"$ADMIN_ROOT"'/index.php
        echo "     dashboard: index.php la cusboonaysiiyay"

        # The stylesheet is a real file the web server hands over directly —
        # it never passes through PHP, so shipping the code without it leaves
        # new markup styled by whatever CSS was copied here by hand the first
        # time. That is a change that appears to deploy successfully and then
        # does nothing.
        mkdir -p '"$ADMIN_ROOT"'/assets
        cp -f admin/public/assets/* '"$ADMIN_ROOT"'/assets/
        chmod 644 '"$ADMIN_ROOT"'/assets/*
        echo "     dashboard: assets la cusboonaysiiyay ($(ls admin/public/assets | wc -l) fayl)"
    else
        echo "     DIGNIIN: public_html/admin ma jiro — dashboard-ku ma cusboonaysiin"
    fi

    cd backend

    echo
    echo "--- keyd ---"
    # Before the migrations, never after. A schema change that goes wrong is
    # exactly when last night is worth having, and by the time it has gone
    # wrong it is too late to take one.
    php bin/backup_db.php || echo "     DIGNIIN: keyd lama qaadin — eeg kor"

    echo
    # Schema first, then the upgrades that reshape it, then the one that moves
    # data. Every one of them checks before it acts, so running this script
    # twice is the same as running it once.
    php bin/migrate.php

    echo
    echo "--- payment methods ---"
    # Creates the payment_methods table and drops UNIQUE(restaurant_id, method)
    # so a restaurant can hold two banks. Everything on the Manage Accounts
    # screen 404s without it.
    php bin/upgrade_payment_methods.php

    echo
    echo "--- draft cancel ---"
    # draft_orders.cancel_reason. Cancelling a draft fails without the column.
    php bin/upgrade_draft_cancel.php

    echo
    echo "--- macmiisha: orders.customer_id ---"
    php bin/upgrade_customer_orders.php

    echo
    echo "--- payment_status ---"
    # Splits paid-ness out of orders.status and backfills history from the
    # payments already recorded. Credit orders are impossible without it.
    php bin/upgrade_payment_status.php

    echo
    echo "--- fariimaha ---"
    # notifications, notification_reads, device_tokens.
    php bin/upgrade_notifications.php

    echo
    echo "--- codsiyada la celiyo ---"
    # request_keys: a deposit sent twice used to be two deposits.
    php bin/upgrade_request_keys.php

    echo
    echo "--- ogaysiisyada emailka ---"
    # email_outbox, plus the per-restaurant switches. Alerts queue rather than
    # send inline, so a slow mail server can never hold up a till.
    php bin/upgrade_alerts.php

    echo
    echo "--- kharashka: joojin halkii tirtirid ---"
    # cancelled_at + sabab. Kharash la tirtiray waa lacag aan la sharxi
    # karin; hadda waa la joojiyaa oo diiwaanku wuu hadhayaa.
    php bin/upgrade_expense_cancel.php

    echo
    echo "--- xidhitaanka shifka ---"
    # shifts, shift_id ledger-ka iyo dalabyada, xadka farqiga, iyo
    # ogolaanshaha. shifts.view iyo shifts.manage waa kala duwan yihiin si
    # tirinta sanduuqa aan looga sheekaysan lambarka la filayo.
    php bin/upgrade_shifts.php

    echo
    echo "--- xisaabaad kasta la tirinayo ---"
    # shift_counts: xisaab kasta wuxuu leeyahay farqigiisa. Sanduuq gaabis
    # ah iyo Zaad dheeraad ah oo isku dhici kara waa laba dhibaato.
    php bin/upgrade_shift_counts.php

    echo
    echo "--- celinta lacagta: saf taban ---"
    # order_payments wuxuu diidayay lambar taban, marka dalab la yareeyay
    # wuxuu sii sheegayay lacag uu dib u celiyay. Warbixinta iyo sanduuqa
    # ayaa is khilaafayay.
    php bin/upgrade_refund_rows.php

    echo
    echo "--- amniga maamulayaasha platform-ka ---"
    # 2FA iyo maamul. Akoonka makhaayad kasta gaadhi karaa wuxuu lahaa
    # password oo kaliya, oo mid keliya oo aan la beddeli karin.
    php bin/upgrade_admin_security.php

    echo
    echo "--- qorshayaal, qaansheegyo, xusuusin, doorar, kayd ---"
    # plans (qiimaha iyo xadka shaqaalaha/miisaska), waxa lacag kasta
    # iibsatay (qaansheegga), subscription_reminders, super_admins.role iyo
    # restaurants.status = archived. Maamulayaasha jira waxay noqdaan owner.
    php bin/upgrade_platform_billing.php

    echo
    echo "--- macmiisha: jeebka la qaatay ee aan la diiwaangelin ---"
    # Credit mode used to spend a deposit without writing a payment row, so
    # the order stayed `unpaid` for ever while the money had gone. This
    # writes the missing row and re-derives the status. It reports first and
    # only changes rows it can prove from `balance_after`, and re-running it
    # after a fix finds nothing.
    php bin/repair_wallet_orders.php --fix

    echo
    echo "--- macmiisha: isbarbardhig ---"
    # Read-only. Exits non-zero if a cached balance has drifted from its
    # ledger, which is money either lost or wrongly chased.
    php bin/reconcile_customers.php || echo "     DIGNIIN: xisaabo kala tegey — eeg kor"

    echo
    echo "--- waqtiga ---"
    # Writes a marker the first time and refuses to run again, so it can never
    # turn a three-hour correction into a six-hour error.
    php bin/fix_timestamps.php
'

echo "3/3  Xaqiijin..."

ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$SSH_HOST" "cd $REMOTE_BASE/dacaam/backend && php -r '
    require \"bootstrap.php\";
    use Dacaam\\Core\\Database;

    \$schema = Database::scalar(\"SELECT DATABASE()\");
    \$has = static function (string \$t, string \$c) use (\$schema): bool {
        return (int) Database::scalar(
            \"SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = :s AND TABLE_NAME = :t AND COLUMN_NAME = :c\",
            [\"s\" => \$schema, \"t\" => \$t, \"c\" => \$c],
        ) > 0;
    };

    echo \"     permissions    : \" . Database::scalar(\"SELECT COUNT(*) FROM permissions\") . PHP_EOL;
    foreach (Database::select(\"SELECT r.code, COUNT(rp.permission_id) n FROM roles r LEFT JOIN role_permissions rp ON rp.role_id = r.id GROUP BY r.id, r.code ORDER BY r.id\") as \$x) {
        printf(\"       %-10s %d\" . PHP_EOL, \$x[\"code\"], \$x[\"n\"]);
    }

    echo \"     payment_methods: \" . Database::scalar(\"SELECT COUNT(*) FROM payment_methods\") . PHP_EOL;
    echo \"     cancel_reason  : \" . (\$has(\"draft_orders\", \"cancel_reason\") ? \"waa jiraa\" : \"MAQAN\") . PHP_EOL;
    echo \"     accounts.method: \" . Database::scalar(
        \"SELECT COLUMN_TYPE FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = :s AND TABLE_NAME = \\\"accounts\\\" AND COLUMN_NAME = \\\"method\\\"\",
        [\"s\" => \$schema],
    ) . PHP_EOL;

    \$stuck = (int) Database::scalar(
        \"SELECT COUNT(*) FROM roles r WHERE r.is_system = 1
          AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id)\",
    );
    if (\$stuck > 0) {
        echo \"     DIGNIIN: \$stuck role oo permission la aan ah\" . PHP_EOL;
    }
'"

echo
echo "Waa dhammaatay. App-ka ka bax oo dib u gal."
