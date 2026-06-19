import { defineConfig } from "vite";
import { resolve } from "node:path";

// 构建产物输出到 Mac 包的 Resources/web，由 Swift 服务静态托管。
export default defineConfig({
  base: "./",
  build: {
    outDir: "../mac/Sources/VibeCast/Resources/web",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        config: resolve(__dirname, "config.html"),
      },
    },
  },
  server: {
    host: true,
    port: 5173,
  },
});
