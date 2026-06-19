# VibeCast 安装与使用

VibeCast 把 Android 手机变成 macOS 的远程语音文本输入面板：语音识别由 Android 输入法完成，
Mac 端负责把手机文本镜像到目标应用并执行发送。

## 系统要求

- macOS 13 (Ventura) 及以上
- Mac 与 Android 手机处于同一局域网
- Android 端：最新版 Chrome + 微信输入法（首批验收环境）

## 一、从源码构建

需要 Xcode 命令行工具（Swift 5.9+）与 Node 18+。

```bash
# 1. 构建前端（产物输出到 Mac 包内 Resources/web）
cd web
npm install
npm run build

# 2. 打包 macOS App
cd ..
bash scripts/build_app.sh
# 产物：dist/VibeCast.app
```

> 若 npm 报 `genie-safe-delete` preload 错误，命令前加 `NODE_OPTIONS=""`。

## 二、首次启动与授权

1. 双击 `dist/VibeCast.app` 启动，菜单栏出现 `VC` 图标。
2. 首次启动会弹出辅助功能授权提示。点击进入
   **系统设置 → 隐私与安全性 → 辅助���能**，勾选 VibeCast。
   - 未授权时无法激活应用 / 写入文本 / 发送，手机端会显示「Mac 缺少辅助功能权限」。
3. 菜单栏点 **打开配置页面…**，为四个目标填写 Bundle ID（可从「快速选择」下拉里挑当前运行的应用），
   设置聚焦与发送方式，点 **保存**，再点 **测试目标** 验证。

## 三、手机连接

1. 菜单栏点 **复制访问地址（含令牌）**，得到形如
   `http://192.168.x.x:8787/?token=xxxx` 的地址。
2. 用 Android Chrome 打开该地址（令牌已包含在 URL 中，完成配对）。
3. 可「添加到主屏幕」获得类原生体验。

## 四、日常使用

1. 手机打开 VibeCast 页面，点某个应用卡片的文本框。
2. Mac 自动激活并聚焦该应用输入框。
3. 在微信输入法中点语音按钮说话，识别文字进入手机文本框。
4. 文字实时镜像到 Mac 对应应用；可在手机上继续修改。
5. 点 **发送**，Mac 确认最终文本已同步后执行发送。

> 提示：网页只能唤起输入法，无法自动进入微信输入法的语音模式，需手动点语音按钮。

## 五、停止与退出

- 菜单栏 **退出 VibeCast** 即停止服务并退出。
- 菜单栏 **重启服务** 可在不退出 App 的情况下重启网络服务。
- **登录时自动启动** 开关控制开机自启。

## 六、卸载

见 `docs/UNINSTALL.md`。
