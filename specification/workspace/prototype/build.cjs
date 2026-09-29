// Assembles the self-contained study page from src/ and the shared model files.
// node specification/workspace/prototype/build.cjs
const fs = require('fs'), path = require('path'), here = __dirname, src = f => path.join(here, 'src', f);
const font = fs.readFileSync(path.join(here, '../../flow/prototype/font.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//, '');
const head = fs.readFileSync(src('head.html'), 'utf8').replace('/*FONT*/', font);
const data = ['model.js', 'cases.js', 'register.js'].map(f => '<script>' + fs.readFileSync(path.join(here, f), 'utf8') + '</script>').join('\n');
const app = ['e1.js', 'e2.js', 'e3.js', 'e4.js', 'e5.js'].map(f => fs.readFileSync(src(f), 'utf8')).join('\n');
const html = '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' + head + '\n</head>\n<body>\n' + fs.readFileSync(src('body.html'), 'utf8') + data + '\n<script>' + app + '</script>\n</body>\n</html>\n';
fs.writeFileSync(path.join(here, 'index.html'), html);
console.log(`index.html ${html.length} bytes`);
