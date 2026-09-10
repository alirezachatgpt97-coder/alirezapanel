<div dir="rtl" align="right">

<p align="center">
  <img src="./assets/alirezapanel-header.svg" alt="alirezapanel" width="100%">
</p>

# alirezapanel

**پنل یکپارچه مدیریت VPN و DNS با VPN-UI و رابط کامل AdGuard Home**

`alirezapanel` یک Integration سبک و Native برای سرورهای Linux است که VPN-UI و AdGuard Home را در یک محیط واحد کنار هم قرار می‌دهد. هدف پروژه این است که رابط‌ها و قابلیت‌های اصلی سرویس‌های بالادستی حفظ شوند و در عین حال ورود مشترک، ناوبری یکپارچه، HTTPS، DNS و Branding پروژه در یک پنل واحد در اختیار مدیر قرار بگیرد.

> **Integration:** `1.1.0`  
> **VPN-UI:** `v1.9.4`  
> **AdGuard Home:** `v0.107.79`  
> **Architecture:** `x86_64 / amd64`

<p align="center">
  <img src="./assets/architecture.svg" alt="معماری alirezapanel" width="96%">
</p>

---

## فهرست

- [ویژگی‌ها](#ویژگیها)
- [معماری](#معماری)
- [سیستم‌عامل‌های پشتیبانی‌شده](#سیستمعاملهای-پشتیبانیشده)
- [منابع موردنیاز](#منابع-موردنیاز)
- [پورت‌ها](#پورتها)
- [هشدار بسیار مهم درباره Restart](#هشدار-بسیار-مهم-درباره-restart)
- [نصب](#نصب)
- [نصب با دامنه و SSL](#نصب-با-دامنه-و-ssl)
- [نصب با IP و HTTPS](#نصب-با-ip-و-https)
- [نصب بدون SSL](#نصب-بدون-ssl)
- [نصب غیرتعاملی](#نصب-غیرتعاملی)
- [ورود به پنل](#ورود-به-پنل)
- [DNS](#dns)
- [فایروال](#فایروال)
- [دستورات مدیریت](#دستورات-مدیریت)
- [Health Check](#health-check)
- [Backup](#backup)
- [Repair](#repair)
- [SSL و Certificate](#ssl-و-certificate)
- [ساختار فایل‌ها](#ساختار-فایلها)
- [امنیت](#امنیت)
- [به‌روزرسانی](#بهروزرسانی)
- [رفع اشکال](#رفع-اشکال)
- [سؤالات متداول](#سؤالات-متداول)
- [لایسنس](#لایسنس)

---

## ویژگی‌ها

### پنل واحد برای VPN و DNS

VPN-UI و AdGuard Home پشت یک Gateway یکپارچه قرار می‌گیرند. Backend وب VPN روی `127.0.0.1:18080` و Backend وب AdGuard روی `127.0.0.1:18081` باقی می‌مانند و مستقیماً Public نمی‌شوند.

### رابط کامل AdGuard Home

هدف Integration حذف کردن صفحات اصلی AdGuard نیست؛ رابط اصلی آن از داخل پنل در دسترس قرار می‌گیرد و Gateway احراز هویت و Branding را مدیریت می‌کند.

### DNS استاندارد روی پورت 53

DNS مستقیماً روی **IPv4 اصلی سرور** و پورت استاندارد `53` در دسترس است:

```text
SERVER_IP:53
TCP + UDP
```

در این نسخه از Resolver روی `127.0.0.1:15353` استفاده نمی‌شود.

<p align="center">
  <img src="./assets/dns-flow.svg" alt="مسیر DNS" width="94%">
</p>

### سه حالت دسترسی عمومی

Installer در اولین نصب تعاملی سه حالت ارائه می‌دهد:

1. **Domain + SSL معتبر Let's Encrypt**
2. **Server IP + HTTPS با Self-Signed SSL**
3. **Server IP/Domain بدون SSL با HTTP**

<p align="center">
  <img src="./assets/access-modes.svg" alt="حالت‌های دسترسی" width="95%">
</p>

### Native و بدون Docker

خود پروژه برای اجرا نیازی به Docker، Node.js، npm یا Build Toolchain ندارد و سرویس‌ها با systemd اجرا می‌شوند.

### بررسی نسخه و SHA-256

نسخه‌های VPN-UI و AdGuard Home در Installer Pin شده‌اند و فایل‌های دانلودی قبل از استفاده با SHA-256 بررسی می‌شوند.

### Health Check واقعی

Installer فقط به Running بودن Processها اکتفا نمی‌کند و بعد از نصب Ready بودن رابط، Auth و DNS Resolution واقعی را بررسی می‌کند.

---

## معماری

```text
Browser
   │
   │ HTTPS / HTTP
   ▼
alirezapanel Gateway
   │
   ├── VPN-UI Web     → 127.0.0.1:18080
   │
   └── AdGuard Web    → 127.0.0.1:18081


Phone / PC / Router / VPN Client
   │
   │ DNS TCP/UDP :53
   ▼
Server IPv4
   │
   ▼
AdGuard Home
   │
   ▼
Upstream DNS
```

Web Backendهای اصلی فقط روی Loopback نگهداری می‌شوند. DNS برخلاف Web Backendها روی IPv4 اصلی سرور و پورت استاندارد 53 Bind می‌شود.

---

## سیستم‌عامل‌های پشتیبانی‌شده

| سیستم‌عامل | نسخه | وضعیت |
|---|---:|---|
| Debian | 12 | ✅ پشتیبانی |
| Debian | 13 | ✅ پشتیبانی |
| Ubuntu | 24.04 | ✅ پشتیبانی |

معماری موردنیاز:

```text
x86_64 / amd64
```

### ARM

نسخه فعلی Installer برای ARM طراحی نشده است. قبل از نصب می‌توانید معماری را بررسی کنید:

```bash
uname -m
```

خروجی مورد انتظار:

```text
x86_64
```

### Docker

Container معمولی Docker که systemd واقعی در آن فعال نیست پشتیبانی نمی‌شود.

---

## منابع موردنیاز

حداقل‌های Installer:

```text
RAM:       تقریباً 1 GiB
Free /opt: حداقل 2 GiB
CPU:       برای استفاده سبک 1 vCPU
systemd:   الزامی
Root:      الزامی
```

Installer حداقل حدود `850000 KB` حافظه و `2 GiB` فضای آزاد زیر `/opt` را بررسی می‌کند.

> این اعداد حداقل‌های نصب هستند و تضمین ظرفیت برای ترافیک بالا، تعداد کاربر زیاد یا Filter Listهای بسیار بزرگ نیستند.

---

## پورت‌ها

| پورت | پروتکل | کاربرد | Scope |
|---:|---|---|---|
| `443` | TCP | Domain + Let's Encrypt | Public |
| `8443` | TCP | IP + HTTPS پیش‌فرض | Public |
| `8080` | TCP | حالت HTTP پیش‌فرض | Public |
| `18080` | TCP | VPN-UI Web Backend | Loopback Only |
| `18081` | TCP | AdGuard Web Backend | Loopback Only |
| `53` | TCP + UDP | AdGuard DNS | Server IPv4 |

پورت‌های Protocolهای VPN بر اساس چیزی که داخل VPN-UI فعال می‌کنید متفاوت هستند.

---

## هشدار بسیار مهم درباره Restart

<p align="center">
  <img src="./assets/no-manual-restart.svg" alt="Restart دستی ممنوع" width="95%">
</p>

> ## ⛔ به هیچ وجه برای استفاده عادی پنل را دستی Restart نکنید
>
> سرویس‌های اصلی پروژه توسط **systemd** مدیریت می‌شوند و با:
>
> ```text
> Restart=on-failure
> RestartSec=5
> ```
>
> تنظیم شده‌اند. اگر Process به دلیل Failure از کار بیفتد، systemd آن را دوباره اجرا می‌کند.

برای مشکل‌های معمول مثل باز نشدن موقت صفحه، کندی یا خطای اتصال، **اول Restart نزنید**. ترتیب صحیح بررسی:

```bash
sudo alirezapanel status
sudo alirezapanel check
sudo alirezapanel logs
```

این دستورات را برای استفاده روزمره اجرا نکنید:

```bash
sudo alirezapanel restart
sudo systemctl restart alirezapanel
sudo systemctl restart alirezapanel-vpn
sudo systemctl restart alirezapanel-dns
```

دستور `sudo alirezapanel restart` برای عملیات عیب‌یابی/مدیریتی خاص در CLI وجود دارد و به‌صورت ترتیبی DNS → VPN → Gateway را بررسی می‌کند، اما **راه‌حل روزمره پروژه نیست**.

همچنین در عملیات‌هایی مثل `backup` و `--repair`، اگر Stop/Start سرویس لازم باشد، ابزار پروژه چرخه سرویس‌ها را خودش مدیریت می‌کند. سرویس‌ها را جداگانه و دستی دستکاری نکنید.

---

## پیش‌نیاز نصب

قبل از اجرا:

- از **Fresh Server** استفاده کنید.
- Root/Sudo در اختیار داشته باشید.
- سرور به GitHub و Repositoryهای سیستم‌عامل دسترسی داشته باشد.
- DNS Upstreamها قابل دسترس باشند.
- پورت عمومی انتخاب‌شده در Firewall باز باشد.
- اگر DNS را از خارج سرور استفاده می‌کنید، `TCP/UDP 53` باز باشد.
- روی IP اصلی سرور پورت 53 با سرویس دیگری Conflict نداشته باشد.
- نصب قبلی ناسازگار VPN-UI/x-ui/AdGuard Home روی سرور وجود نداشته باشد.

Installer برای جلوگیری از Overwrite نصب‌های موجود، Conflictهای شناخته‌شده را بررسی می‌کند.

---

## نصب

فایل را روی سرور قرار دهید و اجرا کنید:

```bash
sudo bash install.sh
```

در اولین نصب تعاملی، منوی Public Access نمایش داده می‌شود:

```text
alirezapanel - Public access setup

Choose how the panel should be opened:

1) Domain + valid SSL (Let's Encrypt)
2) Server IP + HTTPS (self-signed SSL)
3) Server IP/domain without SSL (plain HTTP)
```

<p align="center">
  <img src="./assets/install-flow.svg" alt="مراحل نصب" width="96%">
</p>

Installer به‌صورت کلی این مراحل را انجام می‌دهد:

1. سیستم‌عامل، systemd و Architecture را بررسی می‌کند.
2. RAM و فضای `/opt` را بررسی می‌کند.
3. Conflictهای نصب قبلی را بررسی می‌کند.
4. حالت IP/Domain/SSL را دریافت می‌کند.
5. Dependencyهای Runtime را نصب می‌کند.
6. نسخه‌های Pin شده VPN-UI و AdGuard Home را دریافت می‌کند.
7. SHA-256 را بررسی می‌کند.
8. Config و Integration را ایجاد می‌کند.
9. آزاد بودن پورت‌های لازم را بررسی می‌کند.
10. systemd Unitها را نصب و فعال می‌کند.
11. Readiness و Health Check واقعی را اجرا می‌کند.
12. فقط بعد از موفقیت بررسی‌ها نصب را Success اعلام می‌کند.

---

## نصب با دامنه و SSL

حالت پیشنهادی برای پنل Public:

```text
1) Domain + valid SSL (Let's Encrypt)
```

### قبل از نصب

یک A Record بسازید:

```text
panel.example.com  →  SERVER_PUBLIC_IP
```

و مطمئن شوید پورت‌های زیر قابل دسترس‌اند:

```text
80/TCP
443/TCP
```

پورت 80 برای Challenge اولیه Let's Encrypt لازم است.

سپس:

```bash
sudo bash install.sh
```

گزینه `1` را انتخاب کنید و Domain را بدون `https://` وارد کنید:

```text
panel.example.com
```

Email برای Let's Encrypt اختیاری است.

آدرس پیش‌فرض پنل:

```text
https://panel.example.com/<random-base-path>/
```

پورت پیش‌فرض Domain Mode:

```text
443
```

### تمدید Certificate

در Domain Mode، Certbot نصب می‌شود و Hook تمدید Certificate ایجاد می‌شود. بعد از Renewal، Certificate جدید داخل مسیر پروژه Sync شده و فقط Gateway عمومی با Certificate جدید اعمال می‌شود؛ DNS و VPN برای Renewal بی‌دلیل Restart نمی‌شوند.

---

## نصب با IP و HTTPS

از منوی نصب:

```text
2) Server IP + HTTPS (self-signed SSL)
```

پورت پیش‌فرض:

```text
8443
```

ساختار URL:

```text
https://SERVER_IP:8443/<random-base-path>/
```

اگر Certificate معتبر شخصی ارائه نکنید، Installer یک Certificate Self-Signed تولید می‌کند و Browser ممکن است Warning نمایش دهد.

---

## نصب بدون SSL

از منوی نصب:

```text
3) Server IP/domain without SSL (plain HTTP)
```

پورت پیش‌فرض:

```text
8080
```

ساختار URL:

```text
http://SERVER_IP:8080/<random-base-path>/
```

> این حالت Traffic پنل را Encrypt نمی‌کند. برای اینترنت عمومی، Domain + HTTPS انتخاب مناسب‌تری است.

---

## نصب غیرتعاملی

می‌توانید Wizard را با Environment Variableها دور بزنید.

### Domain + Let's Encrypt

```bash
sudo env \
  ALIREZA_TLS_MODE=domain \
  ALIREZA_HOST=panel.example.com \
  bash install.sh
```

با Email:

```bash
sudo env \
  ALIREZA_TLS_MODE=domain \
  ALIREZA_HOST=panel.example.com \
  ALIREZA_ACME_EMAIL=admin@example.com \
  bash install.sh
```

### IP + HTTPS

```bash
sudo env ALIREZA_TLS_MODE=ip bash install.sh
```

### بدون SSL

```bash
sudo env ALIREZA_TLS_MODE=none bash install.sh
```

### پورت سفارشی

```bash
sudo env \
  ALIREZA_TLS_MODE=ip \
  ALIREZA_PORT=9443 \
  bash install.sh
```

### User و Password اولیه

```bash
sudo env \
  ALIREZA_USER=admin \
  ALIREZA_PASSWORD='A-Very-Strong-Password-Here' \
  bash install.sh
```

Password باید بین `16` تا `72` بایت UTF-8 باشد.

### متغیرهای پشتیبانی‌شده

| Variable | توضیح |
|---|---|
| `ALIREZA_HOST` | IP یا Domain عمومی، بدون Scheme و Port |
| `ALIREZA_PORT` | پورت عمومی پنل |
| `ALIREZA_TLS_MODE` | `domain` / `ip` / `none` |
| `ALIREZA_ACME_EMAIL` | Email اختیاری Let's Encrypt |
| `ALIREZA_USER` | Username اولیه |
| `ALIREZA_PASSWORD` | Password اولیه |
| `ALIREZA_CERT` | مسیر PEM Certificate Chain |
| `ALIREZA_KEY` | مسیر Private Key متناظر |

---

## ورود به پنل

بعد از نصب:

```bash
sudo alirezapanel info
```

این دستور URL فعلی پنل و اطلاعات پایه را نمایش می‌دهد.

برای Credentials اولیه:

```bash
sudo alirezapanel credentials
```

فایل Credentials اولیه:

```text
/etc/alirezapanel/access.json
```

Permission این فایل محدود است.

> اگر Password را بعداً داخل UI تغییر دهید، فایل `access.json` لزوماً Password جدید را نشان نمی‌دهد؛ این فایل رکورد Credentials اولیه است.

---

## DNS

DNS در نسخه فعلی مستقیماً روی **IPv4 اصلی سرور** و پورت استاندارد `53` ارائه می‌شود.

اگر IP سرور شما مثلاً:

```text
203.0.113.10
```

باشد، DNS Client:

```text
203.0.113.10
```

است و Port استاندارد:

```text
53
```

### تست با dig

```bash
dig @SERVER_IP example.com A
```

### تست با nslookup

```bash
nslookup example.com SERVER_IP
```

### تست داخلی پروژه

```bash
sudo alirezapanel check
```

یا:

```bash
sudo bash install.sh --check
```

### نکته مهم

پروژه Redirect سراسری پورت 53 یا Global DNS Interception ایجاد نمی‌کند و `systemd-resolved` یا `resolv.conf` را به‌صورت کورکورانه تغییر نمی‌دهد.

اگر Client VPN باید از AdGuard استفاده کند، DNS Policy همان Client/Protocol را به IP قابل‌دسترسی سرور هدایت کنید.

---

## فایروال

Installer Firewall سیستم یا Cloud Provider را به‌صورت سراسری بازنویسی نمی‌کند.

### Domain + SSL

```text
80/TCP
443/TCP
```

### IP + HTTPS پیش‌فرض

```text
8443/TCP
```

### HTTP پیش‌فرض

```text
8080/TCP
```

### DNS

```text
53/TCP
53/UDP
```

### مثال UFW

فقط اگر خودتان UFW را فعال کرده‌اید:

```bash
sudo ufw allow 443/tcp
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
```

برای Let's Encrypt اولیه:

```bash
sudo ufw allow 80/tcp
```

اگر Cloud Firewall / Security Group دارید، پورت‌ها باید آنجا هم مجاز باشند.

---

## دستورات مدیریت

### اطلاعات نصب

```bash
sudo alirezapanel info
```

### Credentials اولیه

```bash
sudo alirezapanel credentials
```

### وضعیت سرویس‌ها

```bash
sudo alirezapanel status
```

### بررسی سلامت

```bash
sudo alirezapanel check
```

### مشاهده Log

```bash
sudo alirezapanel logs
```

### Backup

```bash
sudo alirezapanel backup
```

### دسترسی به CLI اصلی VPN-UI

```bash
sudo alirezapanel vpn <COMMAND>
```

### Help

```bash
sudo alirezapanel help
```

### Restart

```bash
sudo alirezapanel restart
```

> **این دستور برای استفاده روزمره توصیه نمی‌شود.** اگر مشکل دارید اول `status`، سپس `check` و سپس `logs` را اجرا کنید.

---

## Health Check

دو روش:

```bash
sudo alirezapanel check
```

یا:

```bash
sudo bash install.sh --check
```

`--check` حالت بررسی Read-only است.

Health Check موارد اصلی زیر را بررسی می‌کند:

- وضعیت سرویس‌های systemd
- پاسخ Public Interface
- Integration و Branding
- دسترسی کنترل‌شده به DNS API
- ارتباط با AdGuard
- DNS Resolution واقعی روی IP/Port تنظیم‌شده

---

## Backup

```bash
sudo alirezapanel backup
```

Backupها در:

```text
/var/backups/alirezapanel/
```

ذخیره می‌شوند.

Backup شامل بخش‌های مهم Config، VPN و AdGuard است.

در Backup، ابزار ممکن است برای Consistency سرویس‌ها را موقتاً متوقف و سپس خودش دوباره Start کند.

> برای Backup سرویس‌ها را دستی Stop/Restart نکنید.

---

## Repair

برای بازسازی Integration و نسخه‌های Pin شده:

```bash
sudo bash install.sh --repair
```

Repair برای حفظ تنظیمات، Userها و داده‌های موجود طراحی شده و قبل از تغییرات Backup می‌گیرد.

اگر نسخه بالادستی را خارج از پروژه Upgrade کرده باشید، Installer از Downgrade خاموش و خطرناک جلوگیری می‌کند.

> هنگام Repair نیز چرخه سرویس را به خود Installer بسپارید.

---

## SSL و Certificate

### Domain + Let's Encrypt

Installer می‌تواند Certificate معتبر را با Certbot دریافت کند.

### Certificate شخصی

در اولین نصب:

```bash
sudo env \
  ALIREZA_HOST=panel.example.com \
  ALIREZA_TLS_MODE=domain \
  ALIREZA_CERT=/root/fullchain.pem \
  ALIREZA_KEY=/root/privkey.pem \
  bash install.sh
```

`ALIREZA_CERT` و `ALIREZA_KEY` باید با هم ارائه شوند.

### مسیر Certificate پروژه

```text
/etc/alirezapanel/tls/cert.pem
/etc/alirezapanel/tls/key.pem
```

---

## ساختار فایل‌ها

| مسیر | کاربرد |
|---|---|
| `/opt/alirezapanel` | Root برنامه |
| `/opt/alirezapanel/gateway` | Gateway Integration |
| `/opt/alirezapanel/vpn` | VPN-UI |
| `/opt/alirezapanel/adguard` | AdGuard Home |
| `/opt/alirezapanel/adguard/AdGuardHome.yaml` | تنظیمات AdGuard |
| `/etc/alirezapanel` | Config اصلی |
| `/etc/alirezapanel/access.json` | Credentials اولیه |
| `/etc/alirezapanel/gateway.json` | تنظیمات Gateway |
| `/etc/alirezapanel/tls/cert.pem` | Certificate |
| `/etc/alirezapanel/tls/key.pem` | Private Key |
| `/var/backups/alirezapanel` | Backupها |
| `/usr/local/bin/alirezapanel` | CLI |

---

## سرویس‌های systemd

سه Unit اصلی:

```text
alirezapanel.service
alirezapanel-vpn.service
alirezapanel-dns.service
```

Recovery Policy:

```text
Restart=on-failure
RestartSec=5
```

این بخش یکی از دلایل اصلی است که **Restart دستی نباید اولین واکنش به یک مشکل باشد**.

---

## امنیت

### Web Backendها Public نیستند

```text
VPN-UI:       127.0.0.1:18080
AdGuard Web:  127.0.0.1:18081
```

Gateway جلوی آن‌ها قرار می‌گیرد.

### Credential داخلی AdGuard

Integration برای ارتباط داخلی با AdGuard Credential خصوصی دارد و طراحی شده که این Credential مستقیماً به Browser ارسال نشود.

### DNS عمومی

اگر پورت 53 را برای اینترنت باز می‌کنید، DNS شما می‌تواند از بیرون قابل دسترسی باشد. Access Policy و Client Settings مناسب را داخل AdGuard تنظیم کنید و Firewall را متناسب با نیاز خود محدود کنید.

Config اولیه DNS دارای Rate Limit است، اما Rate Limit جای Firewall و Access Control را نمی‌گیرد.

### Random Base Path

Public URL دارای Base Path تصادفی است که هنگام نصب ایجاد می‌شود.

---

## Dependencyهای Runtime

Installer Packageهای Runtime کوچک موردنیاز را از Repository سیستم‌عامل نصب می‌کند، از جمله:

```text
ca-certificates
curl
python3
python3-aiohttp
python3-yaml
python3-bcrypt
openssl
iproute2
dnsutils
sqlite3
tar
util-linux
```

در Domain SSL Mode، `certbot` نیز نصب می‌شود.

---

## به‌روزرسانی

نسخه‌های فعلی Pin شده:

```text
Integration:  1.1.0
VPN-UI:       v1.9.4
AdGuard Home: v0.107.79
```

قبل از هر Upgrade:

```bash
sudo alirezapanel backup
```

Update دستی VPN-UI یا AdGuard می‌تواند Layout/API یا Database Schema را تغییر دهد. Installer هنگام Repair تلاش می‌کند از Silent Downgrade نسخه‌ای که قبلاً Upgrade شده جلوگیری کند.

Integration دارای Background Auto-Update مستقل نیست.

---

## رفع اشکال

### پنل باز نمی‌شود

**Restart نکنید.**

اول:

```bash
sudo alirezapanel status
```

بعد:

```bash
sudo alirezapanel check
```

سپس:

```bash
sudo alirezapanel logs
```

اگر لازم بود Journal مستقیم:

```bash
sudo journalctl \
  -u alirezapanel \
  -u alirezapanel-vpn \
  -u alirezapanel-dns \
  -n 100 \
  --no-pager
```

---

### DNS از بیرون جواب نمی‌دهد

ابتدا:

```bash
sudo alirezapanel check
```

سپس بررسی کنید:

```bash
sudo ss -lntup | grep ':53'
```

موارد رایج:

- TCP 53 در Firewall بسته است.
- UDP 53 در Firewall بسته است.
- Cloud Firewall Provider بسته است.
- سرور پشت NAT است و Port Forward ندارید.
- Provider ترافیک DNS را محدود کرده است.
- Client از Secure DNS/DoH دیگری استفاده می‌کند.

---

### پورت 53 Conflict دارد

بررسی:

```bash
sudo ss -lntup | grep ':53'
```

قبل از Disable کردن Resolver سیستم، دقیقاً مشخص کنید کدام Process روی IP موردنظر Listen می‌کند. Installer برای جلوگیری از خرابی شبکه Resolver سیستم را کورکورانه Disable نمی‌کند.

---

### Let's Encrypt خطا می‌دهد

بررسی کنید:

```text
A Record → Server IPv4
TCP 80 → Open
Domain → بدون http:// و https://
```

تست Resolution:

```bash
getent ahostsv4 panel.example.com
```

بعد از رفع مشکل نصب را دوباره روی Fresh Install اجرا کنید.

---

### Browser Certificate Warning می‌دهد

در IP HTTPS Mode، Self-Signed Certificate پیش‌فرض است؛ بنابراین Warning Browser طبیعی است.

برای Certificate عمومی معتبر از Domain + Let's Encrypt استفاده کنید.

---

### اطلاعات ورود را فراموش کرده‌ام

```bash
sudo alirezapanel credentials
```

این دستور Credentials **اولیه** را نشان می‌دهد. Passwordهایی که بعداً داخل UI تغییر کرده‌اند الزاماً در این فایل Sync نمی‌شوند.

---

### می‌خواهم نصب را Repair کنم

```bash
sudo bash install.sh --repair
```

---

### می‌خواهم فقط وضعیت را بررسی کنم

```bash
sudo bash install.sh --check
```

---

## سؤالات متداول

### دستور نصب چیست؟

```bash
sudo bash install.sh
```

### آیا Docker لازم است؟

خیر.

### آیا Node.js یا npm لازم است؟

خیر.

### DNS چه آدرسی دارد؟

```text
SERVER_IP
Port 53 TCP/UDP
```

### آیا `127.0.0.1:15353` استفاده می‌شود؟

خیر. DNS نسخه فعلی روی IPv4 اصلی سرور و پورت `53` قرار می‌گیرد.

### برای دامنه SSL معتبر دارم؟

اگر گزینه Domain + SSL را انتخاب کنید و A Record دامنه به سرور اشاره کند، Installer می‌تواند با Certbot گواهی Let's Encrypt دریافت کند.

### برای IP چه می‌شود؟

حالت IP به‌صورت پیش‌فرض HTTPS روی پورت `8443` و Certificate Self-Signed دارد.

### بدون SSL امکان نصب هست؟

بله. حالت `none` به‌صورت پیش‌فرض HTTP روی پورت `8080` است.

### پنل را Restart کنم؟

**برای استفاده عادی، خیر.** ابتدا:

```bash
sudo alirezapanel status
sudo alirezapanel check
sudo alirezapanel logs
```

سرویس‌ها با systemd و `Restart=on-failure` مدیریت می‌شوند.

### Backup کجاست؟

```text
/var/backups/alirezapanel
```

### ARM پشتیبانی می‌شود؟

خیر؛ Installer فعلی برای `x86_64/amd64` است.

---

## نکات مهم عملیاتی

1. **پنل را برای مشکلات عادی دستی Restart نکنید.**
2. قبل از Upgrade یا تغییر مهم Backup بگیرید.
3. Public DNS را بدون Access Policy مناسب رها نکنید.
4. Backendهای `18080` و `18081` را Public نکنید.
5. برای Domain SSL مطمئن شوید A Record درست است و TCP 80/443 باز است.
6. برای DNS، هر دو `TCP 53` و `UDP 53` را در صورت نیاز Public باز کنید.
7. فایل‌های `/etc/alirezapanel` را بدون Backup دستی تغییر ندهید.
8. Update بالادستی را قبل از بررسی Compatibility انجام ندهید.
9. اگر `check` خطا داد، اول Log را بخوانید؛ Restart کورکورانه نزنید.
10. برای Repair از خود `install.sh --repair` استفاده کنید.

---

## لایسنس

کد Integration پروژه تحت:

```text
GPL-3.0-or-later
```

ارائه می‌شود.

VPN-UI و AdGuard Home پروژه‌های بالادستی مستقل هستند و License و Attribution اصلی آن‌ها حفظ می‌شود.

`alirezapanel` یک Integration مستقل است و مالکیت پروژه‌های بالادستی را ادعا نمی‌کند.

---

## چک‌لیست بعد از نصب

```text
[ ] URL پنل را ذخیره کردم
[ ] Credentials اولیه را در جای امن نگه داشتم
[ ] Password اولیه را تغییر دادم
[ ] Firewall پنل را بررسی کردم
[ ] TCP/UDP 53 را فقط در صورت نیاز باز کردم
[ ] DNS را با dig یا nslookup تست کردم
[ ] sudo alirezapanel check موفق است
[ ] Backup اولیه گرفتم
[ ] فهمیدم Restart دستی راه‌حل روزمره نیست
```

---

<p align="center">
  <img src="./assets/alirezapanel-header.svg" alt="alirezapanel" width="72%">
</p>

<p align="center">
  <strong>alirezapanel</strong><br>
  VPN • DNS • AdGuard Home • Native Linux • systemd
</p>

</div>
