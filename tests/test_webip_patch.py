"""Patch tests: count-only WEB telemetry and upstream-drift fail-closed."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "tgpf_web_patch",
    Path(__file__).resolve().parents[1] / "lib" / "patch_tproxy_metrics.py")
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)

MANAGER = """package session
type Capacity struct {
\tSessions             int
\tStreams              int
}
func (m *Manager) Capacity() Capacity {
\tm.mu.Lock()
\tdefer m.mu.Unlock()
\treturn Capacity{
\t\tSessions:             len(m.sessions),
\t\tStreams:              m.streamsLive,
\t}
}
"""

SERVER = r'''package server
func (s *Server) serveMetrics() {
    _, _ = fmt.Fprintf(w,
        "tproxy_sessions_live %d\n"+
            "tproxy_streams_live %d\n",
        capacity.Sessions, capacity.Streams, capacity.BackendDialsInFlight,
    )
}
'''


class WEBPatchTests(unittest.TestCase):
    def test_metric_is_anonymous_count_from_existing_live_map(self):
        result = web.patched_manager(MANAGER)
        self.assertIn("UniqueClientIPs int", result)
        self.assertIn("UniqueClientIPs:      len(m.sessionsPerIP)", result)
        self.assertNotIn("clientIP", result)
        server = web.patched_server(SERVER)
        self.assertIn("tproxy_unique_client_ips_live %d", server)
        self.assertIn("capacity.UniqueClientIPs", server)
        self.assertNotIn("sessionsPerIP", server)

    def test_idempotent(self):
        self.assertEqual(web.patched_manager(web.patched_manager(MANAGER)),
                         web.patched_manager(MANAGER))
        self.assertEqual(web.patched_server(web.patched_server(SERVER)),
                         web.patched_server(SERVER))

    def test_unrecognized_source_is_refused_without_file_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manager = root / "internal/session/manager.go"
            server = root / "internal/server/server.go"
            manager.parent.mkdir(parents=True)
            server.parent.mkdir(parents=True)
            manager.write_text(MANAGER, encoding="utf-8")
            server.write_text("unexpected upstream source", encoding="utf-8")
            with self.assertRaises(ValueError):
                web.apply(root)
            self.assertEqual(manager.read_text(), MANAGER)
            self.assertEqual(server.read_text(), "unexpected upstream source")

    def test_patch_both_files_in_place(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manager = root / "internal/session/manager.go"
            server = root / "internal/server/server.go"
            manager.parent.mkdir(parents=True)
            server.parent.mkdir(parents=True)
            manager.write_text(MANAGER, encoding="utf-8")
            server.write_text(SERVER, encoding="utf-8")
            self.assertTrue(web.apply(root))
            self.assertFalse(web.apply(root))
            self.assertIn("len(m.sessionsPerIP)", manager.read_text())
            self.assertIn("tproxy_unique_client_ips_live", server.read_text())


if __name__ == "__main__":
    unittest.main()
