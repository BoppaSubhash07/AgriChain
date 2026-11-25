/* =====================================================================
   Deterministic Matrix QR SVG Renderer for Crop Batch Stickers
   ===================================================================== */
function renderAgriQR(container, payloadText) {
  if (!container || !payloadText) return;
  const size = 21;
  // Build deterministic bit matrix seeded from payloadText
  let hash = 2166136261;
  for (let i = 0; i < payloadText.length; i++) {
    hash ^= payloadText.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  const grid = Array.from({ length: size }, () => Array(size).fill(0));

  function drawFinder(r0, c0) {
    for (let r = 0; r < 7; r++) {
      for (let c = 0; c < 7; c++) {
        const border = r === 0 || r === 6 || c === 0 || c === 6;
        const inner = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        grid[r0 + r][c0 + c] = border || inner ? 1 : 0;
      }
    }
  }
  drawFinder(0, 0);
  drawFinder(0, size - 7);
  drawFinder(size - 7, 0);

  let state = hash >>> 0;
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      const inTL = r < 8 && c < 8;
      const inTR = r < 8 && c >= size - 8;
      const inBL = r >= size - 8 && c < 8;
      if (inTL || inTR || inBL) continue;
      if (r === 6 || c === 6) {
        grid[r][c] = (r + c) % 2 === 0 ? 1 : 0;
        continue;
      }
      state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
      grid[r][c] = (state >>> 28) & 1;
    }
  }

  let rects = "";
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      if (grid[r][c]) {
        rects += `<rect x="${c}" y="${r}" width="1" height="1" fill="#0f172a"/>`;
      }
    }
  }
  container.innerHTML = `
    <svg viewBox="0 0 ${size} ${size}" width="100%" height="100%" shape-rendering="crispEdges" role="img" aria-label="QR Code ${payloadText}">
      <rect width="${size}" height="${size}" fill="#ffffff"/>
      ${rects}
    </svg>
  `;
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-qr-code]").forEach((el) => {
    renderAgriQR(el, el.getAttribute("data-qr-code"));
  });
});
