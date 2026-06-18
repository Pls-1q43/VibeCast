# VibeCast

把 Android 手机变成 macOS 的远程语音文本输入面板。语音识别由 Android 输入法完成，
Mac 端负责文本镜像、目标应用聚焦与发送。详见 `PRD.md` 与 `DEVELOPMENT_PLAN.md`。

## 项目结构

- `mac/` — Swift 菜单栏服务（HTTP + WebSocket + Accessibility）
- `web/` — 手机端前端（TypeScript + Vite）
- `shared/protocol.md` — 前后端协议唯一对齐来源
- `docs/` — 安装 / 配置 / 已知限制 / 卸载

## 构建

前端（产物输出到 `mac/.../Resources/web`）：
```bash
cd web && npm install && npm run build
```

Mac 服务：
```bash
cd mac && swift build && swift test
```

> 注：若 npm 报 `genie-safe-delete` preload 错误，前面加 `NODE_OPTIONS=""`。

## 进度

- [x] M0 项目骨架 + 协议定义（双端构建通过、协议单测通过）
- [ ] M1 手机前端
- [ ] M2 Mac 服务 + WebSocket
- [ ] M3 应用激活 + 聚焦
- [ ] M4 文本镜像
- [ ] M5 两阶段发送
- [ ] M6 健壮性
- [ ] M7 配置 + 开机启动 + 四应用适配
- [ ] M8 测试 + 联调 + 交付
