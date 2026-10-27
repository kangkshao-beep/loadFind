#!/usr/bin/env python3
"""Pack standard PNG ICNS chunks without requiring IconServices."""
from pathlib import Path
import struct

root = Path(__file__).resolve().parent.parent
chunks = []
for size, tag in [(16, b'icp4'), (32, b'icp5'), (64, b'icp6'), (128, b'ic07'),
                  (256, b'ic08'), (512, b'ic09'), (1024, b'ic10')]:
    data = (root / f'.build/icon-png/icon_{size}x{size}.png').read_bytes()
    chunks.append(tag + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
(root / 'Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
