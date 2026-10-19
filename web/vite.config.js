import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev: proxy /api về serverless chạy thử (dev-server.mjs cũ ở cổng 3210) nếu cần.
// Prod: Vercel tự chạy web/api/*.js như serverless functions, không qua Vite.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:3210",
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
