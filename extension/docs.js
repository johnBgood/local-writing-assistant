// Google Docs keeps document text in positioned SVG accessibility annotations.
// Never treat its offscreen typing iframe as the document's value.
(() => {
  if (location.hostname !== 'docs.google.com' || window !== top) return;
  if (globalThis.localWriterDocs) { globalThis.localWriterDocs.resume(); return; }
  const {validEdit} = LocalWriterCore;
  const host = document.createElement('div');
  host.style.cssText = 'all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647';
  document.documentElement.append(host);
  const root = host.attachShadow({mode:'closed'});
  const style = document.createElement('style');
  style.textContent = `*{box-sizing:border-box}.line{position:fixed;height:7px;border-bottom:2px solid #ec526a;pointer-events:auto;cursor:pointer}.panel{position:fixed;width:340px;padding:8px;border-radius:12px;background:white;color:#252735;box-shadow:0 5px 30px #0003;pointer-events:auto;font:14px/1.5 system-ui}.card{display:block;width:100%;border:0;border-radius:8px;background:#eff1ff;color:#4b60dc;text-align:left;padding:14px;font:600 17px/1.4 system-ui;cursor:pointer;white-space:pre-wrap;overflow-wrap:anywhere}.card:hover{background:#e4e8ff}small{display:block;font:12px system-ui;color:#737e9c;margin-bottom:7px}.dismiss{border:0;background:none;padding:12px;color:#6b7180;font:14px system-ui;cursor:pointer}.status{padding:10px}`;
  const lines = document.createElement('div'); root.append(style, lines);
  const measure = document.createElement('canvas').getContext('2d');
  let disabled=false, timer, hover, panel, snapshot=null, edits=[], generation=0, busy=false, pending=false, applying=false;
  let status='Waiting for Google Docs text…';
  const pause = ms => new Promise(resolve=>setTimeout(resolve,ms));
  function hide() { clearTimeout(hover); panel?.remove(); panel=null; }
  function clear() { generation++; snapshot=null; edits=[]; lines.replaceChildren(); hide(); }
  function read() {
    const runs=[]; let text='';
    for(const group of document.querySelectorAll('.kix-canvas-tile-text [role="paragraph"]')) {
      let paragraph='', parts=[];
      for(const node of group.querySelectorAll('rect[aria-label][data-font-css]')) {
        const label=node.getAttribute('aria-label');
        if(!label) continue;
        const rect=node.getBoundingClientRect();
        // Only analyze rendered, visible paragraphs; scrolling discovers more.
        if(rect.bottom<0 || rect.top>innerHeight || rect.right<0 || rect.left>innerWidth) continue;
        const last=parts.at(-1);
        if(last && !/\s$/.test(paragraph) && !/^\s/.test(label) &&
          (Math.abs(rect.top-last.rect.top)>rect.height/2 || rect.left-last.rect.right>1)) paragraph+=' ';
        parts.push({node,rect,start:paragraph.length,length:label.length,label}); paragraph+=label;
      }
      if(!paragraph.trim()) continue;
      if(text) text+='\n';
      if(text.length+paragraph.length>4000) break;
      for(const part of parts) runs.push({...part,start:part.start+text.length});
      text+=paragraph;
    }
    return {text,runs};
  }
  function rangeBoxes(value,start,length) {
    const result=[];
    for(const run of value.runs) {
      const from=Math.max(start,run.start)-run.start, to=Math.min(start+length,run.start+run.length)-run.start;
      if(to<=from || !run.node.isConnected) continue;
      const r=run.node.getBoundingClientRect();
      measure.font=run.node.getAttribute('data-font-css');
      const width=measure.measureText(run.label).width;
      if(!width) continue;
      // Fit measured advances to the actual transformed SVG annotation width.
      const left=r.left+r.width*measure.measureText(run.label.slice(0,from)).width/width;
      const right=r.left+r.width*measure.measureText(run.label.slice(0,to)).width/width;
      result.push({left,right,top:r.top,bottom:r.bottom});
    }
    return result;
  }
  function show(message,rect,edit) {
    hide(); panel=document.createElement('div');panel.className='panel';
    const card=document.createElement(edit?'button':'div');card.className=edit?'card':'status';
    if(edit) {const caption=document.createElement('small');caption.textContent='Suggested correction';card.append(caption);card.onclick=()=>apply(edit);}
    card.append(document.createTextNode(message));panel.append(card);
    const dismiss=document.createElement('button');dismiss.className='dismiss';dismiss.textContent='🗑  Dismiss';dismiss.onclick=hide;panel.append(dismiss);
    panel.addEventListener('mousedown',e=>e.preventDefault());root.append(panel);
    const height=panel.getBoundingClientRect().height;
    panel.style.left=Math.max(8,Math.min(rect.left,innerWidth-348))+'px';
    panel.style.top=Math.max(8,rect.top-height-5>8?rect.top-height-5:Math.min(rect.bottom+5,innerHeight-height-8))+'px';
  }
  function notice(message) {status=message;show(message,{left:innerWidth-360,top:80,bottom:80});}
  function draw() {
    lines.replaceChildren();if(disabled || !snapshot) return;
    const current=read();if(current.text!==snapshot.text) return;
    for(const edit of edits) {
      if(!validEdit(snapshot.text,edit)) continue;
      for(const word of edit.original.matchAll(/\S+/gu)) for(const r of rangeBoxes(current,edit.start+word.index,word[0].length)) {
        const line=document.createElement('div');line.className='line';
        line.style.cssText=`left:${r.left}px;top:${r.bottom-5}px;width:${r.right-r.left}px`;
        line.onmouseenter=()=>{clearTimeout(hover);hover=setTimeout(()=>show(edit.replacement||'Remove this text',r,edit),150);};
        line.onmouseleave=()=>clearTimeout(hover);line.onclick=()=>show(edit.replacement||'Remove this text',r,edit);lines.append(line);
      }
    }
  }
  function schedule() {clearTimeout(timer);if(!disabled && !applying) timer=setTimeout(check,800);}
  async function check() {
    if(disabled || applying) return;
    if(busy) {pending=true;return;}
    const value=read();
    if(!value.text.trim()) {status='Google Docs has not exposed its text annotations. Inline checking is unavailable in this document.';return;}
    if(snapshot?.text===value.text) {draw();return;}
    clear();snapshot=value;const run=generation;busy=true;status='Checking visible text with your local model…';
    try {
      const result=await chrome.runtime.sendMessage({method:'analyze',text:value.text});
      if(run!==generation || disabled || read().text!==value.text) return;
      if(!result?.ok) throw Error(result?.error||'LocalWriter did not respond.');
      edits=result.edits.filter(e=>validEdit(value.text,e));status=edits.length?`${edits.length} suggestions in visible text`:'No changes suggested.';draw();
    } catch(e) {if(run===generation)notice(e.message);}
    finally {busy=false;if(pending){pending=false;schedule();}}
  }
  function inputTarget() {
    const doc=document.querySelector('.docs-texteventtarget-iframe')?.contentDocument;
    return {doc,target:doc?.querySelector('[contenteditable="true"]')};
  }
  function mouse(type,point,buttons) {
    const target=document.elementFromPoint(point.x,point.y);
    if(!target || !target.closest('.kix-appview-editor')) throw Error('The document moved. Try the suggestion again.');
    target.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window,clientX:point.x,clientY:point.y,button:0,buttons,detail:1}));
  }
  async function apply(edit) {
    if(applying) return;
    let before=read();
    if(before.text!==snapshot?.text || !validEdit(before.text,edit)) {snapshot=null;notice('The document changed. Checking again…');schedule();return;}
    const rects=rangeBoxes(before,edit.start,edit.length);
    if(!rects.length) return;
    applying=true;hide();lines.replaceChildren();
    try {
      const first=rects[0], last=rects.at(-1);
      const start={x:first.left+.2,y:(first.top+first.bottom)/2};
      const end={x:last.right-.2,y:(last.top+last.bottom)/2};
      mouse('mousedown',start,1);mouse('mousemove',end,1);mouse('mouseup',end,0);
      await pause(80);
      const {target}=inputTarget();
      if(!target) throw Error('Could not find Google Docs’ typing surface.');
      // Ask Docs' copy handler for the real model selection without touching the
      // system clipboard. A mismatch aborts before any document mutation.
      const copied=new DataTransfer();
      target.dispatchEvent(new ClipboardEvent('copy',{bubbles:true,cancelable:true,clipboardData:copied}));
      await pause(30);
      const selected=copied.getData('text/plain');
      if(selected!==edit.original) throw Error('Google Docs did not confirm the exact selection. No text was replaced.');
      if(read().text!==before.text) throw Error('The document changed during selection. Try again.');
      const data=new DataTransfer();data.setData('text/plain',edit.replacement);
      target.dispatchEvent(new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:data}));
      const expected=LocalWriterCore.applyEdits(before.text,[edit]);
      for(let i=0;i<15;i++) {await pause(100);if(read().text===expected) {status='Replacement applied.';snapshot=null;return;}}
      throw Error('Google Docs did not confirm the replacement. Check the document before retrying.');
    } catch(e) {notice(e.message);}
    finally {applying=false;draw();schedule();}
  }
  const observer=new MutationObserver(records=>{
    if(applying || disabled) return;
    const relevant=records.some(record=>record.target.closest?.('.kix-canvas-tile-text') ||
      [...record.addedNodes,...record.removedNodes].some(node=>node.nodeType===1 && (node.matches?.('.kix-canvas-tile-text') || node.querySelector?.('.kix-canvas-tile-text'))));
    if(!relevant) return;
    const current=read();
    if(current.text!==snapshot?.text) {clear();schedule();} else draw();
  });
  const surface=document.querySelector('.kix-appview-editor');
  if(surface) observer.observe(surface,{subtree:true,childList:true,attributes:true,attributeFilter:['aria-label','transform','width','height']});
  document.addEventListener('scroll',()=>{hide();draw();schedule();},true);
  window.addEventListener('resize',()=>{hide();draw();schedule();});
  chrome.runtime.onMessage.addListener((message,_sender,reply)=>{
    if(message.method==='disableTab') {disabled=true;clear();clearTimeout(timer);reply({ok:true});}
    if(message.method==='docsStatus') reply({ok:true,status,annotations:read().runs.length,suggestions:edits.length});
  });
  globalThis.localWriterDocs={resume(){disabled=false;snapshot=null;schedule();}};
  if(!read().text) notice('Google Docs has not exposed its text annotations. Inline checking is unavailable in this document.');
  schedule();
})();
