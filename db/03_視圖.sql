/* =========================================================
   OAV ERP — 03 報表視圖
   ========================================================= */

/* ---------- SD ---------- */
CREATE OR ALTER VIEW 已訂未出明細 AS
SELECT d.訂單編號, d.訂單項次, h.訂單日期, h.銷售組織, h.客戶編號, d.物料編號,
       d.訂單數量, d.出貨數量, d.退回數量,
       d.訂單數量 - d.出貨數量 + d.退回數量 AS 未出數量,
       d.預定交期, d.備註說明
FROM 客戶訂單明細 d
JOIN 客戶訂單主檔 h ON h.訂單編號 = d.訂單編號
WHERE d.訂單數量 - d.出貨數量 + d.退回數量 > 0;
GO

CREATE OR ALTER VIEW 訂單出退分析 AS
SELECT N'出貨' AS 異動類別, h.出貨編號 AS 單據編號, d.出貨項次 AS 單據項次, h.出貨日期 AS 單據日期,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       d.出貨數量 AS 數量, d.出貨數量 AS 淨出貨量, d.備註說明
FROM 訂單出貨明細 d JOIN 訂單出貨主檔 h ON h.出貨編號 = d.出貨編號
UNION ALL
SELECT N'退回', h.退回編號, d.退回項次, h.退回日期,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       d.退回數量, -d.退回數量, d.備註說明
FROM 出貨退回明細 d JOIN 出貨退回主檔 h ON h.退回編號 = d.退回編號;
GO

/* ---------- MM ---------- */
CREATE OR ALTER VIEW 已採未交明細 AS
SELECT d.採購編號, d.採購項次, h.採購日期, h.採購組織, h.廠商編號, d.物料編號,
       d.採購數量, d.收貨數量, d.退回數量,
       d.採購數量 - d.收貨數量 + d.退回數量 AS 未交數量,
       d.預定交期, d.備註說明
FROM 廠商採購明細 d
JOIN 廠商採購主檔 h ON h.採購編號 = d.採購編號
WHERE d.採購數量 - d.收貨數量 + d.退回數量 > 0;
GO

CREATE OR ALTER VIEW 採購收退分析 AS
SELECT N'收貨' AS 異動類別, h.收貨編號 AS 單據編號, d.收貨項次 AS 單據項次, h.收貨日期 AS 單據日期,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       d.收貨數量 AS 數量, d.收貨數量 AS 淨收貨量, d.備註說明
FROM 採購收貨明細 d JOIN 採購收貨主檔 h ON h.收貨編號 = d.收貨編號
UNION ALL
SELECT N'退回', h.退回編號, d.退回項次, h.退回日期,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       d.退回數量, -d.退回數量, d.備註說明
FROM 收貨退回明細 d JOIN 收貨退回主檔 h ON h.退回編號 = d.退回編號;
GO

/* ---------- IM：即時庫存（依倉庫） ---------- */
CREATE OR ALTER VIEW 庫存現況 AS
SELECT w.工廠代碼, t.倉庫代碼, t.物料編號, SUM(t.異動數量) AS 庫存數量
FROM 庫存異動明細 t
JOIN 工廠倉庫維護 w ON w.倉庫代碼 = t.倉庫代碼
GROUP BY w.工廠代碼, t.倉庫代碼, t.物料編號;
GO

/* ---------- PP：庫存在途明細（未來供給 / 需求，依工廠） ----------
   供給：採購在途（採購組織.工廠代碼）、工單產出（生產數量 − 入庫數量，產品物料）
   需求：訂單需求（銷售組織.工廠代碼）、工單用料（應領 − 已領）、物料預留 */
CREATE OR ALTER VIEW 庫存在途明細 AS
SELECT N'採購在途' AS 供需類別, ISNULL(g.工廠代碼, N'未指定') AS 工廠代碼, v.採購編號 AS 單據編號, v.採購項次 AS 單據項次, v.物料編號,
       ISNULL(v.預定交期, v.採購日期) AS 供需日期, v.未交數量 AS 供給數量, 0 AS 需求數量
FROM 已採未交明細 v LEFT JOIN 採購組織維護 g ON g.採購組織 = v.採購組織
UNION ALL
SELECT N'訂單需求', ISNULL(g.工廠代碼, N'未指定'), v.訂單編號, v.訂單項次, v.物料編號,
       ISNULL(v.預定交期, v.訂單日期), 0, v.未出數量
