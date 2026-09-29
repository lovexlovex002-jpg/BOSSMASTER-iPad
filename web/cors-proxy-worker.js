// Cloudflare Worker — CORS Proxy ส่วนตัวสำหรับ BOSSMASTER iPad (ฟรี)
// วิธีใช้:
// 1) ไป https://workers.cloudflare.com → สร้าง Worker ใหม่
// 2) ลบโค้ดเดิม วางไฟล์นี้ทั้งหมด → Deploy
// 3) จะได้ URL เช่น https://bossmaster-proxy.xxx.workers.dev
// 4) เอาไปใส่ช่อง Proxy ในแอปแบบนี้: https://bossmaster-proxy.xxx.workers.dev/?url=
// 5) กด "ทดสอบ Proxy" ในแอปก่อนค้นจริง
//
// หมายเหตุ: อย่าใส่ API key / รหัสผ่านใดๆ ในไฟล์นี้

const ALLOWED_TARGETS = [
  // ใส่โดเมนเว็บต้นทางของคุณที่นี่เพื่อกันคนอื่นเอา Worker ไปใช้มั่ว เช่น:
  // "example.com",
];
// เว้นว่าง [] = อนุญาตทุกโดเมน (ง่ายสุดตอนทดสอบ)

function isAllowed(targetUrl) {
  if (!ALLOWED_TARGETS.length) return true;
  try {
    const host = new URL(targetUrl).hostname.toLowerCase();
    return ALLOWED_TARGETS.some((d) => host === d || host.endsWith("." + d));
  } catch {
    return false;
  }
}

export default {
  async fetch(request) {
    const reqUrl = new URL(request.url);

    // หน้าแนะนำตอนเปิด Worker ตรงๆ
    if (!reqUrl.searchParams.has("url")) {
      return new Response(
        "BOSSMASTER CORS Proxy OK. วิธีใช้: " +
          reqUrl.origin +
          "/?url=" +
          encodeURIComponent("https://example.com/"),
        { headers: { "content-type": "text/plain; charset=utf-8" } }
      );
    }

    const target = reqUrl.searchParams.get("url") || "";
    if (!/^https?:\/\//i.test(target)) {
      return new Response("missing ?url=https://...", { status: 400 });
    }
    if (!isAllowed(target)) {
      return new Response("domain not allowed", { status: 403 });
    }

    const headers = new Headers();
    headers.set(
      "User-Agent",
      "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    );
    const accept = request.headers.get("accept");
    if (accept) headers.set("Accept", accept);
    headers.set("Accept-Language", "th-TH,th;q=0.9,en;q=0.8");

    try {
      const upstream = await fetch(target, {
        method: "GET",
        headers,
        redirect: "follow",
      });
      const body = await upstream.arrayBuffer();
      const out = new Headers();
      const ct = upstream.headers.get("content-type");
      if (ct) out.set("content-type", ct);
      out.set("access-control-allow-origin", "*");
      out.set("access-control-allow-methods", "GET, OPTIONS");
      out.set("access-control-allow-headers", "*");
      out.set("cache-control", "public, max-age=120");
      return new Response(body, { status: upstream.status, headers: out });
    } catch (e) {
      return new Response("proxy fetch failed: " + String((e && e.message) || e), {
        status: 502,
        headers: { "access-control-allow-origin": "*" },
      });
    }
  },
};
