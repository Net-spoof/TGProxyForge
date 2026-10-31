#!/usr/bin/env python3
"""Read-only, loopback-only live telemetry for TGProxyForge.

Sources:
  Telemt API /v1/users: authenticated current connections and active IPs.
  Telemt Prometheus /metrics: client-direction byte counters.
  tproxy-server /metrics: WEB sessions, streams and byte counters.
  systemd MainPID + /proc: per-service resident memory and CPU time.

No proxy secrets, IP addresses or API responses are written to disk.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

TELEMT_USERS = "http://127.0.0.1:9091/v1/users"
TELEMT_METRICS = "http://127.0.0.1:19090/metrics"
SERVICES = ("telemt", "tproxy-server", "mtproxy", "caddy")
HZ = os.sysconf("SC_CLK_TCK")
METRIC_LINE = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{[^}]*\})?\s+([0-9]+(?:\.[0-9]+)?)(?:\s+.*)?$")


def read_url(url):
    request = urllib.request.Request(url, headers={"Accept": "text/plain, application/json"})
    with urllib.request.urlopen(request, timeout=2) as response:
        return response.read(2_000_000).decode("utf-8")


def parse_metrics(body, names):
    """Sum identically named series; Telemt byte metrics are per-user."""
    values = {}
    for line in body.splitlines():
        if not line or line.startswith("#"):
            continue
        match = METRIC_LINE.match(line)
        if not match:
            continue
        metric, value = match.groups()
        if metric in names:
            values[metric] = values.get(metric, 0) + float(value)
    return values


def get_telemt_connections():
    try:
        response = json.loads(read_url(TELEMT_USERS))
        if response.get("ok") is not True or not isinstance(response.get("data"), list):
            return None, None
        rows = response["data"]
        current = sum(max(0, int(x.get("current_connections", 0))) for x in rows)
        # Count actual distinct IP addresses across configured users, not all
        # historical visits, as a supplementary estimate of connected clients.
        ips = set()
        for item in rows:
            for ip in item.get("active_unique_ips_list", []):
                ips.add(str(ip))
        return current, len(ips)
    except (OSError, ValueError, TypeError, KeyError, urllib.error.URLError):
        return None, None


def get_metrics(url, names):
    try:
        return parse_metrics(read_url(url), set(names))
    except (OSError, ValueError, urllib.error.URLError):
        return {}


def process_pid(service):
    try:
        result = subprocess.run(
            ["systemctl", "show", "--property=MainPID", "--value", service],
            check=False, capture_output=True, text=True, timeout=2,
        )
        pid = int(result.stdout.strip())
        return pid if result.returncode == 0 and pid > 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def process_stats(pid):
    """CPU ticks and RSS from the service's main PID; process, not host."""
    if pid is None:
        return None
    try:
        with open("/proc/%d/stat" % pid, encoding="utf-8") as handle:
            stat = handle.read()
        # The comm field can contain spaces and parentheses.
        fields = stat[stat.rfind(")") + 2:].split()
        ticks = int(fields[11]) + int(fields[12])  # utime + stime
        with open("/proc/%d/status" % pid, encoding="utf-8") as handle:
            status = handle.read()
        match = re.search(r"^VmRSS:\s+(\d+)\s+kB", status, re.MULTILINE)
        memory_bytes = int(match.group(1)) * 1024 if match else None
        return {"pid": pid, "ticks": ticks, "rss": memory_bytes}
    except (OSError, ValueError, IndexError):
        return None


def snapshot(admin_port):
    now = time.monotonic()
    conns, ips = get_telemt_connections()
    telemt = get_metrics(TELEMT_METRICS, (
        "telemt_user_octets_from_client_total",
        "telemt_user_octets_to_client_total",
    ))
    web = get_metrics("http://127.0.0.1:%d/metrics" % admin_port, (
        "tproxy_sessions_live", "tproxy_streams_live",
        "tproxy_bytes_up_total", "tproxy_bytes_down_total",
    ))
    return {
        "time": now,
        "connections": conns,
        "ips": ips,
        "telemt": telemt,
        "web": web,
        "processes": {service: process_stats(process_pid(service)) for service in SERVICES},
    }


def counter_rate(before, after, metric, seconds):
    a, b = before.get(metric), after.get(metric)
    if a is None or b is None or seconds <= 0 or b < a:
        return None
    return (b - a) / seconds


