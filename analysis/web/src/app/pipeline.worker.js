// Runs the analysis (track -> players -> identity -> hits -> 3D flights -> analytics) off the UI thread.
import { runPipeline } from './pipeline.js';

self.onmessage = ({ data }) => {
  try {
    const result = runPipeline(data.input, data.opts, (label, frac) => self.postMessage({ type: 'progress', label, frac }));
    self.postMessage({ type: 'done', result });
  } catch (e) {
    self.postMessage({ type: 'error', message: String(e?.stack || e) });
  }
};
