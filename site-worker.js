// The promo video needs byte ranges so browsers can seek it and iPhones can play it. Static assets
// ignore Range, so this worker answers for that one path, named in wrangler.jsonc, and slices the file itself.
export default {
  async fetch(request, env) {
    const asset = await env.ASSETS.fetch(request.url);
    if (!asset.ok) {
      return asset;
    }
    const bytes = await asset.arrayBuffer();
    const size = bytes.byteLength;
    const headers = new Headers(asset.headers);
    headers.set("Accept-Ranges", "bytes");
    headers.set("Content-Length", String(size));
    const head = request.method === "HEAD";
    const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("Range") || "");
    const ifRange = request.headers.get("If-Range");
    const stale = ifRange !== null && ifRange !== asset.headers.get("ETag");
    if (!match || (match[1] === "" && match[2] === "") || stale) {
      return new Response(head ? null : bytes, { headers });
    }
    const start = match[1] === "" ? Math.max(size - Number(match[2]), 0) : Number(match[1]);
    const end = match[1] === "" || match[2] === "" ? size - 1 : Math.min(Number(match[2]), size - 1);
    if (start > end) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } });
    }
    headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
    headers.set("Content-Length", String(end - start + 1));
    return new Response(head ? null : bytes.slice(start, end + 1), { status: 206, headers });
  },
};
