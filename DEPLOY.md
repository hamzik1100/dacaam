# Sida update cusub loo diro

Saddex fayl oo la gujiyo. Kala duwanaanshahoodu waa muhiim:

| Faylka | Waxa uu taabanayo | Goorma |
|---|---|---|
| `TEST.bat` | Kombiyuutarkaaga oo keliya | Deploy kasta ka hor |
| `DEPLOY.bat` | Server-ka (API + web dashboard) | Marka backend/admin la beddelo |
| `BUILD.bat` | APK-ga | Marka `mobile/` la beddelo **oo keliya** |

---

## 1. `TEST.bat` — hubi inaan waxba jabin

**Ka hor: XAMPP MySQL waa inuu shaqaynayaa.** Haddii kale wuu fashilmi doonaa isla markiiba.

Wuxuu qabtaa:

- Database-ka **maxalliga ah** ayuu dib u dhisayaa imtixaan kasta ka hor (`--fresh --seed`)
- Wuxuu bilaabayaa laba server oo leh **isla xayiraadaha Hostinger** (`exec` la damiyay, error log fayl ku qorayo)
- Wuxuu ordayaa 390 hubin: API, auth, operations, security, dashboard
- Ugu dambayn wuxuu eegayaa log-ga khaladaadka

Waxa aad rabto inaad aragto:

```
  ------------------------------------------
  390 guulaystay, 0 fashilmay
  ------------------------------------------
```

Iyo `Waa nadiif — khalad lama qorin.`

> **Database-ka server-ka MA taabanayo.** `dacaam_db` ee kombiyuutarkaaga ayuu tirtirayaa oo dib u dhisayaa. Xogta maxalliga ah waa demo, marka taasi dhib ma laha.

**Haddii wax fashilmo — ha deploy garayn.** Liiska `FAIL` wuxuu kuu sheegayaa halka uu ku jiro.

---

## 2. `DEPLOY.bat` — server-ka

Wuxuu ku weydiin doonaa password-ka server-ka. **Markaad qorayso waxba ma soo bixi doonaan** — taasi waa caadi, sii wad oo Enter taabo.

Waxa uu qabanayo, hal xidhiidh SSH:

1. **Bundle** — `dist/` dib ayuu u dhisayaa (config-kaaga server-ka iyo seed.sql lagama soo qaadayo, sidaas darteed ma burburayaan)
2. **Kor u dhigid** — faylasha wuxuu geynayaa `dacaam/`
3. **Front controllers** — `public_html/api/index.php` iyo `public_html/admin/index.php` wuu cusboonaysiinayaa. *Tan la aan, code-ku wuu cusboonaanayaa laakiin boggagu waxay sii wadayaan kii duugoobay.*
4. **Assets** — `public_html/admin/assets/` (CSS-ka dashboard-ka)
5. **Keyd** — `backup_db.php` **migrations-ka ka hor**, weligeed ka dib
6. **Migrations** — 10 tallaabo, mid walba wuu hubiyaa ka hor inta uusan wax qaban
7. **Xaqiijin** — wuxuu tirinayaa permissions, roles, tables

### Waxa aad ka eegayso dhammaadka

```
     permissions    : 32
       admin      32
       operator   ...
       waiter     ...
     payment_methods: ...
     cancel_reason  : waa jiraa
```

Haddii `permissions` uu ka yar yahay 32, ama `MAQAN` uu soo baxo, migration ayaa fashilmay — kor u eeg qoraalka.

Haddii `DIGNIIN: xisaabo kala tegey` uu soo baxo, macmiil ayaa xisaabtiisu ka duwan tahay ledger-kiisa — taasi waa lacag, marka ii sheeg.

> **Laba jeer oo aad ordiso waa isla mid ah hal jeer.** Migration kasta wuu hubiyaa ka hor. Marka aad shakido, mar kale ordi.

---

## 3. Ka dib deploy-ga

1. `dhuuh.shop/admin` gal → **Health**
2. Waa inuu yiraahdaa `quiet · Nh ago` — micnaheedu waa waxba cusub ma dhicin
3. Haddii `just now` uu jiro, khalad hadda ayaa socda — bogga ayaa kuu sheegaya

