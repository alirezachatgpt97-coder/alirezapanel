<div align="center">🚀 ALIREZAPANEL

پنل یکپارچه مدیریت VPN، DNS، Subscription و Multi-Node

سریع • سبک • فارسی • متن‌باز • مناسب VPS

"Version" (https://img.shields.io/badge/version-2.7.0-00c8ff?style=for-the-badge)
"Linux" (https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu-1793D1?style=for-the-badge&logo=linux&logoColor=white)
"VPN" (https://img.shields.io/badge/VPN-Multi--Protocol-00c853?style=for-the-badge)
"DNS" (https://img.shields.io/badge/DNS-AdGuard%20Home-68BC71?style=for-the-badge&logo=adguard&logoColor=white)
"SSL" (https://img.shields.io/badge/SSL-Automatic-7C4DFF?style=for-the-badge)
"License" (https://img.shields.io/badge/License-GPL--3.0-orange?style=for-the-badge)

vpn-ui + AdGuard Home + Subscription Center + DNS Filtering + Multi-Node

"⚡ نصب سریع" (#-نصب-سریع) •
"✨ امکانات" (#-امکانات) •
"🔗 Subscription" (#-subscription) •
"🛡️ DNS" (#️-dns--adguard-home) •
"🖥️ دستورات" (#️-مدیریت-از-ترمینال) •
"🛠️ رفع مشکل" (#️-رفع-مشکل)

</div>---

🌟 ALIREZAPANEL چیست؟

ALIREZAPANEL یک پنل یکپارچه برای مدیریت سرویس‌های VPN، Proxy، DNS و Subscription روی سرور لینوکسی است.

هدف پروژه این است که بدون استفاده از Docker، Node.js و سرویس‌های سنگین اضافی، امکانات موردنیاز مدیریت سرور در یک محیط ساده و حرفه‌ای در اختیار مدیر قرار بگیرد.

هسته VPN پروژه بر پایه vpn-ui بوده و بخش DNS توسط AdGuard Home مدیریت می‌شود.

در کنار قابلیت‌های اصلی، ALIREZAPANEL امکاناتی مانند:

- 🌐 Subscription چندپروتکلی
- 📋 کپی مستقیم کانفیگ
- 📦 دانلود کانفیگ‌های Native
- 🛡️ فیلترینگ DNS
- 🚫 مسدودسازی تبلیغات
- 🔞 فیلتر محتوای بزرگسال
- 👨‍👩‍👧 حالت Family
- 🌍 Multi-Node
- 🔐 SSL
- 📊 آمار مصرف
- 🖥️ مدیریت از Terminal

را در یک مجموعه ارائه می‌کند.

---

⚡ نصب سریع

نصب با یک دستور

روی سرور با دسترسی "root" اجرا کنید:

curl -fL --retry 3 --connect-timeout 15 --max-time 180 https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh -o install.sh && bash install.sh

«این روش ابتدا "install.sh" را کامل دانلود می‌کند و فقط در صورت موفق بودن دانلود، نصاب را اجرا می‌کند.»

پس از اجرا، Setup Wizard نصب باز می‌شود و می‌توانید نوع دسترسی و SSL را انتخاب کنید.

---

📋 پیش‌نیازها

مورد| مقدار
🐧 سیستم‌عامل| Debian 12 / Debian 13 / Ubuntu 24.04
🏗️ معماری| x86_64 / amd64
⚙️ Init System| systemd
👤 دسترسی| root
🧠 RAM| حداقل حدود 512MB؛ پیشنهاد 1GB یا بیشتر
💾 فضای آزاد| حداقل 2GB
🌐 اینترنت| الزامی
📦 Docker| ❌ نیاز نیست
🟢 Node.js / npm| ❌ نیاز نیست
🛠️ Build Toolchain| ❌ برای نصب پایه نیاز نیست

«برای سرور Production و چندین پروتکل/کاربر، RAM بیشتر توصیه می‌شود. مصرف واقعی به تعداد کاربران، پروتکل‌ها، DNS filtering و میزان ترافیک بستگی دارد.»

---

✨ امکانات

🌐 مدیریت VPN و Proxy

ALIREZAPANEL قابلیت‌های اصلی vpn-ui را حفظ می‌کند و مدیریت Inbound و Client از داخل پنل انجام می‌شود.

پروتکل‌ها و سرویس‌های قابل مدیریت بسته به هسته و تنظیمات نصب شامل مواردی مانند:

"VLESS" • "VMess" • "Trojan" • "Shadowsocks" • "Hysteria" • "Hysteria2" • "AnyTLS" • "TUIC" • "Naive" • "MTProto" • "SSH" • "WireGuard" • "AmneziaWG" • "OpenVPN" • "L2TP" • "PPTP" • "OpenConnect" • "SSTP" • "IKEv2" • "GRE"

هستند.

پروتکل‌های مختلف الزاماً یک نوع خروجی ندارند. ALIREZAPANEL خروجی هر سرویس را در قالب مناسب خودش ارائه می‌کند؛ برای مثال Proxy URI برای پروتکل‌های قابل Import و فایل Native برای سرویس‌هایی مانند OpenVPN و WireGuard.

---

🔗 Subscription

یکی از بخش‌های اصلی نسخه جدید ALIREZAPANEL، صفحه Subscription بازطراحی‌شده است.

امکانات Subscription

🔹 نمایش کانفیگ‌های واقعی کاربر
🔹 پشتیبانی از چند پروتکل در یک Subscription
🔹 Copy مستقیم هر Proxy
🔹 نمایش نوع پروتکل
🔹 نمایش Node
🔹 دانلود فایل‌های Native
🔹 نمایش مصرف کاربر
🔹 نمایش حجم باقی‌مانده
🔹 نمایش تاریخ انقضا
🔹 نمودارهای مصرف
🔹 خروجی‌های مناسب Clientهای مختلف
🔹 Subscription ترکیبی Multi-Node

اگر یک "SubID" روی چند Inbound استفاده شده باشد، پنل کانفیگ‌های واقعی منتشرشده برای همان کاربر را جمع‌آوری و نمایش می‌دهد.

📋 Proxy Config

برای پروتکل‌هایی که URI استاندارد یا قابل Import دارند، کانفیگ مستقیماً از صفحه Subscription قابل Copy است.

مانند:

VLESS
VMess
Trojan
Shadowsocks
Hysteria
Hysteria2
TUIC
AnyTLS
...

اطلاعات حساس پروتکل‌هایی مانند Reality از تنظیمات واقعی vpn-ui گرفته می‌شوند و پنل برای ساخت کانفیگ، پارامترهای حساس را حدس نمی‌زند.

📦 Native Config

برای پروتکل‌هایی که فایل کانفیگ Native دارند، فایل واقعی قابل دریافت است.

از جمله:

WireGuard
AmneziaWG
OpenVPN
GRE

بنابراین هدف این نیست که همه پروتکل‌ها به زور به یک Proxy URI تبدیل شوند؛ هر پروتکل با فرمت صحیح خودش ارائه می‌شود.

---

🛡️ DNS + AdGuard Home

ALIREZAPANEL بخش DNS را با AdGuard Home یکپارچه کرده است.

امکانات DNS

🛡️ DNS Protection
🚫 Ad Blocking
🔞 Adult Content Filtering
👨‍👩‍👧 Family Protection
🔎 Safe Search
🌐 Custom Upstream
📊 DNS Statistics
📜 Query Log
👤 DNS Client اختصاصی
⏳ تاریخ انقضا
📦 Quota
🌍 محدودیت IP
🔗 DoH اختصاصی

---

⚡ DNS Quick Setup

برای ساخت DNS Client لازم نیست تمام تنظیمات AdGuard Home را دستی انجام دهید.

Preset موردنظر را انتخاب کنید و ALIREZAPANEL تنظیمات لازم را هنگام ذخیره اعمال می‌کند.

نمونه:

🚫 AdBlock

فیلترینگ DNS و لیست موردنیاز فعال می‌شود.

🔞 Adult Protection

تنظیمات موردنیاز برای فیلتر محتوای بزرگسال اعمال می‌شود.

👨‍👩‍👧 Family

مجموعه تنظیمات مناسب Family/Safe Search فعال می‌شود.

⚡ Basic

DNS Client با حداقل تغییرات ایجاد می‌شود.

نام DNS Client نیز اختیاری است؛ در صورت خالی بودن، پنل یک نام مناسب ایجاد می‌کند.

---

🔍 Content Filtering

برای Clientها می‌توان سیاست‌های فیلترینگ تعریف کرد.

از جمله:

- 🚫 تبلیغات
- 🔞 محتوای بزرگسال
- 👨‍👩‍👧 Family Protection
- 🔎 Safe Search
- 🌐 دامنه‌های سفارشی
- 📱 دسته‌های محتوایی پشتیبانی‌شده

در بخش‌هایی که Sniffing برای اعمال سیاست انتخاب‌شده لازم باشد، پنل تنظیمات موردنیاز را روی Inbound مربوطه اعمال می‌کند تا کاربر مجبور نباشد HTTP/TLS Sniffing را دستی فعال کند.

تنظیمات Transport، Reality، TLS و اطلاعات Client برای این کار بازسازی یا حدس زده نمی‌شوند.

---

🌍 Multi-Node

ALIREZAPANEL امکان مدیریت Nodeهای دیگر را نیز در نظر گرفته است.

قابلیت‌ها شامل:

- 🔗 اتصال Node
- ❤️ بررسی وضعیت اتصال
- 👤 مدیریت Client
- 🌐 مدیریت Inbound
- 📦 Subscription ترکیبی
- 📋 جمع‌آوری کانفیگ‌های واقعی Nodeها
- 🏷️ مشخص بودن Node هر کانفیگ

Subscription می‌تواند کانفیگ‌های یک کاربر را از چند Node در یک صفحه جمع‌آوری کند.

---

🔐 SSL

چند حالت دسترسی توسط نصاب پشتیبانی می‌شود.

حالت| توضیح
🌐 Domain SSL| SSL معتبر روی دامنه
🌍 Public IP SSL| دریافت SSL برای IP عمومی در شرایط پشتیبانی‌شده
🔒 Self-Signed| HTTPS با گواهی خودامضا
🔓 HTTP| بدون TLS

پورت پیش‌فرض Gateway در حالت HTTPS:

8443

و در حالت HTTP:

8080

پورت 443 عمداً برای استفاده احتمالی Inboundها آزاد نگه داشته می‌شود.

---

🖥️ مدیریت از ترمینال

پس از نصب، ابزار مدیریت پنل در دسترس است:

alireza

یا:

alirezapanel

از طریق CLI می‌توانید کارهایی مانند موارد زیر را انجام دهید:

🔗 مشاهده URL پنل
🔑 مشاهده اطلاعات ورود
🔄 Reset Password
❤️ بررسی وضعیت سرویس‌ها
♻️ Restart سرویس‌ها
📜 مشاهده Log
💾 Backup
🔐 مدیریت SSL
📊 مشاهده منابع سیستم
📁 مشاهده مسیرها و Portها
🩺 اجرای بررسی‌های تشخیصی

---

🩺 بررسی نصب

برای مشاهده وضعیت:

alirezapanel status

برای بررسی سیستم:

alirezapanel check

و برای تست فایل نصاب قبل از نصب:

bash install.sh --self-test

---

🔧 Repair

اگر ALIREZAPANEL از قبل نصب شده است، برای تعمیر نصب می‌توانید نسخه جدید "install.sh" را دریافت کرده و حالت Repair را اجرا کنید.

ابتدا:

curl -fL --retry 3 --connect-timeout 15 --max-time 180 https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh -o install.sh

سپس:

bash install.sh --repair

قبل از Upgrade یا Repair روی سرور Production، گرفتن Backup توصیه می‌شود.

---

💾 Backup

قبل از تغییرات مهم، Upgrade یا Repair از اطلاعات سرور نسخه پشتیبان تهیه کنید.

از ابزار CLI:

alirezapanel backup

پس از Backup، فایل ایجادشده را در محل امن دیگری نیز نگهداری کنید.

---

⚙️ معماری سبک

یکی از اهداف ALIREZAPANEL جلوگیری از اضافه‌کردن سرویس‌های غیرضروری به سرور است.

به همین دلیل نصب پایه به موارد زیر وابسته نیست:

Docker
Node.js
npm
Frontend Build System
Go Compiler

Gateway و ابزارهای یکپارچه‌سازی طوری طراحی شده‌اند که سرویس‌های اصلی را به هم متصل کنند، بدون اینکه برای هر قابلیت یک Daemon جداگانه ایجاد شود.

---

🔒 امنیت

چند نکته مهم:

- 🔑 رمز Admin قوی انتخاب کنید.
- 🔐 در محیط Production ترجیحاً از HTTPS معتبر استفاده کنید.
- 🧱 فقط Portهای موردنیاز را در Firewall باز کنید.
- 💾 قبل از Upgrade از اطلاعات Backup بگیرید.
- 🚫 لینک Subscription کاربران را عمومی منتشر نکنید.
- 🔗 مسیر خصوصی پنل را در اختیار افراد غیرمجاز قرار ندهید.
- 🔄 سیستم‌عامل را به‌روز نگه دارید.
- 🛡️ دسترسی SSH را ایمن کنید.

Subscription URL عملاً اطلاعات دسترسی کاربر را در اختیار دارنده لینک قرار می‌دهد و باید مانند یک اطلاعات خصوصی نگهداری شود.

---

🛠️ رفع مشکل

وضعیت سرویس‌ها

alirezapanel status

بررسی خودکار

alirezapanel check

Restart

alirezapanel restart

مشاهده Log

از منوی:

alireza

بخش Logs را انتخاب کنید.

همچنین برای بررسی سرویس‌ها می‌توانید از "journalctl" و "systemctl" استفاده کنید.

---

🔗 Subscription باز نمی‌شود؟

موارد زیر را بررسی کنید:

- Client فعال باشد.
- "SubID" صحیح داشته باشد.
- Inbound فعال باشد.
- Gateway در حال اجرا باشد.
- Node موردنظر در حالت Multi-Node قابل دسترسی باشد.
- SSL و Hostname صحیح باشند.

سپس:

alirezapanel check

را اجرا کنید.

---

🛡️ DNS فیلتر نمی‌کند؟

ابتدا از داخل ALIREZAPANEL وضعیت DNS Client و Preset انتخاب‌شده را بررسی کنید.

سپس وضعیت AdGuard Home و Gateway را از CLI بررسی کنید:

alirezapanel status

در Quick Setup، پنل تلاش می‌کند تنظیمات لازم Preset را هنگام ذخیره اعمال کند؛ بنابراین برای حالت‌های معمول نباید لازم باشد تمام گزینه‌های AdGuard Home را دستی تنظیم کنید.

---

📂 مسیرهای مهم

مسیرهای دقیق نصب و سرویس‌ها را می‌توانید با CLI مشاهده کنید.

alireza

و گزینه مربوط به Paths & Ports را انتخاب کنید.

این روش نسبت به قراردادن مسیرهای احتمالی در README مطمئن‌تر است، چون اطلاعات همان نصب را نمایش می‌دهد.

---

🔄 بروزرسانی

قبل از بروزرسانی:

alirezapanel backup

سپس آخرین Installer را دریافت کنید:

curl -fL --retry 3 --connect-timeout 15 --max-time 180 https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh -o install.sh

و Repair/Upgrade را مطابق نسخه منتشرشده اجرا کنید.

«قبل از بروزرسانی سرور Production، Release Notes نسخه جدید را بررسی کنید.»

---

🧪 وضعیت پروژه

ALIREZAPANEL یک پروژه در حال توسعه است.

قابلیت‌های اصلی روی سناریوهای واقعی آزمایش می‌شوند، اما تفاوت Kernel، Network، Firewall، Provider، IPv6 و سیستم‌عامل VPS می‌تواند روی رفتار بعضی پروتکل‌ها اثر بگذارد.

در صورت مشاهده مشکل، هنگام ثبت Issue اطلاعات مفید زیر را قرار دهید:

Operating System
RAM
Installation Mode
Protocol
Relevant error
Relevant log
Steps to reproduce

⚠️ رمز عبور، Private Key، Subscription URL، UUID خصوصی یا سایر اطلاعات حساس را داخل Issue عمومی قرار ندهید.

---

🤝 مشارکت

Pull Request و گزارش Bug برای بهتر شدن پروژه استقبال می‌شود.

برای گزارش مشکل:

1. ابتدا آخرین نسخه را بررسی کنید.
2. "alirezapanel check" را اجرا کنید.
3. Log مرتبط را بدون اطلاعات حساس آماده کنید.
4. مراحل دقیق ایجاد مشکل را توضیح دهید.

---

❤️ Credits

ALIREZAPANEL با استفاده و یکپارچه‌سازی پروژه‌های متن‌باز ساخته شده است.

از توسعه‌دهندگان و مشارکت‌کنندگان پروژه‌های زیر تشکر می‌شود:

- vpn-ui
- AdGuard Home
- پروژه‌ها و هسته‌های متن‌باز مورد استفاده توسط vpn-ui
- جامعه متن‌باز Linux

حقوق و License پروژه‌های بالادستی متعلق به صاحبان و مشارکت‌کنندگان همان پروژه‌ها است.

---

⚖️ License

ALIREZAPANEL تحت مجوز GPL-3.0-or-later منتشر می‌شود.

برای جزئیات کامل، فایل "LICENSE" مخزن و License پروژه‌های بالادستی را مطالعه کنید.

---

⭐ حمایت از پروژه

اگر ALIREZAPANEL برایتان مفید بود:

⭐ Repository را Star کنید
🐛 مشکلات را از طریق Issues گزارش کنید
🔧 در توسعه پروژه مشارکت کنید
📢 پروژه را با دیگران به اشتراک بگذارید

---

<div align="center">🚀 ALIREZAPANEL

VPN • DNS • Subscription • Multi-Node

ساخته‌شده برای مدیریت ساده‌تر سرورهای شخصی و سرویس‌های شبکه ❤️

</div>