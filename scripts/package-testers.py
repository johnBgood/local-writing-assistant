#!/usr/bin/env python3
"""Package a prebuilt app and a whitelisted unpacked extension, never local data."""
import hashlib, json, pathlib, shutil, subprocess, tempfile, zipfile
root=pathlib.Path(__file__).resolve().parent.parent
version=json.loads((root/'extension/manifest.json').read_text())['version']
release=root/'dist/testers';release.mkdir(parents=True,exist_ok=True)
app=root/'dist/LocalWriter.app'
zip_path=release/f'LocalWriter-Chrome-{version}.zip'
files=['manifest.json','background.js','activation.js','auto.js','core.js','content.js','docs.js','popup.html','popup.css','popup.js','practice.html']
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as archive:
    for name in files: archive.write(root/'extension'/name,name)
    archive.write(root/'docs/TESTERS.md','TESTER-SETUP.md')
with zipfile.ZipFile(zip_path) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist())==set(files+['TESTER-SETUP.md'])
dmg=release/f'LocalWriter-{version}-arm64-beta.dmg'
with tempfile.TemporaryDirectory(prefix='localwriter-dmg-',dir=root/'dist') as temp:
    stage=pathlib.Path(temp)
    shutil.copytree(app,stage/'LocalWriter.app',symlinks=True)
    subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(stage/'LocalWriter.app')],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(stage/'LocalWriter.app')],check=True)
    (stage/'Applications').symlink_to('/Applications')
    shutil.copy2(root/'docs/TESTERS.md',stage/'START-HERE.md')
    shutil.copy2(zip_path,stage/zip_path.name)
    subprocess.run(['hdiutil','create','-volname',f'LocalWriter {version} Beta','-srcfolder',str(stage),'-format','UDZO','-ov',str(dmg)],check=True)
subprocess.run(['hdiutil','verify',str(dmg)],check=True)
shutil.copy2(root/'docs/TESTERS.md',release/'START-HERE.md')
checksums=''.join(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.name+'\n' for path in [dmg,zip_path])
(release/'SHA256SUMS.txt').write_text(checksums)
print('Ad-hoc-signed beta; NOT notarized. Model not bundled.')
print(dmg);print(zip_path)
