"""Create CoD2 smoke occupancy from compiled BSPs. Does not modify maps or games."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from cod2kit import smoke_bake


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bsp', type=Path, nargs='+', help='Compiled mp_*.d3dbsp maps')
    parser.add_argument('--output', type=Path, required=True, help='Separate bake output directory')
    parser.add_argument('--bounds', choices=('collision', 'hints'), default='collision',
                        help='Full included collision bounds, or explicitly cropped spawn-hint bounds')
    args = parser.parse_args()
    tool = Path(__file__).resolve().parent / 'bin/cod2smoke-bake.exe'
    expected = json.loads(tool.with_suffix('.json').read_text())['sha256']
    if hashlib.sha256(tool.read_bytes()).hexdigest() != expected:
        raise ValueError('Baker binary hash mismatch')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for source in args.bsp:
        source = source.resolve()
        if source.suffix.lower() != '.d3dbsp' or not re.fullmatch(r'mp_[a-z0-9_]{1,28}', source.stem):
            raise ValueError('Expected a compiled mp_*.d3dbsp map')
        if not 0 < source.stat().st_size <= 256 * 1024 * 1024:
            raise ValueError('BSP must be between 1 byte and 256 MiB')
        # The existing bake pipeline expects a workspace. Keep it ephemeral and local
        # to the selected output; no game assets, editor or model extraction are needed.
        with tempfile.TemporaryDirectory(prefix='.smoke-work-', dir=output) as temporary:
            workspace = Path(temporary).resolve()
            if not workspace.is_relative_to(output):
                raise ValueError('Temporary workspace leaves output directory')
            target = workspace / 'tools/bin/cod2smoke-bake.exe'
            target.parent.mkdir(parents=True)
            shutil.copyfile(tool, target)
            (workspace / 'game').mkdir()

            def run(command, cwd, progress):
                result = subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, text=True)
                for line in (result.stdout + result.stderr).splitlines():
                    progress(line)
                result.check_returncode()

            destination = output / source.stem
            report = smoke_bake.bake(workspace, source, destination, run,
                                     install_loose=False, bounds=args.bounds, props='ignore')
            report['boundsReviewRequired'] = args.bounds == 'hints'
            package = destination / ('mapkit_smoke_' + source.stem + '.iwd')
            pending = package.with_suffix('.iwd.pending')
            try:
                with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED) as archive:
                    smoke_bake.package_grid(archive, source.stem, destination, report)
                pending.replace(package)
            finally:
                pending.unlink(missing_ok=True)
            print('Occupancy package:', package)
            if report['boundsReviewRequired']:
                print('CROPPED CANDIDATE: review routes, roofs and grenade trajectories before distribution.')


if __name__ == '__main__':
    main()
