/* =========================================================
   GemioERP — 02 觸發程序（過帳機制）
   1. 單據明細 新增/更改/刪除 → 來源單累計量 = SUM(單據明細數量)（以來源鍵重算，永遠自我校正）
      超出、超收、超領、超退 由來源表 CHECK 條件擋下並整筆回滾
   2. 單據明細 → 庫存異動明細（入庫為正、出庫為負）
   3. 單據主檔 日期變更 → 同步 庫存異動明細.異動日期
   4. 庫存異動明細 → 重算 每日庫存餘額（期初 + 本期入庫 − 本期出庫 = 期末，期末不可為負）
   5. 生產工單主檔 / 途程清單 → 展開 生產工序明細；工單回報明細 → 已報人時 / 已報機時
   6. 工單入庫明細 → 依入庫數量展開 / 收合 工單入庫三階
   ========================================================= */

CREATE OR ALTER TRIGGER trg_庫存異動明細_餘額 ON 庫存異動明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k TABLE (倉庫代碼 nvarchar(20), 物料編號 nvarchar(20), 起日 date, PRIMARY KEY (倉庫代碼, 物料編號));
    INSERT @k
    SELECT 倉庫代碼, 物料編號, MIN(異動日期)
    FROM (SELECT 倉庫代碼, 物料編號, 異動日期 FROM inserted
          UNION ALL SELECT 倉庫代碼, 物料編號, 異動日期 FROM deleted) x
    GROUP BY 倉庫代碼, 物料編號;
    IF @@ROWCOUNT = 0 RETURN;

    DELETE b FROM 每日庫存餘額 b
    JOIN @k k ON k.倉庫代碼 = b.倉庫代碼 AND k.物料編號 = b.物料編號 AND b.餘額日期 >= k.起日;

    WITH 前餘 AS (
        SELECT k.倉庫代碼, k.物料編號,
               ISNULL((SELECT SUM(t.異動數量) FROM 庫存異動明細 t
                       WHERE t.倉庫代碼 = k.倉庫代碼 AND t.物料編號 = k.物料編號 AND t.異動日期 < k.起日), 0) AS 數量
        FROM @k k
    ), 日計 AS (
        SELECT t.倉庫代碼, t.物料編號, t.異動日期,
               SUM(IIF(t.異動數量 > 0,  t.異動數量, 0)) AS 本期入庫,
               SUM(IIF(t.異動數量 < 0, -t.異動數量, 0)) AS 本期出庫
        FROM 庫存異動明細 t
        JOIN @k k ON k.倉庫代碼 = t.倉庫代碼 AND k.物料編號 = t.物料編號 AND t.異動日期 >= k.起日
        GROUP BY t.倉庫代碼, t.物料編號, t.異動日期
    ), 累計 AS (
        SELECT d.*, p.數量 + SUM(d.本期入庫 - d.本期出庫)
                     OVER (PARTITION BY d.倉庫代碼, d.物料編號 ORDER BY d.異動日期 ROWS UNBOUNDED PRECEDING) AS 期末數量
        FROM 日計 d JOIN 前餘 p ON p.倉庫代碼 = d.倉庫代碼 AND p.物料編號 = d.物料編號
    )
    INSERT 每日庫存餘額 (餘額日期, 倉庫代碼, 物料編號, 期初數量, 本期入庫, 本期出庫, 期末數量)
    SELECT 異動日期, 倉庫代碼, 物料編號, 期末數量 - 本期入庫 + 本期出庫, 本期入庫, 本期出庫, 期末數量
    FROM 累計;
END
GO


