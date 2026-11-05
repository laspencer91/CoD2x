"""Check the shipped ProSmoke package: layout, 32-bit binaries, names, data-only grids, configs."""
import hashlib
import json
import re
import struct
import subprocess
import sys
import unittest
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SMOKE = ROOT / 'smoke'
PACKAGE = SMOKE / 'package'
CLIENT = PACKAGE / 'client'
RUNTIME = CLIENT / 'prosmoke'
SERVER = PACKAGE / 'server'
POLICY_FIELDS = {
    'density', 'width', 'height', 'bloom_rate', 'bloom_time', 'thicken', 'duration', 'fade_time', 'fx_after_smoke',
    'brightness', 'variation', 'shadow_strength', 'lightgrid_strength', 'edge_softness', 'height_gradient',
    'billow_size', 'billow_strength', 'billow_speed', 'wisp_size', 'wisp_strength', 'wisp_speed', 'rise_speed',
    'tint_r', 'tint_g', 'tint_b', 'tint_amount', 'carve_scale', 'carve_pistol', 'carve_smg', 'carve_rifle',
    'carve_semi', 'carve_sniper', 'carve_shotgun',
}


def pe_machine(data):
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset + 4] == b'PE\0\0'
    return struct.unpack_from('<H', data, offset + 4)[0]


