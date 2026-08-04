import json
import os
import sys
import socket
import importlib.util
import time
import traceback
import base64
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler

# 官方机制 1：基于当前工作目录。
# 官方在 4.x 运行时会自动将当前工作目录切换为可写的沙盒 `<application-support>/data`
# 此时直接读写相对路径是绝对安全的，不会因无权限而崩溃返回 null
DATA_DIR = Path(".") 
PY_SOURCES_DIR = DATA_DIR / "py_sources"
PY_SOURCES_DIR.mkdir(exist_ok=True, parents=True)

SPIDERS = {}

def get_free_port():
    s = socket.socket()
    s.bind(("", 0))
    port = s.getsockname()[1]
    s.close()
    return port

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = json.loads(self.rfile.read(length))
        if self.path == "/load":
            self.load_script(data)
        else:
            self._send(404, {"error": "Not Found"})

    def do_GET(self):
        from urllib.parse import parse_qs, urlparse
        q = parse_qs(urlparse(self.path).query)
        key = q.get("key", [None])[0]
        if not key or key not in SPIDERS:
            self._send(400, {"error": "Invalid key"})
            return
        spider = SPIDERS[key]
        try:
            if self.path.startswith("/home"):
                res = spider.homeContent(q.get("filter", ["1"])[0] == "1")
            elif self.path.startswith("/category"):
                res = spider.categoryContent(q.get("tid", [""])[0], int(q.get("pg", ["1"])[0]), "", {})
            elif self.path.startswith("/detail"):
                res = spider.detailContent(json.loads(q.get("ids", ['[""]'])[0]))
            elif self.path.startswith("/search"):
                res = spider.searchContent(q.get("wd", [""])[0], int(q.get("quick", ["0"])[0]), int(q.get("pg", ["1"])[0]))
            elif self.path.startswith("/player"):
                res = spider.playerContent(q.get("flag", [""])[0], q.get("id", [""])[0], "")
            else:
                self._send(404, {"error": "Not Found"})
                return
            self._send(200, res)
        except Exception as e:
            self._send(500, {"error": str(e), "traceback": traceback.format_exc()})

    def load_script(self, data):
        try:
            key = data["key"]
            py_code = base64.b64decode(data["py_b64"]).decode()
            py_path = PY_SOURCES_DIR / f"{key}.py"
            py_path.write_text(py_code, encoding='utf-8')
            spec = importlib.util.spec_from_file_location(f"py_{key}", py_path)
            mod = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = mod
            spec.loader.exec_module(mod)
            spider = mod.Spider(data.get("ext", ""))
            spider.init(data.get("ext", ""))
            SPIDERS[key] = spider
            self._send(200, {"ok": True})
        except Exception as e:
            error_detail = traceback.format_exc()
            with open(DATA_DIR / 'load_error.log', 'w', encoding='utf-8') as f:
                f.write(error_detail)
            self._send(500, {"ok": False, "error": str(e), "traceback": error_detail})

def run():
    try:
        with open(DATA_DIR / 'heartbeat.txt', 'w') as f:
            f.write('running at ' + time.strftime('%Y-%m-%d %H:%M:%S'))
            
        port = get_free_port()
        port_file_path = os.environ.get('PORT_FILE_PATH')
        if port_file_path:
            with open(port_file_path, 'w') as f:
                f.write(str(port))
        
        server = HTTPServer(("127.0.0.1", port), Handler)
        while True:
            server.handle_request()
            time.sleep(0.01)
    except Exception as e:
        with open(DATA_DIR / 'py_error.log', 'w', encoding='utf-8') as f:
            f.write(traceback.format_exc())
        raise

if __name__ == "__main__":
    run()
