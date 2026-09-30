/* =========================================================
   OAV ERP — 04 系統資料表 + API 預存程序
   前端只呼叫 api.* 預存程序，傳入 @JSON、取回 @回應(JSON)。
   畫面欄位、下拉選單、單號編碼、存檔、刪除、報表查詢
   全部由 SQL Server 依中繼資料動態處理。
   ========================================================= */
IF SCHEMA_ID(N'api') IS NULL EXEC (N'CREATE SCHEMA api');
GO

/* ---------- 系統資料表 ---------- */
IF OBJECT_ID(N'dbo.系統功能表') IS NULL
CREATE TABLE 系統功能表 (
    功能代碼   nvarchar(20) NOT NULL CONSTRAINT PK_系統功能表 PRIMARY KEY,
    上層代碼   nvarchar(20) NULL CONSTRAINT FK_系統功能表_上層 REFERENCES 系統功能表(功能代碼),
    功能名稱   nvarchar(30) NOT NULL,
    功能類型   nvarchar(4)  NOT NULL,
    主資料表   sysname NULL,
    明細資料表 sysname NULL,
    單號前綴   nvarchar(6) NULL,
    排序       int NOT NULL,
    說明       nvarchar(100) NULL
);
/* 樞紐分析設定：縱軸欄位 × 月份(由日期欄位取) ，統計 SUM(值欄位)，依「年度」篩選 */
IF COL_LENGTH(N'dbo.系統功能表', N'樞紐縱軸') IS NULL
    ALTER TABLE 系統功能表 ADD 樞紐縱軸 sysname NULL, 樞紐日期 sysname NULL, 樞紐數值 sysname NULL;
IF OBJECT_ID(N'CK_系統功能表_類型') IS NOT NULL ALTER TABLE 系統功能表 DROP CONSTRAINT CK_系統功能表_類型;
ALTER TABLE 系統功能表 ADD CONSTRAINT CK_系統功能表_類型 CHECK (功能類型 IN (N'模組', N'群組', N'維護', N'報表', N'樞紐', N'下鑽'));

/* 多層下鑽：第 N 層資料來源，以「連結對應」{本層欄位: 上層欄位} 依上層點選列篩選 */
IF OBJECT_ID(N'dbo.系統下鑽設定') IS NULL
CREATE TABLE 系統下鑽設定 (
    功能代碼 nvarchar(20) NOT NULL CONSTRAINT FK_系統下鑽設定_功能 REFERENCES 系統功能表(功能代碼) ON DELETE CASCADE,
    層級     int NOT NULL CONSTRAINT CK_系統下鑽設定_層級 CHECK (層級 >= 1),
    標題     nvarchar(30) NOT NULL,
    資料來源 sysname NOT NULL,
    連結對應 nvarchar(400) NULL CONSTRAINT CK_系統下鑽設定_連結 CHECK (連結對應 IS NULL OR ISJSON(連結對應) = 1),
    排序     nvarchar(200) NULL,           -- 例：倉庫代碼, 餘額日期 DESC（欄位須存在於資料來源）
    CONSTRAINT PK_系統下鑽設定 PRIMARY KEY (功能代碼, 層級)
);

/* 參照帶入：單據建檔時瀏覽來源（如 已訂未出明細），勾選後拷貝到主檔/明細
   篩選對應 {來源欄位: 主檔欄位}（主檔有值才篩）、主檔對應 {主檔欄位: 來源欄位}、明細對應 {明細欄位: 來源欄位} */
IF OBJECT_ID(N'dbo.系統參照設定') IS NULL
CREATE TABLE 系統參照設定 (
    功能代碼 nvarchar(20) NOT NULL CONSTRAINT FK_系統參照設定_功能 REFERENCES 系統功能表(功能代碼) ON DELETE CASCADE,
    參照名稱 nvarchar(30) NOT NULL,
    資料來源 sysname NOT NULL,
    篩選對應 nvarchar(400) NULL CONSTRAINT CK_系統參照設定_篩選 CHECK (篩選對應 IS NULL OR ISJSON(篩選對應) = 1),
    主檔對應 nvarchar(400) NULL CONSTRAINT CK_系統參照設定_主檔 CHECK (主檔對應 IS NULL OR ISJSON(主檔對應) = 1),
    明細對應 nvarchar(800) NOT NULL CONSTRAINT CK_系統參照設定_明細 CHECK (ISJSON(明細對應) = 1),
    排序     nvarchar(200) NULL,
    CONSTRAINT PK_系統參照設定 PRIMARY KEY (功能代碼, 參照名稱)
);
IF OBJECT_ID(N'dbo.系統欄位設定') IS NULL
CREATE TABLE 系統欄位設定 (
    資料表   sysname NOT NULL,
    欄位名稱 sysname NOT NULL,
    唯讀     bit NOT NULL CONSTRAINT DF_系統欄位設定_唯讀 DEFAULT 0,   -- 由觸發程序回寫的累計欄位
    選單來源 sysname NULL,                                            -- 非單一外鍵時的下拉來源（表/視圖）
    選單欄位 sysname NULL,
    CONSTRAINT PK_系統欄位設定 PRIMARY KEY (資料表, 欄位名稱)
);
/* 畫面欄位顯示順序（預設 = column_id × 10），讓 ALTER 新增在表尾的欄位可排到適當位置 */
IF COL_LENGTH(N'dbo.系統欄位設定', N'顯示順序') IS NULL
    ALTER TABLE 系統欄位設定 ADD 顯示順序 int NULL;
IF OBJECT_ID(N'dbo.系統錯誤訊息') IS NULL
CREATE TABLE 系統錯誤訊息 (
    約束名稱 sysname NOT NULL CONSTRAINT PK_系統錯誤訊息 PRIMARY KEY,
    訊息     nvarchar(200) NOT NULL
);
/* 離線重傳的冪等紀錄：同一 請求ID 只處理一次，重送直接回傳上次結果 */
IF OBJECT_ID(N'dbo.系統請求紀錄') IS NULL
CREATE TABLE 系統請求紀錄 (
    請求ID   uniqueidentifier NOT NULL CONSTRAINT PK_系統請求紀錄 PRIMARY KEY,
    功能代碼 nvarchar(20) NOT NULL,
    動作     nvarchar(10) NOT NULL,
    回應     nvarchar(max) NULL,
    處理時間 datetime2(0) NOT NULL CONSTRAINT DF_系統請求紀錄_時間 DEFAULT (SYSDATETIME())
);
GO

