#!/usr/bin/env python3
"""Real-model checks; uses the native protocol and cleans up its temporary word."""
import json, pathlib, struct, subprocess
root=pathlib.Path(__file__).resolve().parent.parent
binary=root/'dist/LocalWriter.app/Contents/MacOS/LocalWriter'
def call(method,text=None):
    data=json.dumps({'method':method,'text':text},ensure_ascii=False).encode()
    p=subprocess.run([str(binary),'--native-messaging'],input=struct.pack('<I',len(data))+data,capture_output=True,timeout=100,check=True)
    n=struct.unpack('<I',p.stdout[:4])[0];assert len(p.stdout)==n+4
    r=json.loads(p.stdout[4:]);assert r['ok'],r
    return r
original=call('settings'); word='Zorbiflax'
try:
    call('setLanguage','auto')
    for sentence,expected in [('She go to work yesterday.','went'),('Je suis aller au bureau hier.','allé'),('Ich habe gestern ein Buch gelest.','gelesen')]:
        edits=call('analyze',sentence)['edits']
        assert any(expected in e['replacement'] for e in edits),(sentence,edits)
        rewrite=call('rewrite',sentence)['rewrite']
        assert expected in rewrite,(sentence,rewrite)
        print('PASS:',sentence,'→',rewrite)
    call('addWord',word)
    assert word in call('settings')['words']
    edits=call('analyze','Zorbiflax go to work yesterday.')['edits']
    assert any('went' in e['replacement'] for e in edits),edits
    assert all(word not in e['original'] for e in edits),edits
    assert word in call('rewrite','Zorbiflax go to work yesterday.')['rewrite']
    print('PASS: shared dictionary preserves its word while grammar is corrected')
finally:
    call('setLanguage',original['language'])
    if word not in original['words']: call('removeWord',word)
