# ارتقا و بازگشت

این راهنما فقط برای نصب موجود **alirezapanel** است. به alirezaserver یا پنل دیگر اعمال نکنید. باینری‌های pinned تغییر نکرده‌اند؛ نسخهٔ بالاتر vpn-ui/AdGuard به‌صورت مخفی downgrade نمی‌شود.

## ارتقای کوتاه

1. ZIP را باز کنید و `install.sh` جدید را روی سرور اصلی و تمام نودها بگذارید.
2. در هر سرور:

```bash
bash install.sh --self-test
sudo alirezapanel backup
sudo bash install.sh --repair
sudo alirezapanel check
```

3. مسیر پشتیبان چاپ‌شده را یادداشت کنید. ارتقا سرویس‌ها را موقتاً متوقف می‌کند؛ پنجرهٔ نگهداری مناسب انتخاب کنید.
4. در مرورگر تازه‌سازی کامل انجام دهید. در بخش نودها اتصال را بررسی کنید؛ روی سرور مقصد یک اینباند آزمایشی بسازید و مطمئن شوید در سرور اصلی ساخته نشده است.
5. یک ادمین محدود را در پنجرهٔ خصوصی امتحان کنید: صفحهٔ مجاز باز شود، دادهٔ غیرمجاز دیده نشود و خروج کار کند.
6. DNS بومی، Subscription واقعی و پروتکل‌هایی را که خودتان استفاده می‌کنید کنترل کنید.

بعد از انتشار فایل جدید در `main` همین مخزن، دریافت و ارتقای یک‌خطی:

```bash
curl -fL --retry 3 --connect-timeout 15 --max-time 180 https://raw.githubusercontent.com/alirezachatgpt97-coder/alirezapanel/main/install.sh -o install.sh && sudo alirezapanel backup && sudo bash install.sh --repair
```

**این دستور تا پیش از انتشار فایل جدید، نسخهٔ قدیمی موجود در GitHub را دریافت می‌کند.** انتشار خودکار انجام نشده است.

## چه چیزهایی حفظ می‌شوند؟

پایگاه دادهٔ VPN، کاربران، ادمین‌ها و مجوزهایشان، اینباندها، نودها و توکن‌ها، سیاست‌های Xray، تنظیمات Gateway، گواهی‌ها، داده و تنظیمات AdGuard و دادهٔ DNS اضافیِ قدیمی. رابط مستقل کلاینت DNS نمایش داده نمی‌شود، اما فایل SQLite و لینک‌های قدیمی حذف نشده‌اند.

اگر فایل `gateway.json` موجود باشد، مقداردهی اولیه نام کاربری، رمز و تنظیمات را بازنویسی نمی‌کند. YAML مربوط به AdGuard برای فعال‌کردن DoH یا استثنای rate limit دوباره نوشته نمی‌شود. HTTPS و تمدید گواهی باقی‌اند.

`--repair` قبل از تعویض فایل‌ها سرویس‌ها را متوقف و پوشه‌های زیر را پشتیبان می‌گیرد:

| نام داخل Backup | داده |
|---|---|
| `config/` | `/etc/alirezapanel`، تنظیمات و گواهی‌ها |
| `vpn/` | پایگاه داده، باینری و فایل‌های VPN |
| `adguard/` | باینری، YAML و داده‌های AdGuard |
| `gateway/` | کد رابط و اتصال‌ها |
| `nodes/` | state نود، سیاست‌ها و DNS SQLite قدیمی |
| `units/` | سرویس‌ها، timerها و drop-inهای systemd |
| `cli` | فرمان `/usr/local/bin/alirezapanel` |
| `README.txt` | راهنمای نصب‌شدهٔ قبلی |

اگر توقف سرویس ناموفق باشد، کپی دادهٔ زنده ادامه پیدا نمی‌کند. پشتیبان‌ها حساس‌اند و با دسترسی محدود ساخته می‌شوند. خروجی گواهی عمومی و API Token را در GitHub قرار ندهید.

## بازگشت دستی

پشتیبان کامل و سازگارِ چاپ‌شده توسط `--repair` نسخهٔ 2.8 را انتخاب کنید؛ این Snapshot **محتوای نسخهٔ قبلی** را دارد. Backupهای قدیمی ممکن است `units` و `cli` نداشته باشند؛ برای آن‌ها راهنمای مخصوص همان نسخه لازم است. مسیر را خودتان دقیق جایگزین کنید.

