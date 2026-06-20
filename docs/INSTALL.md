# 安装与使用

VibeCast 由一个 macOS 菜单栏 App 和一个手机端网页组成。Mac 负责托管网页、维护 WebSocket 连接、聚焦目标应用、写入文本和执行发送；Android 手机只负责打开网页并使用输入法输入文字。

## 系统要求

- macOS 13 Ventura 及以上
- Xcode Command Line Tools，Swift 5.9+
- Node.js 18+
- Android Chrome
- Mac 与 Android 手机处于同一局域网
- macOS 辅助功能权限

## 0.1 发布包构建

```bash
# 首次构建先安装前端依赖
cd web && npm install && cd ..

# 构建真实 Web 资源、Release Swift 可执行文件、本地签名 .app 和 zip
bash scripts/build_app.sh
```

打包产物位于：

```text
dist/VibeCast.app
dist/VibeCast-0.1.0-macos.zip
```

0.1 使用本地签名（ad-hoc 或 `CODESIGN_IDENTITY` 指定的本机证书），不做 Apple Developer ID 公证。首次打开时如果 macOS 安全提示拦截，请在系统设置中允许本地应用运行。

如果 npm 报 `genie-safe-delete` preload 相关错误，改用：

```bash
NODE_OPTIONS="" npm run build
```

## 首次启动

1. 双击或运行：

   ```bash
   open dist/VibeCast.app
   ```

2. 菜单栏出现 `VC` 图标。
3. 如果系统提示辅助功能授权，打开“系统设置 → 隐私与安全性 → 辅助功能”，勾选 VibeCast。
4. 回到菜单栏，确认显示“辅助功能：已授权”。

未授权时，VibeCast 可以托管页面，但不能安全地激活应用、聚焦输入框、写入文本或发送。

## 配置通用目标

1. 菜单栏点击“打开配置页面…”。
2. 按顶部首次安装清单确认辅助功能权限、启用需要的 App，并为启用目标填写或选择 Bundle ID。
3. 需要更多目标时，使用“添加自定义 App”，可从运行中的应用自动填入名称和 Bundle ID。
4. 常用项保存即可；聚焦策略、写入方式、发送方式在每个目标的“高级设置”里。
5. 点击“测试”，确认目标应用能被激活、聚焦并写入测试文本。

配置详情见 [目标应用配置](CONFIGURATION.md)。

## 手机连接

1. 菜单栏点击“复制访问地址（含令牌）”。
2. 得到类似地址：

   ```text
   http://192.168.x.x:8787/?token=...
   ```

3. 用 Android Chrome 打开该地址。
4. 可通过 Chrome 菜单“添加到主屏幕”，获得更接近 App 的入口。

配对令牌会保存在手机浏览器 localStorage。重新生成令牌后，旧手机页面需要使用新地址重新连接。

## 日常使用

1. 手机打开 VibeCast 页面。
2. 点击目标应用卡片里的文本框。
3. Mac 激活并聚焦对应目标应用。
4. Android 输入法出现后，手动点击输入法里的语音按钮。
5. 说话，识别文字进入手机文本框。
6. 文本实时镜像到 Mac 目标输入框。
7. 在手机上继续修改、删除或补充文字。
8. 点击“发送”，Mac 确认最终文本已同步后执行发送动作。

网页只能通过标准聚焦行为唤起输入法，不能直接命令微信输入法进入语音模式。

## 停止服务

- 菜单栏点击“退出 VibeCast”即可停止服务。
- 菜单栏点击“重启服务”会重启 HTTP/WebSocket 服务。
- “登录时自动启动”用于控制开机自启。

## 验证安装

```bash
cd web
NODE_OPTIONS="" npm test
NODE_OPTIONS="" npm run build

cd ../mac
swift test
```

发布前完整检查见 [0.1 发布检查清单](RELEASE_0_1_CHECKLIST.md)。