/* ---------- SD出貨：訂單出貨明細（出庫 −） ---------- */
CREATE OR ALTER TRIGGER trg_訂單出貨明細 ON 訂單出貨明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 客戶訂單明細 o ON o.訂單編號 = i.訂單編號 AND o.訂單項次 = i.訂單項次 WHERE o.物料編號 <> i.物料編號)
        THROW 50001, N'明細物料編號與訂單項次的物料不一致', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 訂單出貨主檔 h ON h.出貨編號 = i.出貨編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號 WHERE o.客戶編號 <> h.客戶編號)
        THROW 50002, N'單據客戶編號與訂單客戶編號不一致', 1;
    /* 過帳：客戶訂單明細.出貨數量 = SUM(訂單出貨明細.出貨數量) 以 訂單編號 + 訂單項次 */
    WITH k AS (SELECT 訂單編號, 訂單項次 FROM inserted UNION SELECT 訂單編號, 訂單項次 FROM deleted)
    UPDATE o SET 出貨數量 = ISNULL((SELECT SUM(d.出貨數量) FROM 訂單出貨明細 d WHERE d.訂單編號 = o.訂單編號 AND d.訂單項次 = o.訂單項次), 0)
    FROM 客戶訂單明細 o JOIN k ON k.訂單編號 = o.訂單編號 AND k.訂單項次 = o.訂單項次;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'SD出貨' AND t.單據編號 = d.出貨編號 AND t.單據項次 = d.出貨項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.出貨日期, N'SD出貨', i.出貨編號, i.出貨項次, i.倉庫代碼, i.物料編號, -i.出貨數量
    FROM inserted i JOIN 訂單出貨主檔 h ON h.出貨編號 = i.出貨編號;
END
GO
CREATE OR ALTER TRIGGER trg_訂單出貨主檔_日期 ON 訂單出貨主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(出貨日期)
        UPDATE t SET 異動日期 = i.出貨日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'SD出貨' AND t.單據編號 = i.出貨編號 AND t.異動日期 <> i.出貨日期;
END
GO

/* ---------- SD退回：出貨退回明細（入庫 +） ---------- */
CREATE OR ALTER TRIGGER trg_出貨退回明細 ON 出貨退回明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 客戶訂單明細 o ON o.訂單編號 = i.訂單編號 AND o.訂單項次 = i.訂單項次 WHERE o.物料編號 <> i.物料編號)
        THROW 50001, N'明細物料編號與訂單項次的物料不一致', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 出貨退回主檔 h ON h.退回編號 = i.退回編號
               JOIN 客戶訂單主檔 o ON o.訂單編號 = i.訂單編號 WHERE o.客戶編號 <> h.客戶編號)
        THROW 50002, N'單據客戶編號與訂單客戶編號不一致', 1;
    /* 過帳：客戶訂單明細.退回數量 = SUM(出貨退回明細.退回數量) 以 訂單編號 + 訂單項次 */
    WITH k AS (SELECT 訂單編號, 訂單項次 FROM inserted UNION SELECT 訂單編號, 訂單項次 FROM deleted)
    UPDATE o SET 退回數量 = ISNULL((SELECT SUM(d.退回數量) FROM 出貨退回明細 d WHERE d.訂單編號 = o.訂單編號 AND d.訂單項次 = o.訂單項次), 0)
    FROM 客戶訂單明細 o JOIN k ON k.訂單編號 = o.訂單編號 AND k.訂單項次 = o.訂單項次;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'SD退回' AND t.單據編號 = d.退回編號 AND t.單據項次 = d.退回項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.退回日期, N'SD退回', i.退回編號, i.退回項次, i.倉庫代碼, i.物料編號, i.退回數量
    FROM inserted i JOIN 出貨退回主檔 h ON h.退回編號 = i.退回編號;
END
GO
CREATE OR ALTER TRIGGER trg_出貨退回主檔_日期 ON 出貨退回主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(退回日期)
        UPDATE t SET 異動日期 = i.退回日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'SD退回' AND t.單據編號 = i.退回編號 AND t.異動日期 <> i.退回日期;
END
GO

/* ---------- MM收貨：採購收貨明細（入庫 +） ---------- */
CREATE OR ALTER TRIGGER trg_採購收貨明細 ON 採購收貨明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 廠商採購明細 o ON o.採購編號 = i.採購編號 AND o.採購項次 = i.採購項次 WHERE o.物料編號 <> i.物料編號)
        THROW 50001, N'明細物料編號與採購項次的物料不一致', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 採購收貨主檔 h ON h.收貨編號 = i.收貨編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號 WHERE o.廠商編號 <> h.廠商編號)
        THROW 50002, N'單據廠商編號與採購單廠商編號不一致', 1;
    /* 過帳：廠商採購明細.收貨數量 = SUM(採購收貨明細.收貨數量) 以 採購編號 + 採購項次 */
    WITH k AS (SELECT 採購編號, 採購項次 FROM inserted UNION SELECT 採購編號, 採購項次 FROM deleted)
    UPDATE o SET 收貨數量 = ISNULL((SELECT SUM(d.收貨數量) FROM 採購收貨明細 d WHERE d.採購編號 = o.採購編號 AND d.採購項次 = o.採購項次), 0)
    FROM 廠商採購明細 o JOIN k ON k.採購編號 = o.採購編號 AND k.採購項次 = o.採購項次;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'MM收貨' AND t.單據編號 = d.收貨編號 AND t.單據項次 = d.收貨項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.收貨日期, N'MM收貨', i.收貨編號, i.收貨項次, i.倉庫代碼, i.物料編號, i.收貨數量
    FROM inserted i JOIN 採購收貨主檔 h ON h.收貨編號 = i.收貨編號;
