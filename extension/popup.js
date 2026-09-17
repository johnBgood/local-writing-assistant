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
    if (tab.url?.startsWith('https://docs.google.com/document/')) throw Error('Google Docs uses a canvas editor. Use selected-text checking below; inline Docs underlines are not available yet.');
    await chrome.scripting.executeScript({target:{tabId:tab.id,allFrames:true},files:['core.js','content.js']});
    $('status').textContent='Enabled for this tab until reload. Focus a text field and pause typing.';
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
