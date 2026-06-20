# 卸载 VibeCast

## 1. 退出 App

在菜单栏点击“退出 VibeCast”。如果开启过“登录时自动启动”，建议先在菜单栏关闭该开关。

## 2. 删除 App

如果你使用源码打包：

```bash
rm -rf dist/VibeCast.app
```

如果你把 App 移到了其他位置，也可以直接拖入废纸篓。

## 3. 删除配置与本地数据

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

这会删除目标应用配置和配对令牌等本地状态。

## 4. 移除辅助功能授权

打开：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

取消勾选并移除 VibeCast。

## 5. 清理登录项

如果曾开启开机自启，但 App 内开关已经不可用，可在：

```text
系统设置 → 通用 → 登录项
```

移除 VibeCast。

## 6. 清理手机端数据

在 Android Chrome 中删除该站点数据，或移除主屏幕图标。手机端草稿和配对令牌只保存在浏览器本地存储中。
