const fs = require('fs');
const path = require('path');
const out = path.resolve(__dirname, '../../Sources/Features/Resources/RichContent');
fs.mkdirSync(out, {recursive: true});
require('esbuild').buildSync({entryPoints: ['entry.js'], bundle: true, minify: true,
  format: 'iife', platform: 'browser', outfile: path.join(out, 'render.js')});
fs.copyFileSync('node_modules/katex/dist/katex.min.css', path.join(out, 'katex.css'));
fs.cpSync('node_modules/katex/dist/fonts', path.join(out, 'fonts'), {recursive: true});
for (const pkg of ['katex','mermaid','esbuild']) {
  const root = path.dirname(require.resolve(pkg + '/package.json'));
  const license = ['LICENSE','LICENSE.md','LICENSE.txt'].find(x => fs.existsSync(path.join(root,x)));
  if (license) fs.copyFileSync(path.join(root,license), path.join(out,pkg + '-LICENSE.txt'));
}
