#!/usr/bin/env python3
"""Patch the pinned WEB relay checkout to expose one anonymous live IP count.

The tproxy-server Manager already maintains sessionsPerIP under a mutex.
Only the map length is exposed; client addresses and session keys are not logged
or added to the metrics output. Fail closed if the pinned upstream drifts.
"""
import argparse
import re
from pathlib import Path


def replace_exactly_once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        raise ValueError(f"{label}: expected one upstream anchor, found {count}")
    return source.replace(old, new, 1)


def patched_manager(source):
    if "UniqueClientIPs" in source:
        if source.count("UniqueClientIPs") == 2 and "len(m.sessionsPerIP)" in source:
            return source
        raise ValueError("manager appears partially patched")

    pattern = r"(type Capacity struct \{\n[^\n]*\tSessions\s+int\n)"
    if len(re.findall(pattern, source)) != 1:
        raise ValueError("upstream Capacity struct changed")
    source = re.sub(pattern, r"\g<1>\tUniqueClientIPs int\n", source, count=1)
    marker = "Sessions:             len(m.sessions),"
    source = replace_exactly_once(source, marker,
                                  marker + "\n\t\tUniqueClientIPs:      len(m.sessionsPerIP),",
                                  "Capacity return statement")
    return source


def patched_server(source):
    metric = "tproxy_unique_client_ips_live"
    if metric in source:
        if source.count(metric) == 1 and "capacity.UniqueClientIPs" in source:
            return source
        raise ValueError("server appears partially patched")

    line = '"tproxy_sessions_live %d\\n"+'
    source = replace_exactly_once(
        source, line,
        line + '\n\t\t\t"tproxy_unique_client_ips_live %d\\n"+',
        "WEB metrics format",
    )
    marker = "capacity.Sessions, capacity.Streams, capacity.BackendDialsInFlight,"
    source = replace_exactly_once(
        source, marker,
        "capacity.Sessions, capacity.UniqueClientIPs, capacity.Streams, capacity.BackendDialsInFlight,",
        "WEB metrics arguments",
    )
    return source


def apply(root):
    manager_path = root / "internal/session/manager.go"
    server_path = root / "internal/server/server.go"
    manager = manager_path.read_text(encoding="utf-8")
    server = server_path.read_text(encoding="utf-8")
    new_manager = patched_manager(manager)
    new_server = patched_server(server)
    # Validate every anchor before writing either file.
    if new_manager != manager:
        manager_path.write_text(new_manager, encoding="utf-8")
    if new_server != server:
        server_path.write_text(new_server, encoding="utf-8")
    return (new_manager != manager) or (new_server != server)


def main():
    parser = argparse.ArgumentParser(description="Enable anonymous WEB live-IP metric")
    parser.add_argument("checkout", type=Path, help="pinned tproxy-server source directory")
    args = parser.parse_args()
    try:
        changed = apply(args.checkout)
    except (ValueError, OSError) as exc:
        parser.exit(1, f"Refusing to patch unrecognized tproxy-server checkout: {exc}\n")
    print("WEB unique live-IP metric: source patched" if changed else
          "WEB unique live-IP metric: source already patched")


if __name__ == "__main__":
    main()
