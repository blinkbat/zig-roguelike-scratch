import argparse
import gzip
import hashlib
import http.client
import io
import json
import pathlib
import posixpath
import shutil
import struct
import subprocess
import tarfile
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SELF = pathlib.Path(__file__).resolve()
ROOT = SELF.parents[1]
LOCK_PATH = SELF.with_name('release-deps.json')
MAPS = ROOT / 'maps'
ASSETS = ROOT / 'assets'
EXE = 'cistern'
LINUX_ARCH = 'x86_64'
LINUX_TRIPLE = LINUX_ARCH + '-linux-gnu'
EMBEDDED = ('.png', '.ttf', '.txt')
PREFIX_LAYOUT = 1
GLIBC = (2, 31)
MACOS = (11, 0)
MACOS_ARCHES = {'arm64': ('aarch64', 0x100000c), 'x86_64': ('x86_64', 0x1000007)}
PREAMBLE = b'#!/bin/sh\nset -eu\ncd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\n'
EXEC = b'exec ./' + EXE.encode() + b' "$@"\n'
LAUNCHER = PREAMBLE + EXEC
LINUX_LAUNCHER = PREAMBLE + b'''if [ -e /proc/driver/nvidia ]; then
  export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD-1}"
  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME-nvidia}"
else
  export DRI_PRIME="${DRI_PRIME-1}"
fi
''' + EXEC


def dotted(version):
    return '.'.join(map(str, version))


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def publish(dest, write, check=None):
    with tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as temporary:
        pending = pathlib.Path(temporary.name)
    try:
        with pending.open('wb') as stream:
            write(stream)
        if check:
            check(pending)
        pending.replace(dest)
    except BaseException:
        pending.unlink(missing_ok=True)
        raise


def download(record, cache):
    dest = cache / 'downloads' / record['sha256']
    if dest.is_file() and sha256(dest.read_bytes()) == record['sha256']:
        return dest
    failures = []
    for url in record['urls']:
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
            if sha256(data) != record['sha256']:
                raise ValueError('SHA-256 mismatch: ' + url)
            dest.parent.mkdir(parents=True, exist_ok=True)
            publish(dest, lambda stream: stream.write(data))
            return dest
        except (OSError, ValueError, http.client.HTTPException) as error:
            failures.append(str(error))
    raise RuntimeError('Download failed for ' + record['name'] + ': ' + '; '.join(failures))


def contained(root, name):
    result = (root / name).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError('Archive path escapes destination: ' + name)
    return result


def deb_data(path):
    data = path.read_bytes()
    if not data.startswith(b'!<arch>\n'):
        raise ValueError('Invalid Debian archive: ' + str(path))
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        size = int(header[48:58])
        if header[:16].decode().strip().rstrip('/').startswith('data.tar'):
            return data[offset + 60:offset + 60 + size]
        offset += 60 + size + size % 2
    raise ValueError('Missing Debian data archive: ' + str(path))


def prepare_linux(lock, cache):
    records = lock['linux']
    identity = sha256(json.dumps({'layout': PREFIX_LAYOUT, 'records': records}, sort_keys=True).encode())[:16]
    prefix = cache / ('linux-' + identity)
    if (prefix / '.complete').is_file():
        return prefix
    print('Preparing pinned Linux headers and libraries...', flush=True)
    with ThreadPoolExecutor(max_workers=6) as pool:
        packages = list(pool.map(lambda record: download(record, cache), records))
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='linux-extract-', dir=cache) as temporary:
        unpacked = pathlib.Path(temporary)
        links = []
        for package in packages:
            with tarfile.open(fileobj=io.BytesIO(deb_data(package)), mode='r:*') as archive:
                for entry in archive:
                    name = entry.name.removeprefix('./')
                    if not name.startswith(('usr/include/', 'usr/lib/', 'lib/')):
                        continue
                    dest = contained(unpacked, name)
                    if entry.isfile():
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        dest.write_bytes(archive.extractfile(entry).read())
                    elif entry.issym() or entry.islnk():
                        target = entry.linkname
                        if target.startswith('/'):
                            target = target.lstrip('/')
                        elif entry.issym():
                            target = posixpath.join(posixpath.dirname(name), target)
                        links.append((dest, contained(unpacked, target)))
        while links:
            pending = []
            for dest, source in links:
                if source.is_file():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, dest)
                else:
                    pending.append((dest, source))
            if len(pending) == len(links):
                raise ValueError('Unresolved Linux library/header symlinks')
            links = pending
        shutil.copytree(unpacked / 'usr/include', prefix / 'include', dirs_exist_ok=True)
        shutil.copytree(unpacked / 'usr/lib' / LINUX_TRIPLE, prefix / 'lib', dirs_exist_ok=True)
    (prefix / '.complete').write_text(identity, encoding='ascii')
    return prefix


