#!/usr/bin/env bash
#
# Builds the shipping APK for DHUUH.
#
#   bash build_apk.sh
#
# The defines below are the whole point of this file. `flutter build apk`
# without them produces a working-looking app that runs entirely on the seeded
# demo dataset: it accepts any restaurant code, phone and password, shows
# invented takings, and never contacts the server at all. That APK was built
# and handed over once. This script is so it cannot be the easy path again.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/mobile"

API_BASE_URL="https://api.dhuuh.shop/api/v1"

echo "1/5  Serverka la hubinayo — $API_BASE_URL"

# Built against a server that is not answering, the APK is not shippable: the
# first thing staff would meet is a sign-in that cannot complete. Better to
# find out here than after it is on a handset.
health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$API_BASE_URL/health" || true)"
if [ "$health" != "200" ]; then
    echo "     FAIL: /health -> ${health:-ma jawaabin}" >&2
    echo "     Server-ku ma shaqaynayo. DEPLOY.bat marka hore ordi." >&2
    exit 1
fi
echo "     OK (200)"

# The customer routes are the newest thing the app depends on. 404 here means
# the backend on the server is older than this app, and the customer screens
# would be empty with no explanation.
customers="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$API_BASE_URL/customers" || true)"
if [ "$customers" = "404" ]; then
    echo "     FAIL: /customers -> 404 — backend-ku wuu duugoobay." >&2
    echo "     DEPLOY.bat marka hore ordi, kaddibna mar kale halkan ku noqo." >&2
    exit 1
fi
echo "     /customers -> $customers (jira)"

echo "2/5  Imtixaanada..."

# The app compares AppConfig.appVersion with the minimum set in the dashboard.
# If it drifts from pubspec.yaml, a brand-new APK can describe itself as old
# and lock itself out on the first start.
pub_version="$(grep -m1 -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9.]+).*/\1/')"
app_version="$(grep -m1 -E "appVersion = '" lib/core/config/app_config.dart | sed -E "s/.*appVersion = '([0-9.]+)'.*/\1/")"
if [ "$pub_version" != "$app_version" ]; then
    echo "     FAIL: pubspec.yaml waa $pub_version, AppConfig.appVersion waa $app_version" >&2
    echo "     Labadaba isku mid ka dhig, kaddibna mar kale dhis." >&2
    exit 1
fi
echo "     nooca: $app_version"

flutter analyze --no-pub

# -j 1, not the default. The runner starts one VM per core, and on this machine
# that exhausted memory and killed the shell mid-suite — which reads as failing
# tests rather than as a machine that ran out of room. Slower, and honest.
flutter test --no-pub -j 1

echo "3/5  APK-ga la dhisayo..."
flutter build apk --release \
    --dart-define=USE_API=true \
    --dart-define=API_BASE_URL="$API_BASE_URL" 

APK="$ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "APK lama helin: $APK" >&2; exit 1; }

echo "4/5  Xaqiijin — cinwaanka server-ka ma ku dhex jiraa APK-ga?"

# Reads the built artefact rather than trusting the command line above: a
# typo in a dart-define is silent, and the app would fall back to demo data
# exactly as before. If the host string is not in the binary, it was not baked
# in, and this must not be shipped.
if ! grep -qa "api.dhuuh.shop" "$APK"; then
    echo "     FAIL: 'api.dhuuh.shop' APK-ga kuma jiro — dart-define ma dhicin." >&2
    exit 1
fi
echo "     OK — server-ku wuu ku dhex jiraa"

echo "5/5  Xaqiijin — saxeexa release-ka miyaa?"

# An APK signed with the debug key installs and runs perfectly well, which is
# exactly the problem: it looks finished, cannot be published, and the debug key
# lives in a per-machine file nobody backs up. Handing one out strands every
# install the day that file is lost.
#
# Read out of the built artefact rather than trusting that key.properties was
# present — a wrong path there falls back to debug in silence, and the silence
# is the whole risk.
#
# apksigner, not `keytool -printcert -jarfile`: keytool reads the old v1 JAR
# signature, and a modern Flutter release carries v2/v3 only. Asking the wrong
# tool produced an empty answer that read exactly like a debug-signed APK — a
# check that fails when nothing is wrong gets switched off, which is worse than
# having none.
export JAVA_HOME="${JAVA_HOME:-D:/android/jbr}"

APKSIGNER=""
for candidate in \
    "$HOME/AppData/Local/Android/Sdk/build-tools"/*/apksigner.bat \
    /d/android/sdk/build-tools/*/apksigner.bat; do
    [ -f "$candidate" ] && APKSIGNER="$candidate"
done

if [ -z "$APKSIGNER" ]; then
    echo "     DIGNIIN: apksigner lama helin — saxeexa lama hubin" >&2
else
    signer="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -m1 'certificate DN:' || true)"

    if ! echo "$signer" | grep -q "CN=DACAAM POS"; then
        echo "     FAIL: APK-gu ma saxeexna furaha release-ka." >&2
        echo "     ${signer:-saxeex lama akhriyi karin}" >&2
        echo "     mobile/android/key.properties hubi — HA QAYBIN." >&2
        exit 1
    fi

    echo "     OK — CN=DACAAM POS"
fi
cp "$APK" "$ROOT/DACAAM.apk"
echo
echo "Diyaar: $ROOT/DACAAM.apk"
ls -lh "$ROOT/DACAAM.apk" | awk '{print "        " $5}'
