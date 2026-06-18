// VibeCast 手机端入口。
// M0 阶段：仅验证 Vite 构建链路与协议类型可用。M1 起实现四目标卡片 UI。

import { PROTOCOL_VERSION, TARGET_IDS } from "./ws/protocol.ts";

const app = document.getElementById("app");
if (app) {
  app.textContent = `VibeCast protocol v${PROTOCOL_VERSION} — targets: ${TARGET_IDS.join(", ")}`;
}
