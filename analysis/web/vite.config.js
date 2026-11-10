import { defineConfig } from 'vite';

// Cross-origin isolation enables SharedArrayBuffer => multi-threaded WASM (CPU fallback ~3-4x faster).
const isolation = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};

export default defineConfig({
  server: { headers: isolation, port: 5174 },
  preview: { headers: isolation, port: 5174 },
  worker: { format: 'es' },
  build: { target: 'es2022' },
  optimizeDeps: { exclude: ['onnxruntime-web'] },
});
