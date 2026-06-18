import { defineConfig } from "vite";

// 构建产物输出到 Mac 包的 Resources/web，由 Swift 服务静态托管。
export default defineConfig({
  base: "./",
  build: {
    outDir: "../mac/Sources/VibeCast/Resources/web",
    emptyOutDir: true,
  },
  server: {
    host: true,
    port: 5173,
  },
});
