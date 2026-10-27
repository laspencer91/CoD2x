"""Verify the checked-in component/data snapshot without loading a game."""
import hashlib
import json
import struct
import subprocess
import sys
import unittest
import zipfile
import zlib
from pathlib import Path

SMOKE = Path(__file__).resolve().parents[1]
PREBUILT = SMOKE / 'prebuilt'


class PrebuiltPackage(unittest.TestCase):
    def test_file_hashes_and_runtime_only_contract(self):
        manifest = json.loads((PREBUILT / 'manifest.json').read_text())
        self.assertFalse(manifest['releaseReady'])
        self.assertFalse(manifest['implementationSourcesIncluded'])
        self.assertFalse(manifest['shaderSourcesIncluded'])
        for name, expected in manifest['files'].items():
            data = (PREBUILT / name).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), expected['sha256'], name)
            self.assertEqual(len(data), expected['bytes'], name)
            self.assertFalse(name.endswith(('.cpp', '.hpp', '.hlsl', '.pyc')), name)
            self.assertNotIn('source.zip', name)
        for name in ('runtime/mss32.dll', 'runtime/mapkit-smoke/mapkit_smoke.dll'):
            data = (PREBUILT / name).read_bytes()
            offset = struct.unpack_from('<I', data, 0x3c)[0]
            self.assertEqual(data[offset:offset+4], b'PE\0\0')
            self.assertEqual(struct.unpack_from('<H', data, offset+4)[0], 0x14c, name)
        provenance = json.loads((PREBUILT / 'provenance/bridge-build.json').read_text())
        for name, expected in provenance['sourceHashes'].items():
            self.assertEqual(hashlib.sha256((SMOKE.parent / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest(), expected, name)

    def test_compiled_shader_variants_without_hlsl(self):
        data = (PREBUILT / 'runtime/mapkit-smoke/smoke.shaders').read_bytes()
        magic, version, _, count = struct.unpack_from('<IIQI', data)
        self.assertEqual((magic, version, count), (0x42535350, 1, 16))
        self.assertFalse((PREBUILT / 'runtime/mapkit-smoke/smoke.hlsl').exists())
        cursor = 20
        seen = set()
        for _ in range(count):
            name, shadow, profile, size, _ = struct.unpack_from('<32sIIIQ', data, cursor)
            cursor += 52
            key = (name.split(b'\0')[0].decode(), shadow)
            self.assertNotIn(key, seen)
            seen.add(key)
            self.assertEqual(profile, 0xffff0200 if key[0] == 'weapon_mask' else 0xffff0300)
            self.assertEqual(struct.unpack_from('<I', data, cursor)[0], profile)
            self.assertEqual(struct.unpack_from('<I', data, cursor+size-4)[0], 0xffff)
            cursor += size
        self.assertEqual(cursor, len(data))

    def test_all_occupancy_is_data_only_and_matches_inventory(self):
        inventory = json.loads((PREBUILT / 'occupancy-inventory.json').read_text())
        stock = [r for r in inventory['maps'] if r['kind'] == 'stock']
        custom = [r for r in inventory['maps'] if r['kind'] == 'custom']
        self.assertEqual((len(stock), len(custom)), (15, 21))
        for records, path in [(stock, PREBUILT / 'runtime/mapkit_smoke_test/mapkit_smoke_stock.iwd')] + [
            ([r], PREBUILT / 'optional-custom-occupancy' / ('mapkit_smoke_' + r['map'] + '.iwd')) for r in custom
        ]:
            with zipfile.ZipFile(path) as archive:
                self.assertIsNone(archive.testzip())
                expected = set()
                for record in records:
                    prefix = 'maps/mp/' + record['map']
                    expected.update(prefix + s for s in ('.smokegrid', '.smokebind', '.smoke.json'))
                    grid = archive.read(prefix + '.smokegrid')
                    self.assertEqual(hashlib.sha256(grid).hexdigest(), record['gridSha256'])
                    magic, _, crc = struct.unpack('<4sII', archive.read(prefix + '.smokebind'))
                    self.assertEqual(magic, b'PSB1')
                    self.assertEqual(crc, zlib.crc32(grid))
                self.assertEqual(set(archive.namelist()), expected)

    def test_baker_imports_without_site_packages(self):
        result = subprocess.run([sys.executable, '-S', '-B', str(SMOKE.parent / 'tools/smoke-bake/bake.py'), '--help'],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('--bounds', result.stdout)


if __name__ == '__main__':
    unittest.main()
