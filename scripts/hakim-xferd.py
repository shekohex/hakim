#!/usr/bin/env python3

import argparse
import base64
import json
import mimetypes
import os
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import cast


def _norm_ext(ext: str) -> str:
    ext = ext.strip().lower()
    if not ext:
        return ""
    if not ext.startswith("."):
        ext = "." + ext
    return ext


def _json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return {}
    raw = handler.rfile.read(length)
    return json.loads(raw.decode("utf-8"))


def _is_under(path: pathlib.Path, root: pathlib.Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _best_mime(path: pathlib.Path) -> str:
    mime, _ = mimetypes.guess_type(str(path))
    return mime or "application/octet-stream"


class Handler(BaseHTTPRequestHandler):
    server_version = "hakim-xferd/0"
    protocol_version = "HTTP/1.1"

    def _xfer_server(self) -> "XferServer":
        return cast("XferServer", self.server)

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write((format % args) + "\n")

    def _require_auth(self) -> bool:
        token = self._xfer_server().token
        if not token:
            return True
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer ") and header[len("Bearer ") :].strip() == token:
            return True
        _json_response(self, 401, {"error": "unauthorized"})
        return False

    def do_GET(self) -> None:
        if self.path == "/health":
            _json_response(
                self,
                200,
                {
                    "ok": True,
                    "allow_roots": [str(p) for p in self._xfer_server().allow_roots],
                    "allow_exts": sorted(self._xfer_server().allow_exts),
                    "max_bytes": self._xfer_server().max_bytes,
                },
            )
            return
        _json_response(self, 404, {"error": "not_found"})

    def do_POST(self) -> None:
        if self.path != "/v1/read":
            _json_response(self, 404, {"error": "not_found"})
            return

        if not self._require_auth():
            return

        try:
            body = _read_json(self)
        except Exception:
            _json_response(self, 400, {"error": "invalid_json"})
            return

        path_str = body.get("path")
        if not isinstance(path_str, str) or not path_str.strip():
            _json_response(self, 400, {"error": "missing_path"})
            return

        try:
            src = pathlib.Path(path_str).expanduser()
            resolved = src.resolve(strict=True)
        except FileNotFoundError:
            _json_response(self, 404, {"error": "not_found"})
            return
        except Exception:
            _json_response(self, 400, {"error": "bad_path"})
            return

        if not resolved.is_file():
            _json_response(self, 400, {"error": "not_a_file"})
            return

        ext = _norm_ext(resolved.suffix)
        if ext not in self._xfer_server().allow_exts:
            _json_response(self, 403, {"error": "extension_denied", "ext": ext})
            return

        allowed = any(_is_under(resolved, root) for root in self._xfer_server().allow_roots)
        if not allowed:
            _json_response(self, 403, {"error": "path_denied"})
            return

        try:
            size = resolved.stat().st_size
        except Exception:
            _json_response(self, 500, {"error": "stat_failed"})
            return

        max_bytes = self._xfer_server().max_bytes
        if max_bytes is not None and size > max_bytes:
            _json_response(
                self,
                413,
                {"error": "too_large", "bytes": size, "max_bytes": max_bytes},
            )
            return

        try:
            data = resolved.read_bytes()
        except Exception:
            _json_response(self, 500, {"error": "read_failed"})
            return

        mime = _best_mime(resolved)
        payload = {
            "filename": resolved.name,
            "mime": mime,
            "bytes": len(data),
            "data_base64": base64.b64encode(data).decode("ascii"),
        }
        _json_response(self, 200, payload)


class XferServer(HTTPServer):
    def __init__(
        self,
        address: tuple[str, int],
        handler_cls,
        *,
        token: str | None,
        allow_roots: list[pathlib.Path],
        allow_exts: set[str],
        max_bytes: int | None,
    ):
        super().__init__(address, handler_cls)
        self.token = token
        self.allow_roots = allow_roots
        self.allow_exts = allow_exts
        self.max_bytes = max_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", default=os.environ.get("HAKIM_XFER_TOKEN", "").strip() or None)
    parser.add_argument(
        "--allow-root",
        action="append",
        default=[],
        help="Allowed root directory (repeatable). If omitted, defaults to ~/Downloads and ~/Desktop.",
    )
    parser.add_argument(
        "--allow-ext",
        action="append",
        default=[],
        help="Allowed file extension (repeatable). If omitted, defaults to .png,.jpg,.jpeg,.webp,.gif.",
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=int(os.environ.get("HAKIM_XFER_MAX_BYTES", "15728640")),
    )
    args = parser.parse_args()

    allow_roots = [pathlib.Path(p).expanduser().resolve() for p in args.allow_root]
    if not allow_roots:
        allow_roots = [
            pathlib.Path("~/Downloads").expanduser().resolve(),
            pathlib.Path("~/Desktop").expanduser().resolve(),
        ]

    allow_exts = {_norm_ext(x) for x in args.allow_ext}
    if not allow_exts or "" in allow_exts:
        allow_exts = {".png", ".jpg", ".jpeg", ".webp", ".gif"}

    max_bytes = args.max_bytes
    if max_bytes <= 0:
        max_bytes = None

    server = XferServer(
        (args.host, args.port),
        Handler,
        token=args.token,
        allow_roots=allow_roots,
        allow_exts=allow_exts,
        max_bytes=max_bytes,
    )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
