# DACAAM ku dhig Hostinger Cloud Startup

Hal jid. Ha ka leexan. Qiyaastii 45 daqiiqo.

Cloud Startup wuxuu leeyahay **SSH**, taasina way ka fududaynaysaa shared
hosting caadi ah â€” badi shaqada waxaad ku qabanaysaa terminal-ka.

Waxaad ka bilaabaysaa: `dhuuh.shop` oo Hostinger ku xiran.

---

## Qaab-dhismeedka aan gaarayno

```
api.dhuuh.shop     â†’  /home/uXXXXXXXXX/dacaam/backend/public
admin.dhuuh.shop   â†’  /home/uXXXXXXXXX/dacaam/admin/public
```

Xogta dhabta ah â€” `src/`, `config/`, `database/` â€” waxay ku jiraan
`/home/uXXXXXXXXX/dacaam/`, oo **aan internet-ka laga gaari karin**.
Kaliya labada folder ee `public/` ayaa la arkaa.

---

## Tallaabo 0 â€” Ururi afar qiimo

Ka hor inta aanad wax bilaabin, buuxi shaxdan. Intaas ka dib wax walba waa
copy-paste.

| | Qiimahaaga | Halka laga helo |
|---|---|---|
| Hostinger username | `u_________` | hPanel â†’ Files â†’ File Manager, waddada sare |
| SSH IP | `___.___.___.___` | hPanel â†’ Advanced â†’ SSH Access |
| SSH port | `_____` | isla goobtaas (badanaa 65002) |
| DB password | `_______________` | tallaabada 2, marka aad abuurto |

Username-kaagu wuxuu u eg yahay `uXXXXXXXXX`. Tilmaamahan oo dhan
`uXXXXXXXXX` waxaad ku beddelaysaa kaaga.

Marka aad SSH gasho, waxaad si sax ah u arki kartaa:

```bash
whoami && echo ~
```

> **Subdomain-ka admin-ka:** waxaan isticmaalaynaa `admin.dhuuh.shop`.
> Haddii aad magac kale rabto (`dashboard`, `panel`), beddel meel kasta oo
> tilmaamahan ku jira **iyo** `allowed_origins` ee tallaabada 6.

---

## Tallaabo 1 â€” Hubi PHP-ga

hPanel â†’ **Websites** â†’ dooro `dhuuh.shop` â†’ **Dashboard** â†’
**Advanced** â†’ **PHP Configuration**

- **PHP version**: dooro **8.2** ama **8.3**
- Tabka **PHP extensions**: hubi in `pdo_mysql`, `openssl`, `mbstring`, `gd`
  ay tikan yihiin
- **Save**

> Haddii PHP 8.1 ama ka hooseeya la doortay, koodhku ma shaqaynayo.
> `declare(strict_types=1)` iyo qaabab kale waxay u baahan yihiin 8.2.

---

## Tallaabo 2 â€” Samee database-ka

hPanel â†’ **Databases** â†’ **Management**

1. **Database name**: `dacaam` â†’ Hostinger wuxuu ka dhigayaa `uXXXXXXXXX_dacaam`
2. **Username**: `dacaam` â†’ wuxuu noqonayaa `uXXXXXXXXX_dacaam`
3. **Password**: guji **Generate** â€” oo **koobi garee meel ammaan ah hadda**
4. **Create**

Qor saddexdan. Waad u baahan doontaa tallaabada 6-aad:

```
Database : uXXXXXXXXX_dacaam
Username : uXXXXXXXXX_dacaam
Password : ..........................
Host     : localhost
```

> Hostinger wuxuu si toos ah u siinayaa user-ka xuquuq buuxda database-kaas.
> Waxba dheeraad ah ma jiraan.

---

## Tallaabo 3 â€” Fur SSH

hPanel â†’ **Advanced** â†’ **SSH Access**

1. **SSH access**: daar (**Enable**)
2. Qor: **IP**, **Port** (badanaa 65002), **Username** (`uXXXXXXXXX`)
3. Password-ku waa isla kan hPanel-ka

Kombiyuutarkaaga, fur PowerShell:

