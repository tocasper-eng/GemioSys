# AGENT.md

給在本 repo 工作的 AI 代理（Claude Code、Codex、其他 agent）的操作守則。專案說明見 [README.md](README.md)，詳細規範見 [CLAUDE.md](CLAUDE.md)，擴充食譜見 [SKILL.md](SKILL.md)。

## 角色分工
| 層 | 負責 | 禁止 |
|---|---|---|
| SQL Server (`db/`) | 所有商業規則、過帳、檢核、報表、畫面中繼資料 | — |
| Node (`server.js`) | 把 JSON 轉交 `api.*` 預存程序、HTTP 狀態碼對應 | 任何商業邏輯、直接下 SQL |
| 前端 (`public/`) | 依 `api.畫面定義` 繪製（左側樹狀功能表、首頁關聯圖）、離線佇列、快取 | 計算數量、檢核規則、寫死欄位 |

## 工作流程
1. 讀 `CLAUDE.md` 的注意事項（定序不分大小寫、JSON 中文路徑要加引號）。
2. 修改 `db/*.sql`（02 之後的物件皆為 `CREATE OR ALTER`，可重複部署）。改資料表結構要同時改 `01_資料表.sql` 與 `01_遷移.sql`，不要靠 reset 升級。
3. `npm run db:deploy`（會執行遷移）；`npm run db:reset` 會清空資料，只在確認後使用。
4. 執行 `npm test`（自動建立 `<資料庫>_test` 與測試伺服器，不影響正式資料），必須全部 ✔。
5. 更新 README.md / CLAUDE.md / SKILL.md / AGENT.md。
6. commit（訊息說明「為什麼」），push 到 `tocasper-eng/GemioSys`；里程碑建立 Release。
7. 前端或 `server.js` 有改動時重新部署 Zeabur（README「雲端部署」）；資料庫物件只靠 `db:deploy`。

## 共用資料庫注意
`oav00` 是共用的遠端資料庫，**已有使用者資料**。`db:reset` 會 DROP DATABASE，執行前確認沒有其他人或其他 agent 正在使用；發現資料庫物件與本 repo 不一致時，先停下來詢問使用者，不要直接覆蓋。

## 安全
- `設定.json` 含資料庫密碼，已 gitignore，不得提交或貼到 issue / PR / 對話紀錄。
- repo 為公開；提交前檢查 diff 不含主機位址、帳密、個資。
