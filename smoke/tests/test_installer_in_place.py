"""Exercise in-place setup under a disposable Steam-shaped directory, never a real game."""
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

PREBUILT = Path(__file__).resolve().parents[1] / 'prebuilt'


@unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell required')
class InPlaceInstaller(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cod2 in-place fixture ')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.bundle = root / 'bundle'
        self.bundle.mkdir()
        shutil.copytree(PREBUILT / 'runtime', self.bundle / 'runtime')
        shutil.copytree(PREBUILT / 'provenance', self.bundle / 'provenance')
        shutil.copyfile(PREBUILT / 'manifest.json', self.bundle / 'manifest.json')
        script = (PREBUILT / 'Smoke-Test.ps1').read_text(encoding='utf-8')
        start = script.index('function Assert-Stopped(')
        end = script.index('function Read-Receipt(', start)
        # Isolate host process state and replace ONLY the game launcher with a recorder.
        # The install/backup/restore implementation and Try orchestration stay intact.
        fixture = '''function Assert-Stopped([switch]$Launching) {
    if ($Launching -and (Test-Path -LiteralPath (Join-Path $bundle 'fixture-block-launch'))) {
        throw 'Fixture game is running'
    }
}
function Start-Process($FilePath, $WorkingDirectory, $ArgumentList, $WindowStyle) {
    $record = @{ executable = $FilePath; arguments = $ArgumentList } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'fixture-launch.json'), $record)
}

'''
        (self.bundle / 'Smoke-Test.ps1').write_text(script[:start] + fixture + script[end:], encoding='utf-8')
        self.game = root / 'Steam/steamapps/common/Call of Duty 2'
        self.game.mkdir(parents=True)
        (self.game / 'CoD2MP_s.exe').write_bytes(b'Fixture only; never execute')
        self.original = b'Existing CoD2x bridge fixture; preserve these exact bytes'
        (self.game / 'mss32.dll').write_bytes(self.original)
        renderer = b'DX9 renderer fixture; never load'
        (self.game / 'gfx_d3d_mp_x86_s.dll').write_bytes(renderer)
        bridge_path = self.bundle / 'provenance/bridge-build.json'
        bridge = json.loads(bridge_path.read_text())
        bridge['rendererSha256'] = hashlib.sha256(renderer).hexdigest()
        bridge_path.write_text(json.dumps(bridge), encoding='utf-8')
        self.config = self.game / 'players/Player/config_mp.cfg'
        self.config.parent.mkdir(parents=True)
        self.config.write_bytes(b'Existing player config')
        self.mod = self.game / 'main/custom.iwd'
        self.mod.parent.mkdir()
        self.mod.write_bytes(b'Existing mod fixture')

    def run_action(self, action, *extra, succeeds=True):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass', '-File', str(self.bundle / 'Smoke-Test.ps1'),
            '-Action', action, '-GameDirectory', str(self.game), *extra],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def assert_original(self):
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), self.original)
        self.assertFalse((self.game / 'cod2-smoke-test-install.json').exists())
        self.assertEqual(self.config.read_bytes(), b'Existing player config')
        self.assertEqual(self.mod.read_bytes(), b'Existing mod fixture')

    def test_try_on_steam_then_repeat_and_restore_previous_client(self):
        self.run_action('Try', '-CheckOnly')
        self.assert_original()
        self.assertFalse((self.game / 'fixture-launch.json').exists())
        self.run_action('Try', '-Map', 'mp_burgundy')
        launch = json.loads((self.game / 'fixture-launch.json').read_text())
        self.assertIn('mp_burgundy', launch['arguments'])
        self.assertIn('mapkit_smoke_test', launch['arguments'])
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), (PREBUILT / 'runtime/mss32.dll').read_bytes())
        receipt = json.loads((self.game / 'cod2-smoke-test-install.json').read_text())
        backup = next(entry['backup'] for entry in receipt['files'] if entry['path'] == 'mss32.dll')
        self.assertEqual((self.game / backup).read_bytes(), self.original)
        self.run_action('Try')
        self.run_action('Verify')
        self.run_action('Uninstall')
        self.assert_original()
        self.assertEqual((self.game / backup).read_bytes(), self.original)

    def test_try_checks_launch_conflicts_before_installing(self):
        (self.bundle / 'fixture-block-launch').touch()
        self.assertIn('Fixture game is running', self.run_action('Try', succeeds=False))
        self.assert_original()
        self.assertFalse((self.game / 'cod2-smoke-test-backups').exists())

    def test_try_rejects_unsupported_renderer_before_replacing_client(self):
        (self.game / 'gfx_d3d_mp_x86_s.dll').write_bytes(b'Unsupported renderer fixture')
        self.assertIn('Unsupported DX9 renderer', self.run_action('Try', succeeds=False))
        self.assert_original()


if __name__ == '__main__':
    unittest.main()
