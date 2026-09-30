// 離線待傳佇列（IndexedDB），頁面與 Service Worker 共用。
// 每筆寫入都帶 請求ID；伺服器端 api.存檔 / api.刪除 以 請求ID 做冪等，重送不會重複入帳。
const Outbox = (() => {
  const open = () => new Promise((ok, no) => {
    const r = indexedDB.open('oav-outbox', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('q', { keyPath: '請求ID' });
    r.onsuccess = () => ok(r.result); r.onerror = () => no(r.error);
  });
  const tx = async (mode, fn) => {
    const db = await open();
    return new Promise((ok, no) => {
      const t = db.transaction('q', mode), s = t.objectStore('q'), r = fn(s);
      t.oncomplete = () => ok(r && r.result); t.onerror = () => no(t.error);
    });
  };
  const put = item => tx('readwrite', s => s.put(item));
  const del = id => tx('readwrite', s => s.delete(id));
  const all = () => tx('readonly', s => s.getAll());

  // 依建立順序逐筆上傳；網路或伺服器暫時性錯誤就停下等下次，商業錯誤則標記失敗不再重送
  let busy = false;
  async function flush() {
    if (busy) return { 上傳: 0 };
    busy = true;
    let 上傳 = 0; const 結果 = [];
    try {
      const items = (await all()).filter(i => !i.錯誤).sort((a, b) => a.時間 - b.時間);
      for (const it of items) {
        let res;
        try {
          res = await fetch('/api/' + encodeURIComponent(it.程序), {
            method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(it.資料)
          });
        } catch { break; }                       // 斷線：留在佇列
        const body = await res.json().catch(() => ({}));
        if (res.ok) { await del(it.請求ID); 上傳++; 結果.push({ ...it, 回應: body }); }
        else if (res.status === 400) { await put({ ...it, 錯誤: body.錯誤 || '上傳失敗' }); 結果.push({ ...it, 錯誤: body.錯誤 }); }
        else break;                              // 503 等可重送錯誤
      }
    } finally { busy = false; }
    return { 上傳, 結果 };
  }
  return { put, del, all, flush };
})();