def inspect_linux(path):
    data = path.read_bytes()
    if data[:7] != b'\x7fELF\x02\x01\x01':
        raise ValueError('Expected a little-endian ELF64 executable')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    if header[2] != 62:
        raise ValueError('Expected an x86-64 executable')
    programs = [struct.unpack_from('<IIQQQQQQ', data, header[5] + i * header[9]) for i in range(header[10])]
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, header[6] + i * header[11]) for i in range(header[12])]

    def string(offset):
        return data[offset:data.index(b'\0', offset)].decode()

    def mapped(address):
        for kind, flags, off, va, pa, filesz, memsz, align in programs:
            if kind == 1 and va <= address < va + filesz:
                return off + address - va
        raise ValueError('Unmapped ELF address')

    interpreter = next(string(p[2]) for p in programs if p[0] == 3)
    if interpreter != '/lib64/ld-linux-x86-64.so.2':
        raise ValueError('Unexpected Linux interpreter: ' + interpreter)
    dynamic = next(p for p in programs if p[0] == 2)
    tags = list(struct.iter_unpack('<qQ', data[dynamic[2]:dynamic[2] + dynamic[5]]))
    strings = mapped(next(value for tag, value in tags if tag == 5))
    if any(tag in (15, 29) for tag, value in tags):
        raise ValueError('Release must not contain RPATH/RUNPATH')
    versions = set()
    for section in sections:
        if section[1] != 0x6ffffffe:
            continue
        string_table = sections[section[6]][4]
        pos = section[4]
        while True:
            version, count, filename, aux, next_entry = struct.unpack_from('<HHIII', data, pos)
            auxpos = pos + aux
            for _ in range(count):
                hash_, flags, other, name, next_aux = struct.unpack_from('<IHHII', data, auxpos)
                versions.add(string(string_table + name))
                auxpos += next_aux
            if not next_entry:
                break
            pos += next_entry
    glibc = [tuple(map(int, value[6:].split('.'))) for value in versions if value.startswith('GLIBC_')]
    if not glibc or max(glibc) > GLIBC:
        raise ValueError('Release requires a newer glibc than ' + dotted(GLIBC))
    return {'format': 'ELF64 x86-64', 'interpreter': interpreter,
            'needed': [string(strings + value) for tag, value in tags if tag == 1],
            'symbol_versions': sorted(versions), 'sha256': sha256(data)}


