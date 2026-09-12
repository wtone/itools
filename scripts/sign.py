#!/usr/bin/env python3
"""Sign one build artifact without silently replacing a stable identity with ad-hoc signing."""
import json
import os
import shlex
import fcntl
from pathlib import Path
import subprocess
import sys

def run(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        # Never include a command line: keychain unlock arguments contain a local secret.
        sys.stderr.write(result.stderr or 'Signing command failed\n')
        raise SystemExit(result.returncode)
    if result.stderr: sys.stderr.write(result.stderr)
    return result.stdout

temporary_keychain = None
identity = os.environ.get('SIGN_IDENTITY')
flags = ['--force']
if identity and identity != '-':
    flags += ['--sign', identity, '--options', 'runtime', '--timestamp']
    if os.environ.get('SIGN_KEYCHAIN'): flags += ['--keychain', os.environ['SIGN_KEYCHAIN']]
elif identity == '-' or os.environ.get('ALLOW_ADHOC_SIGNING') == '1':
    flags += ['--sign', '-']
else:
    folder = Path.home() / 'Library/Application Support/iTools Development/Signing'
    config = folder / 'identity.json'
    if not config.exists():
        sys.exit('No stable signing identity. Set SIGN_IDENTITY (Developer ID), or run scripts/setup-local-signing.py for local development. Explicit ALLOW_ADHOC_SIGNING=1 is only for disposable builds; privacy access will not survive updates.')
    info = json.loads(config.read_text())
    run(['/usr/bin/security', 'unlock-keychain', '-p', (folder / 'keychain-password').read_text(), info['keychain']])
    flags += ['--sign', info['identity'], '--keychain', info['keychain'], '--timestamp=none']
    temporary_keychain = info['keychain']
if temporary_keychain:
    # codesign resolves a private key through the user search list even with --keychain.
    # Serialize our own builds and preserve edits from other processes when restoring it.
    with (folder / 'signing.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        original = shlex.split(run(['/usr/bin/security', 'list-keychains', '-d', 'user']))
        added = temporary_keychain not in original
        try:
            if added: run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *original, temporary_keychain])
            run(['/usr/bin/codesign', *flags, *sys.argv[1:]])
        finally:
            if added:
                current = shlex.split(run(['/usr/bin/security', 'list-keychains', '-d', 'user']))
                run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *[p for p in current if p != temporary_keychain]])
else:
    run(['/usr/bin/codesign', *flags, *sys.argv[1:]])
