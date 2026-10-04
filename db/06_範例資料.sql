/* =========================================================
   OAV ERP — 06 範例主數據（僅供初版展示，可重複執行）
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM 工廠代碼維護) INSERT 工廠代碼維護 VALUES (N'1000', N'台中廠'), (N'2000', N'彰化廠');
IF NOT EXISTS (SELECT 1 FROM 銷售組織維護) INSERT 銷售組織維護 (銷售組織, 備註說明, 工廠代碼) VALUES (N'S100', N'台中業務部', N'1000'), (N'S200', N'彰化業務部', N'2000');
IF NOT EXISTS (SELECT 1 FROM 採購組織維護) INSERT 採購組織維護 (採購組織, 備註說明, 工廠代碼) VALUES (N'P100', N'台中採購', N'1000'), (N'P200', N'彰化採購', N'2000');
IF NOT EXISTS (SELECT 1 FROM 工廠倉庫維護) INSERT 工廠倉庫維護 VALUES (N'1000', N'W01', N'台中成品倉'), (N'1000', N'W02', N'台中原料倉'), (N'2000', N'W11', N'彰化成品倉');
IF NOT EXISTS (SELECT 1 FROM 客戶資料維護) INSERT 客戶資料維護 VALUES (N'C001', N'大肚山商行'), (N'C002', N'中科電子');
IF NOT EXISTS (SELECT 1 FROM 廠商資料維護) INSERT 廠商資料維護 VALUES (N'V001', N'精密五金'), (N'V002', N'台中塑膠');
IF NOT EXISTS (SELECT 1 FROM 物料資料維護) INSERT 物料資料維護 VALUES (N'A001', N'成品-桌燈'), (N'B001', N'零件-燈座'), (N'B002', N'零件-燈罩');
IF NOT EXISTS (SELECT 1 FROM 物管資料維護) INSERT 物管資料維護 VALUES (N'M01', N'王物管');
IF NOT EXISTS (SELECT 1 FROM 用量清單維護) INSERT 用量清單維護 VALUES (N'A001', N'B001', 1, NULL), (N'A001', N'B002', 2, NULL);
IF NOT EXISTS (SELECT 1 FROM 製程資料維護) INSERT 製程資料維護 VALUES (N'P10', N'組裝'), (N'P20', N'檢驗');
IF NOT EXISTS (SELECT 1 FROM 機台資料維護) INSERT 機台資料維護 VALUES (N'MC01', N'組裝線一'), (N'MC02', N'檢驗台');
IF NOT EXISTS (SELECT 1 FROM 途程清單維護) INSERT 途程清單維護 VALUES (N'A001', N'P10', 2, 1, NULL), (N'A001', N'P20', 1, 0, NULL);
