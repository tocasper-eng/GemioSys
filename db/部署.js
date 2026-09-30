// 依序執行 db/*.sql（以 GO 分批）。用法：node db/部署.js [--reset]
const 載入設定 = f => { try { return require(f); } catch { console.error('找不到 設定.json：請複製 設定.example.json 為 設定.json 並填入連線資訊'); process.exit(1); } };
const fs = require('fs'), path = require('path'), sql = require('mssql');
const cfg = 載入設定('../設定.json').db;

(async () => {
  const reset = process.argv.includes('--reset');
  const master = await sql.connect({ ...cfg, database: 'master' });
  if (reset) {
    await master.request().query(`IF DB_ID(N'${cfg.database}') IS NOT NULL BEGIN
      ALTER DATABASE [${cfg.database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${cfg.database}]; END`);
    console.log('已刪除資料庫', cfg.database);
  }
  const r = await master.request().query(`SELECT DB_ID(N'${cfg.database}') id`);
  const isNew = r.recordset[0].id === null;
  if (isNew) {
    await master.request().query(`CREATE DATABASE [${cfg.database}] COLLATE Chinese_Taiwan_Stroke_CI_AS`);
    console.log('已建立資料庫', cfg.database);
  }
  await master.close();

  const pool = await new sql.ConnectionPool(cfg).connect();
  const dir = __dirname;
  const files = fs.readdirSync(dir).filter(f => /^\d\d_.*\.sql$/.test(f)).sort();
  for (const f of files) {
    if (f === '01_資料表.sql' && !isNew) { console.log('略過', f, '(資料表已存在，重建請加 --reset)'); continue; }
    const batches = fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '').split(/^\s*GO\s*$/im).filter(b => b.trim());
    for (const b of batches) {
      try { await pool.request().batch(b); }
      catch (e) { console.error(`✗ ${f}\n${e.message}\n---\n${b.slice(0, 400)}`); process.exit(1); }
    }
    console.log('✓', f, `(${batches.length} 批)`);
  }
  await pool.close();
})().catch(e => { console.error(e.message); process.exit(1); });
