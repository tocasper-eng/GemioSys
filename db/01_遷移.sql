/* =========================================================
   OAV ERP — 01 遷移（既有資料庫升級用，可重複執行）
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