FROM 已訂未出明細 v LEFT JOIN 銷售組織維護 g ON g.銷售組織 = v.銷售組織
UNION ALL
SELECT N'工單產出', 工廠代碼, 工單編號, N'', 產品物料,
       ISNULL(預定完工, 工單日期), 生產數量 - 入庫數量, 0
FROM 生產工單主檔
WHERE 生產數量 > 入庫數量
UNION ALL
SELECT N'工單用料', h.工廠代碼, d.工單編號, d.工單項次, d.物料編號,
       ISNULL(d.預定領料, h.工單日期), 0, d.應領用量 - d.已領用量
FROM 生產工單明細 d JOIN 生產工單主檔 h ON h.工單編號 = d.工單編號
WHERE d.應領用量 > d.已領用量
UNION ALL
SELECT N'物料預留', h.工廠代碼, d.預留編號, d.預留項次, d.物料編號,
       ISNULL(d.預定交期, h.預留日期), 0, d.預留數量
FROM 物料預留明細 d JOIN 物料預留主檔 h ON h.預留編號 = d.預留編號;
GO

/* ---------- PP：每日供需餘額（依 工廠 + 物料 逐日滾算）----------
   第一列 在手數量 = 目前庫存；之後每列 在手數量 = 前一列 可用數量
   每列：在手數量 + 供給入庫 − 需求入庫 = 可用數量 */
CREATE OR ALTER VIEW 每日供需餘額 AS
WITH 庫存 AS (
    SELECT 工廠代碼, 物料編號, SUM(庫存數量) AS 數量 FROM 庫存現況 GROUP BY 工廠代碼, 物料編號
), 日計 AS (
    SELECT 工廠代碼, 物料編號, 供需日期, SUM(供給數量) AS 供給入庫, SUM(需求數量) AS 需求入庫
    FROM (SELECT 工廠代碼, 物料編號, 供需日期, 供給數量, 需求數量 FROM 庫存在途明細
          UNION ALL   -- 有庫存但無在途的物料也列出今日一列
          SELECT 工廠代碼, 物料編號, CAST(GETDATE() AS date), 0, 0 FROM 庫存) x
    GROUP BY 工廠代碼, 物料編號, 供需日期
), 滾算 AS (
    SELECT d.*, ISNULL(s.數量, 0) + SUM(d.供給入庫 - d.需求入庫)
               OVER (PARTITION BY d.工廠代碼, d.物料編號 ORDER BY d.供需日期 ROWS UNBOUNDED PRECEDING) AS 可用數量
    FROM 日計 d LEFT JOIN 庫存 s ON s.工廠代碼 = d.工廠代碼 AND s.物料編號 = d.物料編號
)
SELECT 工廠代碼, 物料編號, 供需日期, 可用數量 - 供給入庫 + 需求入庫 AS 在手數量, 供給入庫, 需求入庫, 可用數量
FROM 滾算;
GO

