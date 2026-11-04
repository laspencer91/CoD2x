"""Compile and execute the production short-wait fixture with the bridge compiler."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
CXX=os.environ.get('CXX') or shutil.which('g++')

@unittest.skipUnless(os.name=='nt' and CXX,'Windows x86 bridge compiler required')
class ProductionWaits(unittest.TestCase):
    def test_real_win32_routes_timers_guards_and_failure_fallback(self):
        with tempfile.TemporaryDirectory(prefix='prosmoke native waits ') as folder:
            output=Path(folder)/'waits.exe'
            result=subprocess.run([CXX,'-std=c++17','-m32','-O2','-Wall','-Wextra','-Werror','-static',str(ROOT/'smoke/tests/smoke_waits_probe.cpp'),'-o',str(output)],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(output)],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('PASS production short waits',result.stdout)

if __name__=='__main__':unittest.main()