App-ka mobile-ka: **ka bax oo dib u gal**. Token-ku wuu sii shaqaynayaa, laakiin bootstrap-ku wuxuu soo qaadayaa wixii cusub.

---

## 4. `BUILD.bat` — APK-ga

**Kaliya marka `mobile/` la beddelo.** Backend-ka oo keliya haddii la beddelay, APK-ga dib looma dhisayo.

Ka hor inta aanu wax dhisin wuxuu hubinayaa:

- `api.dhuuh.shop/health` → 200 (server-ku wuu shaqaynayaa)
- `/customers` → 404 ma aha (backend-ku ma duugoobin)

Sidaas darteed: **DEPLOY.bat marka hore, BUILD.bat ka dib** — weligiis hab kale.

Dhammaadka wuxuu ku eegayaa APK-ga gudihiisa in `api.dhuuh.shop` uu ku jiro. Haddii uusan ku jirin wuu joojinayaa — APK-gaas demo data ayuu isticmaali lahaa, sidii mar hore dhacday.

Faylka: `D:\DACAAM\DACAAM.apk`

---

## Nidaamka oo dhan

```
XAMPP MySQL shid
        ↓
TEST.bat          →  390 guulaystay?  maya → sax
        ↓ haa
DEPLOY.bat        →  permissions 32?  maya → eeg qoraalka
        ↓ haa
Health page       →  quiet?           maya → eeg khaladka
        ↓ haa
mobile la beddelay?  maya → dhammaad
        ↓ haa
BUILD.bat         →  DACAAM.apk
```

---

## Cron — afar xariiq oo hPanel

hPanel → **Advanced → Cron Jobs**. La'aantood keydku ma ordo oo emailku ma baxo.

Beddel `USER` kaaga (`u511759483`):

```
*/5 * * * *  cd /home/USER/domains/dhuuh.shop/dacaam/backend && php bin/send_outbox.php
0 6 * * *    cd /home/USER/domains/dhuuh.shop/dacaam/backend && php bin/send_digest.php
30 2 * * *   cd /home/USER/domains/dhuuh.shop/dacaam/backend && php bin/backup_db.php
0 9 * * *    cd /home/USER/domains/dhuuh.shop/dacaam/backend && php bin/send_renewal_reminders.php
```

| Waqti | Waxa uu qabanayo |
|---|---|
| 5 daqiiqo kasta | Emailka safka ku jira dir |
| 06:00 | Warbixinta shalay diyaari |
| 02:30 | Keyd database |
| 09:00 | Xusuusinta ishtiraakka: 7 maalmood ka hor, 1 maalin ka hor, iyo marka uu dhaco |

Xusuusinta waligeed laba jeer lama diro — cron-ka iyo badhanka **Subscriptions → Send due reminders now** ee dashboard-ka isku mar way wada socon karaan.

Emailku wuu shaqaynayaa cron la'aanteed — API-gu hal fariin ayuu dirayaa codsi kasta ka dib. Laakiin taasi waxay socotaa oo kaliya inta la isticmaalayo; habeenkii wax ma dhaqaaqayaan. Keydku cron la'aan **ma ordo** oo dhan.

Hubi: `dhuuh.shop/admin` → **Health** → `Alert email`. Haddii "Waiting to send" uu ka badan yahay 20, cron-ku ma shaqaynayo.

---

## Marka wax qaldamaan

Keyd ayaa la qaaday **migrations-ka ka hor**, marka waxaa jira meel laga noqdo.

- **Makhaayad kaliya** — `dhuuh.shop/admin` → makhaayadda → kaarka `Backups` → `Restore`. Waxaad ku qori doontaa code-ka makhaayadda si aad u xaqiijiso. Xaaladda hadda jirta si toos ah ayaa keyd loogu qaadayaa marka hore, marka restore-ku isaga laftiisu waa laga noqon karaa.
- **Database-ka oo dhan** — badhan ma leh, mana yeelan doono. Mid kasta oo makhaayad ah ayuu la tegayaa. SSH ayaa loo baahan yahay, taasina waa caqabad ku habboon wax sidaas u weyn.

Keydadku waxay ku jiraan `backend/storage/backups/`, 14 kii ugu dambeeyay.
