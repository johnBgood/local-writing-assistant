const HOST = 'com.johnbgood.localwriter';
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => chrome.contextMenus.create({id:'check', title:'Check with LocalWriter', contexts:['selection']}));
});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (!['ping','analyze','rewrite','settings','setLanguage','addWord','removeWord'].includes(message?.method)) return;
  if (!['ping','settings'].includes(message.method) && (typeof message.text !== 'string' || !message.text.trim() || message.text.length > 4000)) {
    reply({ok:false,error:'Use 1–4,000 characters.'}); return;
  }
  chrome.runtime.sendNativeMessage(HOST, {method:message.method,text:message.text}, response => {
    const error = chrome.runtime.lastError;
    if(!error && response?.ok && ['setLanguage','addWord','removeWord'].includes(message.method)) chrome.tabs.query({},tabs=>{for(const tab of tabs) chrome.tabs.sendMessage(tab.id,{method:'preferencesChanged'}).catch(()=>{});});
    reply(error ? {ok:false,error:'LocalWriter connection failed. Run scripts/install-extension-host.py and keep the local model running. '+error.message} : response);
  });
  return true;
});
chrome.contextMenus.onClicked.addListener(async info => {
  if (info.menuItemId !== 'check' || !info.selectionText) return;
  await chrome.storage.session.set({reviewText:info.selectionText.slice(0,4000)});
  await chrome.tabs.create({url:chrome.runtime.getURL('popup.html?review=1')});
});