```bash
ssh -p 65002 uXXXXXXXXX@203.0.113.45
```

Beddel lambarka port-ka iyo IP-ga kuwaaga. Marka la ku weydiiyo password,
qor kan hPanel â€” **ma muuqanayo markaad qorayso, taasi waa caadi**.

Marka aad gasho, hubi PHP-ga:

```bash
php -v
```

Waa inuu muujiyaa 8.2 ama ka sarreeya.

---

## Tallaabo 4 â€” Samee bundle-ka kombiyuutarkaaga

Fur PowerShell **cusub** (mid aan SSH ahayn), kombiyuutarkaaga:

```bash
cd D:/DACAAM/backend && php bin/bundle.php
```

Waxay abuurtaa `D:/DACAAM/dist/` â€” 72 fayl, 0.4 MB.

Ka dib ku cadaadi ZIP. File Explorer â†’ `D:/DACAAM/dist` â†’ dooro labada folder
(`backend`, `admin`) â†’ midig guji â†’ **Send to** â†’ **Compressed (zipped) folder**
â†’ magaca `dacaam.zip`.

---

## Tallaabo 5 â€” Soo raro oo furfur

hPanel â†’ **Files** â†’ **File Manager**

1. Guji folder-ka **root** (`/home/uXXXXXXXXX`) â€” **ma aha** `public_html`
2. **New Folder** â†’ magaca `dacaam`
3. Gal `dacaam`
4. **Upload** â†’ dooro `dacaam.zip`
5. Marka la dhammeeyo: midig guji `dacaam.zip` â†’ **Extract**
6. Tirtir `dacaam.zip`

Waa inaad haysataa:

```
/home/uXXXXXXXXX/dacaam/
â”œâ”€â”€ backend/
â””â”€â”€ admin/
```

Hubi SSH:

```bash
ls ~/dacaam/backend/public/
```

Waa inaad aragto `index.php` iyo `.htaccess`.

---

## Tallaabo 6 â€” Config-ga

SSH:

```bash
nano ~/dacaam/backend/config/config.local.php
```

Ku dheji kan, adigoo beddelaya database-ka tallaabada 2:

```php
<?php

declare(strict_types=1);

return [
    'app' => [
        'env'   => 'production',
        'debug' => false,
    ],
    'db' => [
        'host'     => 'localhost',
        'port'     => 3306,
        'database' => 'uXXXXXXXXX_dacaam',
        'username' => 'uXXXXXXXXX_dacaam',
        'password' => 'PASSWORD-KII-AAD-KOOBIGARAYSAY',
    ],
    'auth' => [
        'bcrypt_cost' => 12,
    ],
    'cors' => [
        'allowed_origins' => ['https://admin.dhuuh.shop'],
    ],
];
```

Keydi: **Ctrl+O** â†’ **Enter** â†’ **Ctrl+X**

Xaddid gelitaanka faylka:

```bash
chmod 600 ~/dacaam/backend/config/config.local.php
```

---

## Tallaabo 7 â€” Soo geli schema-da

SSH:

```bash
cd ~/dacaam/backend && php bin/migrate.php
```

Waa inaad aragto:

```
uXXXXXXXXX_dacaam is ready â€” 33 tables.
```

> Haddii uu yiraahdo *"Cannot create ... expecting it to exist"* â€” taasi waa
> caadi. Hostinger uma ogola user-ka inuu database abuuro; adiga ayaa mid horeba
> u sameeyay tallaabada 2-aad, wuuna sii wadayaa.

**Weligaa ha ku darin `--seed` ama `--fresh`.** `--seed` wuxuu abuurayaa
makhaayado tijaabo ah oo password-kastaa yahay `admin123`. `--fresh` wuxuu
**tirtirayaa database-ka oo dhan**.

---

## Tallaabo 8 â€” Samee subdomain-nada

hPanel â†’ **Domains** â†’ **Subdomains**

Samee laba:

| Subdomain | Domain | Custom folder |
|---|---|---|
| `api` | `dhuuh.shop` | **ha calaamadin** |
| `admin` | `dhuuh.shop` | **ha calaamadin** |

