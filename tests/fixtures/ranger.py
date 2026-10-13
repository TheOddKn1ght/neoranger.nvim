#!/usr/bin/env python3
"""Controllable terminal process for the plugin's process/lifecycle checks."""

import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

args = sys.argv[1:]
files_path = next(arg.split("=", 1)[1] for arg in args if arg.startswith("--choosefiles="))
action = next((arg.split(" eval ", 1)[1] for arg in args if arg.startswith("--cmd=map ")), None)
Path(os.environ["NEORANGER_TEST_CAPTURE"]).write_text(json.dumps({
    "argv": args,
    "cwd": os.getcwd(),
    "directory_result": os.environ["NEORANGER_CWD_FILE"],
    "files_result": files_path,
}), encoding="utf-8")

busy = False


def exit_ranger():
    raise SystemExit(0)


fm = SimpleNamespace(
    loader=SimpleNamespace(has_work=lambda: busy),
    thisdir=SimpleNamespace(path=os.environ.get("NEORANGER_TEST_DIRECTORY", os.getcwd())),
    notify=lambda message, **kwargs: print(message, flush=True),
    exit=exit_ranger,
)

print("NEORANGER_READY", flush=True)
for line in sys.stdin:
    command = line.strip()
    if command == "files":
        paths = json.loads(os.environ["NEORANGER_TEST_FILES"])
        Path(files_path).write_text("\n".join(paths) + "\n", encoding="utf-8")
        sys.exit(0)
    if command == "cwd" and action:
        eval(action, {"fm": fm})
    elif command == "busy":
        busy = True
        print("NEORANGER_BUSY", flush=True)
    elif command == "idle":
        busy = False
        print("NEORANGER_IDLE", flush=True)
    elif command == "quit":
        sys.exit(0)
    elif command == "fail":
        Path(os.environ["NEORANGER_CWD_FILE"]).write_text(fm.thisdir.path, encoding="utf-8")
        sys.exit(7)
