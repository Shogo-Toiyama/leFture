import { createRequire } from 'node:module';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const webapp = new URL('../../../webapp/', import.meta.url);
const resolveDir = fileURLToPath(webapp);
const require = createRequire(new URL('package.json', webapp));
const { build } = require('esbuild');
const started = performance.now();
const fixtures = {
  LanguageContext: 'export const useLanguage = () => ({ t: (key) => key });',
  env: 'export const BACKEND_API_URL = "https://fixture.invalid";',
  supabase: 'export const supabase = new Proxy({}, { get() { throw Error("Unexpected backend request"); } });',
};

const bundle = await build({
  absWorkingDir: resolveDir,
  stdin: {
    resolveDir,
    loader: 'jsx',
    contents: `
      import React from 'react';
      import { renderToStaticMarkup } from 'react-dom/server';
      import { ChatMessageItem } from './src/components/chat/ChatMessageItem';
      import { CitationPreviewModal } from './src/components/chat/CitationPreviewModal';
      import { AnnotatedMarkdown } from './src/components/annotations/AnnotatedMarkdown';

      const source = '**サンク(thunk)**と**（遅延評価）**を使う';
      const citation = { n: 1, source_type: 'web', label: 'Example', url: 'https://fixture.invalid', snippet: source };
      const renderChat = (content, status = 'complete') => renderToStaticMarkup(
        <ChatMessageItem message={{ id: 'fixture', role: 'assistant', content, status, citations: [citation] }}
                         onOpenCitation={() => {}} />
      );
      const boldSpans = (html) => [...html.matchAll(/<strong>(.*?)<\\/strong>/g)].map((match) => match[1]);
      const expected = ['サンク(thunk)', '（遅延評価）'];
      const checkSpans = (html) => {
        const actual = boldSpans(html);
        if (JSON.stringify(actual) !== JSON.stringify(expected)) throw Error(JSON.stringify(actual));
      };

      const cases = [
        ['Completed reply', () => checkSpans(renderChat(source))],
        ['Streaming reply', () => checkSpans(renderChat(source, 'streaming'))],
        ['Care message', () => checkSpans(renderChat(source, 'crisis'))],
        ['Citation preview', () => checkSpans(renderToStaticMarkup(
          <CitationPreviewModal citation={citation} onClose={() => {}} />
        ))],
        ['Shared annotated Markdown', () => checkSpans(renderToStaticMarkup(
          <AnnotatedMarkdown markdown={source} rawMarkdown={source} annotations={[]} blockIdx={null} />
        ))],
        ['Non-bracket punctuation, inline code, math and citation', () => {
          const html = renderChat('これは**（答え）、**です。つぎは**太字。**です。 \`**(code)**\` $x^2$ ⟦1⟧');
          if (!html.includes('<strong>太字</strong>。です')) throw Error('Punctuation formatting changed');
          if (!html.includes('<code>**(code)**</code>')) throw Error('Inline code changed');
          if (!html.includes('class="katex"')) throw Error('Math did not render');
          if (!html.includes('class="chat-cite-marker"')) throw Error('Citation did not render');
          if (!html.includes('<strong>（答え）</strong>、です')) throw Error('Mixed brackets and punctuation changed');
        }],
      ];
      const lines = cases.map(([name, run]) => {
        try { run(); return 'PASS ' + name; }
        catch (error) { return 'FAIL ' + name + ': ' + error.message; }
      });
      export default lines;
    `,
  },
  bundle: true,
  platform: 'node',
  format: 'cjs',
  write: false,
  loader: { '.css': 'empty' },
  plugins: [{
    name: 'local-chat-fixtures',
    setup(builder) {
      builder.onResolve({ filter: /\/(LanguageContext|supabase|env)$/ }, ({ path }) => ({
        path: path.split('/').at(-1), namespace: 'fixture',
      }));
      builder.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
        contents: fixtures[path], resolveDir, loader: 'js',
      }));
    },
  }],
});
const module = { exports: {} };
new Function('module', 'exports', 'require', bundle.outputFiles[0].text)(module, module.exports, require);
const lines = module.exports.default;
lines.push(`Elapsed: ${Math.round(performance.now() - started)} ms`);
const summary = `${lines.join('\n')}\n`;
console.log(summary);
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
await writeFile(new URL(`results/${stamp}.log`, import.meta.url), summary);
if (lines.some((line) => line.startsWith('FAIL'))) process.exitCode = 1;
