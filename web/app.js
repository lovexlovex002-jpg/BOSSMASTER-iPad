// BOSSMASTER iPad - generic source-template searcher (part 1/2)
const DEFAULT_SOURCES = [
  {
    id: "source-template",
    name: "ต้นฉบับเพิ่มเติม (ปิดไว้)",
    enabled: false,
    priority: 50,
    partition: "persist:bossmaster-source-default",
    mode: "browser",
    detailUrlTemplate: "https://example.com/search?q={code}",
    searchResultSelector: "a[href]",
    waitMs: 1500,
    timeoutMs: 45000,
    retry: 3,
    rateLimitMs: 2200,
    proxy: "",
    selectors: {
      title: "h1",
      actor: "[data-actor]",
      actor_en: "",
      studio: "[data-studio]",
      release_date: "time",
      duration: "[data-duration]",
      plot: ".description",
      genres: ".genres",
      cover: "meta[property=\"og:image\"]",
      poster: ".poster img",
      gallery: ".gallery img"
    },
    attributes: {
      cover: "content",
      poster: "src",
      gallery: "src"
    }
  }
];

const $ = (id) => document.getElementById(id);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function loadSources() {
  try {
    const raw = localStorage.getItem("bossmaster_sources");
    if (raw) return JSON.parse(raw);
  } catch (e) {}
  return DEFAULT_SOURCES;
}
function saveSources(s) {
  localStorage.setItem("bossmaster_sources", JSON.stringify(s, null, 2));
}
function parseCodes() {
  const t = $("codes").value || "";
  return [...new Set(t.split(/[\n,;\s]+/).map(s => s.trim().toUpperCase()).filter(Boolean))];
}
function renderSourceUI() {
  const sources = loadSources();
  $("sourcesJson").value = JSON.stringify(sources, null, 2);
  const sel = $("sourceSel");
  sel.innerHTML = "";
  sources.forEach((s, i) => {
    const o = document.createElement("option");
    o.value = String(i);
    o.textContent = (s.enabled ? "OK " : "OFF ") + s.name;
    sel.appendChild(o);
  });
  const idx = Math.max(0, sources.findIndex(s => s.enabled));
  sel.value = String(idx);
  $("proxyInput").value = localStorage.getItem("bossmaster_proxy") || sources[idx]?.proxy || "";
}
function absUrl(url, base) {
  try { return new URL(url, base).href; } catch (e) { return url; }
}
function pickAttr(el, attr) {
  if (!el) return "";
  if (!attr || attr === "text") return (el.textContent || "").trim();
  return el.getAttribute(attr) || (el.textContent || "").trim();
}
async function fetchDoc(url, proxy, timeoutMs) {
  const target = proxy ? proxy + encodeURIComponent(url) : url;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs || 45000);
  try {
    let res;
    try {
      res = await fetch(target, { signal: ctrl.signal });
    } catch (e) {
      const msg = String((e && e.name) || "") + " " + String((e && e.message) || e);
      if (/abort/i.test(msg)) throw new Error("หมดเวลาเชื่อมต่อ (timeout) — VPN อาจช้า/หลุด ลองกดทดสอบ Proxy หรือเปลี่ยน Proxy");
      if (/failed to fetch|networkerror|load failed/i.test(msg)) {
        if (proxy) throw new Error("Failed to fetch ผ่าน Proxy นี้ — Proxy อาจล่ม/บล็อกเว็บนี้ ลองกดทดสอบ Proxy หรือเปลี่ยนตัวใหม่");
        throw new Error("Failed to fetch แบบต่อตรง — โดน CORS บล็อก กรุณาใส่ Proxy ด้านบนแล้วกดทดสอบ Proxy");
      }
      throw e;
    }
    if (!res.ok) {
      if (res.status === 403 || res.status === 401) throw new Error("ต้นทางตอบ " + res.status + " (เว็บกันบอท/ต้อง login) — ลองเปลี่ยน Proxy หรือเปิดต้นฉบับในเบราว์เซอร์ก่อน 1 ครั้ง");
      if (res.status === 404) throw new Error("ต้นทางตอบ 404 — ตรวจ detailUrlTemplate ว่าถูกเว็บ/ถูกรูปแบบ {code} หรือยัง");
      if (res.status === 429) throw new Error("ต้นทางตอบ 429 (โดน rate-limit) — รอสักครู่แล้วค้นทีละรหัส");
      throw new Error("ต้นทางตอบ HTTP " + res.status + " — ลองเปลี่ยน Proxy");
    }
    const html = await res.text();
    if (!html || html.length < 500) throw new Error("โหลดมาได้แต่เนื้อหาว่าง/สั้นผิดปกติ — เว็บอาจกันบอทด้วย JavaScript ต้องใช้ Proxy แบบ render หรือเปิดต้นฉบับเอง");
    return new DOMParser().parseFromString(html, "text/html");
  } finally { clearTimeout(t); }
}
async function searchOne(code, source, proxy) {
  const url = (source.detailUrlTemplate || "").replace("{code}", encodeURIComponent(code));
  if (!url.startsWith("http")) return { code, url, error: "ยังไม่ได้ตั้ง detailUrlTemplate" };
  let lastErr = "";
  const retry = source.retry ?? 2;
  for (let a = 0; a <= retry; a++) {
    try {
      if (source.rateLimitMs) await sleep(source.rateLimitMs);
      const doc = await fetchDoc(url, proxy, source.timeoutMs);
      const S = source.selectors || {};
      const A = source.attributes || {};
      const q = (sel) => sel ? doc.querySelector(sel) : null;
      const qa = (sel) => sel ? [...doc.querySelectorAll(sel)] : [];
      const get = (key, defAttr) => pickAttr(q(S[key]), A[key] || defAttr || "text");
      const gallery = qa(S.gallery).map(el => absUrl(pickAttr(el, A.gallery || "src"), url)).filter(Boolean);
      return {
        code, url, title: get("title"), actor: get("actor"),
        studio: get("studio"), release_date: get("release_date"),
        duration: get("duration"), plot: get("plot"), genres: get("genres"),
        cover: absUrl(get("cover", "content"), url),
        poster: absUrl(get("poster", "src"), url), gallery
      };
    } catch (e) { lastErr = String((e && e.message) || e); await sleep(800); }
  }
  return { code, url, error: "โหลดไม่ได้: " + lastErr + " ลองเปิด VPN / ใส่ Proxy" };
}
function esc(s){return String(s||"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
function cardHTML(r) {
  const imgs = [...new Set([r.cover, r.poster, ...(r.gallery || [])].filter(Boolean))];
  const meta = [r.title, r.actor && ("นักแสดง: " + r.actor), r.studio && ("ค่าย: " + r.studio), r.release_date && ("วางจำหน่าย: " + r.release_date), r.duration && ("ความยาว: " + r.duration), r.genres && ("แนว: " + r.genres), r.plot].filter(Boolean).join("\n");
  return '<div class="card" data-code="' + r.code + '"><div class="p"><div class="code">' + r.code + '</div><div class="meta">' + esc(meta).replace(/\n/g,"<br>") + '</div><div class="btns"><a href="' + r.url + '" target="_blank" rel="noopener">เปิดต้นฉบับ</a><button data-dl="' + r.code + '">โหลดรูป (' + imgs.length + ')</button></div></div>' + imgs.map((u,i)=>'<img loading="lazy" src="'+u+'" alt="'+r.code+' '+(i+1)+'">').join("") + '<div class="p"><div class="btns">' + imgs.map(u=>'<a href="'+u+'" download="'+r.code+'.jpg" target="_blank" rel="noopener">รูป</a>').join("") + '</div></div></div>';
}
async function downloadAll(card) {
  const links = [...card.querySelectorAll("a[download]")];
  for (const a of links) {
    const tmp = document.createElement("a");
    tmp.href = a.href; tmp.download = a.getAttribute("download") || "image.jpg";
    tmp.target = "_blank"; tmp.rel = "noopener";
    document.body.appendChild(tmp); tmp.click(); tmp.remove();
    await sleep(900);
  }
}
$("btnSearch").onclick = async () => {
  const sources = loadSources();
  const src = sources[Number($("sourceSel").value) || 0];
  if (!src) return alert("ยังไม่มี source");
  const proxy = $("proxyInput").value.trim();
  localStorage.setItem("bossmaster_proxy", proxy);
  const codes = parseCodes();
  if (!codes.length) return alert("วางรหัสก่อน เช่น START-628");
  if (!src.enabled && !confirm('แหล่ง "' + src.name + '" ยังปิดไว้ จะลองค้นเลยไหม?')) return;
  $("results").innerHTML = "";
  for (const code of codes) {
    const div = document.createElement("div");
    div.innerHTML = '<div class="hint">ค้น ' + code + ' ...</div>';
    $("results").appendChild(div);
    const r = await searchOne(code, src, proxy || src.proxy);
    if (r.error) div.innerHTML = '<div class="card"><div class="p"><div class="code">' + code + '</div><div class="meta">' + esc(r.error) + '</div><div class="btns"><a href="' + r.url + '" target="_blank">ลองเปิดเอง</a></div></div></div>';
    else {
      div.innerHTML = cardHTML(r);
      const btn = div.querySelector("[data-dl]");
      if (btn) btn.onclick = (e) => downloadAll(e.target.closest(".card"));
    }
  }
};
$("btnSaveAll").onclick = async () => {
  const cards = [...document.querySelectorAll(".card")];
  if (!cards.length) return alert("กดค้นหาก่อน");
  for (const c of cards) await downloadAll(c);
};
$("btnClear").onclick = () => { $("results").innerHTML = ""; };
$("proxyPreset").onchange = (e) => {
  const v = e.target.value;
  if (!v) return;
  if (v === "CUSTOM") {
    alert("สร้าง Proxy เองฟรี: เปิด Cloudflare Workers → วางโค้ดจากไฟล์ cors-proxy-worker.js ใน repo → Deploy → เอา URL มาใส่ช่อง Proxy");
    e.target.value = "";
    return;
  }
  $("proxyInput").value = v;
  localStorage.setItem("bossmaster_proxy", v);
};
$("btnTestProxy").onclick = async () => {
  const box = $("proxyTestResult");
  const proxy = $("proxyInput").value.trim();
  localStorage.setItem("bossmaster_proxy", proxy);
  box.style.display = "block";
  if (!proxy) {
    box.textContent = "⚠️ ยังไม่ได้ใส่ Proxy — การต่อตรงมักโดน CORS บล็อก เลือก Proxy สำเร็จรูปด้านบนก่อน";
    return;
  }
  box.textContent = "⏳ กำลังทดสอบ Proxy...";
  const tests = ["https://example.com/", "https://httpbin.org/get"];
  for (const u of tests) {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 20000);
      const res = await fetch(proxy + encodeURIComponent(u), { signal: ctrl.signal });
      clearTimeout(t);
      const txt = await res.text();
      if (res.ok && txt.length > 50) {
        box.textContent = "✅ Proxy ใช้ได้ (โหลด " + u + " สำเร็จ " + txt.length + " ตัวอักษร) — ถ้าค้นแล้วยัง Failed to fetch แปลว่าเว็บต้นทางบล็อกเว็บนี้โดยเฉพาะ";
        return;
      }
      box.textContent = "⚠️ Proxy ตอบ HTTP " + res.status + " ที่ " + u + " — ลองเปลี่ยน Proxy ตัวอื่น";
      return;
    } catch (e) {
      box.textContent = "❌ Proxy นี้ใช้ไม่ได้ (" + String((e && e.message) || e) + ") — ลองเปลี่ยนตัวอื่น หรือสร้าง Worker เองตามวิธีใน ❓";
      return;
    }
  }
};
$("btnSaveSrc").onclick = () => {
  try { const s = JSON.parse($("sourcesJson").value); saveSources(s); renderSourceUI(); alert("บันทึกแล้ว"); }
  catch(e){ alert("JSON ผิด: " + e.message); }
};
$("btnResetSrc").onclick = () => { saveSources(DEFAULT_SOURCES); renderSourceUI(); };
renderSourceUI();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(()=>{});

