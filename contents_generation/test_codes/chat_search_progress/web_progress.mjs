import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const webapp = new URL('../../../webapp/', import.meta.url);
const resolveDir = fileURLToPath(webapp);
const require = createRequire(new URL('package.json', webapp));
const { build } = require('esbuild');

const fixtures = {
  LanguageContext: `
    import { translations } from './src/i18n/translations';
    export const useLanguage = () => ({
      t: (key, params) => Object.entries(params ?? {}).reduce(
        (copy, [name, value]) => copy.replace('{' + name + '}', value),
        translations[globalThis.testChatLanguage][key],
      ),
    });
  `,
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
      import { translations } from './src/i18n/translations';
      import { parseSseEvent } from './src/lib/chat';

      const cases = [
        ['pending search target', {}, 'chatStageThinking'],
        ['web query', { searchDetail: ['web'], searchTarget: 'web', searchQuery: 'electric ferries' },
            'chatStageSearchingWebWithQuery'],
        ['web without query', { searchDetail: ['web'] }, 'chatStageSearchingWeb'],
        ['lecture lookup', { searchDetail: ['lectures'] }, 'chatStageSearching'],
        ['chat lookup', { searchDetail: ['chats'] }, 'chatStageSearchingChats'],
        ['organizing', { searchDetail: ['organizing'] }, 'chatStageOrganizingMaterials'],
      ];

      const results = [];
      for (const language of ['en', 'ja']) {
        globalThis.testChatLanguage = language;
        const label = language === 'ja' ? '変数のスコープを確認中' : 'Checking variable scope';
        const fallback = language === 'ja' ? '考え中...' : 'Thinking...';
        const event = parseSseEvent('event: status\\ndata: ' +
          JSON.stringify({ stage: 'reasoning', progress_label: label }));
        const renderReasoning = (progressLabel, content = '') => renderToStaticMarkup(<ChatMessageItem
          message={{ id: 'fixture', role: 'assistant', status: 'streaming', stage: event.stage,
            content, progressLabel }}
          onOpenCitation={() => {}}
        />);
        const before = renderReasoning(undefined);
        const during = renderReasoning(event.progress_label);
        const after = renderReasoning(event.progress_label, 'Response');
        const expectedReasoning = before.includes('aria-label="' + fallback + '"') &&
          during.includes('aria-label="' + label + '"') &&
          during.includes('chat-thinking-label slabel') && !during.includes(fallback) &&
          !during.includes('chat-thinking-thought-box') && !after.includes(label);
        results.push((expectedReasoning ? 'PASS ' : 'FAIL ') + language + ' inline reasoning progress');
        for (const [name, fields, key] of cases) {
          const expected = translations[language][key].replace('{query}', fields.searchQuery ?? '');
          const markup = renderToStaticMarkup(<ChatMessageItem
            message={{ id: 'fixture', role: 'assistant', content: '', status: 'streaming', stage: 'searching', ...fields }}
            onOpenCitation={() => {}}
          />);
          const visible = markup.replace(/&quot;/g, '"');
          const wrongLectureLabel = key !== 'chatStageSearching' && visible.includes(translations[language].chatStageSearching);
          results.push((visible.includes(expected) && !wrongLectureLabel ? 'PASS ' : 'FAIL ') + language + ' ' + name);
        }
      }
      export default results;
    `,
  },
  bundle: true,
  platform: 'node',
  format: 'cjs',
  write: false,
  loader: { '.css': 'empty' },
  plugins: [{
    name: 'local-status-fixtures',
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
for (const result of module.exports.default) console.log(result);
if (module.exports.default.some((result) => result.startsWith('FAIL'))) process.exitCode = 1;
