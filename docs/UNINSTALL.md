# 卸载 VibeCast

1. 菜单栏 **退出 VibeCast**（先关闭开机自启开关，再退出）。

2. 删除 App：
   ```bash
   rm -rf /path/to/VibeCast.app   # 或拖到废纸篓
   ```

3. 删除配置与数据：
   ```bash
   rm -rf "$HOME/Library/Application Support/VibeCast"
   defaults delete VibeCast 2>/dev/null   # 配对令牌等
   ```

4. 移除辅助功能授权：
   **系统设置 → 隐私与安全性 → 辅助功能**，取消勾选并移除 VibeCast。

5. 若曾开启开机自启但未在 App 内关闭，可在
   **系统设置 → 通用 → 登录项** 中移除 VibeCast。

6. 手机端：在 Chrome 中清除该站点数据 / 移除主屏幕图标即可（草稿仅存于手机本地）。