/* ---------- 系統：過帳驗證（驗證準則逐條檢核，違規筆數應全為 0）---------- */
CREATE OR ALTER VIEW 系統驗證結果 AS
WITH r AS (
    SELECT 1 AS 序號, N'訂單出貨 → 客戶訂單明細.出貨數量' AS 檢核項目, N'以 訂單編號+訂單項次 累加' AS 規則,
           (SELECT COUNT(*) FROM 客戶訂單明細 o WHERE o.出貨數量 <> ISNULL((SELECT SUM(出貨數量) FROM 訂單出貨明細 d WHERE d.訂單編號 = o.訂單編號 AND d.訂單項次 = o.訂單項次), 0)) AS 違規筆數
    UNION ALL SELECT 2, N'出貨退回 → 客戶訂單明細.退回數量', N'以 訂單編號+訂單項次 累加',
           (SELECT COUNT(*) FROM 客戶訂單明細 o WHERE o.退回數量 <> ISNULL((SELECT SUM(退回數量) FROM 出貨退回明細 d WHERE d.訂單編號 = o.訂單編號 AND d.訂單項次 = o.訂單項次), 0))
    UNION ALL SELECT 3, N'採購收貨 → 廠商採購明細.收貨數量', N'以 採購編號+採購項次 累加',
           (SELECT COUNT(*) FROM 廠商採購明細 o WHERE o.收貨數量 <> ISNULL((SELECT SUM(收貨數量) FROM 採購收貨明細 d WHERE d.採購編號 = o.採購編號 AND d.採購項次 = o.採購項次), 0))
    UNION ALL SELECT 4, N'收貨退回 → 廠商採購明細.退回數量', N'以 採購編號+採購項次 累加',
           (SELECT COUNT(*) FROM 廠商採購明細 o WHERE o.退回數量 <> ISNULL((SELECT SUM(退回數量) FROM 收貨退回明細 d WHERE d.採購編號 = o.採購編號 AND d.採購項次 = o.採購項次), 0))
    UNION ALL SELECT 5, N'工單入庫 → 生產工單主檔.入庫數量', N'以 工單編號 累加',
           (SELECT COUNT(*) FROM 生產工單主檔 o WHERE o.入庫數量 <> ISNULL((SELECT SUM(入庫數量) FROM 工單入庫明細 d WHERE d.工單編號 = o.工單編號), 0))
    UNION ALL SELECT 6, N'工單領料 → 生產工單明細.已領用量', N'以 工單編號+物料編號 累加',
           (SELECT COUNT(*) FROM 生產工單明細 o WHERE o.已領用量 <> ISNULL((SELECT SUM(領料數量) FROM 工單領料明細 d WHERE d.工單編號 = o.工單編號 AND d.物料編號 = o.物料編號), 0))
    UNION ALL SELECT 7, N'每日庫存餘額 逐列平衡', N'期初數量 + 本期入庫 − 本期出庫 = 期末數量',
           (SELECT COUNT(*) FROM 每日庫存餘額 WHERE 期初數量 + 本期入庫 - 本期出庫 <> 期末數量)
    UNION ALL SELECT 8, N'每日庫存餘額 前後銜接', N'本日期初 = 前一異動日期末（首日期初 = 0）',
           (SELECT COUNT(*) FROM (SELECT 期初數量, LAG(期末數量, 1, 0) OVER (PARTITION BY 倉庫代碼, 物料編號 ORDER BY 餘額日期) AS 前期末 FROM 每日庫存餘額) x WHERE 期初數量 <> 前期末)
    UNION ALL SELECT 9, N'每日庫存餘額 與 庫存異動明細 一致', N'最後一日期末 = 異動數量總和',
           (SELECT COUNT(*) FROM 庫存現況 s
            OUTER APPLY (SELECT TOP (1) 期末數量 FROM 每日庫存餘額 b WHERE b.倉庫代碼 = s.倉庫代碼 AND b.物料編號 = s.物料編號 ORDER BY 餘額日期 DESC) b
            WHERE ISNULL(b.期末數量, 0) <> s.庫存數量)
    UNION ALL SELECT 10, N'每日供需餘額 逐列平衡', N'在手數量 + 供給入庫 − 需求入庫 = 可用數量',
           (SELECT COUNT(*) FROM 每日供需餘額 WHERE 在手數量 + 供給入庫 - 需求入庫 <> 可用數量)
    UNION ALL SELECT 11, N'每日供需餘額 前後銜接', N'本日在手 = 前一日可用（首日在手 = 目前庫存）',
           (SELECT COUNT(*) FROM (SELECT v.在手數量, LAG(v.可用數量, 1, ISNULL(s.數量, 0)) OVER (PARTITION BY v.工廠代碼, v.物料編號 ORDER BY v.供需日期) AS 前可用
                                  FROM 每日供需餘額 v
                                  LEFT JOIN (SELECT 工廠代碼, 物料編號, SUM(庫存數量) AS 數量 FROM 庫存現況 GROUP BY 工廠代碼, 物料編號) s
                                         ON s.工廠代碼 = v.工廠代碼 AND s.物料編號 = v.物料編號) x WHERE 在手數量 <> 前可用)
    UNION ALL SELECT 12, N'工單入庫物料 = 工單產品物料', N'工單入庫明細.物料編號 = 生產工單主檔.產品物料',
           (SELECT COUNT(*) FROM 工單入庫明細 d JOIN 生產工單主檔 o ON o.工單編號 = d.工單編號 WHERE d.物料編號 <> o.產品物料)
)
SELECT 序號, 檢核項目, 規則, 違規筆數, IIF(違規筆數 = 0, N'✔ 通過', N'✘ 不符') AS 結果 FROM r;
GO
