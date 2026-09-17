#!/usr/bin/env python3
"""Register only this extension with Chrome's per-user native messaging host."""
import base64, hashlib, json, pathlib, shlex
root=pathlib.Path(__file__).resolve().parent.parent
manifest=json.loads((root/'extension/manifest.json').read_text())
digest=hashlib.sha256(base64.b64decode(manifest['key'])).hexdigest()[:32]
extension_id=''.join(chr(ord('a')+int(c,16)) for c in digest)
launcher=root/'dist/localwriter-native-host'
launcher.parent.mkdir(exist_ok=True)
launcher.write_text('#!/bin/sh\nexec '+shlex.quote(str(root/'dist/LocalWriter.app/Contents/MacOS/LocalWriter'))+' --native-messaging "$@"\n')
launcher.chmod(0o755)
folder=pathlib.Path.home()/'Library/Application Support/Google/Chrome/NativeMessagingHosts'
folder.mkdir(parents=True,exist_ok=True)
path=folder/'com.johnbgood.localwriter.json'
path.write_text(json.dumps({'name':'com.johnbgood.localwriter','description':'LocalWriter local model bridge','path':str(launcher),'type':'stdio','allowed_origins':[f'chrome-extension://{extension_id}/']},indent=2)+'\n')
print('Extension ID:',extension_id)
print('Registered:',path)
print('Load unpacked:',root/'extension')
