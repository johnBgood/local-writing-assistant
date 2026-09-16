#!/usr/bin/env python3
"""Verify two distinct bundles have the same certificate-pinned identity."""
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
requirements = []
hashes = []
with tempfile.TemporaryDirectory(prefix='localwriter-signing-') as directory:
    for version in ['101', '102']:
        app = pathlib.Path(directory) / f'LocalWriter-{version}.app'
        shutil.copytree(root / 'dist/LocalWriter.app', app)
        info = app / 'Contents/Info.plist'
        content = plistlib.loads(info.read_bytes())
        content['CFBundleVersion'] = version
        info.write_bytes(plistlib.dumps(content))
        subprocess.run(['python3', str(root / 'scripts/sign-app.py'), str(app)], check=True)
        result = subprocess.run(['codesign', '-d', '-r-', str(app)], check=True, capture_output=True, text=True)
        output = result.stdout + result.stderr
        requirements.append(next(line for line in output.splitlines() if line.startswith('designated =>')))
        output = subprocess.run(['codesign', '-dv', '--verbose=4', str(app)], check=True, capture_output=True, text=True).stderr
        hashes.append(re.search(r'^CDHash=(.+)$', output, re.MULTILINE).group(1))
assert requirements[0] == requirements[1], 'Signing identity changed across builds'
assert 'certificate leaf' in requirements[0] and 'cdhash' not in requirements[0]
assert hashes[0] != hashes[1], 'Fixtures must represent different signed builds'
print('PASS: distinct builds share the same certificate-pinned identity')