def cpu_percent(before, after, seconds):
    if not before or not after or before["pid"] != after["pid"] or seconds <= 0:
        return None
    diff = after["ticks"] - before["ticks"]
    return (diff * 100 / (HZ * seconds)) if diff >= 0 else None


def size_text(value, per_sec=False):
    if value is None:
        return "N/A"
    unit = "B"
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            break
        value /= 1024
    return "%.1f %s%s" % (value, unit, "/s" if per_sec else "")


def int_text(value):
    return str(int(value)) if value is not None else "N/A"


def render(before, after, admin_port):
    seconds = after["time"] - before["time"]
    fake = after["telemt"]
    web = after["web"]
    fake_up = counter_rate(before["telemt"], fake, "telemt_user_octets_from_client_total", seconds)
    fake_down = counter_rate(before["telemt"], fake, "telemt_user_octets_to_client_total", seconds)
    web_up = counter_rate(before["web"], web, "tproxy_bytes_up_total", seconds)
    web_down = counter_rate(before["web"], web, "tproxy_bytes_down_total", seconds)

    print("TGProxyForge | Live proxy monitoring | %s" %
          datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("=" * 76)
    print("%-17s %-17s %15s %15s" % ("PROXY", "LIVE", "DOWNLOAD", "UPLOAD"))
    print("-" * 76)
    print("%-17s %-17s %15s %15s" % (
        "FakeTLS / Telemt",
        int_text(after["connections"]) + " connections" if after["connections"] is not None else "N/A",
        size_text(fake_down, True), size_text(fake_up, True),
    ))
    print("%-17s %-17s %15s %15s" % (
        "WEB / tproxy",
        int_text(web.get("tproxy_sessions_live")) + " sessions" if "tproxy_sessions_live" in web else "N/A",
        size_text(web_down, True), size_text(web_up, True),
    ))
    print("-" * 76)
    if after["ips"] is not None:
        print("FakeTLS unique active IPs : %d (not necessarily distinct people)" % after["ips"])
    if "tproxy_streams_live" in web:
        print("WEB active streams       : %d (not distinct users)" % web["tproxy_streams_live"])
    total_down = fake_down + web_down if fake_down is not None and web_down is not None else None
    total_up = fake_up + web_up if fake_up is not None and web_up is not None else None
    print("Combined proxy throughput: down %s | up %s" %
          (size_text(total_down, True), size_text(total_up, True)))
    print()
    print("%-20s %10s %14s %12s" % ("SERVICE", "PID", "CPU (1 core)", "RAM (RSS)"))
    print("-" * 64)
    for service in SERVICES:
        proc = after["processes"][service]
        prev = before["processes"][service]
        cpu = cpu_percent(prev, proc, seconds)
        print("%-20s %10s %14s %12s" % (
            service,
            str(proc["pid"]) if proc else "offline",
            "%.1f%%" % cpu if cpu is not None else "N/A",
            size_text(proc["rss"]) if proc else "N/A",
        ))
    print("-" * 76)
    if not fake or "telemt_user_octets_to_client_total" not in fake or "telemt_user_octets_from_client_total" not in fake:
        print("NOTE: Telemt throughput unavailable; run 'tgproxy apply' after updating")
        print("      to enable loopback-only metrics (restarts proxy services).")
    if not web or "tproxy_bytes_up_total" not in web or "tproxy_bytes_down_total" not in web:
        print("NOTE: WEB metrics unavailable on 127.0.0.1:%d; check tproxy-server." % admin_port)
    print("Throughput is payload bytes/sec, not physical network throughput.")
    print("CPU is per main process and can exceed 100%% on multicore systems.")
    print("Ctrl+C to return to the manager.")


def main():
    parser = argparse.ArgumentParser(description="Local proxy metrics monitor")
    parser.add_argument("--once", action="store_true", help="take two samples and exit")
    parser.add_argument("--interval", type=float, default=2.0, help="seconds between samples (1-60)")
    parser.add_argument("--admin-port", type=int, required=True, help="local WEB admin port")
    options = parser.parse_args()
    if not 1 <= options.interval <= 60:
        parser.error("interval must be between 1 and 60 seconds")
    if not 1 <= options.admin_port <= 65535:
        parser.error("admin-port must be between 1 and 65535")
    try:
        before = snapshot(options.admin_port)
        while True:
            time.sleep(options.interval)
            after = snapshot(options.admin_port)
            if sys.stdout.isatty() and not options.once:
                print("\033[2J\033[H", end="")
            render(before, after, options.admin_port)
            if options.once:
                break
            before = after
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")


if __name__ == "__main__":
    main()