END
GO
CREATE OR ALTER TRIGGER trg_採購收貨主檔_日期 ON 採購收貨主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(收貨日期)
        UPDATE t SET 異動日期 = i.收貨日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'MM收貨' AND t.單據編號 = i.收貨編號 AND t.異動日期 <> i.收貨日期;
END
GO

/* ---------- MM退回：收貨退回明細（出庫 −） ---------- */
CREATE OR ALTER TRIGGER trg_收貨退回明細 ON 收貨退回明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 廠商採購明細 o ON o.採購編號 = i.採購編號 AND o.採購項次 = i.採購項次 WHERE o.物料編號 <> i.物料編號)
        THROW 50001, N'明細物料編號與採購項次的物料不一致', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 收貨退回主檔 h ON h.退回編號 = i.退回編號
               JOIN 廠商採購主檔 o ON o.採購編號 = i.採購編號 WHERE o.廠商編號 <> h.廠商編號)
        THROW 50002, N'單據廠商編號與採購單廠商編號不一致', 1;
    /* 過帳：廠商採購明細.退回數量 = SUM(收貨退回明細.退回數量) 以 採購編號 + 採購項次 */
    WITH k AS (SELECT 採購編號, 採購項次 FROM inserted UNION SELECT 採購編號, 採購項次 FROM deleted)
    UPDATE o SET 退回數量 = ISNULL((SELECT SUM(d.退回數量) FROM 收貨退回明細 d WHERE d.採購編號 = o.採購編號 AND d.採購項次 = o.採購項次), 0)
    FROM 廠商採購明細 o JOIN k ON k.採購編號 = o.採購編號 AND k.採購項次 = o.採購項次;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'MM退回' AND t.單據編號 = d.退回編號 AND t.單據項次 = d.退回項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.退回日期, N'MM退回', i.退回編號, i.退回項次, i.倉庫代碼, i.物料編號, -i.退回數量
    FROM inserted i JOIN 收貨退回主檔 h ON h.退回編號 = i.退回編號;
END
GO
CREATE OR ALTER TRIGGER trg_收貨退回主檔_日期 ON 收貨退回主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(退回日期)
        UPDATE t SET 異動日期 = i.退回日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'MM退回' AND t.單據編號 = i.退回編號 AND t.異動日期 <> i.退回日期;
END
GO

/* ---------- IM領用：庫存領用明細（出庫 −） ---------- */
CREATE OR ALTER TRIGGER trg_庫存領用明細 ON 庫存領用明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 庫存領用主檔 h ON h.領用編號 = i.領用編號
               JOIN 工廠倉庫維護 w ON w.倉庫代碼 = i.倉庫代碼 WHERE w.工廠代碼 <> h.工廠代碼)
        THROW 50003, N'倉庫不屬於單據的工廠', 1;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'IM領用' AND t.單據編號 = d.領用編號 AND t.單據項次 = d.領用項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.領用日期, N'IM領用', i.領用編號, i.領用項次, i.倉庫代碼, i.物料編號, -i.領用數量
    FROM inserted i JOIN 庫存領用主檔 h ON h.領用編號 = i.領用編號;
END
GO
CREATE OR ALTER TRIGGER trg_庫存領用主檔_日期 ON 庫存領用主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(領用日期)
        UPDATE t SET 異動日期 = i.領用日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'IM領用' AND t.單據編號 = i.領用編號 AND t.異動日期 <> i.領用日期;
END
GO

