// OAV ERP 前端：只負責「畫出 SQL Server 給的畫面定義」與「離線佇列」。
// 功能表、欄位、下拉選單、單號、檢核、過帳全部由 api.* 預存程序決定。
const $ = (s, el = document) => el.querySelector(s);
const esc = v => v == null ? '' : String(v).replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const view = $('#view');

/* ---------- 與伺服器溝通 ---------- */
const cacheKey = (p, b) => 'c:' + p + ':' + JSON.stringify(b);
async function api(proc, body = {}) {           // 讀取：線上取最新並快取，離線退回快取
  try {
    const r = await fetch('/api/' + encodeURIComponent(proc), {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body)
    });
    const j = await r.json();
    if (!r.ok) throw Object.assign(new Error(j.錯誤 || r.statusText), { 商業: r.status === 400 });
    try { localStorage.setItem(cacheKey(proc, body), JSON.stringify(j)); } catch {}
    setNet(true);
    return j;
  } catch (e) {
    if (e.商業) throw e;
    setNet(false);
    let c = null; try { c = localStorage.getItem(cacheKey(proc, body)); } catch {}
    if (c) return JSON.parse(c);
    throw new Error('離線中，且此畫面尚無快取資料');
  }
}
async function write(proc, 資料, 摘要) {         // 寫入：一律先進佇列再上傳，斷線自動重傳
  const 請求ID = crypto.randomUUID();
  await Outbox.put({ 請求ID, 程序: proc, 資料: { ...資料, 請求ID }, 摘要, 時間: Date.now() });
  const r = await Outbox.flush();
  await refreshQ();
  const mine = r.結果?.find(x => x.請求ID === 請求ID);
  if (!mine) try { (await navigator.serviceWorker?.ready)?.sync?.register('oav-outbox'); } catch {}  // 送不出去才交給背景同步
  if (mine?.錯誤) { await Outbox.del(請求ID); await refreshQ(); throw new Error(mine.錯誤); }
  return mine ? mine.回應 : null;               // null = 已暫存待傳
}

/* ---------- 連線狀態與待傳佇列 ---------- */
function setNet(on) {
  const n = $('#net'); n.classList.toggle('off', !on);
  $('span', n).textContent = on ? '連線中' : '離線';
}
async function refreshQ() {
  const q = await Outbox.all();
  const b = $('#qn'); b.hidden = !q.length; b.textContent = q.length;
  b.classList.toggle('err', q.some(i => i.錯誤));
  $('#qlist').innerHTML = q.length ? q.sort((a, b) => a.時間 - b.時間).map(i => `
    <div class="qi ${i.錯誤 ? 'bad' : ''}">
      <div><b>${esc(i.摘要)}</b><small>${new Date(i.時間).toLocaleString()}</small>
      ${i.錯誤 ? `<em>${esc(i.錯誤)}</em>` : '<em class="wait">等待上傳</em>'}</div>
      ${i.錯誤 ? `<button data-drop="${i.請求ID}">移除</button>` : ''}
    </div>`).join('') : '<p class="muted">沒有待傳資料</p>';
}
async function syncNow(silent) {
  const r = await Outbox.flush(); await refreshQ();
  if (r.上傳) toast(`已補傳 ${r.上傳} 筆`);
  else if (!silent && (await Outbox.all()).some(i => !i.錯誤)) toast('仍無法連線，稍後自動重傳');
  if (r.上傳) setNet(true);
}
$('#net').onclick = () => { refreshQ(); $('#qdlg').showModal(); };
$('#qsend').onclick = () => syncNow();
$('#qlist').onclick = async e => { const id = e.target.dataset.drop; if (id) { await Outbox.del(id); refreshQ(); } };
addEventListener('online', () => { setNet(true); syncNow(true); });
addEventListener('offline', () => setNet(false));
setInterval(() => syncNow(true), 20000);
navigator.serviceWorker?.addEventListener('message', e => { if (e.data?.類型 === '已同步') { refreshQ(); if (e.data.上傳) toast(`背景補傳 ${e.data.上傳} 筆`); } });

let toastT;
function toast(msg, bad) {
  const t = $('#toast'); t.textContent = msg; t.className = 'show' + (bad ? ' bad' : '');
  clearTimeout(toastT); toastT = setTimeout(() => t.className = '', 3200);
}

