"""Monitor parser/rate tests (no network, no root, no secrets)."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "tgproxy_monitor", Path(__file__).resolve().parents[1] / "lib" / "monitor.py")
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class MonitorTests(unittest.TestCase):
    def test_telemt_user_metrics_are_summed(self):
        raw = (
            '# HELP telemt_user_octets_to_client_total bytes\n'
            'telemt_user_octets_to_client_total{user="main"} 1024\n'
            'telemt_user_octets_to_client_total{user="second"} 2048\n'
            'telemt_user_octets_from_client_total{user="main"} 300\n'
        )
        parsed = monitor.parse_metrics(raw, {
            "telemt_user_octets_to_client_total",
            "telemt_user_octets_from_client_total",
        })
        self.assertEqual(parsed["telemt_user_octets_to_client_total"], 3072)
        self.assertEqual(parsed["telemt_user_octets_from_client_total"], 300)

    def test_online_estimates_are_labeled_and_not_added(self):
        fake, web = monitor.estimated_online_clients({
            "connections": 674, "ips": 197,
            "web": {"tproxy_sessions_live": 29, "tproxy_streams_live": 54},
        })
        self.assertEqual((fake, web), (197, 29))
        self.assertEqual(monitor.estimated_online_clients({
            "ips": None, "web": {},
        }), (None, None))

    def test_telemt_missing_active_ip_data_is_unknown(self):
        from unittest.mock import patch
        payload = '{"ok":true,"data":[{"current_connections":2,"active_unique_ips_list":[]}]}'
        with patch.object(monitor, "read_url", return_value=payload):
            self.assertEqual(monitor.get_telemt_connections(), (2, None))

    def test_web_metrics(self):
        parsed = monitor.parse_metrics(
            "tproxy_sessions_live 7\n"
            "tproxy_streams_live 11\n"
            "tproxy_bytes_down_total 8192\n"
            "tproxy_bytes_up_total 4096\n",
            {"tproxy_sessions_live", "tproxy_streams_live",
             "tproxy_bytes_down_total", "tproxy_bytes_up_total"})
        self.assertEqual(parsed["tproxy_sessions_live"], 7)
        self.assertEqual(parsed["tproxy_bytes_down_total"], 8192)

    def test_rate_resets_and_missing_are_unknown(self):
        name = "tproxy_bytes_up_total"
        self.assertEqual(monitor.counter_rate({name: 100}, {name: 400}, name, 2), 150)
        self.assertIsNone(monitor.counter_rate({name: 100}, {name: 90}, name, 2))
        self.assertIsNone(monitor.counter_rate({}, {name: 90}, name, 2))

    def test_cpu_pid_change_is_unknown(self):
        a, b = {"pid": 12, "ticks": 300}, {"pid": 15, "ticks": 500}
        self.assertIsNone(monitor.cpu_percent(a, b, 2))
        self.assertIsNone(monitor.cpu_percent(a, None, 2))

    def test_size_and_empty_metrics(self):
        self.assertEqual(monitor.size_text(None, True), "N/A")
        self.assertEqual(monitor.size_text(1024, True), "1.0 KiB/s")
        self.assertEqual(monitor.parse_metrics("# nothing\n", {"foo"}), {})


if __name__ == "__main__":
    unittest.main()
