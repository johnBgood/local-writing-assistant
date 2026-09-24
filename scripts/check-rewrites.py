#!/usr/bin/env python3
"""Real-model style regression cases; requires the built app and local Ollama."""
import json,pathlib,re,struct,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parent.parent
cases=["I'm currently working on it, so it might change quite a bit, but it can already be used to spark discussions.","Je voulais juste te dire que je pense que ce serait bien si on pouvait prendre un moment pour discuter de ce sujet.","I wanted to reach out to you to ask if it would be possible for us to have a discussion about this issue.","Ich wollte dir nur sagen, dass ich denke, dass es gut wäre, wenn wir uns etwas Zeit nehmen könnten, um über dieses Thema zu sprechen."]
for text in cases:
 data=json.dumps({'method':'rewrite','text':text}).encode();t=time.monotonic()
 p=subprocess.run([str(ROOT/'dist/LocalWriter.app/Contents/MacOS/LocalWriter'),'--native-messaging'],input=struct.pack('<I',len(data))+data,stdout=subprocess.PIPE,check=True,timeout=190)
 result=json.loads(p.stdout[4:]); assert result.get('ok'),result
 words=lambda value: re.findall(r"\w+",value.casefold())
 assert words(text)!=words(result['rewrite']),(text,result)
 print(json.dumps({'text':text,'response':json.loads(p.stdout[4:]),'seconds':round(time.monotonic()-t,2)},ensure_ascii=False),flush=True)