/* ---------- IM繳庫：庫存繳庫明細（入庫 +） ---------- */
CREATE OR ALTER TRIGGER trg_庫存繳庫明細 ON 庫存繳庫明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 庫存繳庫主檔 h ON h.繳庫編號 = i.繳庫編號
               JOIN 工廠倉庫維護 w ON w.倉庫代碼 = i.倉庫代碼 WHERE w.工廠代碼 <> h.工廠代碼)
        THROW 50003, N'倉庫不屬於單據的工廠', 1;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'IM繳庫' AND t.單據編號 = d.繳庫編號 AND t.單據項次 = d.繳庫項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.繳庫日期, N'IM繳庫', i.繳庫編號, i.繳庫項次, i.倉庫代碼, i.物料編號, i.繳庫數量
    FROM inserted i JOIN 庫存繳庫主檔 h ON h.繳庫編號 = i.繳庫編號;
END
GO
CREATE OR ALTER TRIGGER trg_庫存繳庫主檔_日期 ON 庫存繳庫主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(繳庫日期)
        UPDATE t SET 異動日期 = i.繳庫日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'IM繳庫' AND t.單據編號 = i.繳庫編號 AND t.異動日期 <> i.繳庫日期;
END
GO

/* ---------- PP領料：工單領料明細（出庫 −） ---------- */
CREATE OR ALTER TRIGGER trg_工單領料明細 ON 工單領料明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 工單領料主檔 h ON h.領料編號 = i.領料編號
               JOIN 工廠倉庫維護 w ON w.倉庫代碼 = i.倉庫代碼 WHERE w.工廠代碼 <> h.工廠代碼)
        THROW 50003, N'倉庫不屬於單據的工廠', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 工單領料主檔 h ON h.領料編號 = i.領料編號
               JOIN 生產工單主檔 o ON o.工單編號 = i.工單編號 WHERE o.工廠代碼 <> h.工廠代碼)
        THROW 50004, N'工單不屬於單據的工廠', 1;
    /* 過帳：生產工單明細.已領用量 = SUM(工單領料明細.領料數量) 以 工單編號 + 物料編號 */
    WITH k AS (SELECT 工單編號, 物料編號 FROM inserted UNION SELECT 工單編號, 物料編號 FROM deleted)
    UPDATE o SET 已領用量 = ISNULL((SELECT SUM(d.領料數量) FROM 工單領料明細 d WHERE d.工單編號 = o.工單編號 AND d.物料編號 = o.物料編號), 0)
    FROM 生產工單明細 o JOIN k ON k.工單編號 = o.工單編號 AND k.物料編號 = o.物料編號;

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'PP領料' AND t.單據編號 = d.領料編號 AND t.單據項次 = d.領料項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.領料日期, N'PP領料', i.領料編號, i.領料項次, i.倉庫代碼, i.物料編號, -i.領料數量
    FROM inserted i JOIN 工單領料主檔 h ON h.領料編號 = i.領料編號;
END
GO
CREATE OR ALTER TRIGGER trg_工單領料主檔_日期 ON 工單領料主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(領料日期)
        UPDATE t SET 異動日期 = i.領料日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'PP領料' AND t.單據編號 = i.領料編號 AND t.異動日期 <> i.領料日期;
END
GO

