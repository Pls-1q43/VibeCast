// VibeCast 手机端入口。
import "./ui/styles.css";
import { App } from "./app.ts";

const mount = document.getElementById("app");
if (mount) {
  new App(mount).start();
}
