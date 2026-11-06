"""Pack generated PNG renditions into the standard ICNS container."""
from pathlib import Path
import struct
import sys

directory, destination = map(Path, sys.argv[1:])
chunks = []
for kind, filename in [
    (b"icp4", "icon_16x16.png"), (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"), (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"), (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png")
]:
    png = (directory / filename).read_bytes()
    chunks.append(kind + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