/* ---------- PP入庫：工單入庫明細（入庫 +） ---------- */
CREATE OR ALTER TRIGGER trg_工單入庫明細 ON 工單入庫明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 工單入庫主檔 h ON h.入庫編號 = i.入庫編號
               JOIN 工廠倉庫維護 w ON w.倉庫代碼 = i.倉庫代碼 WHERE w.工廠代碼 <> h.工廠代碼)
        THROW 50003, N'倉庫不屬於單據的工廠', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 工單入庫主檔 h ON h.入庫編號 = i.入庫編號
               JOIN 生產工單主檔 o ON o.工單編號 = i.工單編號 WHERE o.工廠代碼 <> h.工廠代碼)
        THROW 50004, N'工單不屬於單據的工廠', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 生產工單主檔 o ON o.工單編號 = i.工單編號 WHERE o.產品物料 <> i.物料編號)
        THROW 50005, N'入庫物料與工單產品物料不一致', 1;
    /* 過帳：生產工單主檔.入庫數量 = SUM(工單入庫明細.入庫數量) 以 工單編號 */
    WITH k AS (SELECT 工單編號 FROM inserted UNION SELECT 工單編號 FROM deleted)
    UPDATE o SET 入庫數量 = ISNULL((SELECT SUM(d.入庫數量) FROM 工單入庫明細 d WHERE d.工單編號 = o.工單編號), 0)
    FROM 生產工單主檔 o JOIN k ON k.工單編號 = o.工單編號;

    /* 工單入庫三階：筆數 = 入庫數量（多的由最大三階項次刪起，少的補 0001、0002…） */
    IF EXISTS (SELECT 1 FROM inserted WHERE 入庫數量 > 9999)
        THROW 50006, N'入庫數量超過 9999，工單入庫三階項次無法編號', 1;
    DELETE s FROM 工單入庫三階 s
    JOIN (SELECT 入庫編號, 入庫項次, 三階項次, ROW_NUMBER() OVER (PARTITION BY 入庫編號, 入庫項次 ORDER BY 三階項次) AS 序
          FROM 工單入庫三階) r ON r.入庫編號 = s.入庫編號 AND r.入庫項次 = s.入庫項次 AND r.三階項次 = s.三階項次
    JOIN inserted i ON i.入庫編號 = s.入庫編號 AND i.入庫項次 = s.入庫項次
    WHERE r.序 > i.入庫數量;
    INSERT 工單入庫三階 (入庫編號, 入庫項次, 三階項次)
    SELECT i.入庫編號, i.入庫項次, n.項次
    FROM inserted i
    CROSS APPLY (SELECT TOP (i.入庫數量) RIGHT(N'0000' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS nvarchar(5)), 4) AS 項次
                 FROM sys.all_columns a CROSS JOIN sys.all_columns b) n
    WHERE NOT EXISTS (SELECT 1 FROM 工單入庫三階 s WHERE s.入庫編號 = i.入庫編號 AND s.入庫項次 = i.入庫項次 AND s.三階項次 = n.項次);

    DELETE t FROM 庫存異動明細 t JOIN deleted d ON t.單據類別 = N'PP入庫' AND t.單據編號 = d.入庫編號 AND t.單據項次 = d.入庫項次;
    INSERT 庫存異動明細 (異動日期, 單據類別, 單據編號, 單據項次, 倉庫代碼, 物料編號, 異動數量)
    SELECT h.入庫日期, N'PP入庫', i.入庫編號, i.入庫項次, i.倉庫代碼, i.物料編號, i.入庫數量
    FROM inserted i JOIN 工單入庫主檔 h ON h.入庫編號 = i.入庫編號;
END
GO
CREATE OR ALTER TRIGGER trg_工單入庫主檔_日期 ON 工單入庫主檔 AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(入庫日期)
        UPDATE t SET 異動日期 = i.入庫日期
        FROM 庫存異動明細 t JOIN inserted i ON t.單據類別 = N'PP入庫' AND t.單據編號 = i.入庫編號 AND t.異動日期 <> i.入庫日期;
END
GO

/* ---------- 工單入庫三階：只允許修改 Macaddress / 備註說明，筆數必須等於入庫數量 ---------- */
CREATE OR ALTER TRIGGER trg_工單入庫三階 ON 工單入庫三階
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM 工單入庫明細 d
               JOIN (SELECT 入庫編號, 入庫項次 FROM inserted UNION SELECT 入庫編號, 入庫項次 FROM deleted) k
                 ON k.入庫編號 = d.入庫編號 AND k.入庫項次 = d.入庫項次
               WHERE d.入庫數量 <> (SELECT COUNT(*) FROM 工單入庫三階 s WHERE s.入庫編號 = d.入庫編號 AND s.入庫項次 = d.入庫項次))
        THROW 50007, N'工單入庫三階筆數須等於入庫數量（由工單入庫明細自動產生，只能修改 Macaddress）', 1;
END
GO

/* ---------- 生產工序明細 展開：途程清單(途程編號 = 產品物料) × 生產數量 ----------
   未回報的工序若已不在途程中則刪除；已有回報的保留（外鍵保護） */
