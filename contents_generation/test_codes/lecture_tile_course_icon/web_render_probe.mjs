import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const webapp = new URL('../../../webapp/', import.meta.url);
const require = createRequire(new URL('package.json', webapp));
const { build } = require('esbuild');

const mocks = {
  useLanguage: "export const useLanguage = () => ({ locale: 'en', t: (key) => key });",
  useFirstTopicImagePath: 'export const useFirstTopicImagePath = () => null;',
  useArtifactImage: "export const useArtifactImage = (path) => path === 'ready.webp' ? '/fixture.webp' : null;",
};
const bundle = await build({
  stdin: {
    loader: 'jsx',
    resolveDir: fileURLToPath(webapp),
    contents: String.raw`
      import assert from 'node:assert/strict';
      import React from 'react';
      import { renderToStaticMarkup } from 'react-dom/server';
      import { MemoryRouter } from 'react-router-dom';
      import { LectureTile } from './src/components/LectureTile';

      function render(courseId, icon, imagePath) {
        const lecture = {
          id: 'lecture',
          title: 'Fixture lecture',
          course_id: courseId,
          lecture_datetime: '2026-11-18T12:00:00Z',
          metadata: imagePath ? { cover_thumb_path: imagePath } : null,
        };
        return renderToStaticMarkup(
          <MemoryRouter><LectureTile lecture={lecture} courseIcon={icon} /></MemoryRouter>,
        );
      }
      assert.match(render('course', 'science'), />science<\/span>/);
      assert.match(render('course'), />school<\/span>/);
      assert.match(render(null, 'science'), /class="tile-svg"/);
      assert.match(render('course', 'science', 'pending.webp'), />science<\/span>/);
      const withImage = render('course', 'science', 'ready.webp');
      assert.match(withImage, /src="\/fixture.webp"/);
      assert.doesNotMatch(withImage, /lecture-tile-fallback-icon/);
      console.log('Web lecture tile render: five cases passed.');
    `,
  },
  bundle: true,
  packages: 'external',
  platform: 'node',
  write: false,
  plugins: [{
    name: 'local-fixtures',
    setup(builder) {
      builder.onResolve({ filter: /(?:LanguageContext|useFirstTopicImagePath|useArtifactImage)$/ }, ({ path }) => ({
        path: path.endsWith('LanguageContext') ? 'useLanguage' : path.split('/').at(-1),
        namespace: 'local-fixtures',
      }));
      builder.onLoad({ filter: /.*/, namespace: 'local-fixtures' }, ({ path }) => ({
        contents: mocks[path],
      }));
    },
  }],
});
new Function('require', bundle.outputFiles[0].text)(require);
