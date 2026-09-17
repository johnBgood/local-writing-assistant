import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const state={autoEnabled:false,disabledSites:[]};let granted=false,registered=[],injections=[];
const messages=[];
const event=()=>({addListener(){}});
const chrome={
 storage:{local:{get:async defaults=>({...defaults,...state}),set:async value=>Object.assign(state,value)}},
 permissions:{contains:async()=>granted,onRemoved:event()},
 scripting:{getRegisteredContentScripts:async()=>registered,registerContentScripts:async list=>{registered=list;},unregisterContentScripts:async()=>{registered=[];},executeScript:async value=>{injections.push(value);}},
 tabs:{query:async()=>[],sendMessage:async()=>{}},
 runtime:{onMessage:{addListener:fn=>messages.push(fn)},onInstalled:event(),onStartup:event()}
};
const context=vm.createContext({chrome,URL});
vm.runInContext(fs.readFileSync(new URL('../extension/activation.js',import.meta.url),'utf8'),context);
const send=(message,sender={})=>new Promise(resolve=>messages[0](message,sender,resolve));
assert.equal((await send({method:'setAuto',enabled:true})).ok,false);
assert.equal(registered.length,0);
granted=true;
assert.equal((await send({method:'setAuto',enabled:true})).ok,true);
assert.equal(registered[0].persistAcrossSessions,true);
const sender={url:'https://docs.google.com/document/d/test/edit',frameId:0,tab:{id:42,url:'https://docs.google.com/document/d/test/edit'}};
await send({method:'autoStart'},sender);
assert.equal(injections.at(-1).files.at(-1),'docs.js');
await send({method:'toggleSite',url:sender.url});
injections=[];await send({method:'autoStart'},sender);assert.equal(injections.length,0);
// A cross-origin iframe must respect its parent site's exclusion.
await send({method:'autoStart'},{...sender,url:'https://editor.example.org/',frameId:2});assert.equal(injections.length,0);
await send({method:'toggleSite',url:sender.url});
await send({method:'autoStart'},sender);assert.equal(injections.length,1);
await send({method:'setAuto',enabled:false});
assert.equal(registered.length,0);injections=[];
await send({method:'autoStart'},sender);assert.equal(injections.length,0);
await send({method:'setAuto',enabled:true});granted=false;
await send({method:'autoStart'},sender);assert.equal(injections.length,0);
console.log('PASS: permission gate, persistent activation, Docs routing, site exclusions, iframe exclusions and disable');
