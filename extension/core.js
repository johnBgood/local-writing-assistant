// UTF-16 offsets match Swift's NSRange and the browser's Range APIs.
(() => {
  const validEdit = (text, e) => Number.isInteger(e.start) && Number.isInteger(e.length) && e.start >= 0 && e.length > 0 && e.start + e.length <= text.length && typeof e.replacement === 'string' && text.slice(e.start,e.start+e.length) === e.original;
  const applyEdits = (text, edits) => {
    const sorted = [...edits].sort((a,b)=>a.start-b.start);
    let end = 0;
    for (const e of sorted) { if (!validEdit(text,e) || e.start < end) throw Error('Outdated or invalid correction. Check again.'); end=e.start+e.length; }
    return sorted.reverse().reduce((s,e)=>s.slice(0,e.start)+e.replacement+s.slice(e.start+e.length),text);
  };
  globalThis.LocalWriterCore = {validEdit,applyEdits};
})();
