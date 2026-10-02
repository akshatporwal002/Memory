import mermaid from 'mermaid';
import katex from 'katex';
mermaid.initialize({startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
  maxTextSize: 30000, flowchart: {htmlLabels: false}});
window.engramRender = async (kind, source, dark) => {
  const root = document.getElementById('content');
  try {
    if (kind === 'mermaid') {
      mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:dark?'dark':'neutral',
        suppressErrorRendering:true,maxTextSize:30000,flowchart:{htmlLabels:false}});
      const {svg} = await mermaid.render('engram-diagram', source);
      root.innerHTML = svg;
    } else if (kind === 'paragraph') {
      root.replaceChildren();
      const pattern = /\$\$([\s\S]+?)\$\$|\\\(([\s\S]+?)\\\)|\$([^$\n]+?)\$/g;
      let end = 0;
      for (const match of source.matchAll(pattern)) {
        root.append(document.createTextNode(source.slice(end,match.index)));
        const span = document.createElement('span'); root.append(span);
        try { katex.render(match[1]||match[2]||match[3],span,{trust:false,throwOnError:true,maxExpand:1000,maxSize:20,displayMode:!!match[1]}); }
        catch (_) { span.textContent = match[0]; }
        end = match.index + match[0].length;
      }
      root.append(document.createTextNode(source.slice(end)));
    } else {
      katex.render(source, root, {displayMode:kind==='displayMath',trust:false,
        throwOnError:true,maxExpand:1000,maxSize:20,output:'htmlAndMathml'});
    }
  } catch (_) { root.textContent = source; }
  window.webkit?.messageHandlers?.height?.postMessage(Math.min(2000,Math.max(36,root.scrollHeight+16)));
};
