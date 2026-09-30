/* =========================================================
   OAV ERP 庫存管理系統 — 01 資料表
   主鍵 / 外鍵 / 檢查條件 全部由 SQL Server 把關
   ========================================================= */

/* ---------- 組織架構 ---------- */
CREATE TABLE 工廠代碼維護 (
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠代碼維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
/* 銷售/採購組織加掛「工廠代碼」(可空)：未交訂單、未交採購才能歸屬到工廠，供 每日供需餘額 以 物料+工廠 計算 */
CREATE TABLE 銷售組織維護 (
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT PK_銷售組織維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL,
    工廠代碼 nvarchar(20) NULL CONSTRAINT FK_銷售組織_工廠 REFERENCES 工廠代碼維護(工廠代碼)
);
CREATE TABLE 採購組織維護 (
    採購組織 nvarchar(20) NOT NULL CONSTRAINT PK_採購組織維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL,
    工廠代碼 nvarchar(20) NULL CONSTRAINT FK_採購組織_工廠 REFERENCES 工廠代碼維護(工廠代碼)
);
CREATE TABLE 工廠倉庫維護 (
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工廠倉庫_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠倉庫維護 PRIMARY KEY,   -- 倉庫代碼唯一
    備註說明 nvarchar(20) NULL
);

/* ---------- 主數據 ---------- */
CREATE TABLE 客戶資料維護 (
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 廠商資料維護 (
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物料資料維護 (
    物料編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物管資料維護 (
    物管編號 nvarchar(20) NOT NULL CONSTRAINT PK_物管資料維護 PRIMARY KEY,
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 用量清單維護 (
    主階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單_主階 REFERENCES 物料資料維護(物料編號),
    子階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單_子階 REFERENCES 物料資料維護(物料編號),
    標準用量 int NOT NULL CONSTRAINT CK_用量清單_用量 CHECK (標準用量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_用量清單維護 PRIMARY KEY (主階編號, 子階編號),
    CONSTRAINT CK_用量清單_不可自身 CHECK (主階編號 <> 子階編號)
);

/* =========================================================
   SD 訂單模組
   ========================================================= */
CREATE TABLE 客戶訂單主檔 (
    訂單編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶訂單主檔 PRIMARY KEY,
    訂單日期 date NOT NULL CONSTRAINT DF_客戶訂單主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單主檔_組織 REFERENCES 銷售組織維護(銷售組織),
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單主檔_客戶 REFERENCES 客戶資料維護(客戶編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 客戶訂單明細 (
    訂單編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_主檔 REFERENCES 客戶訂單主檔(訂單編號) ON DELETE CASCADE,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_物料 REFERENCES 物料資料維護(物料編號),
    訂單數量 int NOT NULL CONSTRAINT CK_客戶訂單明細_訂單 CHECK (訂單數量 > 0),
    出貨數量 int NOT NULL CONSTRAINT DF_客戶訂單明細_出貨 DEFAULT 0,
    退回數量 int NOT NULL CONSTRAINT DF_客戶訂單明細_退回 DEFAULT 0,
    預定交期 date NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_客戶訂單明細 PRIMARY KEY (訂單編號, 訂單項次),
    CONSTRAINT CK_客戶訂單明細_超出 CHECK (出貨數量 - 退回數量 <= 訂單數量),
    CONSTRAINT CK_客戶訂單明細_超退 CHECK (退回數量 <= 出貨數量 AND 退回數量 >= 0)
);
CREATE TABLE 訂單出貨主檔 (
    出貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_訂單出貨主檔 PRIMARY KEY,
    出貨日期 date NOT NULL CONSTRAINT DF_訂單出貨主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨主檔_組織 REFERENCES 銷售組織維護(銷售組織),
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨主檔_客戶 REFERENCES 客戶資料維護(客戶編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 訂單出貨明細 (
    出貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_主檔 REFERENCES 訂單出貨主檔(出貨編號) ON DELETE CASCADE,
    出貨項次 nvarchar(04) NOT NULL,
    訂單編號 nvarchar(20) NOT NULL,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    出貨數量 int NOT NULL CONSTRAINT CK_訂單出貨明細_數量 CHECK (出貨數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_訂單出貨明細 PRIMARY KEY (出貨編號, 出貨項次),
    CONSTRAINT FK_訂單出貨明細_訂單 FOREIGN KEY (訂單編號, 訂單項次) REFERENCES 客戶訂單明細(訂單編號, 訂單項次)
);
CREATE TABLE 出貨退回主檔 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_出貨退回主檔 PRIMARY KEY,
    退回日期 date NOT NULL CONSTRAINT DF_出貨退回主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回主檔_組織 REFERENCES 銷售組織維護(銷售組織),
    客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回主檔_客戶 REFERENCES 客戶資料維護(客戶編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 出貨退回明細 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_主檔 REFERENCES 出貨退回主檔(退回編號) ON DELETE CASCADE,
    退回項次 nvarchar(04) NOT NULL,
    訂單編號 nvarchar(20) NOT NULL,
    訂單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    退回數量 int NOT NULL CONSTRAINT CK_出貨退回明細_數量 CHECK (退回數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_出貨退回明細 PRIMARY KEY (退回編號, 退回項次),
    CONSTRAINT FK_出貨退回明細_訂單 FOREIGN KEY (訂單編號, 訂單項次) REFERENCES 客戶訂單明細(訂單編號, 訂單項次)
);

/* =========================================================
   MM 採購模組
   ========================================================= */
CREATE TABLE 廠商採購主檔 (
    採購編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商採購主檔 PRIMARY KEY,
    採購日期 date NOT NULL CONSTRAINT DF_廠商採購主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購主檔_組織 REFERENCES 採購組織維護(採購組織),
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購主檔_廠商 REFERENCES 廠商資料維護(廠商編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 廠商採購明細 (
    採購編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_主檔 REFERENCES 廠商採購主檔(採購編號) ON DELETE CASCADE,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_物料 REFERENCES 物料資料維護(物料編號),
    採購數量 int NOT NULL CONSTRAINT CK_廠商採購明細_採購 CHECK (採購數量 > 0),
    收貨數量 int NOT NULL CONSTRAINT DF_廠商採購明細_收貨 DEFAULT 0,
    退回數量 int NOT NULL CONSTRAINT DF_廠商採購明細_退回 DEFAULT 0,
    預定交期 date NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_廠商採購明細 PRIMARY KEY (採購編號, 採購項次),
    CONSTRAINT CK_廠商採購明細_超收 CHECK (收貨數量 - 退回數量 <= 採購數量),
    CONSTRAINT CK_廠商採購明細_超退 CHECK (退回數量 <= 收貨數量 AND 退回數量 >= 0)
);
CREATE TABLE 採購收貨主檔 (
    收貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_採購收貨主檔 PRIMARY KEY,
    收貨日期 date NOT NULL CONSTRAINT DF_採購收貨主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨主檔_組織 REFERENCES 採購組織維護(採購組織),
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨主檔_廠商 REFERENCES 廠商資料維護(廠商編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 採購收貨明細 (
    收貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_主檔 REFERENCES 採購收貨主檔(收貨編號) ON DELETE CASCADE,
    收貨項次 nvarchar(04) NOT NULL,
    採購編號 nvarchar(20) NOT NULL,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    收貨數量 int NOT NULL CONSTRAINT CK_採購收貨明細_數量 CHECK (收貨數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_採購收貨明細 PRIMARY KEY (收貨編號, 收貨項次),
    CONSTRAINT FK_採購收貨明細_採購 FOREIGN KEY (採購編號, 採購項次) REFERENCES 廠商採購明細(採購編號, 採購項次)
);
CREATE TABLE 收貨退回主檔 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_收貨退回主檔 PRIMARY KEY,
    退回日期 date NOT NULL CONSTRAINT DF_收貨退回主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回主檔_組織 REFERENCES 採購組織維護(採購組織),
    廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回主檔_廠商 REFERENCES 廠商資料維護(廠商編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 收貨退回明細 (
    退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_主檔 REFERENCES 收貨退回主檔(退回編號) ON DELETE CASCADE,
    退回項次 nvarchar(04) NOT NULL,
    採購編號 nvarchar(20) NOT NULL,
    採購項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    退回數量 int NOT NULL CONSTRAINT CK_收貨退回明細_數量 CHECK (退回數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_收貨退回明細 PRIMARY KEY (退回編號, 退回項次),
    CONSTRAINT FK_收貨退回明細_採購 FOREIGN KEY (採購編號, 採購項次) REFERENCES 廠商採購明細(採購編號, 採購項次)
);

/* =========================================================
   IM 庫存模組
   ========================================================= */
CREATE TABLE 物料預留主檔 (
    預留編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料預留主檔 PRIMARY KEY,
    預留日期 date NOT NULL CONSTRAINT DF_物料預留主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 物料預留明細 (
    預留編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_主檔 REFERENCES 物料預留主檔(預留編號) ON DELETE CASCADE,
    預留項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_物料 REFERENCES 物料資料維護(物料編號),
    預留數量 int NOT NULL CONSTRAINT CK_物料預留明細_數量 CHECK (預留數量 > 0),
    預定交期 date NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_物料預留明細 PRIMARY KEY (預留編號, 預留項次)
);
CREATE TABLE 庫存領用主檔 (
    領用編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存領用主檔 PRIMARY KEY,
    領用日期 date NOT NULL CONSTRAINT DF_庫存領用主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 庫存領用明細 (
    領用編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_主檔 REFERENCES 庫存領用主檔(領用編號) ON DELETE CASCADE,
    領用項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    領用數量 int NOT NULL CONSTRAINT CK_庫存領用明細_數量 CHECK (領用數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_庫存領用明細 PRIMARY KEY (領用編號, 領用項次)
);
CREATE TABLE 庫存繳庫主檔 (
    繳庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存繳庫主檔 PRIMARY KEY,
    繳庫日期 date NOT NULL CONSTRAINT DF_庫存繳庫主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 庫存繳庫明細 (
    繳庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_主檔 REFERENCES 庫存繳庫主檔(繳庫編號) ON DELETE CASCADE,
    繳庫項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    繳庫數量 int NOT NULL CONSTRAINT CK_庫存繳庫明細_數量 CHECK (繳庫數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_庫存繳庫明細 PRIMARY KEY (繳庫編號, 繳庫項次)
);

/* 報表：庫存異動明細（由各單據明細的觸發程序自動寫入，勿手動維護） */
CREATE TABLE 庫存異動明細 (
    異動序號 bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_庫存異動明細 PRIMARY KEY,
    異動日期 date NOT NULL,
    單據類別 nvarchar(10) NOT NULL,
    單據編號 nvarchar(20) NOT NULL,
    單據項次 nvarchar(04) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    異動數量 int NOT NULL,              -- 入庫為正、出庫為負
    建立時間 datetime2(0) NOT NULL CONSTRAINT DF_庫存異動明細_時間 DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_庫存異動明細_單據 UNIQUE (單據類別, 單據編號, 單據項次)
);
CREATE INDEX IX_庫存異動明細_料倉日 ON 庫存異動明細 (倉庫代碼, 物料編號, 異動日期) INCLUDE (異動數量);

/* 報表：每日庫存餘額（由 庫存異動明細 觸發程序自動重算，只記錄有異動的日期） */
CREATE TABLE 每日庫存餘額 (
    餘額日期 date NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    期初數量 int NOT NULL,
    本期入庫 int NOT NULL,
    本期出庫 int NOT NULL,
    期末數量 int NOT NULL,
    CONSTRAINT CK_每日庫存餘額_平衡 CHECK (期初數量 + 本期入庫 - 本期出庫 = 期末數量),
    CONSTRAINT PK_每日庫存餘額 PRIMARY KEY (倉庫代碼, 物料編號, 餘額日期)
);

/* =========================================================
   PP 生產模組
   ========================================================= */
CREATE TABLE 生產工單主檔 (
    工單編號 nvarchar(20) NOT NULL CONSTRAINT PK_生產工單主檔 PRIMARY KEY,
    工單日期 date NOT NULL CONSTRAINT DF_生產工單主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    預定完工 date NULL,
    生產數量 int NOT NULL CONSTRAINT CK_生產工單主檔_生產 CHECK (生產數量 > 0),
    入庫數量 int NOT NULL CONSTRAINT DF_生產工單主檔_入庫 DEFAULT 0,
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL,
    產品物料 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單主檔_產品 REFERENCES 物料資料維護(物料編號),  -- 畫面顯示順序見 系統欄位設定
    CONSTRAINT CK_生產工單主檔_超入 CHECK (入庫數量 BETWEEN 0 AND 生產數量)
);
CREATE TABLE 生產工單明細 (
    工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_主檔 REFERENCES 生產工單主檔(工單編號) ON DELETE CASCADE,
    工單項次 nvarchar(04) NOT NULL,
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_物料 REFERENCES 物料資料維護(物料編號),
    應領用量 int NOT NULL CONSTRAINT CK_生產工單明細_應領 CHECK (應領用量 > 0),
    已領用量 int NOT NULL CONSTRAINT DF_生產工單明細_已領 DEFAULT 0,
    預定領料 date NULL,
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_生產工單明細 PRIMARY KEY (工單編號, 工單項次),
    CONSTRAINT UQ_生產工單明細_物料 UNIQUE (工單編號, 物料編號),   -- 工單領料以 工單+物料 對應
    CONSTRAINT CK_生產工單明細_超領 CHECK (已領用量 BETWEEN 0 AND 應領用量)
);
CREATE TABLE 工單入庫主檔 (
    入庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單入庫主檔 PRIMARY KEY,
    入庫日期 date NOT NULL CONSTRAINT DF_工單入庫主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 工單入庫明細 (
    入庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_主檔 REFERENCES 工單入庫主檔(入庫編號) ON DELETE CASCADE,
    入庫項次 nvarchar(04) NOT NULL,
    工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_工單 REFERENCES 生產工單主檔(工單編號),
    物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_物料 REFERENCES 物料資料維護(物料編號),
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    入庫數量 int NOT NULL CONSTRAINT CK_工單入庫明細_數量 CHECK (入庫數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單入庫明細 PRIMARY KEY (入庫編號, 入庫項次)
);
CREATE TABLE 工單領料主檔 (
    領料編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單領料主檔 PRIMARY KEY,
    領料日期 date NOT NULL CONSTRAINT DF_工單領料主檔_日期 DEFAULT (CAST(GETDATE() AS date)),
    工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料主檔_工廠 REFERENCES 工廠代碼維護(工廠代碼),
    物管編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料主檔_物管 REFERENCES 物管資料維護(物管編號),
    備註說明 nvarchar(20) NULL
);
CREATE TABLE 工單領料明細 (
    領料編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_主檔 REFERENCES 工單領料主檔(領料編號) ON DELETE CASCADE,
    領料項次 nvarchar(04) NOT NULL,
    工單編號 nvarchar(20) NOT NULL,
    物料編號 nvarchar(20) NOT NULL,
    倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_倉庫 REFERENCES 工廠倉庫維護(倉庫代碼),
    領料數量 int NOT NULL CONSTRAINT CK_工單領料明細_數量 CHECK (領料數量 > 0),
    備註說明 nvarchar(20) NULL,
    CONSTRAINT PK_工單領料明細 PRIMARY KEY (領料編號, 領料項次),
    CONSTRAINT FK_工單領料明細_工單 FOREIGN KEY (工單編號, 物料編號) REFERENCES 生產工單明細(工單編號, 物料編號)
);

/* 過帳彙總用索引（觸發程序依來源鍵 SUM） */
CREATE INDEX IX_訂單出貨明細_訂單 ON 訂單出貨明細 (訂單編號, 訂單項次) INCLUDE (出貨數量);
CREATE INDEX IX_出貨退回明細_訂單 ON 出貨退回明細 (訂單編號, 訂單項次) INCLUDE (退回數量);
CREATE INDEX IX_採購收貨明細_採購 ON 採購收貨明細 (採購編號, 採購項次) INCLUDE (收貨數量);
CREATE INDEX IX_收貨退回明細_採購 ON 收貨退回明細 (採購編號, 採購項次) INCLUDE (退回數量);
CREATE INDEX IX_工單入庫明細_工單 ON 工單入庫明細 (工單編號) INCLUDE (入庫數量);
CREATE INDEX IX_工單領料明細_工單 ON 工單領料明細 (工單編號, 物料編號) INCLUDE (領料數量);
