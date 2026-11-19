import argparse
import contextlib
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'tools/tile_art'


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--aseprite', required=True)
    parser.add_argument('--scripts-dir', type=Path, default=SCRIPTS)
    args, remaining = parser.parse_known_args()
    args.scripts_dir = args.scripts_dir.resolve()
    args.root = args.scripts_dir.parents[1]
    return args, remaining


def main(remaining):
    unittest.main(argv=[sys.argv[0], *remaining])


def environment(temp, **extra):
    env = dict(os.environ, **extra)
    if temp is not None:
        env.update(TEMP=str(temp), TMP=str(temp))
    return env


def aseprite(executable, script, params=None, timeout=30, temp=None):
    command = [executable, '--batch']
    for key, value in (params or {}).items():
        if isinstance(value, Path):
            value = value.as_posix()
        command += ['--script-param', f'{key}={value}']
    return subprocess.run(command + ['--script', str(script)], capture_output=True, text=True,
                          timeout=timeout, env=environment(temp),
                          creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))


def run_lua(executable, script, code, params=None, **options):
    script.write_text(code, encoding='utf-8')
    return aseprite(executable, script, params, **options)


def generate(script, *arguments, temp=None):
    return subprocess.run([sys.executable, '-B', str(script), *map(str, arguments)],
                          env=environment(temp, PYTHONIOENCODING='utf-8'),
                          capture_output=True, text=True, encoding='utf-8', timeout=30)


class WorkTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cistern-' + type(self).__name__ + '-')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)


@contextlib.contextmanager
def read_locked(path):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                                  ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
                                  ctypes.c_void_p]
    kernel.CreateFileW.restype = ctypes.c_void_p
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.CreateFileW(str(path), 0x80000000, 1, None, 3, 0, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        yield
    finally:
        kernel.CloseHandle(handle)


def quote(value):
    return json.dumps(str(value).replace('\\', '/'), ensure_ascii=False)


def arial(size, bold=False):
    from PIL import ImageFont
    return ImageFont.truetype('C:/Windows/Fonts/arial' + ('bd' if bold else '') + '.ttf', size)


SHEET_INK = (50, 50, 50, 255)


# Arial Bold 23 at (12, 8), matched pixel for pixel against cave-walls.aseprite's header.
def sheet_title(draw, title):
    draw.text((12, 8), title, font=arial(23, True), fill=SHEET_INK)


def corner_order(scripts=SCRIPTS):
    text = (scripts / 'ground_corners.lua').read_text(encoding='utf-8')
    order = [int(value) for value in re.search(r'return\s*\{([^}]+)\}', text).group(1).split(',') if value.strip()]
    assert sorted(order) == list(range(16))
    return order


def ground_layout(scripts=SCRIPTS):
    text = (scripts / 'ground_layout.lua').read_text(encoding='utf-8')
    layout = {}
    for names, values in re.findall(r'^((?:layout\.\w+,?)+)=([\d,]+)\s*$', text, re.M):
        keys = [name.removeprefix('layout.') for name in names.split(',')]
        numbers = [int(value) for value in values.split(',')]
        assert len(keys) == len(numbers)
        layout.update(zip(keys, numbers))
    return layout


def water_cliff_layout(scripts=SCRIPTS):
    text = (scripts / 'water_cliff_layout.lua').read_text(encoding='utf-8')
    return {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', re.search(r'return\s*\{([^}]+)\}', text).group(1))}