/* ---------- 欄位中繼資料（由 sys.* 推導） ---------- */
CREATE OR ALTER VIEW api.欄位定義 AS
SELECT o.name AS 資料表,
       ISNULL(s.顯示順序, c.column_id * 10) AS 欄位順序,
       c.name AS 欄位名稱,
       ty.name AS 資料型別,
       CASE WHEN ty.name IN (N'nvarchar', N'nchar') THEN IIF(c.max_length = -1, -1, c.max_length / 2)
            WHEN ty.name IN (N'varchar', N'char')   THEN c.max_length END AS 長度,
       ty.name + CASE
            WHEN ty.name IN (N'nvarchar', N'nchar') THEN N'(' + IIF(c.max_length = -1, N'max', CAST(c.max_length / 2 AS nvarchar(10))) + N')'
            WHEN ty.name IN (N'varchar', N'char')   THEN N'(' + IIF(c.max_length = -1, N'max', CAST(c.max_length AS nvarchar(10))) + N')'
            WHEN ty.name IN (N'decimal', N'numeric') THEN N'(' + CAST(c.precision AS nvarchar(3)) + N',' + CAST(c.scale AS nvarchar(3)) + N')'
            ELSE N'' END AS 型別定義,
       /* OPENJSON WITH 子句用：[欄位] 型別 N'$."欄位"' */
       QUOTENAME(c.name) + N' ' + ty.name + CASE
            WHEN ty.name IN (N'nvarchar', N'nchar') THEN N'(' + IIF(c.max_length = -1, N'max', CAST(c.max_length / 2 AS nvarchar(10))) + N')'
            WHEN ty.name IN (N'varchar', N'char')   THEN N'(' + IIF(c.max_length = -1, N'max', CAST(c.max_length AS nvarchar(10))) + N')'
            WHEN ty.name IN (N'decimal', N'numeric') THEN N'(' + CAST(c.precision AS nvarchar(3)) + N',' + CAST(c.scale AS nvarchar(3)) + N')'
            ELSE N'' END + N' N''$."' + REPLACE(c.name, N'''', N'''''') + N'"''' AS JSON路徑,
       c.is_nullable AS 可空,
       CAST(IIF(ic.column_id IS NULL, 0, 1) AS bit) AS 主鍵,
       CAST(IIF(c.is_identity = 1 OR c.is_computed = 1 OR ISNULL(s.唯讀, 0) = 1, 1, 0) AS bit) AS 唯讀,
       dc.definition AS 預設定義,
       COALESCE(s.選單來源, fk.參照資料表) AS 選單來源,
       COALESCE(s.選單欄位, fk.參照欄位) AS 選單欄位
FROM sys.objects o
JOIN sys.columns c  ON c.object_id = o.object_id
JOIN sys.types ty   ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.indexes i        ON i.object_id = o.object_id AND i.is_primary_key = 1
LEFT JOIN sys.index_columns ic ON ic.object_id = o.object_id AND ic.index_id = i.index_id AND ic.column_id = c.column_id
LEFT JOIN sys.default_constraints dc ON dc.parent_object_id = o.object_id AND dc.parent_column_id = c.column_id
LEFT JOIN dbo.系統欄位設定 s   ON s.資料表 = o.name AND s.欄位名稱 = c.name
OUTER APPLY (
    SELECT TOP (1) OBJECT_NAME(f.referenced_object_id) AS 參照資料表,
                   COL_NAME(f.referenced_object_id, fc.referenced_column_id) AS 參照欄位
    FROM sys.foreign_key_columns fc
    JOIN sys.foreign_keys f ON f.object_id = fc.constraint_object_id
    WHERE fc.parent_object_id = o.object_id AND fc.parent_column_id = c.column_id
      AND (SELECT COUNT(*) FROM sys.foreign_key_columns x WHERE x.constraint_object_id = f.object_id) = 1
) fk
WHERE o.type IN ('U', 'V') AND o.schema_id = SCHEMA_ID(N'dbo');
GO

/* ---------- 共用：錯誤轉譯（須於 CATCH 區塊內呼叫） ---------- */
CREATE OR ALTER PROCEDURE api.拋出錯誤 AS
BEGIN
    DECLARE @n int = ERROR_NUMBER(), @msg nvarchar(2048) = ERROR_MESSAGE(), @友善 nvarchar(200);
    IF @n IN (1205, -2)                          -- 死結 / 逾時：前端可重送
        THROW 50999, N'資料庫忙碌，請稍後重試', 1;
    SELECT TOP (1) @友善 = 訊息 FROM dbo.系統錯誤訊息
    WHERE @msg LIKE N'%' + 約束名稱 + N'%' ORDER BY LEN(約束名稱) DESC;
    DECLARE @表 nvarchar(200) = SUBSTRING(@msg, NULLIF(CHARINDEX(N'table "dbo.', @msg), 0) + 11, 200),
            @欄 nvarchar(200) = SUBSTRING(@msg, NULLIF(CHARINDEX(N'column ''', @msg), 0) + 8, 200);
    SET @表 = LEFT(@表, CHARINDEX(N'"', @表 + N'"') - 1);
    SET @欄 = LEFT(@欄, CHARINDEX(N'''', @欄 + N'''') - 1);
    IF @友善 IS NOT NULL SET @msg = @友善;
    ELSE IF @n = 547 AND @msg LIKE N'%REFERENCE constraint%'
        SET @msg = N'此資料已被「' + @表 + N'」引用，無法刪除';
    ELSE IF @n = 547 AND @msg LIKE N'%FOREIGN KEY constraint%'
        SET @msg = N'「' + @欄 + N'」的值不存在於「' + @表 + N'」';
    ELSE IF @n = 547 AND @msg LIKE N'%CHECK constraint%'
        SET @msg = N'「' + ISNULL(NULLIF(@欄, N''), @表) + N'」不符合檢核條件';
    ELSE IF @n = 547        SET @msg = N'資料檢核失敗：' + @msg;
    ELSE IF @n IN (2627, 2601) SET @msg = N'資料重複：' + @msg;
    ELSE IF @n = 515        SET @msg = N'「' + @欄 + N'」為必填欄位';
    THROW 50000, @msg, 1;
END
GO

/* ---------- api.功能表 ---------- */
CREATE OR ALTER PROCEDURE api.功能表 @JSON nvarchar(max) = NULL, @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    SET @回應 = (SELECT 功能代碼, 上層代碼, 功能名稱, 功能類型, 排序, 說明
                 FROM dbo.系統功能表 ORDER BY 排序
                 FOR JSON PATH, INCLUDE_NULL_VALUES);
END
GO

/* ---------- api.畫面定義 {功能代碼} ---------- */
CREATE OR ALTER PROCEDURE api.畫面定義 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"');
    IF NOT EXISTS (SELECT 1 FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 IN (N'維護', N'報表', N'樞紐', N'下鑽'))
        THROW 50000, N'功能代碼不存在', 1;

    SET @回應 = (
        SELECT f.功能代碼, f.功能名稱, f.功能類型, f.主資料表, f.明細資料表, f.單號前綴, f.樞紐縱軸, f.樞紐日期, f.樞紐數值,
               p.功能名稱 AS 群組名稱, g.功能名稱 AS 模組名稱,
               JSON_QUERY((SELECT 欄位名稱, 資料型別, 長度, 可空, 主鍵, 唯讀,
                                  CAST(IIF(預設定義 IS NULL, 0, 1) AS bit) AS 有預設, 選單來源, 選單欄位
                           FROM api.欄位定義 WHERE 資料表 = f.主資料表 ORDER BY 欄位順序
                           FOR JSON PATH, INCLUDE_NULL_VALUES)) AS 主檔欄位,
               JSON_QUERY(ISNULL((SELECT d.欄位名稱, d.資料型別, d.長度, d.可空, d.主鍵, d.唯讀,
                                  CAST(IIF(d.預設定義 IS NULL, 0, 1) AS bit) AS 有預設, d.選單來源, d.選單欄位,
                                  CAST(IIF(EXISTS (SELECT 1 FROM api.欄位定義 m WHERE m.資料表 = f.主資料表
                                                   AND m.主鍵 = 1 AND m.欄位名稱 = d.欄位名稱), 1, 0) AS bit) AS 連結
                           FROM api.欄位定義 d WHERE d.資料表 = f.明細資料表 ORDER BY d.欄位順序
                           FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS 明細欄位,
               JSON_QUERY(ISNULL((SELECT 參照名稱 FROM dbo.系統參照設定 r WHERE r.功能代碼 = f.功能代碼 ORDER BY 參照名稱
                           FOR JSON PATH), N'[]')) AS 參照,
               (SELECT COUNT(*) FROM dbo.系統下鑽設定 k WHERE k.功能代碼 = f.功能代碼) AS 下鑽層數
        FROM dbo.系統功能表 f
        LEFT JOIN dbo.系統功能表 p ON p.功能代碼 = f.上層代碼
        LEFT JOIN dbo.系統功能表 g ON g.功能代碼 = p.上層代碼
        WHERE f.功能代碼 = @功能
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
END
GO

/* ---------- api.清單 {功能代碼, 關鍵字} ：維護清單 / 報表資料 ---------- */
CREATE OR ALTER PROCEDURE api.清單 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'),
            @關鍵字 nvarchar(50) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@JSON, N'$."關鍵字"'))), N''),
            @T sysname, @串 nvarchar(max), @序 nvarchar(max), @sql nvarchar(max), @r nvarchar(max);

    SELECT @T = 主資料表 FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 IN (N'維護', N'報表', N'下鑽');
    IF @T IS NULL THROW 50000, N'功能代碼不存在', 1;

    SELECT @串 = STRING_AGG(CAST(N'CAST(' + QUOTENAME(欄位名稱) + N' AS nvarchar(100))' AS nvarchar(max)), N',')
    FROM api.欄位定義 WHERE 資料表 = @T;
    SELECT @序 = STRING_AGG(CAST(QUOTENAME(欄位名稱) + N' DESC' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 欄位順序)
    FROM api.欄位定義 WHERE 資料表 = @T AND 主鍵 = 1;

    SET @sql = N'SET @r = (SELECT TOP (500) * FROM ' + QUOTENAME(@T)
             + N' WHERE @k IS NULL OR CONCAT_WS(N''|'', N'''', ' + @串 + N') LIKE N''%'' + @k + N''%'''
             + N' ORDER BY ' + ISNULL(@序, N'1') + N' FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@k nvarchar(50), @r nvarchar(max) OUTPUT', @關鍵字, @r OUTPUT;
    SET @回應 = ISNULL(@r, N'[]');
END
GO

/* ---------- api.選單 {來源, 欄位} ：下拉選項 ---------- */
CREATE OR ALTER PROCEDURE api.選單 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @來源 sysname = JSON_VALUE(@JSON, N'$."來源"'), @欄 sysname = JSON_VALUE(@JSON, N'$."欄位"'),
            @說明 bit, @sql nvarchar(max), @r nvarchar(max);
    IF NOT EXISTS (SELECT 1 FROM api.欄位定義 WHERE 資料表 = @來源 AND 欄位名稱 = @欄)
        THROW 50000, N'選單來源不存在', 1;
    /* 欄位為來源唯一主鍵且來源有 備註說明 時，一併帶出說明 */
    SET @說明 = IIF((SELECT COUNT(*) FROM api.欄位定義 WHERE 資料表 = @來源 AND 主鍵 = 1) = 1
                    AND EXISTS (SELECT 1 FROM api.欄位定義 WHERE 資料表 = @來源 AND 主鍵 = 1 AND 欄位名稱 = @欄)
                    AND EXISTS (SELECT 1 FROM api.欄位定義 WHERE 資料表 = @來源 AND 欄位名稱 = N'備註說明'), 1, 0);
    SET @sql = N'SET @r = (SELECT DISTINCT TOP (1000) ' + QUOTENAME(@欄) + N' AS 值'
             + IIF(@說明 = 1, N', 備註說明 AS 說明', N'')
             + N' FROM ' + QUOTENAME(@來源) + N' ORDER BY 1 FOR JSON PATH);';
    EXEC sp_executesql @sql, N'@r nvarchar(max) OUTPUT', @r OUTPUT;
    SET @回應 = ISNULL(@r, N'[]');
END
GO

/* ---------- api.讀取 {功能代碼, 鍵值:{…}} ：單據主檔 + 明細 ---------- */
CREATE OR ALTER PROCEDURE api.讀取 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'), @k nvarchar(max) = JSON_QUERY(@JSON, N'$."鍵值"'),
            @T sysname, @D sysname, @withK nvarchar(max), @onM nvarchar(max), @onD nvarchar(max), @序D nvarchar(max),
            @sql nvarchar(max), @r nvarchar(max);
    SELECT @T = 主資料表, @D = 明細資料表 FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 = N'維護';
    IF @T IS NULL THROW 50000, N'功能代碼不存在', 1;

    SELECT @withK = STRING_AGG(CAST(JSON路徑 AS nvarchar(max)), N','),
           @onM   = STRING_AGG(CAST(N'x.' + QUOTENAME(欄位名稱) + N'=k.' + QUOTENAME(欄位名稱) AS nvarchar(max)), N' AND ')
    FROM api.欄位定義 WHERE 資料表 = @T AND 主鍵 = 1;
    SET @onD = @onM;
    SELECT @序D = STRING_AGG(CAST(N'x.' + QUOTENAME(欄位名稱) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 欄位順序)
    FROM api.欄位定義 WHERE 資料表 = @D AND 主鍵 = 1;

    SET @sql = N'SET @r = (SELECT JSON_QUERY((SELECT x.* FROM ' + QUOTENAME(@T) + N' x CROSS APPLY OPENJSON(@k) WITH (' + @withK + N') k WHERE ' + @onM
             + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) AS 主檔'
             + IIF(@D IS NULL, N'',
               N', JSON_QUERY(ISNULL((SELECT x.* FROM ' + QUOTENAME(@D) + N' x CROSS APPLY OPENJSON(@k) WITH (' + @withK + N') k WHERE ' + @onD
             + N' ORDER BY ' + @序D + N' FOR JSON PATH, INCLUDE_NULL_VALUES), N''[]'')) AS 明細')
             + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@k nvarchar(max), @r nvarchar(max) OUTPUT', @k, @r OUTPUT;
    IF JSON_QUERY(@r, N'$."主檔"') IS NULL THROW 50000, N'查無此筆資料', 1;
    SET @回應 = @r;
END
GO

/* ---------- api.存檔 {請求ID, 功能代碼, 主檔:{…}, 明細:[…]} ----------
   • 同一 請求ID 重送：直接回傳第一次的結果（離線重傳不會重複入帳）
   • 主檔單一主鍵且空白：依 單號前綴+yyMMdd+流水號 自動編號
   • 明細項次空白：自動以 0010、0020… 編號
   • 主檔 MERGE；明細 MERGE（新增/修改/刪除），觸發程序負責回寫與庫存異動 */
CREATE OR ALTER PROCEDURE api.存檔 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @id uniqueidentifier = TRY_CAST(JSON_VALUE(@JSON, N'$."請求ID"') AS uniqueidentifier),
            @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'),
            @m nvarchar(max) = JSON_QUERY(@JSON, N'$."主檔"'),
            @dj nvarchar(max) = ISNULL(JSON_QUERY(@JSON, N'$."明細"'), N'[]'),
            @T sysname, @D sysname, @前綴 nvarchar(6), @sql nvarchar(max), @鍵 nvarchar(max);

    IF @id IS NULL THROW 50000, N'缺少請求ID', 1;
    SELECT @回應 = 回應 FROM dbo.系統請求紀錄 WHERE 請求ID = @id;
    IF @回應 IS NOT NULL BEGIN SET @回應 = JSON_MODIFY(@回應, N'$."重送"', CAST(1 AS bit)); RETURN; END

    SELECT @T = 主資料表, @D = 明細資料表, @前綴 = 單號前綴 FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 = N'維護';
    IF @T IS NULL THROW 50000, N'功能代碼不存在或不可維護', 1;
    IF @m IS NULL THROW 50000, N'缺少主檔資料', 1;

    /* 可寫入欄位 */
    DECLARE @欄 TABLE (表 char(1), 欄位 sysname, 路徑 nvarchar(400), 主鍵 bit, 預設 nvarchar(400), 連結 bit, 序 int);
    INSERT @欄 SELECT 'M', 欄位名稱, JSON路徑, 主鍵, 預設定義, 0, 欄位順序 FROM api.欄位定義 WHERE 資料表 = @T AND 唯讀 = 0;
    INSERT @欄 SELECT 'D', 欄位名稱, JSON路徑, 主鍵, 預設定義,
                      IIF(EXISTS (SELECT 1 FROM api.欄位定義 m WHERE m.資料表 = @T AND m.主鍵 = 1 AND m.欄位名稱 = f.欄位名稱), 1, 0), 欄位順序
               FROM api.欄位定義 f WHERE 資料表 = @D AND 唯讀 = 0;

    DECLARE @withM nvarchar(max), @withK nvarchar(max), @onM nvarchar(max), @setM nvarchar(max), @colsM nvarchar(max),
            @valsM nvarchar(max), @sM nvarchar(max), @tM nvarchar(max), @kSel nvarchar(max),
            @withD nvarchar(max), @srcD nvarchar(max), @linkD nvarchar(max), @onD nvarchar(max), @setD nvarchar(max),
            @colsD nvarchar(max), @valsD nvarchar(max), @sD nvarchar(max), @tD nvarchar(max);

    SELECT @withM = STRING_AGG(CAST(路徑 AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序),
           @colsM = STRING_AGG(CAST(QUOTENAME(欄位) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序),
           @valsM = STRING_AGG(CAST(IIF(預設 IS NULL, N's.' + QUOTENAME(欄位), N'ISNULL(s.' + QUOTENAME(欄位) + N',' + 預設 + N')') AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序)
    FROM @欄 WHERE 表 = 'M';
    SELECT @withK = STRING_AGG(CAST(路徑 AS nvarchar(max)), N','),
           @onM   = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) + N'=s.' + QUOTENAME(欄位) AS nvarchar(max)), N' AND '),
           @kSel  = STRING_AGG(CAST(QUOTENAME(欄位) AS nvarchar(max)), N',')
    FROM @欄 WHERE 表 = 'M' AND 主鍵 = 1;
    SELECT @setM = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) + N'=' + IIF(預設 IS NULL, N's.' + QUOTENAME(欄位), N'ISNULL(s.' + QUOTENAME(欄位) + N',' + 預設 + N')') AS nvarchar(max)), N','),
           @sM   = STRING_AGG(CAST(N's.' + QUOTENAME(欄位) AS nvarchar(max)), N','),
           @tM   = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) AS nvarchar(max)), N',')
    FROM @欄 WHERE 表 = 'M' AND 主鍵 = 0;

    SELECT @withD = STRING_AGG(CAST(路徑 AS nvarchar(max)), N',')
    FROM @欄 WHERE 表 = 'D' AND 連結 = 0;
    SELECT @srcD  = STRING_AGG(CAST(IIF(連結 = 1, N'm.', N's.') + QUOTENAME(欄位) + N' AS ' + QUOTENAME(欄位) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序),
           @colsD = STRING_AGG(CAST(QUOTENAME(欄位) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序),
           @valsD = STRING_AGG(CAST(IIF(預設 IS NULL, N's.' + QUOTENAME(欄位), N'ISNULL(s.' + QUOTENAME(欄位) + N',' + 預設 + N')') AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序)
    FROM @欄 WHERE 表 = 'D';
    SELECT @linkD = STRING_AGG(CAST(N'x.' + QUOTENAME(欄位) + N'=m.' + QUOTENAME(欄位) AS nvarchar(max)), N' AND ')
    FROM @欄 WHERE 表 = 'D' AND 連結 = 1;
    SELECT @onD = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) + N'=s.' + QUOTENAME(欄位) AS nvarchar(max)), N' AND ')
    FROM @欄 WHERE 表 = 'D' AND 主鍵 = 1;
    SELECT @setD = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) + N'=s.' + QUOTENAME(欄位) AS nvarchar(max)), N','),
           @sD   = STRING_AGG(CAST(N's.' + QUOTENAME(欄位) AS nvarchar(max)), N','),
           @tD   = STRING_AGG(CAST(N't.' + QUOTENAME(欄位) AS nvarchar(max)), N',')
    FROM @欄 WHERE 表 = 'D' AND 主鍵 = 0;

    BEGIN TRY
        BEGIN TRAN;
        /* 同一 請求ID 併發重送（頁面與背景同步同時送出）時序列化，後到者直接取前次結果 */
        DECLARE @鎖 nvarchar(255) = N'oav-req-' + CAST(@id AS nvarchar(36));
        EXEC sp_getapplock @Resource = @鎖, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;
        SELECT @回應 = 回應 FROM dbo.系統請求紀錄 WHERE 請求ID = @id;
        IF @回應 IS NOT NULL BEGIN COMMIT; SET @回應 = JSON_MODIFY(@回應, N'$."重送"', CAST(1 AS bit)); RETURN; END

        /* 自動單號 */
        DECLARE @pk sysname, @pkn int;
        SELECT @pkn = COUNT(*), @pk = MAX(欄位) FROM @欄 WHERE 表 = 'M' AND 主鍵 = 1;
        IF @pkn = 1 AND @前綴 IS NOT NULL AND NULLIF(JSON_VALUE(@m, N'$."' + @pk + N'"'), N'') IS NULL
        BEGIN
            DECLARE @前 nvarchar(20) = @前綴 + FORMAT(GETDATE(), 'yyMMdd'), @流水 int;
            SET @sql = N'SELECT @流水 = ISNULL(MAX(TRY_CAST(SUBSTRING(' + QUOTENAME(@pk) + N', LEN(@前) + 1, 10) AS int)), 0) + 1 FROM '
                     + QUOTENAME(@T) + N' WITH (UPDLOCK, HOLDLOCK) WHERE ' + QUOTENAME(@pk) + N' LIKE @前 + N''%''';
            EXEC sp_executesql @sql, N'@前 nvarchar(20), @流水 int OUTPUT', @前, @流水 OUTPUT;
            SET @m = JSON_MODIFY(@m, N'$."' + @pk + N'"', @前 + RIGHT(N'000' + CAST(@流水 AS nvarchar(10)), 3));
        END

        /* 主檔 */
        SET @sql = N'MERGE ' + QUOTENAME(@T) + N' AS t USING (SELECT * FROM OPENJSON(@m) WITH (' + @withM + N')) AS s ON ' + @onM
                 + ISNULL(N' WHEN MATCHED AND EXISTS (SELECT ' + @sM + N' EXCEPT SELECT ' + @tM + N') THEN UPDATE SET ' + @setM, N'')
                 + N' WHEN NOT MATCHED THEN INSERT (' + @colsM + N') VALUES (' + @valsM + N');';
        EXEC sp_executesql @sql, N'@m nvarchar(max)', @m;

        /* 明細 */
        IF @D IS NOT NULL
        BEGIN
            /* 空白項次自動編號 */
            DECLARE @項 sysname = (SELECT TOP (1) 欄位 FROM @欄 WHERE 表 = 'D' AND 主鍵 = 1 AND 連結 = 0), @mx int, @k int;
            SET @sql = N'SELECT @mx = ISNULL(MAX(TRY_CAST(x.' + QUOTENAME(@項) + N' AS int)), 0) FROM ' + QUOTENAME(@D)
                     + N' x CROSS APPLY OPENJSON(@m) WITH (' + @withK + N') m WHERE ' + @linkD;
            EXEC sp_executesql @sql, N'@m nvarchar(max), @mx int OUTPUT', @m, @mx OUTPUT;
            DECLARE @mxj int = (SELECT ISNULL(MAX(TRY_CAST(JSON_VALUE(value, N'$."' + @項 + N'"') AS int)), 0) FROM OPENJSON(@dj));
            SET @mx = IIF(@mxj > @mx, @mxj, @mx) / 10 * 10;
            DECLARE @空 TABLE (k int PRIMARY KEY);
            INSERT @空 SELECT CAST([key] AS int) FROM OPENJSON(@dj) WHERE NULLIF(JSON_VALUE(value, N'$."' + @項 + N'"'), N'') IS NULL;
            WHILE EXISTS (SELECT 1 FROM @空)
            BEGIN
                SELECT TOP (1) @k = k FROM @空 ORDER BY k;
                SET @mx += 10;
                SET @dj = JSON_MODIFY(@dj, N'$[' + CAST(@k AS nvarchar(10)) + N']."' + @項 + N'"', RIGHT(N'0000' + CAST(@mx AS nvarchar(10)), 4));
                DELETE @空 WHERE k = @k;
            END

            SET @sql = N'WITH t AS (SELECT * FROM ' + QUOTENAME(@D) + N' x WHERE EXISTS (SELECT 1 FROM OPENJSON(@m) WITH (' + @withK + N') m WHERE ' + @linkD + N'))'
                     + N' MERGE t USING (SELECT ' + @srcD + N' FROM OPENJSON(@d) j CROSS APPLY OPENJSON(j.value) WITH (' + @withD + N') s'
                     + N' CROSS APPLY OPENJSON(@m) WITH (' + @withK + N') m) AS s ON ' + @onD
                     + N' WHEN MATCHED AND EXISTS (SELECT ' + @sD + N' EXCEPT SELECT ' + @tD + N') THEN UPDATE SET ' + @setD
                     + N' WHEN NOT MATCHED BY TARGET THEN INSERT (' + @colsD + N') VALUES (' + @valsD + N')'
                     + N' WHEN NOT MATCHED BY SOURCE THEN DELETE;';
            EXEC sp_executesql @sql, N'@m nvarchar(max), @d nvarchar(max)', @m, @dj;
        END

        SET @sql = N'SET @鍵 = (SELECT ' + @kSel + N' FROM OPENJSON(@m) WITH (' + @withK + N') FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);';
        EXEC sp_executesql @sql, N'@m nvarchar(max), @鍵 nvarchar(max) OUTPUT', @m, @鍵 OUTPUT;
        SET @回應 = (SELECT CAST(1 AS bit) AS 成功, N'存檔完成' AS 訊息, JSON_QUERY(@鍵) AS 鍵值 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        INSERT dbo.系統請求紀錄 (請求ID, 功能代碼, 動作, 回應) VALUES (@id, @功能, N'存檔', @回應);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC api.拋出錯誤;
    END CATCH
END
GO

/* ---------- api.刪除 {請求ID, 功能代碼, 鍵值:{…}} ：明細以 ON DELETE CASCADE 連動刪除並觸發沖銷 ---------- */
CREATE OR ALTER PROCEDURE api.刪除 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @id uniqueidentifier = TRY_CAST(JSON_VALUE(@JSON, N'$."請求ID"') AS uniqueidentifier),
            @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'), @k nvarchar(max) = JSON_QUERY(@JSON, N'$."鍵值"'),
            @T sysname, @withK nvarchar(max), @on nvarchar(max), @sql nvarchar(max), @n int;

    IF @id IS NULL THROW 50000, N'缺少請求ID', 1;
    SELECT @回應 = 回應 FROM dbo.系統請求紀錄 WHERE 請求ID = @id;
    IF @回應 IS NOT NULL BEGIN SET @回應 = JSON_MODIFY(@回應, N'$."重送"', CAST(1 AS bit)); RETURN; END

    SELECT @T = 主資料表 FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 = N'維護';
    IF @T IS NULL THROW 50000, N'功能代碼不存在或不可維護', 1;
    SELECT @withK = STRING_AGG(CAST(JSON路徑 AS nvarchar(max)), N','),
           @on    = STRING_AGG(CAST(N'x.' + QUOTENAME(欄位名稱) + N'=k.' + QUOTENAME(欄位名稱) AS nvarchar(max)), N' AND ')
    FROM api.欄位定義 WHERE 資料表 = @T AND 主鍵 = 1;

    BEGIN TRY
        BEGIN TRAN;
        /* 同一 請求ID 併發重送（頁面與背景同步同時送出）時序列化，後到者直接取前次結果 */
        DECLARE @鎖 nvarchar(255) = N'oav-req-' + CAST(@id AS nvarchar(36));
        EXEC sp_getapplock @Resource = @鎖, @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;
        SELECT @回應 = 回應 FROM dbo.系統請求紀錄 WHERE 請求ID = @id;
        IF @回應 IS NOT NULL BEGIN COMMIT; SET @回應 = JSON_MODIFY(@回應, N'$."重送"', CAST(1 AS bit)); RETURN; END
        SET @sql = N'DELETE x FROM ' + QUOTENAME(@T) + N' x CROSS APPLY OPENJSON(@k) WITH (' + @withK + N') k WHERE ' + @on + N'; SET @n = @@ROWCOUNT;';
        EXEC sp_executesql @sql, N'@k nvarchar(max), @n int OUTPUT', @k, @n OUTPUT;
        SET @回應 = (SELECT CAST(1 AS bit) AS 成功, IIF(@n > 0, N'刪除完成', N'資料已不存在') AS 訊息 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        INSERT dbo.系統請求紀錄 (請求ID, 功能代碼, 動作, 回應) VALUES (@id, @功能, N'刪除', @回應);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC api.拋出錯誤;
    END CATCH
END
GO

/* ---------- api.樞紐 {功能代碼, 年度} ----------
   縱軸 × 01~12 月，統計 SUM(數值)；CUBE 同時產生列合計（合計欄）與欄合計（合計列） */
CREATE OR ALTER PROCEDURE api.樞紐 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'),
            @年 int = ISNULL(TRY_CAST(JSON_VALUE(@JSON, N'$."年度"') AS int), YEAR(GETDATE())),
            @T sysname, @列 sysname, @日 sysname, @值 sysname, @sql nvarchar(max), @r nvarchar(max);
    SELECT @T = 主資料表, @列 = 樞紐縱軸, @日 = 樞紐日期, @值 = 樞紐數值
    FROM dbo.系統功能表 WHERE 功能代碼 = @功能 AND 功能類型 = N'樞紐';
    IF @T IS NULL THROW 50000, N'功能代碼不存在或不是樞紐分析', 1;
    IF (SELECT COUNT(*) FROM api.欄位定義 WHERE 資料表 = @T AND 欄位名稱 IN (@列, @日, @值)) < 3
        THROW 50000, N'樞紐設定的欄位不存在', 1;

    SET @sql = N'
    WITH 來源 AS (
        SELECT CAST(' + QUOTENAME(@列) + N' AS nvarchar(50)) AS 縱軸, MONTH(' + QUOTENAME(@日) + N') AS 月, ' + QUOTENAME(@值) + N' AS 值
        FROM ' + QUOTENAME(@T) + N' WHERE ' + QUOTENAME(@日) + N' >= DATEFROMPARTS(@年, 1, 1) AND ' + QUOTENAME(@日) + N' < DATEFROMPARTS(@年 + 1, 1, 1)
    ), 彙總 AS (
        SELECT GROUPING(縱軸) AS 合計列, ISNULL(縱軸, N''合計'') AS 縱軸, IIF(GROUPING(月) = 1, 13, 月) AS 月, SUM(值) AS 值
        FROM 來源 GROUP BY CUBE(縱軸, 月)
    )
    SELECT @r = (
        SELECT 縱軸 AS ' + QUOTENAME(@列) + N',
               ISNULL([1],0) AS [01月], ISNULL([2],0) AS [02月], ISNULL([3],0) AS [03月], ISNULL([4],0) AS [04月],
               ISNULL([5],0) AS [05月], ISNULL([6],0) AS [06月], ISNULL([7],0) AS [07月], ISNULL([8],0) AS [08月],
               ISNULL([9],0) AS [09月], ISNULL([10],0) AS [10月], ISNULL([11],0) AS [11月], ISNULL([12],0) AS [12月],
               ISNULL([13],0) AS [合計]
        FROM 彙總 PIVOT (SUM(值) FOR 月 IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12],[13])) p
        ORDER BY 合計列, 縱軸
        FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@年 int, @r nvarchar(max) OUTPUT', @年, @r OUTPUT;
    SET @回應 = (SELECT @年 AS 年度, @列 AS 縱軸, @值 AS 數值, JSON_QUERY(ISNULL(@r, N'[]')) AS 資料
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
END
GO

/* ---------- 共用：驗證「排序」設定，回傳安全的 ORDER BY 子句（欄位不存在就退回 1） ---------- */
CREATE OR ALTER FUNCTION api.fn_排序子句 (@資料表 sysname, @排序 nvarchar(200), @別名 nvarchar(10))
RETURNS nvarchar(max) AS
BEGIN
    DECLARE @r nvarchar(max), @錯 int;
    WITH t AS (
        SELECT LTRIM(RTRIM(value)) AS v FROM STRING_SPLIT(@排序, N',') WHERE LTRIM(RTRIM(value)) <> N''
    ), p AS (
        SELECT CASE WHEN v LIKE N'% DESC' THEN RTRIM(LEFT(v, LEN(v) - 5)) WHEN v LIKE N'% ASC' THEN RTRIM(LEFT(v, LEN(v) - 4)) ELSE v END AS 欄,
               IIF(v LIKE N'% DESC', N' DESC', N'') AS 向
        FROM t
    )
    SELECT @錯 = SUM(IIF(f.欄位名稱 IS NULL, 1, 0)),
           @r = STRING_AGG(CAST(ISNULL(@別名, N'') + QUOTENAME(p.欄) + p.向 AS nvarchar(max)), N', ')
    FROM p LEFT JOIN api.欄位定義 f ON f.資料表 = @資料表 AND f.欄位名稱 = p.欄;
    RETURN IIF(@錯 > 0 OR @r IS NULL, N'1', @r);
END
GO

/* ---------- api.下鑽 {功能代碼, 層級, 上層列:{…}, 關鍵字} ----------
   依 系統下鑽設定 取第 N 層資料，並以上層點選列的值篩選 */
CREATE OR ALTER PROCEDURE api.下鑽 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'),
            @層 int = ISNULL(TRY_CAST(JSON_VALUE(@JSON, N'$."層級"') AS int), 1),
            @上層 nvarchar(max) = ISNULL(JSON_QUERY(@JSON, N'$."上層列"'), N'{}'),
            @關鍵字 nvarchar(50) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@JSON, N'$."關鍵字"'))), N''),
            @T sysname, @標題 nvarchar(30), @連結 nvarchar(400), @序 nvarchar(max), @篩 nvarchar(max), @串 nvarchar(max),
            @層數 int, @下層欄 nvarchar(max), @sql nvarchar(max), @r nvarchar(max);

    SELECT @T = 資料來源, @標題 = 標題, @連結 = 連結對應, @序 = api.fn_排序子句(資料來源, 排序, NULL)
    FROM dbo.系統下鑽設定 WHERE 功能代碼 = @功能 AND 層級 = @層;
    IF @T IS NULL THROW 50000, N'下鑽設定不存在', 1;
    SELECT @層數 = MAX(層級) FROM dbo.系統下鑽設定 WHERE 功能代碼 = @功能;

    /* 連結對應 {本層欄位: 上層欄位} → 本層欄位 = 上層列的值；本層欄位必須存在 */
    IF EXISTS (SELECT 1 FROM OPENJSON(@連結) j LEFT JOIN api.欄位定義 f ON f.資料表 = @T AND f.欄位名稱 = j.[key] COLLATE DATABASE_DEFAULT WHERE f.欄位名稱 IS NULL)
        THROW 50000, N'下鑽連結欄位不存在', 1;
    SELECT @篩 = STRING_AGG(CAST(QUOTENAME([key]) + N' = JSON_VALUE(@上層, N''$."' + REPLACE(value, N'''', N'''''') + N'"'')' AS nvarchar(max)), N' AND ')
    FROM OPENJSON(@連結);
    SELECT @串 = STRING_AGG(CAST(N'CAST(' + QUOTENAME(欄位名稱) + N' AS nvarchar(100))' AS nvarchar(max)), N',')
    FROM api.欄位定義 WHERE 資料表 = @T;
    /* 下一層會用到的上層欄位（前端用來顯示麵包屑） */
    SELECT @下層欄 = (SELECT value AS 欄 FROM dbo.系統下鑽設定 CROSS APPLY OPENJSON(連結對應)
                      WHERE 功能代碼 = @功能 AND 層級 = @層 + 1 FOR JSON PATH);

    SET @sql = N'SET @r = (SELECT TOP (1000) * FROM ' + QUOTENAME(@T) + N' WHERE 1 = 1'
             + ISNULL(N' AND ' + @篩, N'')
             + N' AND (@k IS NULL OR CONCAT_WS(N''|'', N'''', ' + @串 + N') LIKE N''%'' + @k + N''%'')'
             + N' ORDER BY ' + @序 + N' FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@上層 nvarchar(max), @k nvarchar(50), @r nvarchar(max) OUTPUT', @上層, @關鍵字, @r OUTPUT;

    SET @回應 = (SELECT @層 AS 層級, @層數 AS 層數, @標題 AS 標題, @T AS 資料來源,
                        JSON_QUERY((SELECT 欄位名稱, 資料型別 FROM api.欄位定義 WHERE 資料表 = @T ORDER BY 欄位順序 FOR JSON PATH)) AS 欄位,
                        JSON_QUERY(ISNULL((SELECT N'[' + STRING_AGG(N'"' + STRING_ESCAPE(JSON_VALUE(x.value, N'$."欄"'), 'json') + N'"', N',') + N']'
                                           FROM OPENJSON(@下層欄) x), N'[]')) AS 下層欄位,
                        JSON_QUERY(ISNULL(@r, N'[]')) AS 資料
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
END
GO

/* ---------- api.參照 {功能代碼, 參照名稱, 主檔:{…}} ----------
   回傳來源資料，每列附「帶入主檔」「帶入明細」（依對應設定組好，前端直接貼上） */
CREATE OR ALTER PROCEDURE api.參照 @JSON nvarchar(max), @回應 nvarchar(max) OUTPUT AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @功能 nvarchar(20) = JSON_VALUE(@JSON, N'$."功能代碼"'),
            @名稱 nvarchar(30) = JSON_VALUE(@JSON, N'$."參照名稱"'),
            @m nvarchar(max) = ISNULL(JSON_QUERY(@JSON, N'$."主檔"'), N'{}'),
            @T sysname, @篩設定 nvarchar(400), @主設定 nvarchar(400), @明設定 nvarchar(800), @序 nvarchar(max),
            @篩 nvarchar(max), @主 nvarchar(max), @明 nvarchar(max), @sql nvarchar(max), @r nvarchar(max);

    SELECT TOP (1) @T = 資料來源, @名稱 = 參照名稱, @篩設定 = 篩選對應, @主設定 = 主檔對應, @明設定 = 明細對應,
           @序 = api.fn_排序子句(資料來源, 排序, N's.')
    FROM dbo.系統參照設定 WHERE 功能代碼 = @功能 AND (@名稱 IS NULL OR 參照名稱 = @名稱) ORDER BY 參照名稱;
    IF @T IS NULL THROW 50000, N'參照設定不存在', 1;

    /* 設定中引用的來源欄位都必須存在 */
    IF EXISTS (SELECT 1 FROM (SELECT [key] AS 欄 FROM OPENJSON(@篩設定)
                              UNION ALL SELECT value FROM OPENJSON(@主設定)
                              UNION ALL SELECT value FROM OPENJSON(@明設定)) c
               LEFT JOIN api.欄位定義 f ON f.資料表 = @T AND f.欄位名稱 = c.欄 COLLATE DATABASE_DEFAULT WHERE f.欄位名稱 IS NULL)
        THROW 50000, N'參照設定的來源欄位不存在', 1;

    /* 主檔有值才篩選：來源欄位 = 主檔欄位值 */
    SELECT @篩 = STRING_AGG(CAST(N'(JSON_VALUE(@m, N''$."' + REPLACE(value, N'''', N'''''') + N'"'') IS NULL OR s.' + QUOTENAME([key])
                 + N' = JSON_VALUE(@m, N''$."' + REPLACE(value, N'''', N'''''') + N'"''))' AS nvarchar(max)), N' AND ')
    FROM OPENJSON(@篩設定);
    SELECT @主 = STRING_AGG(CAST(N's.' + QUOTENAME(value) + N' AS ' + QUOTENAME([key]) AS nvarchar(max)), N', ') FROM OPENJSON(@主設定);
    SELECT @明 = STRING_AGG(CAST(N's.' + QUOTENAME(value) + N' AS ' + QUOTENAME([key]) AS nvarchar(max)), N', ') FROM OPENJSON(@明設定);

    SET @sql = N'SET @r = (SELECT TOP (500) s.*'
             + N', JSON_QUERY(' + IIF(@主 IS NULL, N'N''{}''', N'(SELECT ' + @主 + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)') + N') AS 帶入主檔'
             + N', JSON_QUERY((SELECT ' + @明 + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS 帶入明細'
             + N' FROM ' + QUOTENAME(@T) + N' s WHERE 1 = 1' + ISNULL(N' AND ' + @篩, N'')
             + N' ORDER BY ' + @序 + N' FOR JSON PATH, INCLUDE_NULL_VALUES);';
    EXEC sp_executesql @sql, N'@m nvarchar(max), @r nvarchar(max) OUTPUT', @m, @r OUTPUT;

    SET @回應 = (SELECT @名稱 AS 參照名稱, @T AS 資料來源,
                        JSON_QUERY((SELECT 欄位名稱, 資料型別 FROM api.欄位定義 WHERE 資料表 = @T ORDER BY 欄位順序 FOR JSON PATH)) AS 欄位,
                        JSON_QUERY(ISNULL(@r, N'[]')) AS 資料
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
END
GO
