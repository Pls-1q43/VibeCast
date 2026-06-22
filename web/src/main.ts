// VibeCast 手机端入口。
import "./ui/styles.css";
import { App } from "./app.ts";
import { applyTheme, readTheme } from "./ui/theme.ts";

applyTheme(readTheme());

const mount = document.getElementById("app");
if (mount) {
  new App(mount).start();
}
