"""Work around stale private ManifestAPI interfaces in this local CLT installation.

Only copies toolchain files into the project's .build directory; system files
are never changed. Matching public interfaces are used for private imports.
"""
from pathlib import Path
import json
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()).resolve()
toolchain_usr = compiler.parent.parent
source = toolchain_usr / "lib/swift/pm/ManifestAPI"
destination = root / ".build/toolchain-libs/ManifestAPI"
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, destination, dirs_exist_ok=True)
for module in destination.glob("*.swiftmodule"):
    for public in module.glob("*-apple-macos.swiftinterface"):
        private = public.with_name(public.name.replace(".swiftinterface", ".private.swiftinterface"))
        shutil.copyfile(public, private)
empty = root / ".build/empty-module.modulemap"
empty.write_text("// Duplicate legacy SwiftBridging map intentionally hidden for this build.\n")
legacy_map = toolchain_usr / "include/swift/module.modulemap"
current_map = toolchain_usr / "include/swift/bridging.modulemap"
duplicate = (legacy_map.exists() and current_map.exists()
             and "module SwiftBridging" in legacy_map.read_text()
             and "module SwiftBridging" in current_map.read_text())
overlay = {"version": 0, "roots": []}
if duplicate:
    overlay["roots"].append({"type": "file", "name": str(legacy_map), "external-contents": str(empty)})
(root / ".build/toolchain-overlay.json").write_text(json.dumps(overlay))
print(destination.parent)