IF TYPE_ID(N'dbo.工單清單') IS NULL CREATE TYPE dbo.工單清單 AS TABLE (工單編號 nvarchar(20) NOT NULL PRIMARY KEY);
GO
CREATE OR ALTER PROCEDURE dbo.生產工序_展開 @工單 dbo.工單清單 READONLY AS
BEGIN
    SET NOCOUNT ON;
    DELETE p FROM 生產工序明細 p
    JOIN @工單 k ON k.工單編號 = p.工單編號
    JOIN 生產工單主檔 o ON o.工單編號 = p.工單編號
    WHERE NOT EXISTS (SELECT 1 FROM 途程清單維護 r WHERE r.途程編號 = o.產品物料 AND r.製程編號 = p.製程編號)
      AND NOT EXISTS (SELECT 1 FROM 工單回報明細 b WHERE b.工單編號 = p.工單編號 AND b.製程編號 = p.製程編號);

    UPDATE p SET 應報人時 = r.人工小時 * o.生產數量, 應報機時 = r.機器小時 * o.生產數量
    FROM 生產工序明細 p
    JOIN @工單 k ON k.工單編號 = p.工單編號
    JOIN 生產工單主檔 o ON o.工單編號 = p.工單編號
    JOIN 途程清單維護 r ON r.途程編號 = o.產品物料 AND r.製程編號 = p.製程編號
    WHERE p.應報人時 <> r.人工小時 * o.生產數量 OR p.應報機時 <> r.機器小時 * o.生產數量;

    INSERT 生產工序明細 (工單編號, 途程項次, 製程編號, 應報人時, 應報機時)
    SELECT o.工單編號,
           RIGHT(N'0000' + CAST(ISNULL(m.項次, 0) / 10 * 10 + 10 * ROW_NUMBER() OVER (PARTITION BY o.工單編號 ORDER BY r.製程編號) AS nvarchar(10)), 4),
           r.製程編號, r.人工小時 * o.生產數量, r.機器小時 * o.生產數量
    FROM @工單 k
    JOIN 生產工單主檔 o ON o.工單編號 = k.工單編號
    JOIN 途程清單維護 r ON r.途程編號 = o.產品物料
    OUTER APPLY (SELECT MAX(TRY_CAST(p.途程項次 AS int)) AS 項次 FROM 生產工序明細 p WHERE p.工單編號 = o.工單編號) m
    WHERE NOT EXISTS (SELECT 1 FROM 生產工序明細 p WHERE p.工單編號 = o.工單編號 AND p.製程編號 = r.製程編號);
END
GO
CREATE OR ALTER TRIGGER trg_生產工單主檔_工序 ON 生產工單主檔 AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k dbo.工單清單;
    INSERT @k SELECT i.工單編號 FROM inserted i LEFT JOIN deleted d ON d.工單編號 = i.工單編號
    WHERE d.工單編號 IS NULL OR d.產品物料 <> i.產品物料 OR d.生產數量 <> i.生產數量;
    IF @@ROWCOUNT > 0 EXEC dbo.生產工序_展開 @k;
END
GO
/* 途程異動 → 重新展開該產品「尚未完工」(入庫數量 < 生產數量) 的工單 */
CREATE OR ALTER TRIGGER trg_途程清單維護 ON 途程清單維護 AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k dbo.工單清單;
    INSERT @k SELECT o.工單編號 FROM 生產工單主檔 o
    WHERE o.入庫數量 < o.生產數量
      AND o.產品物料 IN (SELECT 途程編號 FROM inserted UNION SELECT 途程編號 FROM deleted);
    IF @@ROWCOUNT > 0 EXEC dbo.生產工序_展開 @k;
END
GO

/* ---------- PP回報：工單回報明細（不影響庫存） ---------- */
CREATE OR ALTER TRIGGER trg_工單回報明細 ON 工單回報明細
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN 工單回報主檔 h ON h.回報編號 = i.回報編號
               JOIN 生產工單主檔 o ON o.工單編號 = i.工單編號 WHERE o.工廠代碼 <> h.工廠代碼)
        THROW 50004, N'工單不屬於單據的工廠', 1;
    /* 過帳：生產工序明細.已報人時 / 已報機時 = SUM(工單回報明細.人工小時 / 機器小時) 以 工單編號 + 製程編號 */
    WITH k AS (SELECT 工單編號, 製程編號 FROM inserted UNION SELECT 工單編號, 製程編號 FROM deleted)
    UPDATE p SET 已報人時 = ISNULL(s.人工, 0), 已報機時 = ISNULL(s.機器, 0)
    FROM 生產工序明細 p JOIN k ON k.工單編號 = p.工單編號 AND k.製程編號 = p.製程編號
    OUTER APPLY (SELECT SUM(d.人工小時) AS 人工, SUM(d.機器小時) AS 機器 FROM 工單回報明細 d
                 WHERE d.工單編號 = p.工單編號 AND d.製程編號 = p.製程編號) s;
END
GO
