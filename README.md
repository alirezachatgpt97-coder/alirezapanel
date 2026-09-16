<div align="center">

# 🔥 alirezapanel

### یک پنل یکپارچه برای مدیریت VPN، DNS، کاربران، Nodeها و Subscription

**alirezapanel** یک Integration سبک، تک‌فایلی و حرفه‌ای برای ترکیب **vpn-ui** و **AdGuard Home** پشت یک Gateway واحد است؛ بدون جایگزین‌کردن قابلیت‌های upstream و بدون نصب Docker، Node.js، npm یا build toolchain روی سرور مقصد.

![Version](https://img.shields.io/badge/alirezapanel-1.4.0-ff7a18?style=for-the-badge)
![VPN UI](https://img.shields.io/badge/vpn--ui-v1.9.4-2f80ed?style=for-the-badge)
![AdGuard Home](https://img.shields.io/badge/AdGuard%20Home-v0.107.79-67b279?style=for-the-badge)
![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white&style=for-the-badge)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white&style=for-the-badge)
![Arch](https://img.shields.io/badge/Arch-x86__64%20%2F%20amd64-555?style=for-the-badge)
![License](https://img.shields.io/badge/Integration-GPL--3.0--or--later-2ea44f?style=for-the-badge)

> ⚡ طراحی‌شده برای اجرای سبک روی VPSهای کم‌منبع؛ **1 vCPU / 1 GiB RAM** هدف عملی پروژه است، با این نکته که ظرفیت واقعی به پروتکل‌ها، تعداد کاربران، فیلترها و حجم ترافیک بستگی دارد.

</div>

---

## 📚 فهرست مطالب

- [معرفی پروژه](#-معرفی-پروژه)
- [فلسفه طراحی](#-فلسفه-طراحی)
- [نمای کلی معماری](#-نمای-کلی-معماری)
- [ویژگی‌های اصلی](#-ویژگیهای-اصلی)
- [لاگ و مصرف واقعی هر کاربر](#-لاگ-و-مصرف-واقعی-هر-کاربر)
- [Subscription Studio](#-subscription-studio)
- [DNS و AdGuard Home](#-dns-و-adguard-home)
- [Nodeها و مدیریت چندسروری](#-nodeها-و-مدیریت-چندسروری)
- [سیستم‌های پشتیبانی‌شده](#-سیستمهای-پشتیبانی‌شده)
- [نیازمندی‌های سخت‌افزاری](#-نیازمندیهای-سختافزاری)
- [نصب سریع از GitHub](#-نصب-سریع-از-github)
- [حالت‌های TLS و SSL](#-حالتهای-tls-و-ssl)
- [پورت‌ها و Firewall](#-پورتها-و-firewall)
- [مدیریت سرویس](#-مدیریت-سرویس)
- [Repair / Check / Self-test](#-repair--check--self-test)
- [Backup و Upgrade](#-backup-و-upgrade)
- [امنیت](#-امنیت)
- [بهینه‌سازی منابع](#-بهینهسازی-منابع)
- [محدودیت‌های مهم](#-محدودیتهای-مهم)
- [عیب‌یابی](#-عیبیابی)
- [اسکرین‌شات‌ها](#-اسکرینشاتها)
- [لایسنس](#-لایسنس)

---

# 🚀 معرفی پروژه

**alirezapanel** یک پنل جدید از صفر نیست؛ یک لایه‌ی Integration روی ابزارهای upstream است.

هدف پروژه این است که:

- رابط کامل **vpn-ui** حفظ شود.
- رابط کامل **AdGuard Home** حفظ شود.
- ورود کاربر از یک نقطه انجام شود.
- DNS داخل همان محیط مدیریتی قابل دسترسی باشد.
- برندینگ و ظاهر پنل یکپارچه شود.
- امکانات تکمیلی مثل Node، Client Policy، گزارش مصرف و Subscription Studio اضافه شوند.
- هیچ Framework سنگین frontend یا daemon اضافه‌ی بی‌دلیل وارد سیستم نشود.

یعنی پروژه تلاش نمی‌کند قابلیت‌های موجود را کم کند؛ بلکه قابلیت‌های جدید را **در کنار امکانات اصلی** اضافه می‌کند.

---

# 🧠 فلسفه طراحی

alirezapanel بر چند اصل بنا شده است:

### 1. حفظ Upstream

فایل‌های اجرایی و رابط‌های اصلی vpn-ui و AdGuard Home حفظ می‌شوند. تنظیمات پروتکل، API payloadها، Routing، Reality، TLS و ساختارهای اصلی VPN به‌صورت خودسرانه بازنویسی نمی‌شوند.

### 2. سبک بودن

روی سرور مقصد موارد زیر نصب نمی‌شوند:

- Docker
- Node.js
- npm
- Go compiler
- Build toolchain کامل

Integration اصلی در همان `install.sh` قرار دارد و هنگام نصب فایل‌های لازم استخراج می‌شوند.

### 3. کمترین Polling ممکن

قابلیت‌های اضافه تا حد ممکن **On-demand** هستند. گزارش مصرف کاربر یا Subscription Studio فقط زمانی داده می‌خوانند که مدیر آن را باز کند.

### 4. امنیت به‌جای میانبر

- Credential خصوصی AdGuard به مرورگر داده نمی‌شود.
- DNS admin مجوز جداگانه بررسی می‌کند.
- TLS trusted در صورت درخواست واقعی استفاده می‌شود.
- در صورت شکست issuance، پروژه بی‌صدا به self-signed downgrade نمی‌کند.

### 5. قابلیت تعمیر

Installer فقط برای نصب اولیه نیست؛ حالت‌های `--repair`، `--check`، `--ssl`، `--enable-nodes` و `--self-test` نیز دارد.

---

# 🏗 نمای کلی معماری

```text
                       Internet / Admin Browser
                                 │
                                 │ HTTPS / HTTP
                                 ▼
                    ┌──────────────────────────┐
                    │   alirezapanel Gateway   │
                    │        aiohttp           │
                    │ shared auth / theme / UI │
                    └─────────────┬────────────┘
                                  │
              ┌───────────────────┴───────────────────┐
              │                                       │
              ▼                                       ▼
    ┌───────────────────┐                   ┌───────────────────┐
    │      vpn-ui       │                   │   AdGuard Home    │
    │ 127.0.0.1:18080   │                   │ 127.0.0.1:18081   │
    └───────────────────┘                   └───────────────────┘
              │                                       │
              │ VPN cores / clients                   │ DNS
              ▼                                       ▼
       User traffic / nodes                      TCP + UDP 53
```

Gateway مسئول این بخش‌هاست:

- shared authentication
- branding
- navigation
- proxy امن رابط‌ها
- DNS integration
- Node integration
- Client feature integrations
- Subscription enhancements

---

# ✨ ویژگی‌های اصلی

## 🔐 ورود یکپارچه

ورود از طریق سیستم authentication پنل VPN انجام می‌شود. Gateway کوکی را خودش decode نمی‌کند و برای دسترسی حساس دوباره مجوز را از endpointهای خود vpn-ui بررسی می‌کند.

## 🎨 رابط هماهنگ

Theme اختصاصی پروژه با ظاهر نارنجی/زغالی روی بخش‌های Integration اعمال می‌شود و تا حد ممکن Navigation و رفتار native پنل را حفظ می‌کند.

## 🧩 Client Tools

در صفحه‌های مرتبط با Client/Inbound ابزارهای تکمیلی مانند:

- فیلتر / Gaming policy
- Certificate و اتصال
- گزارش واقعی مصرف کاربر
- Subscription Studio

اضافه می‌شوند.

## 🌐 مدیریت DNS

AdGuard Home به‌صورت کامل داخل پنل قرار می‌گیرد، نه یک داشبورد ناقص یا API محدود.

## 🖥 Multi-node

Nodeهای سازگار را می‌توان به سرور اصلی متصل کرد و مدیریت Remote انجام داد.

## 🛠 Repair و Health Check

ابزارهای CLI برای بررسی سرویس، تعمیر Integration و بازسازی بخش‌های مدیریت‌شده وجود دارد.

---

# 📊 لاگ و مصرف واقعی هر کاربر

یکی از قابلیت‌های جدید نسخه فعلی، نمایش **مصرف واقعی هر Client به‌صورت جداگانه** است.

این قابلیت داده ساختگی تولید نمی‌کند و packet capture جدیدی هم اضافه نمی‌کند؛ بلکه تا جای ممکن از شمارنده‌های native خود vpn-ui در جدول `client_traffics` استفاده می‌کند.

اطلاعات قابل نمایش شامل:

- Download
- Upload
- Total Usage
- Traffic Limit
- وضعیت Client
- رکوردهای مرتبط با Inbound
- شناسه / Email کاربر

### چرا این روش سبک است؟

برای این قابلیت daemon جدید یا worker دائمی ساخته نشده است. داده‌ها در زمان بازشدن Dialog توسط مدیر خوانده می‌شوند.

### نکته مهم درباره عبارت «لاگ»

این بخش **لاگ مصرف و شمارنده‌های واقعی VPN** است، نه history کامل وب‌سایت‌هایی که کاربر باز کرده است.

alirezapanel برای این قابلیت به‌صورت پیش‌فرض:

- payload کاربران را capture نمی‌کند.
- browsing history مستقل ذخیره نمی‌کند.
- packet sniffer اضافه نصب نمی‌کند.

این تصمیم هم برای Performance و هم برای Privacy مهم است.

---

# 📈 Subscription Studio

**Subscription Studio** نمای مدیریتی حرفه‌ای برای مشاهده وضعیت اشتراک Client است.

این بخش فرمت native subscription را خراب یا جایگزین نمی‌کند؛ بلکه یک لایه‌ی نمایشی حرفه‌ای برای مدیر فراهم می‌کند.

قابلیت‌ها:

- نمایش Client ID / Email
- نمایش حجم مصرف‌شده
- نمایش حجم باقی‌مانده
- Upload
- Download
- تاریخ انقضا در صورت وجود
- وضعیت Unlimited
- نمودار حلقه‌ای درصد مصرف
- نمایش Subscription IDهای ثبت‌شده
- Copy سریع شناسه‌ها
- طراحی هماهنگ با Theme اصلی پنل

### هدف Subscription Studio

به‌جای یک لینک خام و غیرقابل‌فهم، مدیر می‌تواند وضعیت حساب را به‌شکل واضح و حرفه‌ای مشاهده کند.

> فرمت‌های native subscription، JSON و Clash که خود vpn-ui ارائه می‌کند حفظ می‌شوند.

---

# 🛡 DNS و AdGuard Home

رابط کامل AdGuard Home حفظ می‌شود، شامل:

- Dashboard
- Query Log
- Statistics
- Filters
- Blocklists
- Allowlists
- DNS rewrites
- Blocked services
- Client settings
- DNS settings
- Encryption settings
- DHCP settings

## Managed DNS Clients

پروژه قابلیت Managed DoH Client نیز دارد.

هر Client می‌تواند credential مجزا داشته باشد و بسته به تنظیمات از قابلیت‌هایی مانند:

- quota
- query count limit
- expiry
- first-success activation
- IP restriction
- per-client filtering
- custom upstreams
- saved presets

استفاده کند.

### URL Managed DoH

الگوی URL:

```text
https://HOST:PANEL_PORT/dns-query/SECRET
```

این URL با subscription VPN یکسان نیست و برای کلاینت‌های DoH استفاده می‌شود.

---

# 🧩 Nodeها و مدیریت چندسروری

Nodeها اختیاری هستند و به‌صورت پیش‌فرض تمام coreهای اضافه فعال نمی‌شوند.

برای اضافه/به‌روزرسانی قابلیت Node:

```bash
sudo bash install.sh --enable-nodes
```

پس از فعال‌سازی، امکان مدیریت Nodeهای سازگار از پنل اصلی فراهم می‌شود.

در معماری Node:

- Credential روی سرور نگه‌داری می‌شود.
- مسیرهای UI به mount مناسب تبدیل می‌شوند.
- API و protocol identifiers به‌صورت غیرضروری بازنویسی نمی‌شوند.
- لینک‌ها و exportها برای hostname Node مربوطه سازگار می‌شوند.

برای Upgrade بهتر است نسخه Installer روی Master و Nodeها یکسان باشد.

---

# ✅ سیستم‌های پشتیبانی‌شده

Installer فعلی برای موارد زیر طراحی شده است:

| بخش | پشتیبانی |
|---|---|
| Debian 12 | ✅ |
| Debian 13 | ✅ |
| Ubuntu 24.04 | ✅ |
| x86_64 / amd64 | ✅ |
| ARM / ARM64 | ❌ |
| systemd | ✅ الزامی |
| Fresh VPS | ✅ شدیداً توصیه می‌شود |
| Docker container معمولی | ❌ |

نسخه فعلی vpn-ui استفاده‌شده در Installer برای amd64 Pin شده است؛ به همین دلیل ARM توسط Installer فعلی پشتیبانی نمی‌شود.

---

# 💻 نیازمندی‌های سخت‌افزاری

## حداقل منطقی

- 1 vCPU
- 512 MiB RAM برای نصب بسیار سبک
- حداقل 2 GiB فضای خالی روی `/opt`
- دسترسی root
- systemd فعال
- دسترسی اینترنت

## پیشنهاد پروژه

- **1 vCPU**
- **1 GiB RAM یا بیشتر**
- SSD

### توجه

512 MiB حالت حداقلی است و ظرفیت آن تضمین نشده است. پروتکل‌های بیشتر، geofileهای بزرگ، filter listهای سنگین، تعداد زیاد Client و ترافیک بالا RAM بیشتری مصرف می‌کنند.

---

# ⚡ نصب سریع از GitHub

ساده‌ترین روش:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh)
```

یا با `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh)
```

### روش پیشنهادی برای بررسی فایل قبل از اجرا

```bash
curl -fLo install.sh https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh
chmod +x install.sh
bash install.sh --self-test
sudo bash install.sh
```

این روش بهتر است چون قبل از اجرا می‌توانید فایل را مشاهده و self-test کنید.

---

# 🔐 حالت‌های TLS و SSL

Installer چهار مدل دسترسی را پشتیبانی می‌کند.

## 1. Domain + trusted SSL

```bash
sudo env \
  ALIREZA_TLS_MODE=domain \
  ALIREZA_HOST=panel.example.com \
  ALIREZA_ACME_EMAIL=admin@example.com \
  bash install.sh
```

Certificate trusted از Let's Encrypt دریافت می‌شود.

## 2. Public IP + trusted SSL

```bash
sudo env ALIREZA_TLS_MODE=ip-acme bash install.sh
```

این حالت برای Certificate trusted روی IP عمومی در نسخه Installer فعلی در نظر گرفته شده است.

## 3. Self-signed HTTPS

```bash
sudo env ALIREZA_TLS_MODE=ip bash install.sh
```

اگر Certificate خارجی ارائه نشده باشد، Certificate self-signed ساخته می‌شود و مرورگر هشدار trust خواهد داد.

## 4. HTTP بدون TLS

```bash
sudo env ALIREZA_TLS_MODE=none bash install.sh
```

برای شبکه عمومی توصیه نمی‌شود.

---

# 🔑 متغیرهای نصب

| Variable | توضیح |
|---|---|
| `ALIREZA_HOST` | Domain یا IP عمومی بدون scheme |
| `ALIREZA_PORT` | پورت عمومی Gateway |
| `ALIREZA_TLS_MODE` | `domain`, `ip-acme`, `ip`, `none` |
| `ALIREZA_ACME_EMAIL` | ایمیل Let's Encrypt |
| `ALIREZA_USER` | نام مدیر اولیه |
| `ALIREZA_PASSWORD` | رمز مدیر اولیه، بین 16 تا 72 بایت UTF-8 |
| `ALIREZA_CERT` | Certificate PEM خارجی |
| `ALIREZA_KEY` | Private key متناظر |

اگر Password داده نشود، Installer رمز امن تصادفی می‌سازد.

---

# 🌐 پورت‌ها و Firewall

پورت‌های داخلی/پیش‌فرض مهم:

| Port | Protocol | کاربرد |
|---:|---|---|
| `8443` | TCP | Gateway عمومی HTTPS در تنظیمات رایج |
| `8080` | TCP | حالت HTTP بدون TLS |
| `18080` | TCP / loopback | vpn-ui backend |
| `18081` | TCP / loopback | AdGuard Home web backend |
| `2097` | TCP / loopback | Subscription listener داخلی |
| `53` | TCP + UDP | DNS resolver |

پورت‌های VPN وابسته به Inboundها و پروتکل‌هایی هستند که خودتان فعال می‌کنید.

> پورت‌های loopback نباید مستقیماً Public شوند.

---

# ⚙️ مدیریت سرویس

بررسی Gateway:

```bash
systemctl status alirezapanel.service
```

VPN backend:

```bash
systemctl status alirezapanel-vpn.service
```

DNS:

```bash
systemctl status alirezapanel-dns.service
```

Logها:

```bash
journalctl -u alirezapanel.service -n 100 --no-pager
journalctl -u alirezapanel-vpn.service -n 100 --no-pager
journalctl -u alirezapanel-dns.service -n 100 --no-pager
```

---

# 🧰 Repair / Check / Self-test

## Health Check

```bash
sudo bash install.sh --check
```

یا پس از نصب:

```bash
sudo alirezapanel check
```

## Repair

```bash
sudo bash install.sh --repair
```

Repair برای بازگردانی فایل‌های Integration و باینری‌های Pin‌شده استفاده می‌شود و تنظیمات/کاربران موجود را تا حد طراحی پروژه حفظ می‌کند.

## SSL Manager

```bash
sudo bash install.sh --ssl
```

یا:

```bash
sudo alirezapanel ssl
```

## Self-test

```bash
bash install.sh --self-test
```

Self-test بدون نصب:

- Bash syntax را بررسی می‌کند.
- Python moduleهای embedشده را compile می‌کند.

## Restart-page fix

```bash
sudo bash install.sh --fix-restart
```

---

# 💾 Backup و Upgrade

قبل از Repair یا Upgrade مهم از سرور Snapshot بگیرید.

دستور معمول برای ارتقای Integration با همان نسخه‌های سازگار:

```bash
sudo bash install.sh --repair
```

Installer در بخش‌های مدیریت‌شده Backup ایجاد می‌کند و از downgrade خاموش databaseهای ناسازگار جلوگیری می‌کند.

برای Master/Node پیشنهاد می‌شود همه سرورها از نسخه یکسان Installer استفاده کنند.

---

# 🔒 امنیت

alirezapanel در طراحی فعلی چند لایه محافظتی دارد:

- Gateway عمومی و backendهای خصوصی جدا هستند.
- vpn-ui و AdGuard Web به loopback bind می‌شوند.
- Credential خصوصی AdGuard در browser expose نمی‌شود.
- درخواست‌های DNS admin نیاز به session معتبر دارند.
- Same-origin validation روی routeهای integration اعمال می‌شود.
- Certificate/Key در مسیر مدیریت‌شده سرور نگه‌داری می‌شوند.
- پسورد اولیه روی command line log نمی‌شود.
- Binaryهای upstream با Version و SHA256 مشخص Pin می‌شوند.
- Repair در صورت تشخیص version mismatch خطرناک، بی‌صدا downgrade انجام نمی‌دهد.

### توصیه‌های Production

- از trusted TLS استفاده کنید.
- 2FA پنل upstream را فعال کنید.
- فقط پورت‌های لازم را Public کنید.
- SSH را محدود کنید.
- از UFW/nftables یا Firewall provider استفاده کنید.
- از Snapshot و Backup منظم استفاده کنید.
- DNS resolver را بدون سیاست مناسب به اینترنت عمومی باز نگذارید.

---

# ⚙️ بهینه‌سازی منابع

پروژه برای VPSهای کوچک طراحی شده است.

مهم‌ترین تصمیم‌های Performance:

- بدون Node.js runtime
- بدون Docker
- بدون frontend framework سنگین جدید
- بدون daemon جداگانه برای Subscription Studio
- بدون polling دائمی برای گزارش مصرف کاربران
- cache و retention محدود AdGuard
- استفاده از loopback برای backendهای داخلی
- اجرای قابلیت‌ها به‌صورت On-demand
- native coreهای اختیاری تا زمان نیاز فعال نمی‌شوند

### تنظیمات سبک AdGuard

پیکربندی اولیه روی مقادیر محافظه‌کارانه‌ای قرار می‌گیرد، از جمله cache کوچک و retention کوتاه‌تر برای Query Log و Statistics.

با این حال **Go memory target یک hard memory cap نیست** و هیچ نرم‌افزاری نمی‌تواند در تمام workloadها مصرف ثابت 1 GiB را تضمین کند.

---

# ⚠️ محدودیت‌های مهم

برای شفافیت:

1. **1 GiB RAM تضمین ظرفیت نامحدود نیست.** تعداد زیاد Client، فیلترهای سنگین و coreهای مختلف RAM بیشتری می‌خواهند.
2. ARM پشتیبانی نمی‌شود.
3. Migration خودکار از هر نصب قبلی vpn-ui/x-ui/AdGuard تضمین نشده و Fresh Server توصیه می‌شود.
4. DNS per-client نمی‌تواند هر نوع ترافیک رمزگذاری‌شده یا DNS خارج از Tunnel را شناسایی کند.
5. گزارش مصرف Client معادل browsing-history نیست.
6. Self-signed TLS معتبر عمومی نیست.
7. Public DNS port 53 باید با دقت و ACL مناسب استفاده شود.
8. رفتار protocolهای native همچنان تحت محدودیت‌ها و قابلیت‌های upstream است.

---

# 🧯 عیب‌یابی

## پنل بالا نمی‌آید

```bash
sudo alirezapanel check
systemctl status alirezapanel.service
journalctl -u alirezapanel.service -n 200 --no-pager
```

سپس در صورت نیاز:

```bash
sudo bash install.sh --repair
```

## VPN UI مشکل دارد

```bash
systemctl status alirezapanel-vpn.service
journalctl -u alirezapanel-vpn.service -n 200 --no-pager
```

## DNS مشکل دارد

```bash
systemctl status alirezapanel-dns.service
journalctl -u alirezapanel-dns.service -n 200 --no-pager
```

بررسی Port 53:

```bash
ss -lntup | grep ':53 '
```

## SSL مشکل دارد

```bash
sudo alirezapanel ssl status
```

Renew check:

```bash
sudo alirezapanel ssl renew
```

---

# 🖼 اسکرین‌شات‌ها

برای README حرفه‌ای پیشنهاد می‌شود تصاویر واقعی پنل را در مسیر زیر قرار دهید:

```text
docs/images/
├── dashboard.png
├── clients.png
├── user-usage.png
├── subscription-studio.png
├── dns-dashboard.png
└── nodes.png
```

سپس این بخش به‌صورت خودکار در GitHub نمایش داده می‌شود:

## Dashboard

![Dashboard](docs/images/dashboard.png)

## Client management

![Clients](docs/images/clients.png)

## User usage

![User usage](docs/images/user-usage.png)

## Subscription Studio

![Subscription Studio](docs/images/subscription-studio.png)

## DNS

![DNS Dashboard](docs/images/dns-dashboard.png)

## Nodes

![Nodes](docs/images/nodes.png)

> اگر هنوز تصاویر را آپلود نکرده‌اید، GitHub فقط placeholder شکسته نشان می‌دهد؛ بنابراین بهتر است بعد از تهیه Screenshotها این مسیرها را اضافه کنید.

---

# 📦 نسخه‌های Pin شده

| Component | Version |
|---|---:|
| alirezapanel Integration | `1.4.0` |
| vpn-ui | `v1.9.4` |
| AdGuard Home | `v0.107.79` |

Installer علاوه بر Version، SHA256 باینری‌های upstream را نیز بررسی می‌کند.

---

# 📁 مسیرهای مهم

| مسیر | کاربرد |
|---|---|
| `/opt/alirezapanel` | فایل‌های اصلی runtime |
| `/etc/alirezapanel` | تنظیمات و state مدیریت‌شده |
| `/etc/alirezapanel/access.json` | اطلاعات ورود اولیه / recovery record |
| `/etc/alirezapanel/tls/` | Certificate و Key Gateway |
| `/var/lib/alirezapanel-nodes` | state خصوصی Nodeها |

---

# 🧪 بررسی پس از نصب

بعد از نصب:

```bash
sudo alirezapanel check
```

و وضعیت سرویس‌ها:

```bash
systemctl --no-pager --full status \
  alirezapanel.service \
  alirezapanel-vpn.service \
  alirezapanel-dns.service
```

همچنین Firewall و DNS خارجی را از یک دستگاه دیگر تست کنید.

---

# 🧷 فرمان‌های پرکاربرد

```bash
# نصب
sudo bash install.sh

# بررسی
sudo bash install.sh --check

# تعمیر
sudo bash install.sh --repair

# تنظیم SSL
sudo bash install.sh --ssl

# فعال/آپدیت Node
sudo bash install.sh --enable-nodes

# فقط Fix صفحه Restart
sudo bash install.sh --fix-restart

# Self-test بدون نصب
bash install.sh --self-test

# اطلاعات پنل
sudo alirezapanel info

# Credential اولیه
sudo alirezapanel credentials

# Check نصب‌شده
sudo alirezapanel check

# SSL status
sudo alirezapanel ssl status
```

---

# 🌟 چرا alirezapanel؟

اگر می‌خواهید روی یک VPS سبک:

- VPN مدیریت کنید،
- DNS حرفه‌ای داشته باشید،
- چند Node کنترل کنید،
- مصرف Clientها را جداگانه ببینید،
- Subscriptionها را حرفه‌ای‌تر مدیریت کنید،
- و در عین حال UI و قابلیت‌های native ابزارهای اصلی را از دست ندهید،

alirezapanel برای همین سناریو طراحی شده است.

---

# 🤝 مشارکت

Issue و Pull Request برای:

- Bug fix
- Documentation
- UI improvement
- Performance improvement
- Compatibility testing
- Security hardening

خوش‌آمد است.

هنگام گزارش Bug، لطفاً موارد زیر را بدون اطلاعات حساس ارسال کنید:

```text
OS:
RAM / CPU:
alirezapanel version:
Command used:
alirezapanel check output:
Relevant journalctl output:
```

---

# 📜 لایسنس

کد Integration پروژه تحت:

```text
GPL-3.0-or-later
```

منتشر می‌شود.

باینری‌ها و پروژه‌های upstream لایسنس‌های مستقل خود را دارند و attribution آن‌ها حفظ می‌شود.

---

<div align="center">

## 🔥 alirezapanel

**One panel. VPN. DNS. Nodes. Real client usage. Professional subscription management.**

### نصب سریع

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh)
```

⭐ اگر پروژه برایتان مفید بود، Repository را Star کنید.

</div>
