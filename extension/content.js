(() => {
  if (globalThis.localWriterEnabled) { globalThis.localWriterResume?.(); return; }
  globalThis.localWriterEnabled=true;
  // Docs' invisible input is not its document. Never edit it as an ordinary field.
  if(location.hostname==='docs.google.com') return;
  const {validEdit}=globalThis.LocalWriterCore;
  const host=document.createElement('div');host.style.cssText='all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647';
  document.documentElement.append(host);const shadow=host.attachShadow({mode:'closed'});
  const style=document.createElement('style');style.textContent=`*{box-sizing:border-box}.line{position:fixed;border-bottom:2px solid #ec526a;pointer-events:auto;cursor:pointer;background:transparent}.panel{position:fixed;width:340px;padding:8px;background:#fff;color:#252735;border-radius:12px;box-shadow:0 5px 30px #0003;pointer-events:auto;font:14px system-ui}.card{display:block;width:100%;padding:14px;text-align:left;border:0;border-radius:8px;background:#eff1ff;color:#4b60dc;font:600 17px/1.4 system-ui;cursor:pointer;white-space:pre-wrap;overflow-wrap:anywhere}.card:hover{background:#e4e8ff}small{display:block;color:#737e9c;font:12px system-ui;margin-bottom:7px}.dismiss{background:none;border:0;color:#6b7180;font:14px system-ui;padding:12px;cursor:pointer}.status{padding:12px;line-height:1.5}@media(prefers-color-scheme:dark){.panel{background:#232429;color:#eee}.card{background:#2c304a;color:#b9c1ff}}`;
  shadow.append(style);const lines=document.createElement('div');shadow.append(lines);
  let editor=null, snapshot='', edits=[], sequence=0,timer,hoverTimer,panel=null,mirror=null,disabled=false;
  let busy=false,pending=false;
  function field(target){if(!(target instanceof Element))return null;const e=target.closest('textarea,input,[contenteditable="true"],[contenteditable=""]');if(!e||e.readOnly||e.disabled)return null;if(e instanceof HTMLInputElement&&!['text','search','url'].includes(e.type))return null;return e;}
  const text=e=>typeof e.value==='string'?e.value:e.textContent;
  function hide(){panel?.remove();panel=null;clearTimeout(hoverTimer);}
  function reset(){sequence++;edits=[];lines.replaceChildren();hide();}
  const request=async(method,value)=>{const r=await chrome.runtime.sendMessage({method,text:value});if(!r?.ok)throw Error(r?.error||'LocalWriter unavailable');return r;};
  function message(value){hide();if(!editor)return;const r=editor.getBoundingClientRect();panel=document.createElement('div');panel.className='panel';const status=document.createElement('div');status.className='status';status.textContent=value;panel.append(status);finishPanel(r);}
  function finishPanel(rect){const close=document.createElement('button');close.className='dismiss';close.textContent='🗑  Dismiss';close.onclick=hide;panel.append(close);panel.addEventListener('pointerdown',e=>e.preventDefault());shadow.append(panel);const h=panel.getBoundingClientRect().height;panel.style.left=Math.max(8,Math.min(rect.left,innerWidth-348))+'px';panel.style.top=Math.max(8,rect.top-h-5>=8?rect.top-h-5:Math.min(rect.bottom+5,innerHeight-h-8))+'px';}
  function domRange(e,start,length){const walker=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);let n,pos=0,a,b;while(n=walker.nextNode()){const next=pos+n.length;if(!a&&start>=pos&&start<=next)a=[n,start-pos];if(start+length>=pos&&start+length<=next){b=[n,start+length-pos];break;}pos=next;}if(!a||!b)return null;const range=document.createRange();range.setStart(...a);range.setEnd(...b);return range;}
  function boxes(start,length){
    if(!editor?.isConnected)return [];
    const bounds=editor.getBoundingClientRect();let rects=[];
    if(typeof editor.value==='string'){
      mirror?.remove();mirror=document.createElement('div');const css=getComputedStyle(editor);
      for(const property of ['fontFamily','fontSize','fontWeight','fontStyle','lineHeight','letterSpacing','textTransform','textIndent','paddingTop','paddingRight','paddingBottom','paddingLeft','borderTopWidth','borderRightWidth','borderBottomWidth','borderLeftWidth','boxSizing','wordSpacing','tabSize'])mirror.style[property]=css[property];
      Object.assign(mirror.style,{position:'fixed',left:bounds.left+'px',top:bounds.top+'px',width:bounds.width+'px',height:bounds.height+'px',borderStyle:'solid',borderColor:'transparent',overflow:'hidden',visibility:'hidden',pointerEvents:'none',whiteSpace:editor.tagName==='INPUT'?'pre':'pre-wrap',overflowWrap:'break-word'});
      const span=document.createElement('span');span.textContent=snapshot.slice(start,start+length);mirror.append(document.createTextNode(snapshot.slice(0,start)),span,document.createTextNode(snapshot.slice(start+length)||'\u200b'));document.documentElement.append(mirror);mirror.scrollTop=editor.scrollTop;mirror.scrollLeft=editor.scrollLeft;rects=[...span.getClientRects()];mirror.remove();mirror=null;
    }else{const r=domRange(editor,start,length);if(r)rects=[...r.getClientRects()];}
    return rects.map(r=>({left:Math.max(r.left,bounds.left),right:Math.min(r.right,bounds.right),top:Math.max(r.top,bounds.top),bottom:Math.min(r.bottom,bounds.bottom)})).filter(r=>r.right>r.left&&r.bottom>r.top);
  }
  function draw(){lines.replaceChildren();if(!editor||text(editor)!==snapshot)return;
    for(const edit of edits){if(!validEdit(snapshot,edit))continue;
      for(const match of snapshot.slice(edit.start,edit.start+edit.length).matchAll(/\S+/gu))for(const r of boxes(edit.start+match.index,match[0].length)){
        const line=document.createElement('div');line.className='line';line.style.cssText=`left:${r.left}px;top:${r.bottom-3}px;width:${r.right-r.left}px;height:6px`;
        line.onmouseenter=()=>{clearTimeout(hoverTimer);hoverTimer=setTimeout(()=>show(edit,r),200);};line.onmouseleave=()=>clearTimeout(hoverTimer);line.onclick=()=>show(edit,r);lines.append(line);
      }
    }
  }
  function show(edit,rect){hide();panel=document.createElement('div');panel.className='panel';const button=document.createElement('button');button.className='card';const caption=document.createElement('small');caption.textContent='Suggested correction';button.append(caption,document.createTextNode(edit.replacement||'Remove this text'));button.onclick=()=>apply(edit);panel.append(button);
    const word=LocalWriterCore.wordAt(snapshot,edit.start);
    if(word){const add=document.createElement('button');add.className='dismiss';add.textContent='Add “'+word+'” to dictionary';add.onclick=async()=>{try{await request('addWord',word);reset();schedule();}catch(e){message(e.message);}};panel.append(add);}
    finishPanel(rect);}
  function apply(edit){
    if(!editor?.isConnected||text(editor)!==snapshot||!validEdit(snapshot,edit)){message('The draft changed. Check it again.');return;}
    const expected=snapshot.slice(0,edit.start)+edit.replacement+snapshot.slice(edit.start+edit.length),target=editor;
    target.focus();
    if(typeof target.value==='string')target.setSelectionRange(edit.start,edit.start+edit.length);
    else{const range=domRange(target,edit.start,edit.length);if(!range){message('Could not select that text.');return;}const selection=getSelection();selection.removeAllRanges();selection.addRange(range);}
    // Browser editing command preserves contenteditable structure and undo history.
    document.execCommand('insertText',false,edit.replacement);
    if(text(target)===snapshot&&typeof target.value==='string'){
      target.setRangeText(edit.replacement,edit.start,edit.start+edit.length,'end');target.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertReplacementText',data:edit.replacement}));
    }
    if(text(target)!==expected){message('This editor did not accept the replacement. Use the extension panel to copy the suggestion.');return;}
    reset();schedule();
  }
  function schedule(){clearTimeout(timer);if(!disabled)timer=setTimeout(check,700);}
  async function check(){
    if(busy){pending=true;return;}if(!editor||!document.hasFocus())return;
    const target=editor,value=text(target);if(!value.trim()||value.length>4000){if(value.length>4000)message('This field is over 4,000 characters. Check a selection in the extension panel.');return;}
    const run=sequence;snapshot=value;busy=true;
    try{const r=await request('analyze',value);if(run===sequence&&target===editor&&text(target)===value&&document.hasFocus()){edits=r.edits;draw();}}
    catch(e){if(run===sequence)message(e.message);}
    finally{busy=false;if(pending){pending=false;schedule();}}
  }
  document.addEventListener('focusin',e=>{const next=field(e.target);if(next===editor)return;reset();editor=next;if(editor)schedule();},true);
  document.addEventListener('input',e=>{if(field(e.target)!==editor)return;reset();schedule();},true);
  document.addEventListener('scroll',()=>{hide();draw();},true);window.addEventListener('resize',()=>{hide();draw();});window.addEventListener('blur',()=>{lines.replaceChildren();hide();});window.addEventListener('focus',()=>{draw();schedule();});
  chrome.runtime.onMessage.addListener((m,_sender,reply)=>{if(m.method==='preferencesChanged'){reset();schedule();}if(m.method==='disableTab'){disabled=true;reset();reply({ok:true});}});
  globalThis.localWriterResume=()=>{disabled=false;schedule();};
  editor=field(document.activeElement);if(editor)schedule();
})();