Guji **Create** mid kasta.

> ### "Custom folder for subdomain" â€” ha isticmaalin
>
> Goobtaas `/public_html/` ayaa hortaagan oo qufulan. Micnaha: wax kastoo aad
> qorto waxay noqonaysaa `/public_html/MAGACA` â€” **ma gaari karto**
> `/home/uXXXXXXXXX/dacaam/backend/public`, oo ah meesha aan u baahan nahay.
> Goobtaasi keligeed dhibaatada ma xallin karto.
>
> Marka aad ka tagto oo aan la calaamadin, Hostinger wuxuu abuurayaa folder u
> gaar ah subdomain-ka â€” `~/domains/api.dhuuh.shop/public_html` â€” taasoo ka
> madax banaan website-ka weyn. Tallaabada 9-aad ayaa markaa ku beddelaysa.
>
> **Sidoo kale:** haddii aad calaamadiso oo aad qorto `dacaam`, waxaad
> haysanaysaa laba shay oo isku magac leh â€” `~/dacaam` (koodhka, qarsoon) iyo
> `~/public_html/dacaam` (internet-ku wuu arkaa). Habeen dambe waxaad koodhka
> geli doontaa midka khaldan.

Hubi meesha Hostinger sameeyay:

```bash
ls -d ~/domains/*/public_html
```

Waa inaad aragto labada wadal. Haddii ay meel kale galeen, isticmaal waddada
aad aragto tallaabada xigta â€” symlink-ku meel kasta wuu ka shaqeeyaa.

---

## Tallaabo 9 â€” Ku xir subdomain-nada `public/`

Tani waa tallaabada ugu muhiimsan. Waxaan folder-rada Hostinger sameeyay ku
beddelaynaa **symlink** u tilmaamaya `public/` keena.

SSH â€” beddel `uXXXXXXXXX` kaaga:

```bash
rm -rf ~/domains/api.dhuuh.shop/public_html && ln -s ~/dacaam/backend/public ~/domains/api.dhuuh.shop/public_html
```

```bash
rm -rf ~/domains/admin.dhuuh.shop/public_html && ln -s ~/dacaam/admin/public ~/domains/admin.dhuuh.shop/public_html
```

Hubi:

```bash
ls -l ~/domains/api.dhuuh.shop/
```

Waa inaad aragto `public_html -> /home/uXXXXXXXXX/dacaam/backend/public`.

> **Sababta symlink:** haddii aad si toos ah faylasha ugu shubto
> `public_html`, `src/` iyo `config/` waxay noqonayaan kuwo internet-ka laga
> gaari karo â€” qof kastaa wuxuu soo dejisan karaa password-ka database-kaaga.
> Symlink-ku wuxuu keliya soo bandhigayaa `public/`.
>
> Koodhku wuu la shaqeeyaa symlink si sax ah: PHP `__DIR__` wuxuu bixiyaa
> waddada dhabta ah, sidaas darteed `require dirname(__DIR__) . '/bootstrap.php'`
> wuxuu helayaa `~/dacaam/backend/bootstrap.php`.

**Haddii aad horeba u calaamadisay "Custom folder"** oo aad qortay tusaale
`dacaam`, document root-kaagu waa `~/public_html/dacaam`. Symlink-ku isla sidaas
ayuu u shaqeeyaa â€” beddel waddada oo keliya:

```bash
rm -rf ~/public_html/dacaam && ln -s ~/dacaam/backend/public ~/public_html/dacaam
```

Laakiin ogow: markaas API-gu wuxuu ka shaqaynayaa **labada** meelood â€”
`https://api.dhuuh.shop` iyo `https://dhuuh.shop/dacaam`. Khalad ammaan ma aha
(isku folder ayaa la arkaa), laakiin waa dul-saar aadan codsan. Waxaan ku
talinayaa inaad subdomain-ka dib u samayso adigoo aan calaamadin.

---

## Tallaabo 9b â€” CDN-ka subdomain-ka daar

**Tallaabadan ha ka boodin.** Waa tan ugu waqtiga badan lumisa.

