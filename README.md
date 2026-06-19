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

打包可分发 App（产物 `dist/VibeCast.app`）：
```bash
bash scripts/build_app.sh
```

## 测试

```bash
cd mac && swift test     # Swift 单元测试（40）
cd web && npm test       # 前端单元测试（vitest，11）
```

> 注：若 npm 报 `genie-safe-delete` preload 错误，前面加 `NODE_OPTIONS=""`。

## 文档

- `docs/INSTALL.md` — 安装、授权、连接、使用、停止
- `docs/CONFIGURATION.md` — 目标 Profile 字段与四应用建议
- `docs/KNOWN_LIMITS.md` — 已知限制与安全边界
- `docs/UNINSTALL.md` — 卸载

## 进度

- [x] M0 项目骨架 + 协议定义
- [x] M1 手机前端（四目标卡片 / 草稿 / 组合输入 / WS 客户端）
- [x] M2 Mac 服务 + WebSocket + 配对 + 菜单栏
- [x] M3 应用激活 + 聚焦 + 目标绑定校验
- [x] M4 文本镜像（AXValue 直写 + 剪贴板降级 + Revision 校验）
- [x] M5 两阶段发送 + 幂等
- [x] M6 健壮性（脱敏日志 + 诊断导出 + 睡眠唤醒）
- [x] M7 配置页 + 开机启动 + Notion 适配
- [x] M8 测试套件 + 文档 + 打包（真机联调待执行）
