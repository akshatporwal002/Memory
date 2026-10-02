import mermaid from 'mermaid';
import katex from 'katex';
mermaid.initialize({startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
  maxTextSize: 30000, flowchart: {htmlLabels: false}});
window.engramRender = async (kind, source, dark, fontSize = 17) => {
  const root = document.getElementById('content');
  try {
    if (kind === 'mermaid') {
      if (/%%\s*\{|^\s*click\s/im.test(source)) throw new Error('Active diagram directives are disabled');
      mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:dark?'dark':'neutral',
        suppressErrorRendering:true,maxTextSize:30000,themeVariables:{fontSize:`${Math.min(80,Math.max(12,fontSize))}px`},flowchart:{htmlLabels:false}});
      const {svg} = await mermaid.render('engram-diagram', source);
      root.innerHTML = svg;
    } else if (kind === 'paragraph' || kind === 'richParagraph') {
      if (kind === 'richParagraph') root.innerHTML = source;
      else { root.replaceChildren(); root.append(document.createTextNode(source)); }
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      const nodes = [];
      while (walker.nextNode()) if (!walker.currentNode.parentElement.closest('code,pre')) nodes.push(walker.currentNode);
      const pattern = /\$\$([\s\S]+?)\$\$|\\\(([\s\S]+?)\\\)|\$([^$\n]+?)\$/g;
      for (const node of nodes) {
      const source = node.textContent, fragment = document.createDocumentFragment();
      let end = 0;
      for (const match of source.matchAll(pattern)) {
        fragment.append(document.createTextNode(source.slice(end,match.index)));
        const span = document.createElement('span'); fragment.append(span);
        try { katex.render(match[1]||match[2]||match[3],span,{trust:false,throwOnError:true,maxExpand:1000,maxSize:20,displayMode:!!match[1]}); }
        catch (_) { span.textContent = match[0]; }
        end = match.index + match[0].length;
      }
      fragment.append(document.createTextNode(source.slice(end))); node.replaceWith(fragment);
      }
    } else {
      katex.render(source, root, {displayMode:kind==='displayMath',trust:false,
        throwOnError:true,maxExpand:1000,maxSize:20,output:'htmlAndMathml'});
    }
  } catch (_) { root.classList.add('fallback'); root.textContent = source; }
  window.webkit?.messageHandlers?.height?.postMessage(Math.min(2000,Math.max(36,root.scrollHeight+16)));
};
