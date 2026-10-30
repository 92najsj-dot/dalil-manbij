import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const BUCKET = "manbij-images";
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp", "image/avif"]);

function cors(origin: string | null) {
  const allowed = !!origin && /^https:\/\/(?:[a-z0-9-]+\.)?dalil-manbij-new\.pages\.dev$/i.test(origin);
  return {
    "Access-Control-Allow-Origin": allowed ? origin! : "https://dalil-manbij-new.pages.dev",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
function reply(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors(origin), "Content-Type": "application/json", "Cache-Control": "no-store" } });
}
async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function clean(value: FormDataEntryValue | null, max: number) {
  return String(value ?? "").replace(/\u0000/g, "").trim().slice(0, max);
}
function phoneDigits(value: string) { return value.replace(/[^0-9+]/g, "").replace(/^00/, "+"); }

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return reply({ error: "الطريقة غير مدعومة." }, 405, origin);
  if (!origin || !/^https:\/\/(?:[a-z0-9-]+\.)?dalil-manbij-new\.pages\.dev$/i.test(origin)) {
    return reply({ error: "مصدر الطلب غير مسموح." }, 403, origin);
  }

  try {
    const form = await req.formData();
    if (clean(form.get("website"), 200)) return reply({ ok: true, message: "تم استلام الطلب." }, 200, origin); // honeypot
    const durationDays = Number(clean(form.get("duration_days"), 2) || "7");
    if (![3, 7, 15, 30].includes(durationDays)) return reply({ error: "اختر مدة الإعلان الصحيحة." }, 400, origin);
    const expiresAt = new Date(Date.now() + durationDays * 86400000).toISOString();
    const title = clean(form.get("title"), 120);
    const description = clean(form.get("description"), 3000);
    const category = clean(form.get("category"), 80) || "أخرى";
    const area = clean(form.get("area"), 100) || "منبج";
    const village = clean(form.get("village"), 100);
    const condition = clean(form.get("item_condition"), 20) || "used";
    const currency = clean(form.get("currency"), 3);
    const priceText = clean(form.get("price"), 32);
    const phone = phoneDigits(clean(form.get("contact_phone"), 40));
    const files = form.getAll("photos").filter((x): x is File => x instanceof File && x.size > 0);

    if (title.length < 3) return reply({ error: "عنوان الإعلان لازم يكون 3 أحرف على الأقل." }, 400, origin);
    if (!priceText || !Number.isFinite(Number(priceText)) || Number(priceText) < 0) return reply({ error: "أدخل سعراً صحيحاً." }, 400, origin);
    if (!["SYP", "USD"].includes(currency)) return reply({ error: "اختر العملة الصحيحة." }, 400, origin);
    if (!["used", "new", "service"].includes(condition)) return reply({ error: "اختر حالة الإعلان الصحيحة." }, 400, origin);
    if (phone.replace(/\D/g, "").length < 8 || phone.replace(/\D/g, "").length > 15) return reply({ error: "أدخل رقم هاتف صحيحاً للتواصل." }, 400, origin);
    if (files.length > 4) return reply({ error: "يمكن رفع 4 صور كحد أقصى." }, 400, origin);
    for (const file of files) {
      if (file.size > MAX_FILE_BYTES) return reply({ error: "حجم كل صورة يجب ألا يتجاوز 5 ميغابايت." }, 400, origin);
      if (!ALLOWED_MIME.has(file.type)) return reply({ error: "صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WebP أو AVIF." }, 400, origin);
    }

    const client = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const forwarded = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim();
    const ipSource = forwarded || req.headers.get("cf-connecting-ip") || "unknown";
    const ipHash = await sha256(SERVICE_ROLE_KEY + ":ip:" + ipSource);
    const phoneHash = await sha256(SERVICE_ROLE_KEY + ":phone:" + phone.replace(/\D/g, ""));
    const [{ count: ipCount, error: ipErr }, { count: phoneCount, error: phoneErr }] = await Promise.all([
      client.from("guest_listing_submissions").select("id", { count: "exact", head: true }).eq("ip_hash", ipHash).gte("created_at", cutoff),
      client.from("guest_listing_submissions").select("id", { count: "exact", head: true }).eq("phone_hash", phoneHash).gte("created_at", cutoff),
    ]);
    if (ipErr || phoneErr) throw new Error("تعذّر التحقق من حد النشر.");
    if ((ipCount ?? 0) >= 5 || (phoneCount ?? 0) >= 3) return reply({ error: "وصلت للحد اليومي للنشر كزائر. جرّب بعد 24 ساعة أو سجّل الدخول." }, 429, origin);
    // Record the rate-limit entry only after the listing is successfully saved,
    // so failed validation/database attempts do not lock a legitimate guest out.
    const imageUrls: string[] = [];
    for (const file of files) {
      const ext = ({ "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/avif": "avif" } as Record<string, string>)[file.type];
      const path = `guest-listings/${crypto.randomUUID()}.${ext}`;
      const upload = await client.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false, cacheControl: "3600" });
      if (upload.error) throw new Error("تعذّر رفع إحدى الصور. حاول مرة أخرى.");
      const { data } = client.storage.from(BUCKET).getPublicUrl(path);
      imageUrls.push(data.publicUrl);
    }

    const { data, error } = await client.from("listings").insert({
      user_id: null,
      title,
      description: description || null,
      price: Number(priceText),
      currency,
      category,
      item_condition: condition,
      area,
      village: village || null,
      contact_phone: phone,
      image_urls: imageUrls,
      status: "pending",
      duration_days: durationDays,
      expires_at: expiresAt,
    }).select("id,status").single();
    if (error) {
      console.error("guest listing insert failed", error.message);
      throw new Error("تعذّر حفظ الإعلان. حاول مرة أخرى بعد قليل.");
    }
    const rate = await client.from("guest_listing_submissions").insert({ ip_hash: ipHash, phone_hash: phoneHash });
    if (rate.error) console.error("guest rate-limit record failed after listing saved", rate.error.message);

    // Keep the rate-limit table bounded.
    await client.from("guest_listing_submissions").delete().lt("created_at", new Date(Date.now() - 30 * 86400000).toISOString());
    return reply({ ok: true, id: data.id, status: data.status, message: "وصل إعلانك للإدارة، وسيظهر بعد المراجعة." }, 201, origin);
  } catch (error) {
    console.error("guest-listing:", error instanceof Error ? error.message : error);
    return reply({ error: error instanceof Error ? error.message : "حدث خطأ غير متوقع." }, 400, origin);
  }
});