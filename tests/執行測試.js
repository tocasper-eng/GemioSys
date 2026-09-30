// npm test：建立獨立的測試資料庫（<資料庫>_test）與測試伺服器，跑完即關閉，不會動到正式資料庫。
const { execFileSync, spawn } = require('child_process'), path = require('path');
const 根 = path.join(__dirname, '..');
const cfg = require('../設定.json');
const 測試庫 = process.env.OAV_TEST_DB || `${cfg.db.database}_test`;
if (測試庫 === cfg.db.database) { console.error('測試資料庫不可與正式資料庫同名'); process.exit(1); }
const PORT = process.env.OAV_TEST_PORT || 3999;
const env = { ...process.env, OAV_DB: 測試庫, PORT: String(PORT) };

console.log(`▶ 重建測試資料庫 ${測試庫}`);
execFileSync(process.execPath, [path.join(根, 'db', '部署.js'), '--reset'], { env, stdio: 'inherit' });

const srv = spawn(process.execPath, [path.join(根, 'server.js')], { env, stdio: ['ignore', 'pipe', 'inherit'] });
srv.stdout.once('data', () => {
  console.log(`▶ 測試伺服器 http://localhost:${PORT}\n`);
  const t = spawn(process.execPath, [path.join(__dirname, '過帳測試.js')], { env: { ...env, BASE: `http://localhost:${PORT}` }, stdio: 'inherit' });
  t.on('exit', code => { srv.kill(); process.exit(code); });
});
