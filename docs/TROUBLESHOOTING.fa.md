<div dir="rtl" align="right">

<h1>عیب‌یابی TGProxyForge</h1>

<p>این راهنما مشکلات رایج FakeTLS، WEB Proxy، HTTPS و کانال اسپانسری را پوشش می‌دهد. برای شروع، وضعیت تمام سرویس‌ها را ببینید:</p>

<pre dir="ltr" align="left"><code class="language-bash">tgproxy status
tgproxy health</code></pre>

<h2>۱. FakeTLS وصل نمی‌شود</h2>

<p>وضعیت سرویس Telemt، پورت اصلی و لاگ آن را بررسی کنید:</p>

<pre dir="ltr" align="left"><code class="language-bash">systemctl is-active telemt
ss -lntp | grep ':443 '
journalctl -u telemt -n 80 --no-pager</code></pre>

<p>اگر پورت FakeTLS را تغییر داده‌اید، عدد ۴۴۳ را با پورت فعلی جایگزین کنید. همچنین بررسی کنید Cloud Firewall و فایروال سیستم اجازه ورود روی همان پورت را می‌دهند.</p>

<h2>۲. HTTPS یا دامنه باز نمی‌شود</h2>

<pre dir="ltr" align="left"><code class="language-bash">tgproxy status
systemctl --no-pager --full status telemt caddy
ss -lntp | grep -E ':(443|8443) '
curl -Iv --connect-timeout 8 https://YOUR_HOSTNAME/</code></pre>

<p>هنگامی که FakeTLS روی ۴۴۳ است، مسیر HTTPS معمولاً از Telemt به Caddy داخلی روی <code>127.0.0.1:8443</code> عبور می‌کند. صحت DNS، گواهی HTTPS و مسیر ورودی TCP/443 را هم از خارج سرور آزمایش کنید.</p>

<h2>۳. WEB Proxy وصل نمی‌شود</h2>

<p>صرف دریافت <code>HTTPS 200</code> از صفحه عمومی یا <code>readyz</code> تضمین نمی‌کند یک نشست WEB Proxy برقرار شود. ابتدا از تست احراز هویت Bridge استفاده کنید:</p>

<pre dir="ltr" align="left"><code class="language-bash">tgproxy web-test
systemctl --no-pager --full status tproxy-server mtproxy caddy
journalctl -u tproxy-server -n 80 --no-pager</code></pre>

<p>اگر <code>Local relay: OK</code> و <code>Public HTTPS: OK</code> مشاهده شود، Bridge از دید <strong>خود سرور</strong> قابل دسترس است. هنوز باید با یک کلاینت تلگرام که WEB transport را پشتیبانی کند آزمایش کنید.</p>

<h3>تفاوت تست سرور با اینترنت موبایل</h3>

<p>اگر وب‌پروکسی روی موبایل وصل نمی‌شود، HTTPS را با <strong>همان اپراتور موبایل</strong> آزمایش کنید. متغیرهای نمونه را با hostname و IP واقعی سرورتان جایگزین کنید:</p>

<pre dir="ltr" align="left"><code class="language-bash">H="YOUR_HOSTNAME"
IP="YOUR_PUBLIC_IP"

nslookup "$H"

curl -4 -sS -o /dev/null --connect-timeout 8 --max-time 15 \
  -w 'HTTP=%{http_code} IP=%{remote_ip}\n' "https://$H/"

curl -4 -sS -o /dev/null --resolve "$H:443:$IP" \
  --connect-timeout 8 --max-time 15 \
  -w 'HTTP=%{http_code} IP=%{remote_ip}\n' "https://$H/"</code></pre>

<ul>
<li>اگر DNS معمولی خطا می‌دهد اما <code>--resolve</code> جواب می‌دهد، احتمال اختلال در DNS وجود دارد.</li>
<li>اگر هر دو تایم‌اوت می‌شوند، دسترسی TCP/443 به سرور را از آن شبکه بررسی کنید؛ صرف تغییر hostname کافی نیست.</li>
<li>اگر هر دو پاسخ HTTP موفق دارند اما WEB وصل نمی‌شود، لاگ‌های نشست WEB، backend MTProxy و سازگاری نسخه کلاینت را بررسی کنید.</li>
</ul>

<p><strong>مهم:</strong> hostname خودکار <code>sslip.io</code> جایگزین مالکیت دامنه است، نه جایگزین DNS یا دسترسی شبکه. ممکن است از داخل سرور سالم باشد اما روی برخی شبکه‌های موبایل کار نکند.</p>

<h2>۴. کانال اسپانسری نمایش داده نمی‌شود</h2>

<p>ثبت Proxy Tag در کانفیگ کافی نیست؛ Telemt باید واقعاً به Middle Proxy متصل باشد. در خروجی <code>tgproxy health</code> این فیلدها مهم‌اند:</p>

<pre dir="ltr" align="left"><code class="language-text">me_runtime_ready: true
route_mode: middle
reroute_active: false</code></pre>

<p>در شروع سرویس، وضعیت <code>startup_direct_fallback</code> می‌تواند موقتی باشد. اگر ادامه پیدا کرد، خروجی TCP/8888 به سرورهای واقعی Telegram Middle-End و لاگ Telemt را بررسی کنید:</p>

<pre dir="ltr" align="left"><code class="language-bash">journalctl -u telemt -n 150 --no-pager
ss -tnp state established '( dport = :8888 )'</code></pre>

<p>همچنین در <a href="https://t.me/MTProxyBot">@MTProxyBot</a> اطمینان پیدا کنید Proxy Tag درست ثبت شده و کانال عمومی با <strong>Set promotion</strong> انتخاب شده است. نمایش نهایی تبلیغ تحت کنترل تلگرام است.</p>

<h2>۵. لاگ‌ها و بازیابی</h2>

<pre dir="ltr" align="left"><code class="language-bash">journalctl -u telemt -n 100 --no-pager
journalctl -u tproxy-server -n 100 --no-pager
journalctl -u mtproxy -n 100 --no-pager
journalctl -u caddy -n 100 --no-pager</code></pre>

<p>بکاپ‌های تهیه‌شده در زمان نصب و بعضی تغییرات در مسیر زیر قرار می‌گیرند:</p>

<pre dir="ltr" align="left"><code class="language-text">/opt/tgproxyforge/backups/</code></pre>

<p>از ارسال عمومی فایل <code>/etc/tgproxyforge/config.env</code>، Secretها یا لینک‌های دارای Secret خودداری کنید.</p>

<p><a href="../README.md">← بازگشت به صفحه اصلی پروژه</a> • <a href="https://t.me/NET_SPOOF">تلگرام: @NET_SPOOF</a></p>

</div>
