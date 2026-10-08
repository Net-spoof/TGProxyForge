<p align="center">
  <img src="assets/banner.svg" alt="TGProxyForge banner" width="900">
</p>

<p align="center">
  <b>نصب و مدیریت تعاملی Telegram FakeTLS + WEB Proxy با پشتیبانی Sponsor</b><br>
  <b>Interactive Telegram FakeTLS + WEB Proxy installer/manager with sponsor support</b>
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-0.1.4-0ea5e9">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-111827">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-12-A81D33">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-22c55e">
</p>

<p align="center">
  <a href="https://t.me/NET_SPOOF"><strong>💬 Telegram | ارتباط مستقیم: @NET_SPOOF</strong></a>
</p>

---

## 🇮🇷 راهنمای فارسی

**TGProxyForge** یک اسکریپت Bash برای راه‌اندازی و مدیریت دو نوع پروکسی تلگرام روی یک سرور لینوکسی است:

- **MTProto FakeTLS (`ee`)** با [Telemt](https://github.com/telemt/telemt)
- **Telegram WEB Proxy (`dd`)** با [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server) + Official MTProxy + Caddy
- پشتیبانی از **Promoted / Sponsored Channel** با `@MTProxyBot`
- منوی مدیریتی برای تغییر دامنه، IP، پورت، Sponsor Tag و Secret
- تشخیص وضعیت Middle Proxy و هشدار در صورت بسته بودن خروجی `TCP/8888`
- ساخت خودکار لینک‌های FakeTLS و WEB Proxy
- HTTPS fallback / masking واقعی برای FakeTLS

> [!IMPORTANT]
> WEB Proxy یک قابلیت proof-of-concept است و فقط روی کلاینت‌هایی که این نوع transport را پشتیبانی کنند کار می‌کند. FakeTLS روی کلاینت‌های سازگار MTProxy استفاده می‌شود.

### نصب بدون خرید دامنه

اگر دامنه شخصی ندارید، آدرس **IPv4 سرور** را در نصب‌کننده وارد کنید. در سؤال «Your domain» فقط **Enter** بزنید؛ نرم‌افزار به‌صورت خودکار از سرویس شخص ثالث [sslip.io](https://sslip.io/) یک hostname مانند `176-65-151-99.sslip.io` تولید می‌کند. این hostname برای HTTPS/WEB و FakeTLS SNI استفاده می‌شود، اما **لینک FakeTLS مستقیماً به IP سرور متصل می‌شود**.

**شرایط و محدودیت‌ها:** سرویس DNS خارجی باید hostname را به IP درست resolve کند؛ همچنین صدور گواهی معتبر HTTPS توسط Caddy به دسترسی عمومی TCP 80/443، سرویس ACME و قوانین CA وابسته است. اگر DNS خودکار در مرحله پیش‌نیاز پاسخ ندهد نصب متوقف می‌شود. این روش بدون *مالکیت دامنه* است، نه کاملاً بدون DNS/hostname. عملکرد WEB Proxy در کلاینت‌های معمول تلگرام تضمین نشده است.

### نصب سریع

روی یک سرور **تمیز** Ubuntu 22.04/24.04 یا Debian 12 با معماری `x86_64` اجرا کنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Net-spoof/TGProxyForge/main/install.sh)
```

بعد از نصب، برای باز کردن منوی مدیریت:

```bash
tgproxy
```

یا دستورات مستقیم:

```bash
tgproxy status
tgproxy links
tgproxy health
tgproxy apply
tgproxy update
```

### روند نصب تعاملی

اسکریپت به‌ترتیب از شما می‌پرسد:

1. IP عمومی سرور **یا** دامنه پروکسی
2. اگر IP وارد شود، دامنه‌ای که به همان IP اشاره می‌کند
3. پورت FakeTLS — پیش‌فرض `443`
4. ایمیل ACME برای گواهی HTTPS
5. فعال بودن یا نبودن Sponsor
6. در صورت فعال بودن Sponsor، بعد از نصب اطلاعات لازم برای `@MTProxyBot` نمایش داده می‌شود و اسکریپت **Proxy Tag 32-hex** را از شما می‌گیرد

> [!NOTE]
> چیزی که از `@MTProxyBot` دریافت می‌کنید **Proxy Tag** است، نه Bot API Token. این Tag معمولاً ۳۲ کاراکتر hexadecimal است.

### منوی مدیریت

<p align="center">
  <img src="assets/menu-preview.svg" alt="TGProxyForge menu preview" width="760">
</p>

از منوی `tgproxy` می‌توانید:

- وضعیت سرویس‌ها را ببینید
- لینک‌های FakeTLS و WEB را دریافت کنید
- دامنه یا IP عمومی را عوض کنید
- پورت FakeTLS را تغییر دهید
- Sponsor Tag را فعال، عوض یا غیرفعال کنید
- Secret را rotate کنید
- سرویس‌ها را restart کنید
- وضعیت HTTPS، tproxy، Telemt API و `TCP/8888` را تست کنید
- کانفیگ ذخیره‌شده را دوباره apply کنید
- خود TGProxyForge را از GitHub آپدیت کنید

### معماری

<p align="center">
  <img src="assets/architecture.svg" alt="TGProxyForge architecture" width="900">
</p>

اگر FakeTLS روی پورت `443` باشد:

```text
Internet :443
    ↓
Telemt FakeTLS
    ├── MTProto/FakeTLS → Telegram
    └── HTTPS / probe → Caddy 127.0.0.1:8443
                              ↓
                    tproxy-server 127.0.0.1:18xxx
                              ↓
                    Official MTProxy :2398
```

اگر FakeTLS را روی پورتی غیر از `443` بگذارید، Caddy مستقیماً `443` عمومی را برای WEB Proxy می‌گیرد و Telemt روی پورت انتخابی شما گوش می‌دهد.

### Sponsor / Promoted Channel

برای Sponsor:

1. در نصب گزینه Sponsor را فعال کنید.
2. اسکریپت IP، پورت و **Base Secret** را نشان می‌دهد.
3. در `@MTProxyBot` دستور `/newproxy` را بزنید.
4. `IP:PORT` و Base Secret را ارسال کنید.
5. Proxy Tag را کپی کرده و داخل TGProxyForge وارد کنید.
6. در `/myproxies` گزینه **Set promotion** را بزنید و کانال عمومی را انتخاب کنید.

Sponsor در Telemt به Middle Proxy نیاز دارد. اگر شبکه دیتاسنتر خروجی Telegram Middle-End را مسدود کند، پروکسی ممکن است همچنان با direct fallback وصل شود اما Promotion نمایش داده نشود. برای بررسی:

```bash
tgproxy health
```

و در خروجی Telemt باید ideally ببینید:

```text
me_runtime_ready: true
route_mode: middle
reroute_active: false
```

### پورت‌های مورد نیاز

در Cloud Firewall / Provider Firewall معمولاً فقط این ورودی‌ها را باز کنید:

| Port | Direction | Purpose |
|---|---|---|
| `22/tcp` | Inbound | SSH |
| `80/tcp` | Inbound | ACME / HTTP |
| `443/tcp` | Inbound | WEB Proxy / FakeTLS when using 443 |
| `<FakeTLS port>/tcp` | Inbound | فقط اگر FakeTLS روی پورت دیگری است |

پورت‌های backend مثل `2398`, `8888`, relay/admin و `9091` نباید عمومی شوند.

> [!WARNING]
> برای Sponsor ممکن است **خروجی TCP/8888** به برخی Telegram Middle-Endها لازم باشد. اگر دیتاسنتر آن را مسدود کند، `tgproxy health` هشدار می‌دهد.

### فایل‌های مهم روی سرور

```text
/etc/tgproxyforge/config.env       تنظیمات اصلی و Secret
/etc/telemt/telemt.toml            Telemt
/etc/tproxy-server/config.json     WEB relay
/etc/tproxy-server/profiles.json   WEB profile secret
/etc/mtproxy/mtproxy.env           Official MTProxy
/etc/caddy/Caddyfile               HTTPS front
/usr/local/lib/tgproxyforge/           خود سورس TGProxyForge (Git checkout)
/opt/tgproxyforge/                     runtime/source/site/backups
```

تنظیمات حساس با permission محدود ذخیره می‌شوند. فایل `config.env` را عمومی نکنید.

### تغییر نام ریپو

بله، اسم Repository را می‌توانید بعداً از GitHub تغییر دهید. اگر نام ریپو را عوض کردید، آدرس Repository در `install.sh`، متغیر `REPO` در `lib/common.sh` و URL نصب در README را با نام جدید هماهنگ کنید. نصب‌های موجود با `tgproxy update` از remote همان checkout آپدیت می‌شوند.

### حذف

از منوی:

```bash
tgproxy
```

گزینه **Uninstall / disable stack** را انتخاب کنید. TGProxyForge برای امکان recovery، backupها و بعضی binary/configهای upstream را خودکار پاک نمی‌کند.

### ساختار پروژه

```text
TGProxyForge/
├── install.sh
├── tgproxy
├── lib/
│   ├── common.sh
│   ├── render.sh
│   ├── manage.sh
│   ├── wizard.sh
│   └── menu.sh
├── assets/
├── docs/
├── VERSION
└── CHANGELOG.md
```

ساختار ماژولار است تا تغییر و نگه‌داری نصب‌کننده، rendererها و منوی مدیریت ساده‌تر باشد.

### عیب‌یابی

راهنمای فارسی کامل‌تر:

- [`docs/TROUBLESHOOTING.fa.md`](docs/TROUBLESHOOTING.fa.md)

---

## 🇬🇧 English

**TGProxyForge** is an interactive Bash installer and manager for running two Telegram proxy transports on one Linux server:

- **MTProto FakeTLS (`ee`)** via Telemt
- **Telegram WEB Proxy (`dd`)** via `tproxy-server`, the official MTProxy backend, and Caddy
- Optional **promoted/sponsored channel** integration using `@MTProxyBot`
- Persistent management menu for domain/IP, FakeTLS port, sponsor tag, proxy secret, health checks and updates
- Automatic HTTPS fallback/masking when FakeTLS owns public port 443

### Install without buying a domain

Enter the server's **public IPv4** and press **Enter** at the optional domain prompt. TGProxyForge creates a hostname such as `176-65-151-99.sslip.io` via third-party [sslip.io](https://sslip.io/) DNS. FakeTLS share links connect directly to the server IP, while the generated hostname is used for SNI and the experimental HTTPS WEB proxy.

**Limitations:** DNS must resolve the generated name to the public IP; HTTPS certificate issuance requires reachable TCP 80/443 and the ACME service. If auto-DNS does not resolve correctly, the installer fails early. This is a **no-owned-domain** mode, not an IP-only mode with no hostname or DNS dependencies. WEB proxy also requires a compatible experimental client.

### Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Net-spoof/TGProxyForge/main/install.sh)
```

Then run:

```bash
tgproxy
```

### Requirements

- Ubuntu 22.04/24.04 or Debian 12
- `x86_64`
- root access
- a public IPv4 address
- a DNS hostname pointing to the server (your own, or auto-generated via sslip.io when installing from a public IPv4)
- inbound TCP 80/443 (plus a custom FakeTLS port if selected)
- outbound connectivity to Telegram infrastructure; sponsor mode may require reachable Telegram Middle-End endpoints, commonly on TCP/8888

### Security model

- Telemt API is bound to loopback (`127.0.0.1:9091`).
- tproxy relay/admin endpoints are loopback-only.
- Official MTProxy backend is protected by the upstream nftables boundary.
- Secrets are stored in `/etc/tgproxyforge/config.env` with restricted permissions.
- TGProxyForge does not require storing any Telegram account credential or bot API token.

### Project layout

The manager is intentionally modular: `tgproxy` is a small launcher and the implementation lives under `lib/`. The bootstrap installer clones the repository to `/usr/local/lib/tgproxyforge`, so `tgproxy update` can safely fast-forward the installed source from GitHub.

### Upstream projects

TGProxyForge orchestrates and configures these upstream components rather than reimplementing their protocols:

- [telemt/telemt](https://github.com/telemt/telemt)
- [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server)
- [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy)
- [Caddy](https://github.com/caddyserver/caddy)

### Disclaimer

Network filtering, Telegram client support, provider routing and upstream protocol behavior can change. Test the generated proxy links from the networks you actually intend to support. Sponsored channel display is controlled by Telegram and may not appear immediately even after the server side is configured correctly.

---

## Contact / ارتباط

[**Telegram: @NET_SPOOF**](https://t.me/NET_SPOOF) — برای ارتباط مستقیم، روی شناسه کلیک کنید. / Click to open Telegram.

---

## License

MIT — see [`LICENSE`](LICENSE).
