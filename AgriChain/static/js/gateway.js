/* =====================================================================
   AgriChain Gateway Dynamic Telemetry & Toast Handler
   ===================================================================== */
document.addEventListener("DOMContentLoaded", () => {
  // Auto-dismiss flash toast in gateway host if present
  const toastHost = document.querySelector(".gw-toast-host");
  if (toastHost && toastHost.textContent.trim()) {
    setTimeout(() => {
      toastHost.style.transition = "opacity 240ms ease";
      toastHost.style.opacity = "0";
      setTimeout(() => (toastHost.innerHTML = ""), 260);
    }, 4500);
  }

  // Poll /api/health every 20s to keep gateway metrics fresh
  async function syncHealth() {
    try {
      const res = await fetch("/api/health", { headers: { Accept: "application/json" } });
      if (!res.ok) return;
      const data = await res.json();
      if (!data.ok || !data.metrics) return;

      const m = data.metrics;
      document.querySelectorAll("[data-live-metric]").forEach((el) => {
        const key = el.getAttribute("data-live-metric");
        if (key === "rbks" && m.rbks !== undefined) {
          el.textContent = `${m.rbks} centers`;
        } else if (m[key] !== undefined) {
          el.textContent = String(m[key]);
        }
      });
    } catch {
      // silent fallback on transient offline state
    }
  }

  setInterval(syncHealth, 20000);
});