hPanel â†’ **Websites** â†’ `dhuuh.shop` â†’ **Performance** â†’ **CDN**

Waxaad arki doontaa liis. Subdomain cusub wuxuu badanaa yimaadaa **Inactive**:

```
api.dhuuh.shop     âš  Inactive - Enable
dhuuh.shop         âœ“ Active
```

Guji **Enable** kan `api.dhuuh.shop`.

> **Sababta ay muhiim u tahay:** Hostinger wuxuu DNS-ka u diraa `api.dhuuh.shop`
> â†’ `api.dhuuh.shop.cdn.hstgr.net` (CDN edge-ka) isla markaad subdomain-ka
> abuurto. Laakiin CDN-ka **damisan** ayuu ku yimaadaa. Markaas codsigu wuxuu
> gaarayaa edge aan waxba ka aqoon magacaas â€” shahaado ma bixin karo.
>
> Astaanta: browser-ku `ERR_CONNECTION_RESET`, `openssl` wuxuu yiraahdaa
> `tlsv1 alert internal error`, hPanel-kuna wuxuu leeyahay SSL waa **Active**.
> Waa is-burin: shahaadadu waxay ku jirtaa origin-ka, laakiin edge-ka ayaa
> codsiga qaadanaya.
>
> HTTP wuxuu ku jawaabayaa `301` (vhost-ku wuu jiraa), HTTPS-na `000`. Haddii
> aad taas aragto, CDN-ka eeg â€” ma aha SSL, ma aha koodhka.

Enable ka dib: sug 10â€“30 daqiiqo, guji **Flush cache**, ka dibna sii wad.

---

## Tallaabo 10 â€” SSL

hPanel â†’ **Security** â†’ **SSL**

1. Waa inaad aragto `api.dhuuh.shop` iyo `admin.dhuuh.shop`
2. Guji **Install SSL** mid kasta (haddii aan si toos ah loo samayn)
3. Sug 5â€“15 daqiiqo
4. Marka la dhammeeyo, daar **Force HTTPS**

Marka HTTPS shaqeeyo, kuwan si toos ah ayay u shaqeeyaan â€” koodh looma baahna:
HSTS, cookie-ga `Secure`, CSP, `Cache-Control: no-store`.

---

## Tallaabo 11 â€” Hubi in API-gu shaqeeyo

Browser-ka:

```
https://api.dhuuh.shop/api/v1/health
```

Waa inaad aragto:

```json
{"data":{"status":"ok","server_time":"2026-08-14T15:20:00+03:00"}}
```

**Haddii aad aragto khalad:**

| Waxa aad aragto | Sababta | Xalka |
|---|---|---|
| `ERR_CONNECTION_RESET` | CDN-ka subdomain-ku waa Inactive | **Tallaabo 9b** |
| Liiska faylasha | Symlink-ku ma shaqaynin | Tallaabo 9 dib u sameeyo |
| `403` | Docroot maqan, ama symlink aan la raacayn | Tallaabo 9 â€” faylal dhab ah isticmaal |
| `500` | Config qaldan ama PHP hoose | `tail ~/dacaam/backend/*.log`, tallaabo 1 & 6 |
| `404` | `mod_rewrite` | Hostinger wuu leeyahay; hubi in `.htaccess` uu jiro `public/` |
| Bogga Hostinger (AngularJS) | Vhost lama helin | Tallaabo 9b |

> **Ha ku tijaabin `curl -H "Host: ..." http://127.0.0.1/`.** Hostinger
> `127.0.0.1:80` proxy ayuu ka dhigay, mana kala saaro Host-ka sidaad
> filayso â€” wuxuu ku siinayaa 403/404 been ah oo aad saacado ku raadinayso.
> Magaca dhabta ah isticmaal: `curl https://api.dhuuh.shop/api/v1/health`.

---

## Tallaabo 12 â€” Samee admin-kaagii koowaad

Browser-ka:

```
https://admin.dhuuh.shop
```

Si toos ah ayuu kuu gudbinayaa **`/setup`** â€” maadaama aan weli cidna jirin.

