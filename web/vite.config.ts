import { defineConfig, type Plugin } from "vite";
import { resolve } from "node:path";

// 移除产物 HTML 中的 crossorigin 属性。
// 局域网内手机访问 http://<ip>:8787 时，crossorigin 模块脚本会以 CORS 模式加载，
// 部分环境下导致脚本不执行、页面空白；本服务为可信局域网自托管，去掉更稳妥。
function stripCrossorigin(): Plugin {
  return {
    name: "strip-crossorigin",
    enforce: "post",
    transformIndexHtml(html) {
      return html.replace(/\s+crossorigin/g, "");
    },
  };
}

// 构建产物输出到 Mac 包的 Resources/web，由 Swift 服务静态托管。
export default defineConfig({
  base: "./",
  plugins: [stripCrossorigin()],
  build: {
    // 兼容较旧移动端浏览器内核，避免新语法导致整段模块解析失败。
    target: "es2018",
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
