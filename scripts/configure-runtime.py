"""Configure the app without saving credentials to files or command arguments."""
from pathlib import Path
import argparse
import getpass
import json
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--endpoint", required=True)
parser.add_argument("--model", required=True)
parser.add_argument("--disable-json-mode", action="store_true")
arguments = parser.parse_args()
binary = Path(__file__).resolve().parents[1] / "dist/一题.app/Contents/MacOS/OneQuestion"
key = getpass.getpass("API 密钥（输入隐藏，不写入文件）: ")
payload = {
    "settings": {"enabled": True, "endpoint": arguments.endpoint, "model": arguments.model, "jsonMode": not arguments.disable_json_mode},
    "apiKey": key
}
result = subprocess.run([str(binary), "--configure-ai"], input=json.dumps(payload), text=True, capture_output=True, timeout=45)
if result.stdout:
    print(result.stdout.replace(key, "[REDACTED]") if key else result.stdout, end="")
if result.stderr:
    print(result.stderr.replace(key, "[REDACTED]") if key else result.stderr, end="")
raise SystemExit(result.returncode)
