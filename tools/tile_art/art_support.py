import argparse
import contextlib
import ctypes
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'tools/tile_art'


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--aseprite', required=True)
    parser.add_argument('--scripts-dir', type=Path, default=SCRIPTS)
    return parser.parse_known_args()


def main(remaining):
    unittest.main(argv=[sys.argv[0], *remaining])


def aseprite(executable, script, params=None, timeout=30):
    command = [executable, '--batch']
    for key, value in (params or {}).items():
        if isinstance(value, Path):
            value = value.as_posix()
        command += ['--script-param', f'{key}={value}']
    return subprocess.run(command + ['--script', str(script)], capture_output=True, text=True,
                          timeout=timeout, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))


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


def corner_order():
    text = (SCRIPTS / 'ground_corners.lua').read_text(encoding='utf-8')
    order = [int(value) for value in re.search(r'return\s*\{([^}]+)\}', text).group(1).split(',') if value.strip()]
    assert sorted(order) == list(range(16))
    return order


def water_cliff_layout():
    text = (SCRIPTS / 'water_cliff_layout.lua').read_text(encoding='utf-8')
    return {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', re.search(r'return\s*\{([^}]+)\}', text).group(1))}
