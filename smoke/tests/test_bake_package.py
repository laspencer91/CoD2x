"""Check the distributed occupancy package validation, without running a game."""
import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/smoke-bake'))
spec = importlib.util.spec_from_file_location('standalone_bake', ROOT / 'tools/smoke-bake/bake.py')
baker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baker)
sys.path.pop(0)


class PackageValidation(unittest.TestCase):
    def test_accepts_valid_package_rejects_stale_binding_and_extra_entries(self):
        with zipfile.ZipFile(ROOT / 'smoke/package/client/prosmoke/prosmoke_stock.iwd') as stock:
            grid = stock.read('maps/mp/mp_toujane.smokegrid')
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'mp_fixture.d3dbsp'
            source.write_bytes(b'BSP fixture; no executable content')
            package = Path(temporary) / 'occupancy.iwd'
            entries = {
                'maps/mp/mp_fixture.smokegrid': grid,
                'maps/mp/mp_fixture.smokebind': struct.pack('<4sII', b'PSB1', zlib.crc32(source.read_bytes()), zlib.crc32(grid)),
                'maps/mp/mp_fixture.smoke.json': json.dumps({'gridSha256': hashlib.sha256(grid).hexdigest()}),
            }

            def write():
                with zipfile.ZipFile(package, 'w') as archive:
                    for name, value in entries.items():
                        archive.writestr(name, value)

            write()
            baker.validate_package(package, source)
            source.write_bytes(b'a different map revision')
            with self.assertRaisesRegex(ValueError, 'binding mismatch'):
                baker.validate_package(package, source)
            entries['unexpected.cfg'] = 'not occupancy'
            write()
            with self.assertRaisesRegex(ValueError, 'package contents'):
                baker.validate_package(package, source)


if __name__ == '__main__':
    unittest.main()