class PackageLayout(unittest.TestCase):
    def test_required_files_and_nothing_else_suspicious(self):
        expected_files = {'README.txt',
                     'client/main/iw_prosmoke_stock.iwd',
                     'client/mss32.dll', 'client/prosmoke/prosmoke.dll', 'client/prosmoke/smoke.shaders',
                     'client/prosmoke/noise128.rgba', 'client/prosmoke/prosmoke_stock.iwd', 'client/prosmoke/prosmoke.cfg',
                     'client/prosmoke/version.json',
                     'server/README-SERVER.txt', 'server/prosmoke_server.cfg', 'server/prosmoke_stock.iwd',
                     'server/prosmoke_competitive_full.iwd'}
        for name in expected_files:
            self.assertTrue((PACKAGE / name).is_file(), name)
        self.assertEqual({p.relative_to(PACKAGE).as_posix() for p in PACKAGE.rglob('*') if p.is_file()}, expected_files)
        for path in PACKAGE.rglob('*'):
            if path.is_file():
                self.assertNotIn(path.suffix.lower(), ('.cpp', '.hpp', '.h', '.hlsl', '.py', '.exe', '.pyc', '.cmd', '.bat', '.ps1', '.vbs', '.js'), str(path))
                self.assertNotRegex(path.name.lower(), r'licen|notice|mapkit', str(path))
        # Normal launches mount main; fs_game=prosmoke launches also mount the runtime folder.
        self.assertEqual(sorted(p.name for p in CLIENT.iterdir()), ['main', 'mss32.dll', 'prosmoke'])

    def test_binaries_are_32bit_and_carry_the_prosmoke_names(self):
        loader = (CLIENT / 'mss32.dll').read_bytes()
        renderer = (RUNTIME / 'prosmoke.dll').read_bytes()
        self.assertEqual(pe_machine(loader), 0x14c)
        self.assertEqual(pe_machine(renderer), 0x14c)
        self.assertIn(b'sv_prosmoke_policy', loader)
        self.assertIn(b'prosmoke', renderer)   # its runtime folder beside the game executable
        # GCC expands the constant strcpy of the DLL path into immediate stores, so only the
        # dvar names and the wide log folder are expected as contiguous strings.
        self.assertIn('prosmoke'.encode('utf-16-le'), loader)
        self.assertIn(b'prosmoke_resolution', loader)
        self.assertNotIn(b'mapkit-smoke', loader)
        self.assertNotIn(b'mapkit-smoke', renderer)
        self.assertNotIn(b'sv_mapkit_smoke_policy', loader)
        self.assertIn(b'Smoke_Settings', renderer)
        self.assertIn(b'Smoke_PopConsole', renderer)   # console status lines drained by the loader
        self.assertIn(b'Smoke_Status', renderer)
        self.assertIn(b'intz-bound', renderer)        # NVIDIA depth path (INTZ without RESZ)
        self.assertIn(b'prosmoke_status', loader)     # console command
        self.assertNotIn(b'mapkit_smoke.dll', loader)

    def test_compiled_shader_variants_without_hlsl(self):
        data = (RUNTIME / 'smoke.shaders').read_bytes()
        magic, version, _, count = struct.unpack_from('<IIQI', data)
        self.assertEqual((magic, version, count), (0x42535350, 1, 18))
        self.assertFalse((RUNTIME / 'smoke.hlsl').exists())
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
            self.assertEqual(struct.unpack_from('<I', data, cursor + size - 4)[0], 0xffff)
            cursor += size
        self.assertEqual(cursor, len(data))
        self.assertEqual(seen,{(entry,shadow) for entry in ('main','composite','main_cached','composite_cached','weapon_mask','weapon_probe','weapon_integrate','merge_depth','composite_cached_fast') for shadow in (0,1)})

    def test_version_and_optimized_loader_identity(self):
        identity=json.loads((RUNTIME/'version.json').read_text())
        self.assertEqual(identity['version'],'0.1.7-preview')
        self.assertEqual(identity['shortWaitRequestedUs'],250)
        for name,key in [('mss32.dll','loaderSha256')]:
            self.assertEqual(hashlib.sha256((CLIENT/name).read_bytes()).hexdigest(),identity[key])
        for name,key in [('prosmoke.dll','runtimeSha256'),('smoke.shaders','shadersSha256')]:
            self.assertEqual(hashlib.sha256((RUNTIME/name).read_bytes()).hexdigest(),identity[key])
        self.assertIn(b'prosmoke_shortWait',(CLIENT/'mss32.dll').read_bytes())

    def test_occupancy_is_data_only_and_matches_inventory(self):
        self.assertEqual((SERVER / 'prosmoke_competitive_full.iwd').read_bytes(),
                         (SMOKE / 'competitive-occupancy/prosmoke_competitive_full.iwd').read_bytes())
        with zipfile.ZipFile(SERVER / 'prosmoke_competitive_full.iwd') as competitive:
            metadata = [json.loads(competitive.read(name)) for name in competitive.namelist() if name.endswith('.smoke.json')]
            self.assertEqual(len(metadata), 12)
            self.assertTrue(all(record['boundsPolicy'] == 'collision' and not record['boundsReviewRequired'] for record in metadata))
            self.assertIn('mp_toujane_fix', {record['map'] for record in metadata})
        self.assertEqual((RUNTIME / 'prosmoke_stock.iwd').read_bytes(), (CLIENT / 'main/iw_prosmoke_stock.iwd').read_bytes())
        self.assertEqual((RUNTIME / 'prosmoke_stock.iwd').read_bytes(), (SERVER / 'prosmoke_stock.iwd').read_bytes())
        inventory = json.loads((SMOKE / 'occupancy-inventory.json').read_text())
        stock = [r for r in inventory['maps'] if r['kind'] == 'stock']
        custom = [r for r in inventory['maps'] if r['kind'] == 'custom']
        self.assertEqual((len(stock), len(custom)), (15, 21))
        for records, path in [(stock, RUNTIME / 'prosmoke_stock.iwd')] + [
            ([r], SMOKE / 'custom-occupancy' / ('prosmoke_' + r['map'] + '.iwd')) for r in custom
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

    def test_policy_configs_use_known_fields(self):
        for path, command in ((RUNTIME / 'prosmoke.cfg', 'set'), (SERVER / 'prosmoke_server.cfg', 'sets')):
            lines = [l for l in path.read_text().splitlines() if l.strip() and not l.strip().startswith('//')]
            self.assertEqual(len(lines), 1, path)
            match = re.fullmatch(command + r' sv_prosmoke_policy "v1((?: [a-z_]+=[0-9.]+)*)"', lines[0])
            self.assertIsNotNone(match, lines[0])
            for token in match.group(1).split():
                name, value = token.split('=')
                self.assertIn(name, POLICY_FIELDS)
                float(value)
            self.assertLess(len(lines[0]), 400)

    def test_provenance_matches_binaries_and_sources(self):
        bridge = json.loads((SMOKE / 'provenance/bridge-build.json').read_text())
        self.assertEqual(hashlib.sha256((CLIENT / 'mss32.dll').read_bytes()).hexdigest(), bridge['sha256'])
        for name, expected in bridge['sourceHashes'].items():
            data = (ROOT / name).read_bytes().replace(b'\r\n', b'\n')
            self.assertEqual(hashlib.sha256(data).hexdigest(), expected, name)
        component = json.loads((SMOKE / 'provenance/smoke-component.json').read_text())
        self.assertEqual(hashlib.sha256((RUNTIME / 'prosmoke.dll').read_bytes()).hexdigest(), component['runtimeSha256'])
        self.assertEqual(hashlib.sha256((RUNTIME / 'smoke.shaders').read_bytes()).hexdigest(), component['shadersSha256'])

    def test_baker_imports_without_site_packages(self):
        result = subprocess.run([sys.executable, '-S', '-B', str(ROOT / 'tools/smoke-bake/bake.py'), '--help'],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('--bounds', result.stdout)


if __name__ == '__main__':
    unittest.main()