1. Magacaaga
2. Email-kaaga (kaas ayaad ku gelaysaa)
3. Password ugu yaraan **10 xaraf**, mid aanad meel kale ku isticmaalin
4. **Create administrator**

Boggaasi hadda **weligiis wuu xirmay**. Booqashada `/setup` mar labaad waxay ku
celinaysaa `/login`. Ma jiro hab kale oo admin lagu sameeyo.

Gal, ka dibna: **Restaurants â†’ + New restaurant** â€” samee makhaayaddaada
koowaad. Bogga abuuritaanku wuxuu ku weydiinayaa magaca, koodhka (`HAMZE`),
iyo admin-ka makhaayadda.

---

## Tallaabo 13 â€” Hubinta ammaanka

Ku dheji browser-ka mid kasta. **Dhammaantood waa inay diidaan.**

| URL | Waa inuu noqdo |
|---|---|
| `https://api.dhuuh.shop/../config/config.local.php` | 403 / 404 |
| `https://api.dhuuh.shop/config/config.local.php` | 404 |
| `https://api.dhuuh.shop/src/Core/Database.php` | 404 |
| `https://admin.dhuuh.shop/setup` | wuxuu ku celinayaa `/login` |

Haddii middood ay soo bandhigto koodh PHP ah ama xog, **jooji** oo tallaabo 9
dib u eeg.

SSH â€” hubi in `seed.sql` aan la gelin:

```bash
cd ~/dacaam/backend && php -r 'require "bootstrap.php"; echo Dacaam\Core\Database::scalar("SELECT COUNT(*) FROM restaurants"), " restaurants\n";'
```

Waa inuu yiraahdo `0 restaurants` (ama tirada aad adigu abuurtay).
Haddii uu yiraahdo `2`, `seed.sql` waa la geliyay â€” waa inaad tirtirtaa
`HAMZE` iyo `WARFA` dashboard-ka.

---

## Tallaabo 14 â€” Ku xir app-ka

Kombiyuutarkaaga:

```bash
cd D:/DACAAM/mobile && flutter build appbundle --release --dart-define=USE_API=true --dart-define=API_BASE_URL=https://api.dhuuh.shop/api/v1
```

HTTPS waa la isticmaalayaa, sidaa darteed `network_security_config.xml` wax
bedel ah uma baahna.

---

## Tallaabo 15 â€” Backup

hPanel â†’ **Files** â†’ **Backups**

Cloud Startup wuxuu leeyahay backup automatic ah maalin kasta. Hubi inuu daaran
yahay.

Intaa waxaa dheer, database dump toddobaadle ah â€” hPanel â†’ **Advanced** â†’
**Cron Jobs**, Isniin kasta 3:00 subaxnimo:

```bash
mysqldump -u uXXXXXXXXX_dacaam -pPASSWORD uXXXXXXXXX_dacaam | gzip > ~/backups/dacaam-$(date +\%F).sql.gz
```

Marka hore samee folder-ka: `mkdir -p ~/backups`

---

## Cusboonaysiin dambe

Kombiyuutarkaaga:

```bash
cd D:/DACAAM/backend && php bin/bundle.php
```

ZIP garee `dist/`, soo raro `~/dacaam/`, furfur oo dul saar.

`config.local.php` **kuma jiro** bundle-ka, sidaa darteed lama tirtirayo.

Haddii schema-du isbeddesho:

```bash
cd ~/dacaam/backend && php bin/migrate.php
```

Waa idempotent â€” waxna ma tirtiro, kaliya wuxuu ku darayaa waxa cusub.

---

## Marka ay wax qaldamaan

**Eeg log-ga marka hore:**

```bash
tail -50 ~/domains/api.dhuuh.shop/logs/error.log
```

**Debug si ku meel gaar ah u daar** (ka dib **si xaqiiq ah u dami**):

`config.local.php` â†’ `'debug' => true` â†’ dib u eeg â†’ `'debug' => false`

Debug oo furan wuxuu soo bandhigayaa waddooyinka faylasha iyo SQL-ka â€”
weligaa ha ka tagin production.
