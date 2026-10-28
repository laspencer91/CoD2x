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
    $record = @{ executable = $FilePath; arguments = $ArgumentList; path = $env:PATH; render = $env:COD2_SMOKE_RENDER } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $WorkingDirectory 'fixture-launch.json'), $record)
}

'''
        (self.bundle / 'Smoke-Test.ps1').write_text(script[:start] + fixture + script[end:], encoding='utf-8')
        self.game = root / 'Steam/steamapps/common/Call of Duty 2'
        self.game.mkdir(parents=True)
        self.steam = root / 'Steam'
        (self.steam / 'steam.exe').write_bytes(b'Steam client fixture; never execute')
        (self.steam / 'Steam.dll').write_bytes(b'Steam library fixture; never load')
        (self.game / 'CoD2MP_s.exe').write_bytes(b'Fixture only; never execute')
        # Preserve a real version resource without executing the DLL. An overlay
        # distinguishes this previous client from the bundle's smoke loader.
        self.original = (PREBUILT / 'runtime/mss32.dll').read_bytes() + b'Previous CoD2x fixture'
        (self.game / 'mss32.dll').write_bytes(self.original)
        self.sound = b'Original Miles audio fixture; never execute'
        (self.game / 'mss32_original.dll').write_bytes(self.sound)
        renderer = b'DX9 renderer fixture; never load'
        (self.game / 'gfx_d3d_mp_x86_s.dll').write_bytes(renderer)
        bridge_path = self.bundle / 'provenance/bridge-build.json'
        bridge = json.loads(bridge_path.read_text())
        bridge['rendererSha256'] = hashlib.sha256(renderer).hexdigest()
        bridge['originalMss32Sha256'] = hashlib.sha256(self.sound).hexdigest()
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

    def test_verify_reports_runtime_fallback_without_claiming_render_success(self):
        self.run_action('Install')
        self.assertIn('Runtime log not created yet:', self.run_action('Verify'))
        log = self.game / 'mapkit-smoke/client.log'
        log.write_text('server smoke policy missing/invalid; stock retained\n')
        output = self.run_action('Verify')
        self.assertIn('Installed files verified.', output)
        self.assertIn('server smoke policy missing/invalid; stock retained', output)
        self.run_action('Uninstall')
        self.assert_original()

    def test_cod2x_install_after_smoke_becomes_new_restoration_baseline(self):
        original_client = self.original
        self.run_action('Install')
        receipt_path = self.game / 'cod2-smoke-test-install.json'
        previous_receipt = receipt_path.read_bytes()
        previous = json.loads(previous_receipt)
        previous_loader = next(f for f in previous['files'] if f['path'] == 'mss32.dll')
        updated_client = self.original + b'New CoD2x installed after smoke; keep this version'
        (self.game / 'mss32.dll').write_bytes(updated_client)
        backups_before = set((self.game / 'cod2-smoke-test-backups').iterdir())

        self.run_action('Try', '-CheckOnly')
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), updated_client)
        self.assertEqual(receipt_path.read_bytes(), previous_receipt)
        self.assertEqual(set((self.game / 'cod2-smoke-test-backups').iterdir()), backups_before)
        self.assertIn('Installed file changed', self.run_action('Uninstall', '-CheckOnly', succeeds=False))

        self.assertIn('Preserved the updated CoD2x loader', self.run_action('Try'))
        receipt = json.loads(receipt_path.read_text())
        loader = next(f for f in receipt['files'] if f['path'] == 'mss32.dll')
        self.assertNotEqual(loader['backup'], previous_loader['backup'])
        self.assertEqual(loader['originalHash'], hashlib.sha256(updated_client).hexdigest())
        self.assertEqual((self.game / loader['backup']).read_bytes(), updated_client)
        self.assertEqual((self.game / previous_loader['backup']).read_bytes(), self.original)
        history = (self.game / loader['backup']).parent / 'previous-install.json'
        self.assertEqual(history.read_bytes(), previous_receipt)

        self.run_action('Try')
        repeated = json.loads(receipt_path.read_text())
        self.assertEqual(next(f for f in repeated['files'] if f['path'] == 'mss32.dll')['backup'], loader['backup'])
        self.run_action('Uninstall')
        self.original = updated_client
        self.assert_original()
        self.assertEqual((self.game / previous_loader['backup']).read_bytes(), original_client)

    def test_loader_rebase_rolls_back_if_receipt_commit_fails(self):
        self.run_action('Install')
        receipt_path = self.game / 'cod2-smoke-test-install.json'
        previous_receipt = receipt_path.read_bytes()
        updated_client = self.original + b'New CoD2x client; restore on failed smoke install'
        (self.game / 'mss32.dll').write_bytes(updated_client)
        script_path = self.bundle / 'Smoke-Test.ps1'
        script = script_path.read_text()
        commit = 'Write-Json $receiptPath ([ordered]@{ schema = 1;'
        self.assertEqual(script.count(commit), 1)
        script_path.write_text(script.replace(commit, "throw 'Fixture receipt commit failure'\n        " + commit))

        self.assertIn('Fixture receipt commit failure', self.run_action('Install', succeeds=False))
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), updated_client)
        self.assertEqual(receipt_path.read_bytes(), previous_receipt)
        previous = json.loads(previous_receipt)
        backup = next(f['backup'] for f in previous['files'] if f['path'] == 'mss32.dll')
        self.assertEqual((self.game / backup).read_bytes(), self.original)

    def test_reinstall_still_preserves_edits_to_other_installed_files(self):
        self.run_action('Install')
        look = self.game / 'mapkit_smoke_test/smoke_look_wide.cfg'
        look.write_bytes(b'Manually changed smoke settings')
        receipt_path = self.game / 'cod2-smoke-test-install.json'
        receipt_before = receipt_path.read_bytes()
        self.assertIn('Installed file changed', self.run_action('Try', succeeds=False))
        self.assertEqual(look.read_bytes(), b'Manually changed smoke settings')
        self.assertEqual(receipt_path.read_bytes(), receipt_before)

    def test_try_rejects_unsupported_renderer_before_replacing_client(self):
        (self.game / 'gfx_d3d_mp_x86_s.dll').write_bytes(b'Unsupported renderer fixture')
        self.assertIn('Unsupported DX9 renderer', self.run_action('Try', succeeds=False))
        self.assert_original()

    def test_stock_cod2_blocks_inspect_install_and_launch_without_writes(self):
        self.original = self.sound
        (self.game / 'mss32.dll').write_bytes(self.original)
        (self.game / 'mss32_original.dll').unlink()
        status = json.loads(self.run_action('Inspect'))
        self.assertFalse(status['ready'])
        self.assertIn('Install CoD2x first', status['message'])
        for action in ('Try', 'Install', 'Launch', 'Verify'):
            self.assertIn('CoD2x is not installed', self.run_action(action, succeeds=False))
        self.assert_original()
        self.assertFalse((self.game / 'cod2-smoke-test-backups').exists())

    def test_external_steam_client_directory_is_in_child_search_path(self):
        external = Path(self.temp.name) / 'Steam Client With Spaces'
        external.mkdir()
        (self.steam / 'steam.exe').rename(external / 'steam.exe')
        (self.steam / 'Steam.dll').rename(external / 'Steam.dll')
        self.set_steam_candidates(self.steam, external)
        output = self.run_action('Try')
        self.assertIn("game's DLL search path", output)
        launch = json.loads((self.game / 'fixture-launch.json').read_text())
        self.assertEqual(launch['path'].split(';')[0], str(external))
        self.assertEqual(launch['render'], '1')
        self.assertFalse((self.game / 'Steam.dll').exists())
        self.run_action('Uninstall')
        self.assert_original()

    def test_missing_steam_files_stop_try_before_installing(self):
        self.set_steam_candidates(self.steam)
        (self.steam / 'Steam.dll').unlink()
        self.assertIn('Steam client files could not be found', self.run_action('Try', succeeds=False))
        self.assert_original()
        self.assertFalse((self.game / 'cod2-smoke-test-backups').exists())
        self.assertFalse((self.game / 'fixture-launch.json').exists())

    def set_steam_candidates(self, *paths):
        # Isolate the test from real Steam registry entries on the host PC.
        script_path = self.bundle / 'Smoke-Test.ps1'
        script = script_path.read_text()
        start = script.index('function Get-SteamDirectories(')
        end = script.index('function Find-SteamDirectory(', start)
        literals = ','.join("'" + str(path).replace("'", "''") + "'" for path in paths)
        script_path.write_text(script[:start] + 'function Get-SteamDirectories($Game) { @(' + literals + ') }\n\n' + script[end:])

    def test_missing_original_library_stops_setup_and_old_installed_launch(self):
        self.run_action('Install')
        receipt_path = self.game / 'cod2-smoke-test-install.json'
        before = receipt_path.read_bytes()
        (self.game / 'mss32_original.dll').unlink()
        status = json.loads(self.run_action('Inspect'))
        self.assertFalse(status['ready'])
        for action in ('Try', 'Install', 'Launch', 'Verify'):
            self.assertIn('mss32_original.dll is missing', self.run_action(action, succeeds=False))
        self.assertEqual(receipt_path.read_bytes(), before)
        self.assertFalse((self.game / 'fixture-launch.json').exists())
        # A broken prerequisite must not prevent recovery to the previous client.
        self.run_action('Uninstall')
        self.assert_original()

    def test_unsupported_original_library_is_rejected_without_writes(self):
        (self.game / 'mss32_original.dll').write_bytes(b'Wrong sound library')
        self.assertFalse(json.loads(self.run_action('Inspect'))['ready'])
        self.assertIn('sound library is not the supported version', self.run_action('Try', succeeds=False))
        self.assert_original()


if __name__ == '__main__':
    unittest.main()