/* ---------- 路由 ---------- */
let 功能表 = [];
const crumb = t => $('#crumb').textContent = t || '';
async function route() {
  const [, , code, mode, key] = location.hash.split('/');
  try {
    if (!功能表.length) 功能表 = await api('功能表');
    if (!code) return renderMenu();
    const def = await api('畫面定義', { 功能代碼: code });
    crumb(`${def.模組名稱} › ${def.功能名稱}`);
    if (mode === 'new') return renderForm(def, null);
    if (mode === 'edit') return renderForm(def, JSON.parse(decodeURIComponent(key)));
    if (def.功能類型 === '樞紐') return renderPivot(def);
    return renderList(def);
  } catch (e) {
    view.innerHTML = `<div class="empty">⚠ ${esc(e.message)}<br><a href="#/">回主功能表</a></div>`;
  }
}
addEventListener('hashchange', route);

/* ---------- 主功能表 ---------- */
function renderMenu() {
  crumb('');
  const kids = p => 功能表.filter(f => f.上層代碼 === p);
  view.innerHTML = `<section class="menu">${kids(null).map(m => `
    <article class="mod mod-${esc(m.功能代碼)}">
      <header><span class="code">${esc(m.功能代碼)}</span><h2>${esc(m.功能名稱.replace(/^\w+\s*/, ''))}</h2><small>${esc(m.說明)}</small></header>
      ${kids(m.功能代碼).map(g => `
        <div class="grp"><h3>${esc(g.功能名稱)}</h3>
          ${kids(g.功能代碼).map(f => `
            <a class="fn" href="#/f/${esc(f.功能代碼)}"><span>${esc(f.功能名稱)}</span>
              <i class="tag ${f.功能類型 === '報表' ? 'rpt' : ''}">${esc(f.功能類型)}</i></a>`).join('')}
        </div>`).join('')}
    </article>`).join('')}</section>`;
}

/* ---------- 清單 / 報表 ---------- */
async function renderList(def, kw = '') {
  const 維護 = def.功能類型 === '維護', cols = def.主檔欄位;
  view.innerHTML = `
    <div class="toolbar">
      <a href="#/" class="btn">← 功能表</a>
      <h1>${esc(def.功能名稱)}</h1>
      <input id="kw" type="search" placeholder="搜尋…" value="${esc(kw)}">
      ${維護 ? `<a class="btn pri" href="#/f/${def.功能代碼}/new">＋ 新增</a>` : ''}
    </div>
    <div class="tbl"><p class="muted">讀取中…</p></div>`;
  $('#kw').onkeydown = e => { if (e.key === 'Enter') renderList(def, e.target.value); };
  try {
    const rows = await api('清單', { 功能代碼: def.功能代碼, 關鍵字: kw || null });
    const pk = cols.filter(c => c.主鍵).map(c => c.欄位名稱);
    $('.tbl').innerHTML = rows.length ? `<table><thead><tr>${cols.map(c => `<th>${esc(c.欄位名稱)}</th>`).join('')}</tr></thead>
      <tbody>${rows.map(r => `<tr ${維護 ? `data-k="${esc(JSON.stringify(Object.fromEntries(pk.map(k => [k, r[k]]))))}"` : ''}>
        ${cols.map(c => `<td class="${c.資料型別 === 'int' ? 'num' : ''}">${esc(r[c.欄位名稱])}</td>`).join('')}</tr>`).join('')}</tbody></table>
      <p class="muted">共 ${rows.length} 筆${rows.length >= 500 ? '（僅顯示前 500 筆，請用搜尋縮小範圍）' : ''}</p>`
      : '<p class="empty">查無資料</p>';
    if (維護) $('.tbl tbody')?.addEventListener('click', e => {
      const tr = e.target.closest('tr[data-k]');
      if (tr) location.hash = `#/f/${def.功能代碼}/edit/${encodeURIComponent(tr.dataset.k)}`;
    });
  } catch (e) { $('.tbl').innerHTML = `<p class="empty">⚠ ${esc(e.message)}</p>`; }
}