این مراحل را در shell دارای root انجام دهید؛ این دستورات در محیط ساخت بسته اجرا نشده‌اند. ابتدا وجود همهٔ فایل‌ها و فضای دیسک را بررسی کنید:

```bash
set -e
backup_path=/var/backups/alirezapanel/REPLACE-WITH-EXACT-BACKUP
for name in config vpn adguard gateway units; do
    test -d "$backup_path/$name" || exit 1
done
test -f "$backup_path/config/owner" || exit 1
test -f "$backup_path/cli" || exit 1
test -f "$backup_path/vpn/vpn-ui.db" || exit 1
test -f "$backup_path/adguard/AdGuardHome.yaml" || exit 1
```

سرویس‌ها را متوقف کنید. Timerهای اختیاری ممکن است در نسخهٔ قدیمی وجود نداشته باشند:

```bash
systemctl stop alirezapanel-cert-renew.timer alirezapanel-access-log.timer 2>/dev/null || true
systemctl stop alirezapanel-cert-renew.service alirezapanel-access-log.service 2>/dev/null || true
systemctl stop alirezapanel alirezapanel-vpn alirezapanel-dns
```

اگر توقف سه سرویس اصلی ناموفق بود، **ادامه ندهید**. نسخهٔ فعلی را هم به‌عنوان نقطهٔ بازگشت دوم نگه دارید؛ پوشه‌ها حذف نمی‌شوند:

```bash
rollback_checkpoint=/var/backups/alirezapanel/before-rollback-$(date -u +%Y%m%dT%H%M%SZ)-$$
test ! -e "$rollback_checkpoint" || exit 1
install -d -m 700 "$rollback_checkpoint" "$rollback_checkpoint/units"
for saved_unit in /etc/systemd/system/alirezapanel*.service /etc/systemd/system/alirezapanel*.timer /etc/systemd/system/alirezapanel*.service.d; do
    test ! -e "$saved_unit" || cp -a "$saved_unit" "$rollback_checkpoint/units/"
done
cp -a /usr/local/bin/alirezapanel "$rollback_checkpoint/cli"
mv /etc/alirezapanel "$rollback_checkpoint/config"
mv /opt/alirezapanel/vpn "$rollback_checkpoint/vpn"
mv /opt/alirezapanel/adguard "$rollback_checkpoint/adguard"
mv /opt/alirezapanel/gateway "$rollback_checkpoint/gateway"
if test -d /var/lib/alirezapanel-nodes; then
    mv /var/lib/alirezapanel-nodes "$rollback_checkpoint/nodes"
fi
```

سپس snapshot قبلی را با حفظ مالکیت، سطح دسترسی و symlinkها برگردانید:

```bash
cp -a "$backup_path/config" /etc/alirezapanel
cp -a "$backup_path/vpn" /opt/alirezapanel/vpn
cp -a "$backup_path/adguard" /opt/alirezapanel/adguard
cp -a "$backup_path/gateway" /opt/alirezapanel/gateway
if test -d "$backup_path/nodes"; then
    cp -a "$backup_path/nodes" /var/lib/alirezapanel-nodes
fi
cp -a "$backup_path/units/." /etc/systemd/system/
cp -a "$backup_path/cli" /usr/local/bin/alirezapanel
if test -f "$backup_path/README.txt"; then
    cp -a "$backup_path/README.txt" /opt/alirezapanel/README.txt
fi
systemctl daemon-reload
systemctl start alirezapanel-dns alirezapanel-vpn alirezapanel
alirezapanel check
```

Timerهایی را که پیش از بازگشت فعال بودند دوباره با `systemctl start NAME.timer` فعال کنید. اگر بازگرداندن فایل‌ها شکست خورد، سرویس‌ها را در حالت متوقف نگه دارید و با استفاده از checkpoint دوم مجموعهٔ کامل را برگردانید؛ پایگاه دادهٔ یک نسخه را با کد یا گواهیِ مجموعهٔ دیگر مخلوط نکنید. داده‌های ایجادشده پس از snapshot قبلی در checkpoint دوم محفوظ‌اند، ولی در نسخهٔ برگشتی دیده نمی‌شوند.

فایل‌های Certbot خارج از `/etc/alirezapanel` با این طراحی عوض نمی‌شوند؛ اگر جداگانه تنظیمات ACME سیستم را تغییر داده‌اید، پشتیبان همان تنظیمات نیز لازم است.
