const AUTO_ORIGINS = ['http://*/*','https://*/*'];
const AUTO_ID = 'localwriter-auto';
const originOf = value => {try {const url=new URL(value);return ['http:','https:'].includes(url.protocol)?url.origin:null;} catch{return null;}};
async function autoSettings() {return chrome.storage.local.get({autoEnabled:false,disabledSites:[]});}
async function syncAutoRegistration() {
  const state=await autoSettings();
  const allowed=state.autoEnabled && await chrome.permissions.contains({origins:AUTO_ORIGINS});
  const exists=(await chrome.scripting.getRegisteredContentScripts({ids:[AUTO_ID]})).length>0;
  if(allowed && !exists) await chrome.scripting.registerContentScripts([{id:AUTO_ID,matches:AUTO_ORIGINS,js:['auto.js'],runAt:'document_idle',allFrames:true,persistAcrossSessions:true}]);
  if(!allowed && exists) await chrome.scripting.unregisterContentScripts({ids:[AUTO_ID]});
  return allowed;
}
async function autoStart(sender) {
  const state=await autoSettings();
  const origin=originOf(sender.url), topOrigin=originOf(sender.tab?.url);
  if(!state.autoEnabled || !origin || !topOrigin || state.disabledSites.includes(origin) || state.disabledSites.includes(topOrigin)) return;
  if(!await chrome.permissions.contains({origins:AUTO_ORIGINS})) return;
  const docs=sender.url.startsWith('https://docs.google.com/document/');
  if(docs && sender.frameId!==0) return;
  await chrome.scripting.executeScript({target:{tabId:sender.tab.id,frameIds:[sender.frameId]},files:docs?['core.js','docs.js']:['core.js','content.js']});
}
async function refreshAutoTabs(origin=null) {
  for(const tab of await chrome.tabs.query({})) {
    if(origin && originOf(tab.url)!==origin) continue;
    await chrome.tabs.sendMessage(tab.id,{method:'disableTab'}).catch(()=>{});
    if(originOf(tab.url)) await chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:true},files:['auto.js']}).catch(()=>{});
  }
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  if(message?.method==='autoStart') {autoStart(sender).then(()=>reply({ok:true}),()=>reply({ok:false}));return true;}
  if(!['autoSettings','setAuto','toggleSite'].includes(message?.method) || sender.tab) return;
  (async()=>{
    if(message.method==='setAuto') {
      if(message.enabled && !await chrome.permissions.contains({origins:AUTO_ORIGINS})) throw Error('Allow website access to enable automatic checking.');
      await chrome.storage.local.set({autoEnabled:!!message.enabled});await syncAutoRegistration();await refreshAutoTabs();
    }
    if(message.method==='toggleSite') {
      const origin=originOf(message.url);if(!origin) throw Error('This page cannot be enabled.');
      const state=await autoSettings();
      const disabledSites=state.disabledSites.includes(origin)?state.disabledSites.filter(x=>x!==origin):[...state.disabledSites,origin];
      await chrome.storage.local.set({disabledSites});await refreshAutoTabs();
    }
    return {ok:true,...await autoSettings(),permissionGranted:await chrome.permissions.contains({origins:AUTO_ORIGINS})};
  })().then(reply,error=>reply({ok:false,error:error.message}));return true;
});
chrome.runtime.onInstalled.addListener(()=>syncAutoRegistration().catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>syncAutoRegistration().catch(()=>{}));
chrome.permissions.onRemoved.addListener(()=>{syncAutoRegistration().then(()=>refreshAutoTabs()).catch(()=>{});});
