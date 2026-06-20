# VibeCast 0.1 发布检查清单

## 构建

- [ ] 已为本次版本写好 Release Notes：`docs/releases/0.1.0.md`
- [ ] Release Notes 覆盖用户可见变化、安装/升级注意事项、已知限制
- [ ] `cd web && NODE_OPTIONS="" npm test`
- [ ] `cd web && NODE_OPTIONS="" npm run typecheck`
- [ ] `cd web && NODE_OPTIONS="" npm run build`
- [ ] `cd mac && swift test`
- [ ] `bash scripts/build_app.sh`
- [ ] `dist/VibeCast.app` 已本地签名
- [ ] `dist/VibeCast-0.1.0-macos.zip` 已生成
- [ ] App 包内 `index.html`、`config.html`、`assets/` 均存在且不是 placeholder

## 本机验收

- [ ] 首次启动菜单栏显示 `VC`
- [ ] 未授权辅助功能时，页面能连接但写入/发送被拒绝并显示原因
- [ ] 授权辅助功能后，配置页可打开、保存、回读配置
- [ ] 重新生成配对令牌后，旧手机页面断开，新 URL 可重新连接
- [ ] 诊断日志导出不包含完整文本、token 或剪贴板内容

## 通用目标烟测

- [ ] 用 TextEdit 或另一个安全测试输入框配置一个目标
- [ ] 选择目标后能聚焦并写入测试文本
- [ ] Android Chrome 打开含 token 地址后能连接
- [ ] Android 输入法输入中文、英文、标点、粘贴长文本均可同步
- [ ] 点击发送前会等待最新 revision ack
- [ ] `sendMode=none` 不触发发送动作
- [ ] 开启 `clearAfterSend` 后，发送成功会清空手机草稿

## 风险场景

- [ ] 未配置 Bundle ID 时，配置页测试按钮阻止测试
- [ ] `allowSelectAllReplace=false` 时，全选替换写入被拒绝
- [ ] 错误 token 返回失败并断开
- [ ] 断网/重连后不会自动发送旧草稿
- [ ] 旧标签页不是活动控制端时，写入/发送被拒绝
