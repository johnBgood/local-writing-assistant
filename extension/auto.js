// A small bootstrap runs on granted sites; the worker checks saved exclusions
// before injecting any editor reader or contacting the local model.
chrome.runtime.sendMessage({method:'autoStart'}).catch(()=>{});
