// Đăng ký service worker (chỉ bản build) + bắt sự kiện "cài app" và "có bản mới".
const listeners = new Set();
const state = { installEvt: null, update: null, installed: false };
const emit = () => listeners.forEach((f) => f({ ...state }));

export function onPwa(fn) { listeners.add(fn); fn({ ...state }); return () => listeners.delete(fn); }

export async function promptInstall() {
  const e = state.installEvt; if (!e) return false;
  e.prompt(); const r = await e.userChoice.catch(() => null);
  state.installEvt = null; emit();
  return r?.outcome === "accepted";
}

export function applyUpdate() {
  const w = state.update; if (!w) return;
  navigator.serviceWorker.addEventListener("controllerchange", () => location.reload(), { once: true });
  w.postMessage("skipWaiting");
}

export function registerPwa() {
  window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); state.installEvt = e; emit(); });
  window.addEventListener("appinstalled", () => { state.installEvt = null; state.installed = true; emit(); });
  if (!import.meta.env.PROD || !("serviceWorker" in navigator)) return;
  window.addEventListener("load", async () => {
    try {
      const reg = await navigator.serviceWorker.register("/sw.js");
      const track = (w) => w && w.addEventListener("statechange", () => {
        if (w.state === "installed" && navigator.serviceWorker.controller) { state.update = w; emit(); }
      });
      if (reg.waiting && navigator.serviceWorker.controller) { state.update = reg.waiting; emit(); }
      reg.addEventListener("updatefound", () => track(reg.installing));
      setInterval(() => reg.update().catch(() => {}), 60 * 60 * 1000);
    } catch { /* không có SW vẫn chạy bình thường */ }
  });
}