def run(args):
    print(' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


def inspect_macos(path, arch):
    data = path.read_bytes()
    header = struct.unpack_from('<8I', data)
    cpu = MACOS_ARCHES[arch][1]
    if header[0] != 0xfeedfacf or header[1] != cpu or header[3] != 2:
        raise ValueError('Expected a Mach-O executable for ' + arch)
    offset, needed, minimum, signature, interpreter = 32, [], None, None, None
    for _ in range(header[4]):
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > 32 + header[5]:
            raise ValueError('Invalid Mach-O load command')
        if command in (0xc, 0x80000018, 0x8000001f, 0x80000023, 0x20, 0xe):
            name_at = offset + struct.unpack_from('<I', data, offset + 8)[0]
            name = data[name_at:data.index(b'\0', name_at, offset + size)].decode()
            if command == 0xe:
                interpreter = name
            else:
                if not name.startswith(('/usr/lib/', '/System/Library/Frameworks/')):
                    raise ValueError('Non-system macOS dependency: ' + name)
                needed.append(name)
        elif command == 0x8000001c:
            raise ValueError('Release must not contain LC_RPATH')
        elif command == 0x32:
            platform, minimum = struct.unpack_from('<II', data, offset + 8)
            if platform != 1:
                raise ValueError('Expected macOS platform')
        elif command == 0x24:
            minimum = struct.unpack_from('<I', data, offset + 8)[0]
        elif command == 0x1d:
            signature = struct.unpack_from('<II', data, offset + 8)
        offset += size
    if minimum != (MACOS[0] << 16 | MACOS[1] << 8) or interpreter != '/usr/lib/dyld':
        raise ValueError('Unexpected macOS deployment target or loader')
    signed_pages = 0
    if signature:
        start, length = signature
        magic, blob_length, count = struct.unpack_from('>III', data, start)
        if magic != 0xfade0cc0 or blob_length > length or start + length > len(data):
            raise ValueError('Invalid embedded code signature')
        for i in range(count):
            kind, relative = struct.unpack_from('>II', data, start + 12 + 8 * i)
            if kind != 0:
                continue
            directory = start + relative
            magic, size, version, flags, hashes, identifier, specials, slots, limit = struct.unpack_from('>9I', data, directory)
            hash_size, hash_type, platform, page_shift = struct.unpack_from('>4B', data, directory + 36)
            if magic != 0xfade0c02 or not flags & 2 or hash_size != 32 or hash_type != 2 or limit != start:
                raise ValueError('Unexpected ad-hoc code signature format')
            page_size = 1 << page_shift
            if slots != (limit + page_size - 1) // page_size:
                raise ValueError('Incomplete code signature')
            for page in range(slots):
                expected = hashlib.sha256(data[page * page_size:min((page + 1) * page_size, limit)]).digest()
                at = directory + hashes + page * hash_size
                if data[at:at + hash_size] != expected:
                    raise ValueError('Code signature page mismatch: ' + str(page))
            signed_pages = slots
        if not signed_pages:
            raise ValueError('Missing CodeDirectory')
    if arch == 'arm64' and not signed_pages:
        raise ValueError('Apple Silicon executable needs an ad-hoc signature')
    return {'format': 'Mach-O ' + arch, 'minimum_macos': dotted(MACOS), 'needed': needed,
            'verified_signature_pages': signed_pages, 'sha256': sha256(data)}


def map_paths():
    return sorted(MAPS.rglob('*.map'))


def source_hash():
    paths = [ROOT / 'build.zig', ROOT / 'build.zig.zon', LOCK_PATH, SELF]
    paths += list((ROOT / 'src').rglob('*.zig'))
    paths += [p for p in ASSETS.iterdir() if p.suffix in EMBEDDED]
    paths += map_paths()
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def archive_name(platform, arch):
    return EXE + '-' + platform + '-' + arch


def package(binary, output, metadata, platform, arch):
    name = archive_name(platform, arch)
    files = {EXE: (binary.read_bytes(), 0o755), 'run.sh': (LINUX_LAUNCHER if platform == 'linux' else LAUNCHER, 0o755)}
    if platform == 'macos':
        files['run.command'] = (LAUNCHER, 0o755)
    for path in map_paths():
        files[path.relative_to(ROOT).as_posix()] = (path.read_bytes(), 0o644)
    for filename in ('Balthazar-OFL.txt', 'gamecontrollerdb-LICENSE'):
        files['licenses/' + filename] = ((ASSETS / filename).read_bytes(), 0o644)
    requirements = '''Requires glibc ''' + dotted(GLIBC) + ''' or newer, an X11 display (or XWayland), and OpenGL 3.3.
On Debian/Ubuntu, runtime libraries can be installed with:
  sudo apt install libgl1 libglx0 libx11-6 libxcursor1 libxext6 libxfixes3 libxi6 libxinerama1 libxrandr2 libxrender1
run.sh prefers a laptop's dedicated GPU (NVIDIA PRIME offload, or DRI_PRIME on Mesa).
To use the default GPU instead, run ./''' + EXE + ''' from this directory.
''' if platform == 'linux' else '''Requires macOS ''' + dotted(MACOS) + ''' or newer and OpenGL 3.3. Use arm64 on Apple Silicon or x86_64 on Intel.
You can also double-click run.command to launch through Terminal.
If macOS says the developer cannot be verified, run: xattr -dr com.apple.quarantine <this folder>
These are local development builds, not Developer ID signed or notarized releases.
'''
    files['README.txt'] = (('''Cistern for ''' + platform + ' ' + arch + '''

Extract this archive into a writable directory, then run ./run.sh.
The launcher selects the game directory so maps and saves are found.
To use the editor, run ./run.sh --edit ''' + MAPS.name + '''/main.map.

''' + requirements + '''

Graphics, fonts and controller mappings are embedded; keep maps/ beside the game.
Saves are written under saves/ in this directory. This package contains no saved runs.
Uses raylib. Font and controller mapping licenses are in licenses/.

Type-checked, compiled and statically inspected. This build command does not launch the game.
''').encode(), 0o644)
    metadata['files'] = {key: sha256(value[0]) for key, value in sorted(files.items())}
    files['build-info.json'] = ((json.dumps(metadata, indent=2, sort_keys=True) + '\n').encode(), 0o644)
    output.mkdir(parents=True, exist_ok=True)
    destination = output / (name + '.tar.gz')

    def write(stream):
        with gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
                for filename, (data, mode) in sorted(files.items()):
                    entry = tarfile.TarInfo(name + '/' + filename)
                    entry.size, entry.mode, entry.mtime = len(data), mode, 0
                    archive.addfile(entry, io.BytesIO(data))

    def check(pending):
        with tarfile.open(pending, 'r:gz') as archive:
            for entry in archive:
                data, mode = files[entry.name.removeprefix(name + '/')]
                if archive.extractfile(entry).read() != data or entry.mode != mode:
                    raise ValueError('Packaged content or mode mismatch: ' + entry.name)

    publish(destination, write, check)
    checksum = sha256(destination.read_bytes())
    destination.with_suffix(destination.suffix + '.sha256').write_text(checksum + '  ' + destination.name + '\n', encoding='ascii')
    print('PACKAGED: ' + str(destination), flush=True)
    print('SHA256: ' + checksum, flush=True)


def main():
    parser = argparse.ArgumentParser(description='Build and package Cistern with pinned cross-compilation dependencies.')
    parser.add_argument('platform', choices=['linux', 'macos'])
    parser.add_argument('--arch', choices=['all', *MACOS_ARCHES], default='all')
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--cache-dir', type=pathlib.Path, default=ROOT.parent / '.zigtoolchain/cistern-release')
    parser.add_argument('--output-dir', type=pathlib.Path, default=ROOT / 'zig-out/releases')
    parser.add_argument('--build-cache', type=pathlib.Path)
    parser.add_argument('--global-cache', type=pathlib.Path)
    args = parser.parse_args()
    lock = json.loads(LOCK_PATH.read_text(encoding='utf-8'))
    version = subprocess.check_output([args.zig, 'version'], text=True).strip()
    if version != lock['zig_version']:
        raise ValueError('Expected Zig ' + lock['zig_version'] + '; found ' + version)
    output = args.output_dir.resolve()
    if args.platform == 'linux' and args.arch not in ('all', LINUX_ARCH):
        parser.error('The pinned Linux dependencies support ' + LINUX_ARCH + ' only.')
    arches = [LINUX_ARCH] if args.platform == 'linux' else list(MACOS_ARCHES)
    if args.arch != 'all':
        arches = [args.arch]
    prefix = prepare_linux(lock, args.cache_dir.resolve()) if args.platform == 'linux' else None
    before = source_hash()
    for arch in arches:
        target = LINUX_TRIPLE + '.' + dotted(GLIBC) if args.platform == 'linux' else MACOS_ARCHES[arch][0] + '-macos.' + dotted(MACOS)
        install = output / 'build' / (args.platform + '-' + arch)
        common = [args.zig, 'build', '-Dtarget=' + target, '-Dcpu=baseline']
        if prefix:
            common += ['--search-prefix', prefix]
        if args.build_cache:
            common += ['--cache-dir', args.build_cache.resolve()]
        if args.global_cache:
            common += ['--global-cache-dir', args.global_cache.resolve()]
        run(common + ['check', '--summary', 'all'])
        run(common + ['-Doptimize=ReleaseFast', '-Dstrip=true', '--prefix', install, '--summary', 'all'])
        if source_hash() != before:
            raise RuntimeError('Sources changed during the build; rerun to package a consistent snapshot.')
        binary = install / 'bin' / EXE
        inspection = inspect_linux(binary) if args.platform == 'linux' else inspect_macos(binary, arch)
        metadata = {'zig_version': version, 'target': target, 'cpu': 'baseline',
                    'optimize': 'ReleaseFast', 'strip': True, 'source_sha256': before,
                    'dependency_lock_sha256': sha256(LOCK_PATH.read_bytes()), 'binary': inspection}
        package(binary, output, metadata, args.platform, arch)


if __name__ == '__main__':
    main()
