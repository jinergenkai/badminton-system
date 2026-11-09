// Copies the exported ONNX models (../models/web/...) and onnxruntime-web's wasm runtime into public/.
// Models are not committed to git (analysis/.gitignore ignores models/) — run this before dev/build.
import { cpSync, existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(here, '..');
const models = resolve(web, '..', 'models', 'web');

const MODELS = {
  'tracknet_fp16.onnx': join(models, 'out', 'tracknet_fp16.onnx'),
  'tracknet_fp32.onnx': join(models, 'out', 'tracknet_fp32.onnx'),
  'rtmo_s.onnx': join(models, 'dl', 'x', 'rtmo-s', 'end2end.onnx'),
};

mkdirSync(join(web, 'public', 'models'), { recursive: true });
for (const [name, src] of Object.entries(MODELS)) {
  const dst = join(web, 'public', 'models', name);
  if (!existsSync(src)) {
    if (existsSync(dst)) continue;
    console.error(`missing model ${src} — see analysis/web/README.md`);
    process.exit(1);
  }
  if (!existsSync(dst) || statSync(dst).size !== statSync(src).size) {
    cpSync(src, dst);
    console.log('model', name, (statSync(dst).size / 1e6).toFixed(1), 'MB');
  }
}

const ortDist = join(web, 'node_modules', 'onnxruntime-web', 'dist');
mkdirSync(join(web, 'public', 'ort'), { recursive: true });
for (const f of readdirSync(ortDist)) {
  // the webgpu build of onnxruntime-web loads the asyncify variant
  if (/^ort-wasm-simd-threaded\.asyncify\.(wasm|mjs)$/.test(f)) cpSync(join(ortDist, f), join(web, 'public', 'ort', f));
}
