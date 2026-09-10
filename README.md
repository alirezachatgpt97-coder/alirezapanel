<div align="center">

# 🔥 alirezapanel

### یک پنل. مدیریت VPN. کنترل DNS. احراز هویت مشترک.

**alirezapanel** رابط‌های کامل **VPN-UI** و **AdGuard Home** را پشت یک gateway واحد با برند یکپارچه قرار می‌دهد و احراز هویت مشترک، ناوبری یکپارچه، تنظیمات پیش‌فرض امن، مدیریت اختیاری چند Node و یک Installer تک‌فایلی را ارائه می‌کند.

![Version](https://img.shields.io/badge/version-1.1.0-orange)
![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Architecture](https://img.shields.io/badge/arch-x86__64-blue)
![License](https://img.shields.io/badge/integration-GPL--3.0--or--later-green)

</div>

---

## ✨ alirezapanel چیست؟

alirezapanel یک لایه‌ی سبک برای یکپارچه‌سازی است که رابط‌های وب کامل VPN-UI و AdGuard Home را زیر یک پنل عمومی واحد در کنار هم قرار می‌دهد.

این پروژه برنامه‌های upstream را با نسخه‌های ناقص یا بازنویسی‌شده جایگزین **نمی‌کند**. در عوض، فایل‌های اجرایی و رابط‌های اصلی حفظ می‌شوند و یک gateway کوچک پایتونی امکانات زیر را فراهم می‌کند:

- 🔐 احراز هویت مشترک
- 🧭 ناوبری یکپارچه
- 🎨 برندینگ یکپارچه و استایل Ember UI
- 🛡️ دسترسی محافظت‌شده به AdGuard Home
- 🌐 حالت‌های دسترسی Domain، IP HTTPS و HTTP
- 🧩 پشتیبانی از چند Node
- 💾 ابزارهای Backup و Repair
- ❤️ Health Check داخلی

کد یکپارچه‌سازی داخل Installer قرار دارد، در حالی که باینری‌های upstream با نسخه‌های مشخص‌شده هنگام نصب دانلود می‌شوند.

---

## 🚀 ویژگی‌های برجسته

### 🔐 یک ورود

مانند حالت عادی از طریق پنل VPN وارد شوید. مدیریت DNS در همان رابط یکپارچه شده و فقط برای Super Adminهای مجاز در دسترس است.

اطلاعات ورود AdGuard Home به‌صورت خصوصی روی سرور نگه‌داری می‌شود و در اختیار مرورگر قرار نمی‌گیرد.

### 🛡️ رابط کامل AdGuard Home

رابط واقعی AdGuard Home به‌طور کامل حفظ شده است، از جمله:

- Dashboard
- Query Log
- Statistics
- Filters
- DNS blocklists
- Allowlists
- DNS rewrites
- Blocked services
- Client settings
- DNS settings
- Encryption settings
- DHCP settings

هیچ داشبورد ناقص و جایگزینی استفاده نمی‌شود.

### 🌐 رابط کامل VPN-UI

رابط مدیریت VPN upstream و قابلیت‌های Native آن همچنان در دسترس هستند. alirezapanel شناسه‌های پروتکل، payloadهای API، تنظیمات VPN، قوانین Routing یا فایل‌های اجرایی upstream را بازنویسی نمی‌کند.

### 🧩 مدیریت چند Node

alirezapanel قابلیت اختیاری Node را برای اتصال چند سرور سازگار در خود دارد.

Nodeها می‌توانند با اتصال HTTPS احراز هویت‌شده به پنل اصلی اضافه شوند و دسترسی Remote به Inboundها و ساخت پروفایل‌های Subscription ترکیبی را فراهم کنند، در حالی که اطلاعات ورود Node روی خود سرور باقی می‌ماند.

### 🎨 Ember UI

نسخه 1.1 یک لایه‌ی بصری گرم با ترکیب نارنجی و زغالی را روی رابط‌های یکپارچه‌شده ارائه می‌کند.

Theme بخش‌هایی مانند Navigation، Cardها، Formها، Tableها، Dialogها و سایر اجزای رابط را هماهنگ می‌کند و در عین حال رنگ‌های معنادار مربوط به وضعیت و عملیات مخرب را حفظ می‌کند.

کنترل‌های Native حالت روشن همچنان در دسترس هستند.

---

## 📦 اجزای موجود

| Component | Version |
|---|---:|
| alirezapanel integration | `1.1.0` |
| VPN-UI | `v1.9.4` |
| AdGuard Home | `v0.107.79` |

نسخه‌های upstream روی Versionها و SHA-256 Hashهای شناخته‌شده Pin شده‌اند و به‌جای دانلود بی‌صدا از آخرین نسخه موجود، نسخه‌های مشخص و قابل‌تکرار استفاده می‌شوند.

---

## ✅ سیستم‌های پشتیبانی‌شده

استفاده از یک **سرور تازه** به‌شدت توصیه می‌شود.

### سیستم‌عامل‌ها

- Debian 12
- Debian 13
- Ubuntu 24.04

### معماری

- `x86_64 / amd64`

> ARM توسط این Installer پشتیبانی نمی‌شود.

### نیازمندی‌های سرور

حداقل بررسی‌های نصب:

- حدود **1 GiB RAM**
- حداقل **2 GiB فضای خالی روی `/opt`**
- `systemd`
- دسترسی Root / sudo
- دسترسی اینترنت به:
  - GitHub
  - مخازن Package توزیع
  - DNS upstreamها

برای بار کاری سبک، پروژه با درنظر گرفتن سرورهای کوچک مانند **1 vCPU / 1 GiB RAM** طراحی شده است، اما این موضوع تضمین Performance یا Capacity نیست.

برای خود پنل نیازی به Go compiler، Node.js، npm، Docker یا Build Toolchain روی سرور نیست.

> برخی پروتکل‌های اختیاری VPN ممکن است همچنان به Kernel Moduleها یا Packageهای upstream خود نیاز داشته باشند.

---

## ⚡ نصب

این Repository را دانلود یا Clone کنید و مطمئن شوید نام Installer برابر `install.sh` است.

سپس اجرا کنید:

```bash
sudo bash install.sh
```

در Terminal تعاملی، Installer از شما می‌پرسد پنل عمومی به چه شکلی در دسترس قرار بگیرد:

```text
1) Domain + valid SSL (Let's Encrypt)
2) Server IP + HTTPS (self-signed SSL)
3) Server IP/domain without SSL (plain HTTP)
```

پس از نصب موفق، URL پنل به‌صورت خودکار نمایش داده می‌شود.

برای نمایش اطلاعات ورود اولیه تولیدشده:

```bash
sudo alirezapanel credentials
```

---

## 🔒 حالت‌های نصب

### 1. Domain + Let's Encrypt

برای پنل عمومی Production توصیه می‌شود.

```bash
sudo env \
  ALIREZA_TLS_MODE=domain \
  ALIREZA_HOST=panel.example.com \
  ALIREZA_ACME_EMAIL=admin@example.com \
  bash install.sh
```

پورت عمومی پیش‌فرض:

```text
443/TCP
```

قبل از نصب:

1. رکورد IPv4 **A record** دامنه را به سرور اشاره دهید.
2. مطمئن شوید **TCP port 80** ورودی هنگام صدور Certificate قابل دسترسی است.
3. **TCP 443** را در Firewall سرویس‌دهنده باز کنید.

هنگامی که Installer از طریق Certbot Certificate دریافت می‌کند، یک Renewal Hook نیز تنظیم می‌شود تا Certificate مربوط به Gateway پس از تمدید به‌روزرسانی شود.

---

### 2. Server IP + HTTPS

این حالت، پیش‌فرض امن برای نصب غیرتعاملی است.

```bash
sudo env ALIREZA_TLS_MODE=ip bash install.sh
```

پورت عمومی پیش‌فرض:

```text
8443/TCP
```

در صورتی که Certificate/Key جداگانه‌ای ارائه نشود، یک Self-signed Certificate ساخته می‌شود.

مرورگر شما معمولاً هنگام استفاده از Self-signed Certificate تولیدشده هشدار Certificate نمایش می‌دهد.

---

### 3. Plain HTTP

فقط برای محیط‌های قابل اعتماد/خصوصی:

```bash
sudo env ALIREZA_TLS_MODE=none bash install.sh
```

پورت عمومی پیش‌فرض:

```text
8080/TCP
```

> ⚠️ حالت HTTP ترافیک بین مرورگر و پنل عمومی را رمزگذاری نمی‌کند.

---

## 🔑 اطلاعات ورود سفارشی Administrator

نام کاربری پیش‌فرض Administrator برابر است با:

```text
admin
```

اگر Password مشخص نشود، یک Password تصادفی امن ساخته می‌شود.

می‌توانید در **اولین نصب** اطلاعات ورود دلخواه خود را وارد کنید:

```bash
sudo env \
  ALIREZA_USER=admin \
  ALIREZA_PASSWORD='your-strong-password-here' \
  bash install.sh
```

Password باید بین **16 تا 72 بایت UTF-8** باشد.

اطلاعات ورود اولیه در مسیر زیر ذخیره می‌شود:

```text
/etc/alirezapanel/access.json
```

این فایل فقط برای Root قابل دسترسی است و به‌عنوان یک **رکورد بازیابی اولیه** عمل می‌کند.

> تغییر Password در ادامه از داخل رابط Admin مربوط به VPN، Password جدید را با `access.json` همگام نمی‌کند.

پس از اولین ورود، تغییر Password مدیر و فعال‌کردن احراز هویت دومرحله‌ای موجود در پنل upstream توصیه می‌شود.

---

## 🔐 استفاده از TLS Certificate شخصی

Certificate Chain و Private Key متناظر را هر دو وارد کنید:

```bash
sudo env \
  ALIREZA_TLS_MODE=ip \
  ALIREZA_HOST=203.0.113.10 \
  ALIREZA_CERT=/root/fullchain.pem \
  ALIREZA_KEY=/root/privkey.pem \
  bash install.sh
```

هر دو Variable باید هم‌زمان ارائه شوند.

فایل‌های TLS مربوط به Gateway در مسیر زیر ذخیره می‌شوند:

```text
/etc/alirezapanel/tls/
```

---

## ⚙️ متغیرهای محیطی

| Variable | Description |
|---|---|
| `ALIREZA_HOST` | IP عمومی یا Domain بدون Scheme و Port |
| `ALIREZA_PORT` | پورت عمومی پنل |
| `ALIREZA_TLS_MODE` | `domain`، `ip` یا `none` |
| `ALIREZA_ACME_EMAIL` | ایمیل اختیاری Let's Encrypt در حالت Domain |
| `ALIREZA_USER` | نام کاربری اولیه Administrator؛ پیش‌فرض: `admin` |
| `ALIREZA_PASSWORD` | Password اولیه، بین 16 تا 72 بایت UTF-8 |
| `ALIREZA_CERT` | PEM Certificate Chain موجود |
| `ALIREZA_KEY` | PEM Private Key متناظر با `ALIREZA_CERT` |

پورت‌های پیش‌فرض بر اساس TLS Mode:

| Mode | Default |
|---|---:|
| `domain` | `443` |
| `ip` | `8443` |
| `none` | `8080` |

---

## 🔥 Firewall / پورت‌های شبکه

alirezapanel عمداً Ruleهای Hosting Firewall را به‌صورت خودکار ایجاد **نمی‌کند**.

پورت‌های معمول:

| Port | Protocol | Purpose | Exposure |
|---|---|---|---|
| `443` | TCP | پنل عمومی در حالت Domain TLS | Public |
| `8443` | TCP | پنل عمومی در حالت پیش‌فرض IP HTTPS | Public |
| `8080` | TCP | پنل عمومی در حالت HTTP | Public if selected |
| `53` | TCP/UDP | AdGuard DNS resolver | Server IPv4 |
| `18080` | TCP | VPN web backend | Loopback only |
| `18081` | TCP | AdGuard HTTP backend | Loopback only |

همچنین باید پورت‌های موردنیاز پروتکل‌ها/Inboundهای VPN که فعال می‌کنید را باز کنید.

Installer فایل `systemd-resolved`، مسیر `/etc/resolv.conf` یا Ruleهای سراسری DNS NAT/redirect را تغییر نمی‌دهد.

---

## 🛡️ مدل احراز هویت و امنیت

Gateway عمومی طوری طراحی شده است که برنامه‌های upstream مجبور نباشند رابط‌های مدیریتی خود را مستقیماً در اینترنت قرار دهند.

### VPN backend

VPN web backend روی آدرس زیر تنظیم می‌شود:

```text
127.0.0.1:18080
```

### AdGuard Home backend

سرویس HTTP مدیریتی AdGuard Home روی آدرس زیر Pin می‌شود:

```text
127.0.0.1:18081
```

### مجوز دسترسی DNS

مدیریت DNS از طریق رابط یکپارچه وب به یک Session معتبر Super Admin در VPN نیاز دارد.

Gateway به‌جای Decode کردن یا اعتماد مستقل به Session Cookie، مجوز را از VPN backend بررسی می‌کند.

Username/Password خصوصی AdGuard Home و AdGuard Session Cookie به مرورگر ارسال نمی‌شوند.

### سخت‌سازی Gateway

Unit مربوط به Gateway در systemd از چندین گزینه Hardening استفاده می‌کند، از جمله:

- `NoNewPrivileges`
- Private temporary directory
- Strict filesystem protection
- Home directory protection
- Kernel tunable protection
- Control-group protection
- Restricted SUID/SGID behavior
- Restricted address families
- Limited capability set

---

## 🧩 Nodes

پشتیبانی از Node در پروژه وجود دارد اما عمداً به‌صورت جداگانه فعال می‌شود.

روی هر سروری که باید به‌عنوان Node مشارکت کند، اجرا کنید:

```bash
sudo bash install.sh --enable-nodes
```

این دستور بخش مربوط به Node را بدون نصب مجدد VPN یا DNS اضافه یا به‌روزرسانی می‌کند.

پیاده‌سازی از اتصال‌های احراز هویت‌شده Node پشتیبانی می‌کند و هویت Node Remote را اعتبارسنجی می‌کند.

محدودیت‌های فعلی پیاده‌سازی:

- حداکثر **64 Node متصل**
- حداکثر **32 منبع Subscription** در یک Profile ترکیبی

احراز هویت Node API به HTTPS و Bearer Token نیاز دارد.

### روند پیشنهادی Node

1. alirezapanel را روی سرور اصلی نصب کنید.
2. alirezapanel را روی هر Node نصب کنید.
3. در صورت نیاز `--enable-nodes` را اجرا کنید.
4. بخش **Nodes** را در پنل باز کنید.
5. Node Connector را فعال کنید.
6. Node Remote را با اطلاعات اتصال آن اضافه کنید.
7. قبل از استفاده از منابع Remote، اتصال Node را Check کنید.
8. در صورت نیاز Profileهای Subscription ترکیبی بسازید.

---

## 🖥️ CLI مدیریت

فرآیند نصب فایل زیر را ایجاد می‌کند:

```text
/usr/local/bin/alirezapanel
```

دستورهای کاربردی:

```bash
sudo alirezapanel info
```

نمایش URL عمومی و مسیرهای نصب.

```bash
sudo alirezapanel credentials
```

نمایش اطلاعات ورود **اولیه** Administrator.

```bash
sudo alirezapanel status
```

نمایش وضعیت سه سرویس مدیریت‌شده.

```bash
sudo alirezapanel check
```

اجرای بررسی سرویس‌ها، Gateway عمومی، کنترل دسترسی و DNS.

```bash
sudo alirezapanel restart
```

Restart کردن Stack مدیریت‌شده با رعایت ترتیب وابستگی‌ها و بررسی آمادگی پنل.

```bash
sudo alirezapanel logs
```

نمایش Logهای اخیر Gateway، VPN و DNS.

```bash
sudo alirezapanel backup
```

ساخت Backup دستی و سازگار.

```bash
sudo alirezapanel vpn info
```

دسترسی به CLI اصلی مدیریت VPN.

```bash
sudo alirezapanel help
```

نمایش مستندات نصب‌شده پروژه.

---

## 🩺 Health Check

همچنین می‌توانید Checker فقط‌خواندنی Installer را اجرا کنید:

```bash
sudo bash install.sh --check
```

Diagnostics داخلی بخش‌های مهم Stack را بررسی می‌کند، از جمله:

- وضعیت سرویس‌های systemd
- در دسترس بودن Gateway عمومی
- آمادگی Branding/Integration
- رد دسترسی ناشناس به مدیریت DNS
- DNS resolution
- اتصال سرویس‌های یکپارچه

در نصب تازه، پیش از اعلام موفقیت، Checkهای عمیق‌تری برای Login/Integration انجام می‌شود.

Installer فقط زمانی نصب را موفق اعلام می‌کند که بررسی‌های خودکار آن با موفقیت عبور کنند.

---

## 🔧 Repair

برای نصب مجدد Integration و باینری‌های Pin‌شده upstream در حالی که تنظیمات Installation حفظ شوند:

```bash
sudo bash install.sh --repair
```

Repair:

- Backup ایجاد می‌کند
- Userها و Settingها را حفظ می‌کند
- Credentials/Configuration را حفظ می‌کند
- Integration/Binaryهای Pin‌شده را بازیابی می‌کند
- در صورت نیاز سرویس‌ها را موقتاً Pause می‌کند
- نصب را دوباره اعتبارسنجی می‌کند

Repair عمداً در برابر تغییر Versionهای upstream محافظه‌کارانه عمل می‌کند.

اگر Database نصب‌شده VPN یا DNS قبلاً توسط Version جدیدتر upstream Migration شده باشد، Installer از Downgrade بی‌صدا خودداری می‌کند.

---

## 🔄 اصلاح صفحه Restart

برای نصب سازگار موجود، اصلاح Integration مربوط به صفحه Restart را می‌توان به‌صورت مستقل اعمال کرد:

```bash
sudo bash install.sh --fix-restart
```

پیش از اعمال Patch، از فایل Gateway یک Backup ساخته می‌شود.

---

## 💾 Backupها

برای ایجاد Backup دستی اجرا کنید:

```bash
sudo alirezapanel backup
```

Backupها در مسیر زیر ذخیره می‌شوند:

```text
/var/backups/alirezapanel/
```

Backup شامل Configuration/Stateهای مهم مانند موارد زیر است:

- `/etc/alirezapanel`
- فایل‌ها و Database مربوط به VPN
- فایل‌های AdGuard Home
- State مربوط به Nodeها، در صورت وجود

سرویس‌ها برای مدت کوتاهی Stop می‌شوند تا State کپی‌شده سازگار باشد.

دایرکتوری‌های Backup برای دسترسی Root-only در نظر گرفته شده‌اند.

---

## 📁 مسیرهای مهم

| Path | Purpose |
|---|---|
| `/opt/alirezapanel` | دایرکتوری اصلی نصب |
| `/opt/alirezapanel/gateway` | Gateway یکپارچه‌سازی و Assetهای UI |
| `/opt/alirezapanel/vpn` | فایل اجرایی و State مربوط به VPN-UI |
| `/opt/alirezapanel/adguard` | فایل اجرایی و Configuration مربوط به AdGuard Home |
| `/etc/alirezapanel` | Configuration مربوط به alirezapanel |
| `/etc/alirezapanel/gateway.json` | Configuration مربوط به Gateway عمومی |
| `/etc/alirezapanel/access.json` | رکورد بازیابی اطلاعات ورود اولیه |
| `/etc/alirezapanel/tls` | TLS Certificate/Key مربوط به Gateway |
| `/var/lib/alirezapanel-nodes` | State مربوط به Node |
| `/var/backups/alirezapanel` | Backupها |
| `/usr/local/bin/alirezapanel` | Management CLI |

---

## ⚙️ سرویس‌های systemd

alirezapanel سه سرویس اصلی را مدیریت می‌کند:

```text
alirezapanel.service
alirezapanel-vpn.service
alirezapanel-dns.service
```

می‌توانید وضعیت آن‌ها را با دستور زیر بررسی کنید:

```bash
sudo systemctl status \
  alirezapanel \
  alirezapanel-vpn \
  alirezapanel-dns
```

یا Logهای ترکیبی اخیر را با دستور زیر ببینید:

```bash
sudo alirezapanel logs
```

---

## 🌍 رفتار DNS

AdGuard Home روی IPv4 اصلی شناسایی‌شده سرور و Port `53` گوش می‌دهد.

Integration عمداً همه درخواست‌های DNS مربوط به VPN یا Host را مجبور نمی‌کند از AdGuard عبور کنند.

این کار به حفظ موارد زیر کمک می‌کند:

- Xray routing
- Split routing
- SSH/VPN outbounds
- رفتار شبکه خصوصی
- Routing و Limitهای هر Account

برنامه‌هایی که از DNS رمزگذاری‌شده خود، سرویس‌های Third-party DoH/DoT یا DNS Traffic خارج از Tunnel استفاده می‌کنند، به‌اجبار Intercept نمی‌شوند.

اگر Attribution مربوط به DNS برای Setup شما مهم است، Client/Protocol انتخابی را Test کنید و AdGuard Query Log را بررسی کنید.

> ⚠️ یک Recursive DNS Resolver بدون محدودیت را در اختیار Clientهای دلخواه اینترنت قرار ندهید. Firewall و Allowed Clientها را به‌شکل مناسب تنظیم کنید.

---

## 📊 تنظیمات پیش‌فرض منابع

Installer با تنظیمات پیش‌فرض محافظه‌کارانه ارائه می‌شود تا روی سرورهای کوچک‌تر قابل استفاده بماند.

نمونه‌ها:

- AdGuard cache: **4 MiB**
- Query-log memory buffer: **500 entries**
- Query-log retention: **24 hours**
- Statistics retention: **24 hours**
- Concurrent DNS queries: **100**
- VPN Go soft heap target: **300 MiB**
- AdGuard Go soft heap target: **160 MiB**

این مقادیر Hard Limit برای کل Memory نیستند.

Memory Usage واقعی همچنین به VPN Processهای فعال، میزان Traffic، Filter Listها، Kernel Moduleها و Workloadهای دیگر بستگی دارد.

Gateway، Uploadها، Downloadها و WebSocketها را به‌صورت Stream منتقل می‌کند و آن‌ها را به‌طور کامل در Memory Buffer نمی‌کند. تبدیل HTML به‌صورت جداگانه محدود شده است.

---

## 🧠 نکات Configuration

VPN-UI و AdGuard Home مدل Configuration اصلی و Native خود را حفظ می‌کنند.

Configuration اضافی مربوط به Gateway عمومی در مسیر زیر قرار دارد:

```text
/etc/alirezapanel/gateway.json
```

اگر Settingهای Gateway را دستی تغییر دادید، اجرا کنید:

```bash
sudo systemctl restart alirezapanel
```

VPN web port یک **پورت داخلی backend** است، نه پورت عمومی alirezapanel.

Backendهای مدیریتی Native را روی Loopback نگه دارید، مگر اینکه کاملاً پیامدهای امنیتی Public کردن آن‌ها را بدانید و بپذیرید.

---

## ⬆️ به‌روزرسانی

کنترل‌های Update مربوط به upstream ممکن است همچنان داخل رابط‌های Native آن‌ها دیده شوند، اما Update کردن یک Component از upstream می‌تواند UI، API یا Database Schema آن را تغییر دهد.

پیش از هر Update در upstream:

```bash
sudo alirezapanel backup
```

سپس Integration را بررسی کنید:

```bash
sudo alirezapanel check
```

Installer عمداً Versionها و Checksumهای upstream را Pin می‌کند.

هیچ فرآیند Background Auto-update برای Integration مربوط به alirezapanel وجود ندارد.

> ⚠️ اگر یک Component از upstream به‌روزرسانی شده، فرض نکنید `--repair` می‌تواند با امنیت آن را Downgrade کند. از Integration Version سازگار استفاده کنید یا Backup متناظر را Restore کنید.

---

## 🚫 نصب‌های موجود

Installer برای سرور تازه طراحی شده است.

این Installer عمداً از Overwrite یا Migration خودکار نصب‌های مستقل شناسایی‌شده مانند فایل‌های موجود VPN-UI/x-ui/AdGuard Home یا Serviceهای systemd متداخل خودداری می‌کند.

Migration خودکار از یک نصب مستقل موجود در نظر گرفته نشده است.

---

## 🔍 عیب‌یابی

### ابتدا همه‌چیز را بررسی کنید

```bash
sudo alirezapanel check
```

### سرویس‌ها را بررسی کنید

```bash
sudo alirezapanel status
```

### Logها را بخوانید

```bash
sudo alirezapanel logs
```

یا به‌صورت مستقیم:

```bash
sudo journalctl \
  -u alirezapanel \
  -u alirezapanel-vpn \
  -u alirezapanel-dns \
  -n 100 \
  --no-pager
```

### Repair کردن نصب آسیب‌دیده

```bash
sudo bash install.sh --repair
```

### مشکلات رایج نصب

**صدور Certificate دامنه ناموفق است**

- بررسی کنید A Record به همین سرور اشاره کند.
- بررسی کنید TCP `80` ورودی باز باشد.
- بررسی کنید سرور به Let's Encrypt دسترسی داشته باشد.

**پنل Start نمی‌شود**

- بررسی کنید پورت عمومی انتخاب‌شده قبلاً اشغال نشده باشد.
- بررسی کنید Portهای `18080` و `18081` اشغال نباشند.
- `sudo alirezapanel logs` را اجرا کنید.

**DNS Check ناموفق است**

- TCP/UDP Port `53` را بررسی کنید.
- مطمئن شوید سرویس متداخل دیگری Address/Port لازم را اشغال نکرده باشد.
- اتصال DNS upstream را بررسی کنید.
- Firewall/Security Group سرویس‌دهنده را بررسی کنید.

---

## 🔐 توصیه‌های امنیتی

برای Deployment متصل به اینترنت:

1. **Domain + TLS معتبر** را ترجیح دهید.
2. پس از اولین Login، Password اولیه Administrator را تغییر دهید.
3. احراز هویت دومرحله‌ای موجود را فعال کنید.
4. `/etc/alirezapanel` و Backupها را Root-only نگه دارید.
5. پورت‌های Backend یعنی `18080` و `18081` را به‌صورت عمومی در دسترس قرار ندهید.
6. در صورت نیاز دسترسی Public DNS را محدود کنید.
7. فقط پورت‌های VPN که واقعاً استفاده می‌کنید باز کنید.
8. پیش از Upgradeهای upstream یک Backup بگیرید.
9. بعد از تغییر Configuration، `alirezapanel check` را اجرا کنید.
10. سیستم‌عامل و Packageهای امنیتی را به‌روز نگه دارید.

---

## 🧱 معماری

یک جریان ساده‌شده درخواست به شکل زیر است:

```text
                         ┌──────────────────────┐
                         │      Browser         │
                         └──────────┬───────────┘
                                    │
                           HTTPS / HTTP
                                    │
                         ┌──────────▼───────────┐
                         │  alirezapanel Gateway│
                         │   Shared Auth + UI   │
                         └──────┬────────┬──────┘
                                │        │
                 127.0.0.1:18080│        │127.0.0.1:18081
                                │        │
                    ┌───────────▼──┐  ┌──▼──────────────┐
                    │    VPN-UI    │  │  AdGuard Home   │
                    │   Backend    │  │ Web Management  │
                    └──────────────┘  └────────┬────────┘
                                              │
                                         TCP / UDP 53
                                              │
                                      ┌───────▼───────┐
                                      │  DNS Clients  │
                                      └───────────────┘
```

Gateway عمومی، ورودی مدیریتی موردنظر پروژه است. Backendهای مدیریتی Native روی Loopback خصوصی باقی می‌مانند.

---

## ✅ اهداف طراحی

alirezapanel تلاش می‌کند:

- برنامه‌های upstream را دست‌نخورده نگه دارد
- از بازنویسی غیرضروری Protocol/Configuration جلوگیری کند
- از افشای اطلاعات ورود خصوصی AdGuard جلوگیری کند
- از Intercept سراسری DNS جلوگیری کند
- صفحه‌های Setting Native را حفظ کند
- نصب قابل‌تکرار با Binaryهای Pin‌شده فراهم کند
- ابزارهای کاربردی Repair، Backup و Diagnostic ارائه دهد
- تجربه مدیریتی عمومی را یکپارچه نگه دارد
- روی VPSهای با منابع محدود عملی باقی بماند

---

## ⚠️ محدودیت‌ها

این محدودیت‌ها را در نظر داشته باشید:

- فقط Debian 12/13 و Ubuntu 24.04 توسط این Installer پشتیبانی می‌شوند.
- فقط x86_64/amd64 پشتیبانی می‌شود.
- استفاده از سرور تازه انتظار می‌رود.
- سازگاری Protocolهای upstream همچنان به پروژه upstream مربوط است.
- بعضی Protocolهای VPN ممکن است به Kernel Module/Packageهای اضافه نیاز داشته باشند.
- Listenerهای Native مربوط به DHCP/Encrypted-DNS به Network Configuration خود نیاز دارند.
- تنظیمات پیش‌فرض Resource تضمین نمی‌کنند هر Workload داخل 1 GiB RAM جا شود.
- تغییرات آینده UI/API/Schema در upstream ممکن است به Integration به‌روزشده نیاز داشته باشد.
- نصب‌های مستقل موجود به‌صورت خودکار Migration نمی‌شوند.

---

## 📜 License و Attribution

کد Integration مربوط به alirezapanel با License زیر منتشر می‌شود:

**GPL-3.0-or-later**

پروژه‌های upstream که Bundle یا Download می‌شوند، License، Copyright Notice، نام، Interface و Attribution خود را حفظ می‌کنند.

alirezapanel یک Integration مستقل است و به‌عنوان جایگزین پروژه‌های upstream معرفی نمی‌شود.

هنگام انتشار Repository، فایل‌های License و Source/Attribution مربوط به upstream که توسط Installer ایجاد یا ارائه می‌شوند را حفظ کنید.

---

## 🤝 مشارکت

Issueها و Pull Requestها پذیرفته می‌شوند.

هنگام گزارش مشکل، لطفاً خروجی این دستورها را ارائه کنید:

```bash
sudo alirezapanel check
sudo alirezapanel status
```

برای مشکلات مربوط به Log، خروجی مرتبط دستور زیر را نیز ارائه کنید:

```bash
sudo alirezapanel logs
```

قبل از انتشار Logها به‌صورت عمومی، هر IP خصوصی، Domain، Credential، Token، Subscription URL یا اطلاعات حساس دیگر را حذف کنید.

---

## ⭐ حمایت از پروژه

اگر alirezapanel برای شما مفید است، می‌توانید Repository را Star کنید.

این کار به کاربران دیگر کمک می‌کند پروژه را پیدا کنند و دنبال کردن توسعه‌های آینده را آسان‌تر می‌کند.

---

<div align="center">

### 🔥 alirezapanel

**مدیریت VPN + DNS، یکپارچه‌شده بدون پنهان کردن ابزارهای upstream.**

</div>
