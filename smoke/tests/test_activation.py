"""Exercise installed activation with a real Windows child, without loading CoD2."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CXX = os.environ.get('CXX') or shutil.which('g++')


@unittest.skipUnless(os.name == 'nt' and CXX, 'Windows C++ compiler required')
class InstalledActivation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='cod2 smoke activation ')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.folder = Path(cls.temp.name)
        source = cls.folder / 'probe.cpp'
        source.write_text('''#include "smoke_activation.hpp"
#include <cstdio>
int main() {
    const bool installed = cod2_smoke::installed_preview();
    std::printf("%d %d %d", int(installed),
        int(cod2_smoke::activation_flag("COD2_SMOKE_DIAGNOSTICS", installed)),
        int(cod2_smoke::activation_flag("COD2_SMOKE_RENDER", installed)));
}
''')
        for name, flags in [('preview', ['-DCOD2X_SMOKE_TEST_BUILD=1']), ('stable', [])]:
            subprocess.run([CXX, '-std=c++17', '-static', *flags,
                '-I', str(ROOT / 'src/mss32'), str(source), '-o', str(cls.folder / f'{name}.exe')],
                check=True, capture_output=True, text=True, timeout=30)

    def probe(self, installed=False, overrides=None, executable='preview'):
        receipt = self.folder / 'cod2-smoke-test-install.json'
        receipt.unlink(missing_ok=True)
        if installed:
            receipt.write_text('{"schema": 1}')
        env = dict(os.environ)
        for key in ('COD2_SMOKE_DIAGNOSTICS', 'COD2_SMOKE_RENDER'):
            env.pop(key, None)
        env.update(overrides or {})
        # A different working directory must not affect installation detection.
        return subprocess.check_output([str(self.folder / f'{executable}.exe')],
            env=env, cwd=ROOT, text=True, timeout=5)

    def test_installed_preview_survives_missing_launcher_environment(self):
        self.assertEqual(self.probe(installed=True), '1 1 1')

    def test_uninstalled_preview_is_disabled_without_explicit_opt_in(self):
        self.assertEqual(self.probe(), '0 0 0')
        self.assertEqual(self.probe(overrides={'COD2_SMOKE_DIAGNOSTICS': '1'}), '0 1 0')

    def test_explicit_opt_out_and_diagnostic_only_still_work(self):
        self.assertEqual(self.probe(True, {'COD2_SMOKE_RENDER': '0'}), '1 1 0')
        self.assertEqual(self.probe(True, {'COD2_SMOKE_DIAGNOSTICS': '0'}), '1 0 1')
        self.assertEqual(self.probe(True, {'COD2_SMOKE_RENDER': 'invalid-setting'}), '1 1 0')

    def test_stable_build_cannot_enable_preview(self):
        self.assertEqual(self.probe(True, {'COD2_SMOKE_DIAGNOSTICS': '1',
            'COD2_SMOKE_RENDER': '1'}, executable='stable'), '0 0 0')


if __name__ == '__main__':
    unittest.main()
