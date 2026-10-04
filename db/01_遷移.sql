/* =========================================================
   GemioSys — 01 遷移（既有資料庫升級用，可重複執行）
   新建資料庫時 01_資料表.sql 已含最新結構，本檔全部略過
   ========================================================= */

/* 2026-09-30：生產工單主檔 新增 產品物料 */
IF COL_LENGTH(N'dbo.生產工單主檔', N'產品物料') IS NULL
BEGIN
    ALTER TABLE 生產工單主檔 ADD 產品物料 nvarchar(20) NULL
        CONSTRAINT FK_生產工單主檔_產品 REFERENCES 物料資料維護(物料編號);
    /* 既有工單：以已入庫的物料回填 */
    EXEC (N'UPDATE o SET 產品物料 = (SELECT TOP (1) d.物料編號 FROM 工單入庫明細 d WHERE d.工單編號 = o.工單編號 ORDER BY d.入庫編號)
            FROM 生產工單主檔 o WHERE o.產品物料 IS NULL');
END
GO
IF COLUMNPROPERTY(OBJECT_ID(N'dbo.生產工單主檔'), N'產品物料', 'AllowsNull') = 1
   AND NOT EXISTS (SELECT 1 FROM 生產工單主檔 WHERE 產品物料 IS NULL)
    ALTER TABLE 生產工單主檔 ALTER COLUMN 產品物料 nvarchar(20) NOT NULL;
GO

/* 2026-10-04：PP 製程/機台/途程、生產工序明細、工單回報、工單入庫三階；每日庫存餘額 期末不可為負 */
IF OBJECT_ID(N'dbo.製程資料維護') IS NULL
CREATE TABLE 製程資料維護 (
    製程編號 nvarchar(20) NOT NULL CONSTRAINT PK_製程資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
GO
IF OBJECT_ID(N'dbo.機台資料維護') IS NULL
CREATE TABLE 機台資料維護 (
    機台編號 nvarchar(20) NOT NULL CONSTRAINT PK_機台資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
GO
IF OBJECT_ID(N'dbo.途程清單維護') IS NULL
CREATE TABLE 途程清單維護 (
    途程編號 nvarchar(20) NOT NULL CONSTRAINT FK_途程清單_途程 REFERENCES 物料資料維護(物料編號),
    製程編號 nvarchar(20) NOT NULL CONSTRAINT FK_途程清單_製程 REFERENCES 製程資料維護(製程編號),
    人工小時 int NOT NULL CONSTRAINT CK_途程清單_人工 CHECK (人工小時 >= 0),
    機器小時 int NOT NULL CONSTRAINT CK_途程清單_機器 CHECK (機器小時 >= 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_途程清單維護 PRIMARY KEY (途程編號, 製程編號)
);
GO
IF OBJECT_ID(N'dbo.生產工序明細') IS NULL
CREATE TABLE 生產工序明細 (
    工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工序明細_主檔 REFERENCES 生產工單主檔(工單編號) ON DELETE CASCADE,
    途程項次 nvarchar(04) NOT NULL,
    製程編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工序明細_製程 REFERENCES 製程資料維護(製程編號),
    應報人時 int NOT NULL CONSTRAINT DF_生產工序明細_應報人時 DEFAULT 0,
    應報機時 int NOT NULL CONSTRAINT DF_生產工序明細_應報機時 DEFAULT 0,
    已報人時 int NOT NULL CONSTRAINT DF_生產工序明細_已報人時 DEFAULT 0,
    已報機時 int NOT NULL CONSTRAINT DF_生產工序明細_已報機時 DEFAULT 0,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_生產工序明細 PRIMARY KEY (工單編號, 途程項次),
    CONSTRAINT UQ_生產工序明細_製程 UNIQUE (工單編號, 製程編號)   -- 工單回報以 工單+製程 對應
);
GO
IF OBJECT_ID(N'dbo.工單回報主檔') IS NULL
CREATE TABLE 工單回報主檔 (
    回報編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單回報主檔 PRIMARY KEY,
    回報日期 date NOT NULL CONSTRAINT DF_工單回報主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單回報主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單回報主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
GO
IF OBJECT_ID(N'dbo.工單回報明細') IS NULL
CREATE TABLE 工單回報明細 (
    回報編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單回報明細_主檔 REFERENCES 工單回報主檔(回報編號) ON DELETE CASCADE,
    回報項次 nvarchar(04) NOT NULL,
    工單編號 nvarchar(20) NOT NULL,
    製程編號 nvarchar(20) NOT NULL,
    機台代碼 nvarchar(20) NULL CONSTRAINT FK_工單回報明細_機台 REFERENCES 機台資料維護(機台編號),
    機器小時 int NOT NULL CONSTRAINT CK_工單回報明細_機器 CHECK (機器小時 >= 0),
    人工小時 int NOT NULL CONSTRAINT CK_工單回報明細_人工 CHECK (人工小時 >= 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單回報明細 PRIMARY KEY (回報編號, 回報項次),
    CONSTRAINT FK_工單回報明細_工序 FOREIGN KEY (工單編號, 製程編號) REFERENCES 生產工序明細(工單編號, 製程編號)
);
GO
IF OBJECT_ID(N'dbo.工單入庫三階') IS NULL
CREATE TABLE 工單入庫三階 (
    入庫編號 nvarchar(20) NOT NULL,
    入庫項次 nvarchar(04) NOT NULL,
    三階項次 nvarchar(04) NOT NULL,
    Macaddress nvarchar(20) NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單入庫三階 PRIMARY KEY (入庫編號, 入庫項次, 三階項次),
    CONSTRAINT FK_工單入庫三階_明細 FOREIGN KEY (入庫編號, 入庫項次) REFERENCES 工單入庫明細(入庫編號, 入庫項次) ON DELETE CASCADE
);
GO
IF INDEXPROPERTY(OBJECT_ID(N'dbo.工單回報明細'), N'IX_工單回報明細_工序', 'IndexID') IS NULL
    CREATE INDEX IX_工單回報明細_工序 ON 工單回報明細 (工單編號, 製程編號) INCLUDE (人工小時, 機器小時);
GO
/* 既有工單入庫明細：依入庫數量補展 三階（觸發程序尚未建立前執行，之後由觸發程序維護） */
IF NOT EXISTS (SELECT 1 FROM 工單入庫三階)
    INSERT 工單入庫三階 (入庫編號, 入庫項次, 三階項次)
    SELECT d.入庫編號, d.入庫項次, RIGHT(N'0000' + CAST(n.n AS nvarchar(5)), 4)
    FROM 工單入庫明細 d
    CROSS APPLY (SELECT TOP (d.入庫數量) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
                 FROM sys.all_columns a CROSS JOIN sys.all_columns b) n;
GO
IF OBJECT_ID(N'dbo.CK_每日庫存餘額_非負') IS NULL
    ALTER TABLE 每日庫存餘額 ADD CONSTRAINT CK_每日庫存餘額_非負 CHECK (期末數量 >= 0);
GO
