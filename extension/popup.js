if(location.search.includes('review=1')) document.documentElement.classList.add('review');
let output = '';
const $ = id => document.getElementById(id);
const request = async (method,text) => {
  const response = await chrome.runtime.sendMessage({method,text});
  if (!response?.ok) throw Error(response?.error || 'LocalWriter did not respond.');
  return response;
};
request('ping').then(()=>$('connection').textContent='✓ Connected to LocalWriter on your Mac').catch(e=>$('connection').textContent=e.message);
async function activeTab(){return (await chrome.tabs.query({active:true,currentWindow:true}))[0];}
$('enable').onclick=async()=>{
  try {
    const tab=await activeTab();
    const docs=tab.url?.startsWith('https://docs.google.com/document/');
    await chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:!docs},files:docs?['core.js','docs.js']:['core.js','content.js']});
    $('status').textContent=docs?'Enabled for visible Google Docs text. Close this panel to see suggestions.':'Enabled for this tab until reload. Focus a text field and pause typing.';
  } catch(e){$('status').textContent=e.message;}
};
$('selection').onclick=async()=>{
  try {
    const tab=await activeTab();
    const frames=await chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:true},func:()=>{
      const e=document.activeElement;
      if(e instanceof HTMLInputElement && !['text','search','url'].includes(e.type)) return '';
      if(e && typeof e.selectionStart==='number') return e.value.slice(e.selectionStart,e.selectionEnd);
      return window.getSelection()?.toString()||'';
    }});
    const value=frames.map(x=>x.result).find(x=>x?.trim());
    if(!value) throw Error('No accessible selection. Copy your selected text and paste it into this panel.');
    $('draft').value=value.slice(0,4000);$('status').textContent='Selection loaded. Choose Check text or Improve wording.';
  }catch(e){$('status').textContent=e.message;}
};
let generation=0;
$('draft').oninput=()=>{generation++;output='';$('copy').hidden=true;$('results').replaceChildren();};
async function check(method){
  const text=$('draft').value, run=++generation;
  $('status').textContent='Checking with Qwen3 on your Mac…';$('results').replaceChildren();$('copy').hidden=true;
  $('check').disabled=$('rewrite').disabled=true;
  try{
    const result=await request(method,text);
    if(run!==generation || $('draft').value!==text) return;
    if(method==='rewrite') output=result.rewrite;
    else output=LocalWriterCore.applyEdits(text,result.edits);
    $('status').textContent=output===text?'No changes suggested.':'Review the suggestion, then copy it back to your document.';
    if(output!==text){const button=document.createElement('button');button.className='suggestion';const caption=document.createElement('small');caption.textContent=method==='rewrite'?'Suggested rewrite · Click to copy':'Corrected text · Click to copy';button.append(caption,document.createTextNode(output));button.onclick=copy;$('results').append(button);$('copy').hidden=false;}
  }catch(e){$('status').textContent=e.message;}
  finally{$('check').disabled=$('rewrite').disabled=false;}
}
async function copy(){try{await navigator.clipboard.writeText(output);$('status').textContent='Copied. Paste over your selected text in the document.';}catch{$('status').textContent='Could not copy. Select the suggestion and copy it manually.';}}
$('check').onclick=()=>check('analyze');$('rewrite').onclick=()=>check('rewrite');$('copy').onclick=copy;
if(location.search.includes('review=1')) chrome.storage.session.get('reviewText').then(async data=>{$('draft').value=data.reviewText||'';await chrome.storage.session.remove('reviewText');$('enable').hidden=$('disable').hidden=$('selection').hidden=true;});

$('disable').onclick=async()=>{try{const tab=await activeTab();await chrome.tabs.sendMessage(tab.id,{method:'disableTab'});$('status').textContent='Underlines disabled for this tab.';}catch{$('status').textContent='Underlines were not enabled on this tab.';}};

activeTab().then(async tab=>{
  if(!tab.url?.startsWith('https://docs.google.com/document/')) return;
  try {const state=await chrome.tabs.sendMessage(tab.id,{method:'docsStatus'});if(state?.ok) $('status').textContent=state.status;} catch {}
});

function renderPreferences(settings) {
  $('language').value=settings.language;
  $('dictionary-list').replaceChildren();
  for(const word of settings.words) {
    const button=document.createElement('button');button.className='secondary';button.textContent='Remove “'+word+'”';
    button.onclick=async()=>{try{renderPreferences(await request('removeWord',word));}catch(e){$('status').textContent=e.message;}};
    $('dictionary-list').append(button);
  }
}
request('settings').then(renderPreferences).catch(e=>$('status').textContent=e.message);
$('language').onchange=async()=>{try{renderPreferences(await request('setLanguage',$('language').value));$('status').textContent='Language updated for the Mac app and Chrome.';}catch(e){$('status').textContent=e.message;}};
$('add-word').onclick=async()=>{try{renderPreferences(await request('addWord',$('dictionary-word').value.trim()));$('dictionary-word').value='';$('status').textContent='Word added to your shared dictionary.';}catch(e){$('status').textContent=e.message;}};

let autoState;
async function renderAuto() {
  autoState=await chrome.runtime.sendMessage({method:'autoSettings'});
  if(!autoState?.ok) throw Error(autoState?.error||'Could not read activation settings.');
  const enabled=autoState.autoEnabled && autoState.permissionGranted;
  $('automatic').textContent=enabled?'Turn off automatic checking':'Enable automatically on websites';
  $('automatic-status').textContent=enabled?'Automatic checking is on, including new tabs and page reloads.':'Automatic checking needs permission to read text in website editors. Analysis stays on your Mac.';
  const tab=await activeTab();let origin;
  try{const url=new URL(tab.url);if(['http:','https:'].includes(url.protocol))origin=url.origin;}catch{}
  $('site-toggle').hidden=!enabled||!origin;
  if(origin)$('site-toggle').textContent=(autoState.disabledSites.includes(origin)?'Enable for ':'Disable for ')+new URL(origin).hostname;
}
$('automatic').onclick=async()=>{
  try {
    const enabled=!(autoState?.autoEnabled && autoState?.permissionGranted);
    if(enabled && !await chrome.permissions.request({origins:['http://*/*','https://*/*']})) { $('status').textContent='Website access was not granted. Manual activation remains available.';return; }
    const result=await chrome.runtime.sendMessage({method:'setAuto',enabled});if(!result?.ok)throw Error(result?.error);
    await renderAuto();
  }catch(e){$('status').textContent=e.message;}
};
$('site-toggle').onclick=async()=>{try{const tab=await activeTab();const r=await chrome.runtime.sendMessage({method:'toggleSite',url:tab.url});if(!r?.ok)throw Error(r?.error);await renderAuto();}catch(e){$('status').textContent=e.message;}};
renderAuto().catch(e=>$('status').textContent=e.message);