/* ---------- 樞紐分析（api.樞紐 以 PIVOT 產生，前端只畫表） ---------- */
async function renderPivot(def, 年度 = new Date().getFullYear()) {
  view.innerHTML = `
    <div class="toolbar">
      <a href="#/" class="btn">← 功能表</a>
      <h1>${esc(def.功能名稱)} <small>${esc(def.樞紐縱軸)} × 月份．${esc(def.樞紐數值)}</small></h1>
      <label class="yr">年度 <input id="yr" type="number" inputmode="numeric" value="${年度}"></label>
      <button id="go" class="btn pri">查詢</button>
    </div>
    <div class="tbl"><p class="muted">讀取中…</p></div>`;
  const go = () => renderPivot(def, $('#yr').value);
  $('#go').onclick = go; $('#yr').onkeydown = e => { if (e.key === 'Enter') go(); };
  try {
    const r = await api('樞紐', { 功能代碼: def.功能代碼, 年度 });
    const cols = r.資料.length ? Object.keys(r.資料[0]) : [];
    $('.tbl').innerHTML = r.資料.length ? `<table class="pivot"><thead><tr>${cols.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead>
      <tbody>${r.資料.map((row, i) => `<tr class="${i === r.資料.length - 1 ? 'total' : ''}">${cols.map((c, j) =>
        `<td class="${j ? 'num' : ''}">${esc(j && !row[c] ? '' : row[c])}</td>`).join('')}</tr>`).join('')}</tbody></table>`
      : `<p class="empty">${esc(r.年度)} 年度無資料</p>`;
  } catch (e) { $('.tbl').innerHTML = `<p class="empty">⚠ ${esc(e.message)}</p>`; }
}

/* ---------- 維護表單（主檔 + 明細） ---------- */
const lists = new Set();
async function datalist(c) {                    // 下拉選項由 api.選單 提供
  if (!c.選單來源) return '';
  const id = `dl-${c.選單來源}-${c.選單欄位}`;
  if (!lists.has(id)) {
    lists.add(id);
    api('選單', { 來源: c.選單來源, 欄位: c.選單欄位 }).then(opts => {
      let dl = document.getElementById(id);
      if (!dl) { dl = document.createElement('datalist'); dl.id = id; document.body.append(dl); }
      dl.innerHTML = opts.map(o => `<option value="${esc(o.值)}">${esc(o.說明 ?? '')}</option>`).join('');
    }).catch(() => lists.delete(id));
  }
  return id;
}
function input(c, v, o) {
  const type = c.資料型別 === 'date' ? 'date' : /int|decimal|numeric/.test(c.資料型別) ? 'number' : 'text';
  const auto = o.auto, dis = c.唯讀 || o.lock;
  const ph = auto ? '自動編號' : c.有預設 ? '預設' : '';
  return `<input name="${esc(c.欄位名稱)}" type="${type}" value="${esc(v)}" ${type === 'number' ? 'inputmode="numeric"' : ''}
    ${c.長度 > 0 ? `maxlength="${c.長度}"` : ''} ${dis ? 'disabled' : ''} placeholder="${ph}"
    ${!c.可空 && !c.有預設 && !auto && !dis ? 'required' : ''} ${o.list ? `list="${o.list}"` : ''}>`;
}
function collect(el, cols) {
  const o = {};
  for (const c of cols) {
    const i = el.querySelector(`[name="${CSS.escape(c.欄位名稱)}"]`);
    if (!i || i.disabled && !c.主鍵) continue;
    const v = i.value.trim();
    o[c.欄位名稱] = v === '' ? null : i.type === 'number' ? Number(v) : v;
  }
  return o;
}

