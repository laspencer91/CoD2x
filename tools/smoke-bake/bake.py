"""Create CoD2 smoke occupancy from compiled BSPs. Does not modify maps or games."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile
import zlib
from pathlib import Path

from cod2kit import smoke_bake


def validate_package(package, source):
    """Check the actual packaged bytes and their exact BSP binding before publishing."""
    prefix = 'maps/mp/' + source.stem
    with zipfile.ZipFile(package) as archive:
        expected = {prefix + suffix for suffix in ('.smokegrid', '.smokebind', '.smoke.json')}
        if set(archive.namelist()) != expected or len(archive.infolist()) != len(expected) or archive.testzip():
            raise ValueError('Invalid occupancy package contents or ZIP checksum')
        grid = archive.read(prefix + '.smokegrid')
        smoke_bake.inspect_grid(grid)
        magic, bsp_crc, grid_crc = struct.unpack('<4sII', archive.read(prefix + '.smokebind'))
        if (magic, bsp_crc, grid_crc) != (b'PSB1', zlib.crc32(source.read_bytes()), zlib.crc32(grid)):
            raise ValueError('Occupancy package BSP/grid binding mismatch')
        metadata = json.loads(archive.read(prefix + '.smoke.json'))
        if metadata['gridSha256'] != hashlib.sha256(grid).hexdigest():
            raise ValueError('Occupancy package grid hash mismatch')


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
                with subprocess.Popen([str(part) for part in command], cwd=cwd,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
                    for line in process.stdout:
                        progress(line.rstrip())
                    code = process.wait()
                    if code:
                        raise subprocess.CalledProcessError(code, command)

            destination = output / source.stem
            report = smoke_bake.bake(workspace, source, destination, run,
                                     install_loose=False, bounds=args.bounds, props='ignore')
            report['boundsReviewRequired'] = args.bounds == 'hints'
            package = destination / ('prosmoke_' + source.stem + '.iwd')
            pending = package.with_suffix('.iwd.pending')
            try:
                with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED) as archive:
                    smoke_bake.package_grid(archive, source.stem, destination, report)
                validate_package(pending, source)
                pending.replace(package)
            finally:
                pending.unlink(missing_ok=True)
            print('Occupancy package:', package)
            if report['boundsReviewRequired']:
                print('CROPPED CANDIDATE: review routes, roofs and grenade trajectories before distribution.')


if __name__ == '__main__':
    main()
