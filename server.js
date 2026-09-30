// OAV ERP 閘道：只負責把 POST /api/<程序名> 的 JSON 轉交給 SQL Server 的 api.<程序名>，
// 所有商業邏輯都在資料庫。
const 載入設定 = f => { try { return require(f); } catch { console.error('找不到 設定.json：請複製 設定.example.json 為 設定.json 並填入連線資訊'); process.exit(1); } };
const express = require('express'), sql = require('mssql'), path = require('path');
const cfg = 載入設定('./設定.json');

const app = express();
const pool = new sql.ConnectionPool(cfg.db).connect();

app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(__dirname, 'public'), { extensions: ['html'] }));

app.post('/api/:proc', async (req, res) => {
  const proc = req.params.proc;
  if (!/^[\p{L}\p{N}_]{1,50}$/u.test(proc)) return res.status(400).json({ 錯誤: '程序名稱不合法' });
  try {
    const r = await (await pool).request()
      .input('JSON', sql.NVarChar(sql.MAX), JSON.stringify(req.body ?? {}))
      .output('回應', sql.NVarChar(sql.MAX))
      .execute(`api.[${proc}]`);
    res.type('application/json').send(r.output.回應 ?? 'null');
  } catch (e) {
    const n = e.number ?? e.originalError?.info?.number;
    if (n === 2812) return res.status(404).json({ 錯誤: `找不到程序 api.${proc}` });
    // 50000~50998：商業規則錯誤（不可重送）；50999 / 連線錯誤：可重送
    const 可重送 = !(n >= 50000 && n < 50999);
    res.status(可重送 ? 503 : 400).json({ 錯誤: e.message, 可重送 });
  }
});

const port = process.env.PORT || cfg.port;
app.listen(port, () => console.log(`OAV ERP 已啟動：http://localhost:${port}`));
