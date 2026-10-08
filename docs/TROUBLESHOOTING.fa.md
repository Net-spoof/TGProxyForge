# عیب‌یابی TGProxyForge

## پروکسی FakeTLS وصل نمی‌شود

ابتدا:

```bash
tgproxy status
tgproxy health
```

سپس بررسی کنید دامنه به IP صحیح اشاره کند:

```bash
dig +short A proxy.example.com
```

و listener پورت FakeTLS وجود داشته باشد:

```bash
ss -lntp | grep ':443 '
```

اگر FakeTLS روی پورت دیگری است همان پورت را جایگزین کنید.

## HTTPS روی دامنه باز نمی‌شود

وقتی FakeTLS روی 443 است، Telemt باید ترافیک HTTPS عادی را به Caddy روی `127.0.0.1:8443` mask کند.

```bash
systemctl status telemt caddy --no-pager
curl -I https://YOUR_DOMAIN/
ss -lntp | grep -E ':(443|8443) '
```

## Sponsor نمایش داده نمی‌شود

```bash
tgproxy health
```

سه وضعیت مهم Telemt:

```text
me_runtime_ready: true
route_mode: middle
reroute_active: false
```

اگر `route_mode` برابر `direct` و `reroute_reason` برابر `startup_direct_fallback` باشد، Telemt به Middle-Endهای کافی دسترسی ندارد. یکی از دلایل رایج، timeout شدن خروجی TCP/8888 است.

برای تست عمومی:

```bash
timeout 5 bash -c 'echo >/dev/tcp/35.180.139.74/8888' && echo OPEN || echo BLOCKED
```

اگر 8888 عمومی هم timeout شود ولی 443 باز باشد، Cloud Firewall / provider routing / upstream filtering را بررسی کنید.

## WEB Proxy وصل نمی‌شود

وضعیت relay:

```bash
source /etc/tgproxyforge/config.env
curl -fsS "http://127.0.0.1:${ADMIN_PORT}/healthz"
curl -fsS "http://127.0.0.1:${ADMIN_PORT}/readyz"
systemctl status tproxy-server mtproxy caddy --no-pager
```

WEB Proxy به پشتیبانی سمت کلاینت نیاز دارد و یک قابلیت proof-of-concept upstream است.

## مشاهده لاگ‌ها

```bash
journalctl -u telemt -n 150 --no-pager
journalctl -u tproxy-server -n 150 --no-pager
journalctl -u mtproxy -n 150 --no-pager
journalctl -u caddy -n 150 --no-pager
```

## برگرداندن تنظیمات

TGProxyForge قبل از بعضی تغییرات نصب، backupها را زیر مسیر زیر نگه می‌دارد:

```text
/opt/tgproxyforge/backups/
```
