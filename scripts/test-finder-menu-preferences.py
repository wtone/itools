"""Exercise the production preference reader in a persistent sandboxed process.
Only a UUID test key is written; the user's actual menu layout stays untouched.
"""
from pathlib import Path
import json
import plistlib
import platform
import shutil
import subprocess
import uuid

root = Path(__file__).resolve().parent.parent
app = root / '.build/FinderMenuPreferencesProbe.app'
binary = app / 'Contents/MacOS/FinderMenuPreferencesProbe'
binary.parent.mkdir(parents=True, exist_ok=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleIdentifier='app.itools.test.finder-menu-preferences',
    CFBundleExecutable=binary.name, CFBundlePackageType='APPL', LSUIElement=True,
    LSMinimumSystemVersion='12.0')))
host = root / '.build/finder-menu-preference-writer'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(root / '.build/module-cache'),
                '-target', platform.machine() + '-apple-macosx12.0',
                str(root / 'scripts/finder-menu-preferences-probe.swift'),
                str(root / 'Sources/IToolsCore/FinderMenuLayout.swift'),
                str(root / 'Sources/IToolsCore/FinderActions.swift'), '-o', str(host)], check=True)
shutil.copy2(host, binary)
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements',
                str(root / 'Extensions/FinderSync/Finder.entitlements'), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
key = 'test.finder-menu.' + str(uuid.uuid4())
reader = None
try:
    subprocess.run([str(host), 'write', key, 'new-txt'], check=True)
    reader = subprocess.Popen([str(binary), 'read', key, str(root / '.build')], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True, bufsize=1)
    for values in [['new-txt'], ['terminal', 'open-with'], [], ['fast-zip', 'copy-path']]:
        subprocess.run([str(host), 'write', key, *values], check=True)
        reader.stdin.write('read\n'); reader.stdin.flush()
        actual = json.loads(reader.stdout.readline())
        assert actual == sorted(values), (values, actual)
    reader.stdin.close(); assert reader.wait(timeout=8) == 0; reader = None
    result = subprocess.run([str(binary), 'read', key, str(root / '.build')], input='read\n', text=True,
                            capture_output=True, timeout=8, check=True)
    assert json.loads(result.stdout) == ['copy-path', 'fast-zip']
    print('PASS: production shared preference reader; filesystem sandbox denial verified; initial read, live changes in same sandbox PID, empty selection, fresh process persistence; only isolated UUID test key used')
finally:
    if reader is not None:
        reader.terminate(); reader.wait(timeout=8)
    subprocess.run([str(host), 'remove', key], check=True)
