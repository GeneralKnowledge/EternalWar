#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import platform

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)

try:
    os.mkdir('build')
except Exception:
    pass


def binary_name():
    """Match CMake OUTPUT_NAME_RELWITHDEBINFO / RELEASE naming."""
    arch = '64' if sys.maxsize > 2 ** 32 else '32'
    if platform.system() == 'Windows':
        return os.path.join('bin', 'lt%s.exe' % arch)
    # Linux RelWithDebInfo / default single-config Release names
    for name in ('lt%s' % arch, 'lt%sr' % arch, 'lt%sd' % arch):
        path = os.path.join('bin', name)
        if os.path.isfile(path):
            return path
    return os.path.join('bin', 'lt%s' % arch)


if len(sys.argv) > 1:
    if sys.argv[1] == 'build':
        env = os.environ.copy()
        # Prefer g++ on Linux; clang-as-c++ can pick a broken GCC toolchain.
        if platform.system() == 'Linux':
            env.setdefault('CC', 'gcc')
            env.setdefault('CXX', 'g++')
        subprocess.call(
            ['cmake', '--build', './build', '--config', 'RelWithDebInfo'],
            env=env)
    elif sys.argv[1] == 'clean':
        shutil.rmtree('bin', ignore_errors=True)
        shutil.rmtree('build', ignore_errors=True)
    elif sys.argv[1] == 'run':
        cmd = [binary_name()] + sys.argv[2:]
        env = os.environ.copy()
        if platform.system() == 'Linux':
            libdir = os.path.join(ROOT, 'libphx', 'ext', 'lib',
                                  'linux64' if sys.maxsize > 2 ** 32 else 'linux32')
            bindir = os.path.join(ROOT, 'bin')
            parts = [bindir]
            if os.path.isdir(libdir):
                parts.append(libdir)
            if env.get('LD_LIBRARY_PATH'):
                parts.append(env['LD_LIBRARY_PATH'])
            env['LD_LIBRARY_PATH'] = ':'.join(parts)
        raise SystemExit(subprocess.call(cmd, env=env))
    else:
        print('Usage: configure.py [build|clean|run [AppName] ...]')
        raise SystemExit(2)
else:
    env = os.environ.copy()
    if platform.system() == 'Linux':
        env.setdefault('CC', 'gcc')
        env.setdefault('CXX', 'g++')
    # Single-config generators ignore --config; force RelWithDebInfo output name.
    subprocess.call(
        ['cmake', '-S', './', '-B', './build',
         '-DCMAKE_BUILD_TYPE=RelWithDebInfo'],
        env=env)
