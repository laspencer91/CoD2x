"""Exercise the ProSmoke setup script against a disposable fake game folder. Never a real game."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1] / 'package'
SCRIPT = PACKAGE / 'scripts/setup.ps1'
PAYLOAD = PACKAGE / 'client/prosmoke'
LOADER = PACKAGE / 'client/mss32.dll'


@unittest.skipUnless(shutil.which('powershell.exe'), 'Windows PowerShell required')
class SetupScript(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='prosmoke setup fixture ')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.game = root / 'Call of Duty 2'
        self.game.mkdir()
        (self.game / 'CoD2MP_s.exe').write_bytes(b'Fixture only; never execute')
        # A CoD2x-looking loader body without the ProSmoke marker, so it reads as the stock loader.
        self.original = LOADER.read_bytes().replace(b'sv_prosmoke_policy', b'sv_stockcod2x_fixt') + b'Previous CoD2x fixture'
        assert b'sv_prosmoke_policy' not in self.original
        (self.game / 'mss32.dll').write_bytes(self.original)
        (self.game / 'mss32_original.dll').write_bytes(b'Miles fixture; never load')
        self.env = dict(os.environ, LOCALAPPDATA=str(root / 'local'))
        (root / 'local').mkdir()

    def run_script(self, action, game=None, *extra, expect=0):
        result = subprocess.run(
            ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SCRIPT),
             '-Action', action, '-GameDirectory', str(game or self.game), '-NoPrompt', *extra],
            capture_output=True, text=True, timeout=90, env=self.env)
        self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
        return result.stdout

    def assert_installed(self):
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), LOADER.read_bytes())
        for file in PAYLOAD.iterdir():
            self.assertEqual((self.game / 'prosmoke' / file.name).read_bytes(), file.read_bytes(), file.name)

    def test_check_install_reinstall_undo(self):
        out = self.run_script('Check')
        self.assertIn('CoD2x installed: True', out)
        self.assertIn('ProSmoke installed: False', out)
        out = self.run_script('Install')
        self.assertIn('ProSmoke installed.', out)
        self.assert_installed()
        backup = self.game / 'prosmoke-backup/mss32.dll'
        self.assertEqual(backup.read_bytes(), self.original)
        self.assertTrue((self.game / 'prosmoke-backup/install.json').is_file())
        self.assertIn('ProSmoke installed: True', self.run_script('Check'))
        remembered = Path(self.env['LOCALAPPDATA']) / 'prosmoke/game-directory.txt'
        self.assertEqual(remembered.read_text().strip(), str(self.game))
        # Reinstall keeps the first backup.
        self.run_script('Install')
        self.assertEqual(backup.read_bytes(), self.original)
        self.assert_installed()
        out = self.run_script('Undo')
        self.assertIn('Restored your original CoD2x loader', out)
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), self.original)
        self.assertFalse((self.game / 'prosmoke').exists())
        self.assertFalse((self.game / 'prosmoke-backup').exists())
        self.assertTrue((self.game / 'mss32_original.dll').is_file())

    def test_detects_a_single_remembered_game_folder(self):
        # Regression: a lone detected folder came back as a string and '.Count' failed under strict mode.
        state = Path(self.env['LOCALAPPDATA']) / 'prosmoke'
        state.mkdir()
        (state / 'game-directory.txt').write_text(str(self.game))
        result = subprocess.run(
            ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SCRIPT),
             '-Action', 'Check', '-NoPrompt'], capture_output=True, text=True, timeout=90, env=self.env)
        out = result.stdout + result.stderr
        self.assertNotIn("property 'Count'", out)
        if result.returncode and 'Detected: ' in out and str(self.game) in out:
            self.skipTest('this machine has a real Call of Duty 2 install, so more than one folder was detected')
        self.assertEqual(result.returncode, 0, out)
        self.assertIn(f'Game folder: {self.game}', out)

    def test_candidate_on_a_missing_drive_does_not_stop_detection(self):
        # Regression: Test-Path raised "Cannot find drive" for the built-in D:\ candidate on C:-only PCs.
        missing = next(d for d in 'ZYXWVUTSRQPONMLKJIHGFE' if not os.path.exists(d + ':\\'))
        state = Path(self.env['LOCALAPPDATA']) / 'prosmoke'
        state.mkdir()
        (state / 'game-directory.txt').write_text(missing + ':\\Games\\Call of Duty 2')
        result = subprocess.run(
            ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SCRIPT),
             '-Action', 'Check', '-NoPrompt'], capture_output=True, text=True, timeout=90, env=self.env)
        output = result.stdout + result.stderr
        self.assertNotIn('Cannot find drive', output)
        self.assertNotIn('does not exist', output)

    def test_upgrading_prosmoke_keeps_the_original_backup(self):
        # An earlier ProSmoke build in place must not be mistaken for a newer CoD2x loader.
        self.run_script('Install')
        backup = self.game / 'prosmoke-backup/mss32.dll'
        self.assertEqual(backup.read_bytes(), self.original)
        (self.game / 'mss32.dll').write_bytes(LOADER.read_bytes() + b'older ProSmoke build')
        out = self.run_script('Install')
        self.assertIn('Replacing an earlier ProSmoke loader', out)
        self.assertEqual(backup.read_bytes(), self.original)
        self.assertEqual(sorted(p.name for p in backup.parent.iterdir()), ['install.json', 'mss32.dll'])
        self.assert_installed()
        self.run_script('Undo')
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), self.original)

    def test_newer_cod2x_loader_becomes_the_restore_baseline(self):
        self.run_script('Install')
        newer = LOADER.read_bytes().replace(b'sv_prosmoke_policy', b'sv_stockcod2x_fixt') + b'Newer CoD2x fixture'
        (self.game / 'mss32.dll').write_bytes(newer)
        self.run_script('Install')
        self.assert_installed()
        backups = sorted(p.name for p in (self.game / 'prosmoke-backup').glob('mss32*.dll'))
        self.assertIn('mss32.dll', backups)
        self.assertEqual(len(backups), 2, backups)
        dated = next(name for name in backups if name != 'mss32.dll')
        self.assertEqual((self.game / 'prosmoke-backup' / dated).read_bytes(), self.original)
        self.assertEqual((self.game / 'prosmoke-backup/mss32.dll').read_bytes(), newer)
        self.run_script('Undo')
        self.assertEqual((self.game / 'mss32.dll').read_bytes(), newer)

    def test_refuses_wrong_folders_without_writing(self):
        empty = Path(self.temp.name) / 'not a game'
        empty.mkdir()
        self.assertIn('No CoD2MP_s.exe', self.run_script('Install', empty, expect=1))
        (self.game / 'mss32.dll').write_bytes(b'plain Miles library, not CoD2x')
        out = self.run_script('Install', expect=1)
        self.assertIn('CoD2x is not installed', out)
        self.assertFalse((self.game / 'prosmoke').exists())
        self.assertFalse((self.game / 'prosmoke-backup').exists())

    def test_play_dry_run_and_not_installed(self):
        self.assertIn('not installed', self.run_script('Play', None, '-DryRun', expect=1))
        self.run_script('Install')
        out = self.run_script('Play', None, '-DryRun', '-Map', 'mp_burgundy')
        self.assertIn('+set fs_game prosmoke', out)
        self.assertIn('+exec prosmoke.cfg', out)
        self.assertIn('+devmap mp_burgundy', out)
        self.assertIn('r_rendererPreference dx9', out)


if __name__ == '__main__':
    unittest.main()
