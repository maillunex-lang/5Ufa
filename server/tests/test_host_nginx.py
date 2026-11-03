"""Изолированная проверка изменения только игрового snippet."""
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/connect_host_nginx.py"


def test_host_snippet_limit_and_rollback(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    script = scripts / SCRIPT.name
    script.write_text(SCRIPT.read_text())
    (tmp_path / ".env").write_text("DOMAIN=example.test\nPUBLIC_PATH_PREFIX=/games/server\nHTTP_PORT=8085\n")
    nginx = tmp_path / "nginx"
    (nginx / "sites-enabled").mkdir(parents=True)
    (nginx / "snippets").mkdir()
    site = nginx / "sites-enabled/site"
    original_site = "server {\n listen 443 ssl;\n server_name example.test;\n include snippets/ufagame-server.conf;\n}\n"
    site.write_text(original_site)
    snippet = nginx / "snippets/ufagame-server.conf"
    old = "client_max_body_size 200m;\n"
    snippet.write_text(old)
    cmd = ["python3", str(script), "--skip-detect", "--nginx-dir", str(nginx), "--file", str(site)]
    preview = subprocess.run(cmd + ["--dry-run"], capture_output=True, text=True)
    assert preview.returncode == 0 and "client_max_body_size 500m;" in preview.stdout
    assert snippet.read_text() == old and site.read_text() == original_site
    failed = subprocess.run(cmd + ["--test-cmd", "false", "--reload-cmd", "true"], capture_output=True, text=True)
    assert failed.returncode == 5 and snippet.read_text() == old and site.read_text() == original_site
    ok = subprocess.run(cmd + ["--test-cmd", "true", "--reload-cmd", "true"], capture_output=True, text=True)
    assert ok.returncode == 0 and "client_max_body_size 500m;" in snippet.read_text()
    assert site.read_text() == original_site
