// UTF-16 offsets match Swift's NSRange and the browser's Range APIs.
(() => {
  const validEdit = (text, e) => Number.isInteger(e.start) && Number.isInteger(e.length) && e.start >= 0 && e.length > 0 && e.start + e.length <= text.length && typeof e.replacement === 'string' && text.slice(e.start,e.start+e.length) === e.original;
  const applyEdits = (text, edits) => {
    const sorted = [...edits].sort((a,b)=>a.start-b.start);
    let end = 0;
    for (const e of sorted) { if (!validEdit(text,e) || e.start < end) throw Error('Outdated or invalid correction. Check again.'); end=e.start+e.length; }
    return sorted.reverse().reduce((s,e)=>s.slice(0,e.start)+e.replacement+s.slice(e.start+e.length),text);
  };
  // A selected phrase must map to exactly one range before replacing it.
  const selectionRange = (text, selected) => {
    if (typeof selected !== 'string' || !selected.trim() || selected.length > 4000) return null;
    const start = text.indexOf(selected);
    if (start < 0 || text.indexOf(selected,start+1) !== -1) return null;
    return {start,length:selected.length,original:selected};
  };
  const preserveSelectionWhitespace = (selected, replacement) => {
    const leading = selected.match(/^\s*/u)[0];
    const trailing = selected.match(/\s*$/u)[0];
    return leading + replacement + trailing;
  };
  globalThis.LocalWriterCore = {validEdit,applyEdits,selectionRange,preserveSelectionWhitespace};
})();
