#!/usr/bin/env python3
import json, pathlib, struct, subprocess
root=pathlib.Path(__file__).resolve().parent.parent
host=pathlib.Path.home()/'Library/Application Support/Google/Chrome/NativeMessagingHosts/com.johnbgood.localwriter.json'
binary=pathlib.Path(json.loads(host.read_text())['path']) if host.exists() else root/'dist/LocalWriter.app/Contents/MacOS/LocalWriter'
def request(value):
    data=json.dumps(value).encode()
    result=subprocess.run([str(binary),'--native-messaging'],input=struct.pack('<I',len(data))+data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=100,check=True)
    size=struct.unpack('<I',result.stdout[:4])[0]
    assert len(result.stdout)==4+size
    return json.loads(result.stdout[4:])
assert request({'method':'ping'})['ok']
assert not request({'method':'invalid','text':'Hello'})['ok']
assert not request({'method':'analyze','text':'x'*4001})['ok']
result=request({'method':'analyze','text':'This is a speling mistake.'})
assert result['ok'],result
assert any(e['start']==10 and e['original']=='speling' and e['replacement']=='spelling' for e in result['edits']),result
print('PASS: native framing, validation, and real local-model correction')
