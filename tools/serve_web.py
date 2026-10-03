#!/usr/bin/env python3
"""Serve the exported Godot web build locally and open it in a browser."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser


class WebExportHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000, help="HTTP port (default: 8000)")
    parser.add_argument("--no-browser", action="store_true", help="Do not open a browser")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535")

    build_dir = Path(__file__).resolve().parent.parent / "builds" / "web"
    required_files = ("index.html", "index.js", "index.wasm", "index.pck")
    missing_files = [name for name in required_files if not (build_dir / name).is_file()]
    if missing_files:
        parser.error(
            f"Web export is incomplete in {build_dir}: missing {', '.join(missing_files)}. "
            'Export the "Web" preset to builds/web/index.html first.'
        )

    handler = partial(WebExportHandler, directory=str(build_dir))
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError as error:
        parser.exit(1, f"Cannot start web preview: {error}. Try --port 8001.\n")

    with server:
        url = f"http://127.0.0.1:{server.server_port}/"
        print(f"Web preview: {url}", flush=True)
        print("Keep this terminal open. Press Ctrl+C to stop.", flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nWeb preview stopped.")


if __name__ == "__main__":
    main()
