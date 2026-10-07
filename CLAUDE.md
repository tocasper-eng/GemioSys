# CLAUDE.md

GemioSys：ERP 庫存管理系統（PWA + SQL Server）。本檔給在此 repo 工作的 Claude / AI 助理。

## 最高原則
- **極大化 SQL Server、極少化前端**：能用 T-SQL 物件（約束、觸發程序、視圖、函數、預存程序）解決的，絕不寫在前端或 Node。
- `server.js` 只轉送 `POST /api/<程序>` → `EXEC api.<程序> @JSON, @回應 OUTPUT`，不得加入商業邏輯。
- 前端 (`public/app.js`) 只依 `api.畫面定義` 繪製畫面；新增功能優先改 `系統功能表` / `系統欄位設定`，而非改 JS。
- 版面：左側樹狀功能表（`api.功能表`），首頁 = `SY12` 資料表關聯圖。

## 常用指令
```bash
npm run db:deploy   # 執行 01_遷移 + 重新部署 02~06（不清資料）
npm run db:reset    # 刪除並重建整個資料庫（會清空資料！）
npm start           # http://localhost:3000
npm test            # 自動重建 <資料庫>_test + 啟動 port 3999 測試伺服器；必須全綠
```
**正式資料庫 `GemioSys` 已有使用者實際輸入的資料：不要對它執行 `db:reset`；只用 `db:deploy`。** 測試一律走 `npm test`（`GemioSys_test`）。舊庫 `oav00` 已停用（資料已複製到 GemioSys），不要再寫入或刪除。
Zeabur 服務的環境變數 `DB_NAME` 必須是 `GemioSys`。

連線設定在 `設定.json`（已 gitignore，範本為 `設定.example.json`）。**絕不可把 設定.json 或密碼提交到 git。**

## 資料表結構變更（重要）
- `01_資料表.sql` 只在新建資料庫時執行；既有資料庫靠 `01_遷移.sql`（可重複執行、先判斷 `COL_LENGTH` 再 `ALTER`）。
- 改資料表時**兩處都要改**：`01_資料表.sql`（新建用）與 `01_遷移.sql`（升級用），兩者結果必須一致。
- `ALTER ADD` 的欄位會排在表尾；畫面順序用 `系統欄位設定.顯示順序` 調整（預設 = column_id × 10）。

## SQL 撰寫注意
- 資料庫定序 `Chinese_Taiwan_Stroke_CI_AS`（不分大小寫）：變數 `@d` 與 `@D` 視為同一個，會衝突。
- JSON 路徑含中文鍵必須加引號：`N'$."功能代碼"'`，不可寫 `N'$.功能代碼'`。
- `OPENJSON` 的 `[key]` 定序是 `Latin1_General_BIN2`，與欄位名稱比較要加 `COLLATE DATABASE_DEFAULT`。
- 設定表中的排序字串一律經 `api.fn_排序子句` 驗證後才可拼進動態 SQL。
- 觸發程序一律以集合處理（inserted/deleted 多列），過帳用「以來源鍵重算 SUM」，不要用差額加減。
- 超量檢核放在來源表 CHECK 條件；錯誤訊息中文化加在 `系統錯誤訊息`（以約束名稱比對）。
- `api.*` 寫入類程序須保持冪等（`系統請求紀錄` + `sp_getapplock`）。
- 由觸發程序產生的資料（`生產工序明細`、`工單入庫三階`）不要由前端新增；三階的筆數由 `trg_工單入庫三階` 強制 = 入庫數量。
- `途程清單維護.途程編號` = 產品物料編號；工序展開邏輯集中在 `dbo.生產工序_展開`（參數型別 `dbo.工單清單`）。
- 業務規則錯誤 `THROW 50000~50998`（前端不重送）；可重送錯誤 `50999`。

## 完成一段工作前
1. `npm run db:deploy`（或 `db:reset`）成功
2. `npm test` 全部 ✔（含 `系統驗證結果` 15 條違規筆數為 0、下鑽、參照帶入、關聯圖、工序/回報/入庫三階測試）
3. 更新 README.md / CLAUDE.md / SKILL.md / AGENT.md 中受影響的段落
4. commit 並 push 到 `tocasper-eng/GemioSys`，重要里程碑建立 GitHub Release
5. 前端或 `server.js` 有改動時，重新部署 Zeabur（https://gemiosys.zeabur.app，步驟見 README「雲端部署」）

## 規格決定事項
- `物料預留` **不做沖銷機制**（使用者 2026-10-07 決定維持現狀）：預留數量永遠列為需求，不要自行加沖銷。
- `銷售組織維護` / `採購組織維護` 額外加了可空的 `工廠代碼`，讓未交訂單/採購能歸屬工廠（每日供需餘額依工廠計算需要）。