async function renderForm(def, key) {
  const 新增 = !key, hasD = !!def.明細資料表;
  let data = { 主檔: {}, 明細: [] };
  if (!新增) data = await api('讀取', { 功能代碼: def.功能代碼, 鍵值: key });
  const pkCount = def.主檔欄位.filter(c => c.主鍵).length;
  const dCols = def.明細欄位.filter(c => !c.連結);
  const lid = {};
  for (const c of [...def.主檔欄位, ...dCols]) lid[c.欄位名稱] = await datalist(c);

  const mField = c => `<label class="${c.唯讀 ? 'ro' : ''}"><span>${esc(c.欄位名稱)}${c.主鍵 ? ' 🔑' : ''}</span>
    ${input(c, data.主檔[c.欄位名稱], { lock: c.主鍵 && !新增, auto: c.主鍵 && 新增 && def.單號前綴 && pkCount === 1, list: lid[c.欄位名稱] })}</label>`;
  const dRow = (r = {}) => `<tr>${dCols.map(c => `<td>${input(c, r[c.欄位名稱],
      { lock: c.主鍵 && r[c.欄位名稱] != null, auto: false, list: lid[c.欄位名稱] })
      .replace('placeholder=""', c.主鍵 ? 'placeholder="自動"' : 'placeholder=""').replace(' required', c.主鍵 ? '' : ' required')}</td>`).join('')}
      <td><button type="button" class="x" title="刪除此列">✕</button></td></tr>`;

  view.innerHTML = `
    <form id="frm" novalidate>
      <div class="toolbar">
        <a href="#/f/${def.功能代碼}" class="btn">← 清單</a>
        <h1>${esc(def.功能名稱)} <small>${新增 ? '新增' : '修改'}</small></h1>
        <span class="grow"></span>
        ${新增 ? '' : '<button type="button" id="del" class="btn danger">刪除</button>'}
        <button class="btn pri">存檔</button>
      </div>
      <fieldset class="master">${def.主檔欄位.map(mField).join('')}</fieldset>
      ${hasD ? `<div class="dhead"><h2>明細</h2><button type="button" id="add" class="btn">＋ 新增明細</button></div>
        <div class="tbl"><table class="grid"><thead><tr>${dCols.map(c => `<th>${esc(c.欄位名稱)}</th>`).join('')}<th></th></tr></thead>
        <tbody>${(data.明細.length ? data.明細 : 新增 ? [{}] : []).map(dRow).join('')}</tbody></table></div>` : ''}
    </form>`;

  const f = $('#frm'), tb = $('tbody', f);
  $('#add')?.addEventListener('click', () => { tb.insertAdjacentHTML('beforeend', dRow()); tb.lastElementChild.querySelector('input:not([disabled])')?.focus(); });
  tb?.addEventListener('click', e => { if (e.target.matches('.x')) e.target.closest('tr').remove(); });

  f.onsubmit = async e => {
    e.preventDefault();
    const bad = [...f.querySelectorAll('input[required]')].find(i => !i.value.trim());
    if (bad) { bad.focus(); return toast(`請輸入 ${bad.name}`, true); }
    const 主檔 = collect($('.master', f), def.主檔欄位);
    const 明細 = hasD ? [...tb.rows].map(tr => collect(tr, dCols)) : undefined;
    const 摘要 = `${def.功能名稱}：${主檔[def.主檔欄位[0].欄位名稱] ?? '(新單)'}`;
    try {
      const r = await write('存檔', { 功能代碼: def.功能代碼, 主檔, 明細 }, 摘要);
      if (!r) { toast('離線中：已暫存，連線後自動上傳'); location.hash = `#/f/${def.功能代碼}`; return; }
      toast(r.重送 ? '已存檔（重送確認）' : `存檔完成 ${Object.values(r.鍵值).join('/')}`);
      const h = `#/f/${def.功能代碼}/edit/${encodeURIComponent(JSON.stringify(r.鍵值))}`;
      location.hash === h ? route() : location.hash = h;
    } catch (err) { toast(err.message, true); }
  };
  $('#del')?.addEventListener('click', async ev => {
    const b = ev.currentTarget;
    if (!b.dataset.ok) { b.dataset.ok = 1; b.textContent = '再按一次確認刪除'; return; }
    try {
      const r = await write('刪除', { 功能代碼: def.功能代碼, 鍵值: key }, `刪除 ${def.功能名稱}：${Object.values(key).join('/')}`);
      toast(r ? r.訊息 : '離線中：刪除已暫存，連線後自動上傳');
      location.hash = `#/f/${def.功能代碼}`;
    } catch (err) { toast(err.message, true); }
  });
}

/* ---------- 啟動 ---------- */
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js');
setNet(navigator.onLine);
refreshQ(); syncNow(true); route();
