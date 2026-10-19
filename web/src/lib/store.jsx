// Kho sổ tiền — port mục 2 của sổ cũ (web/_legacy/index.html): đọc /api/data, cache
// offline, lưu gộp + xếp hàng theo localSeq, thử lại, chống đè theo rev (409 → hộp chọn).
// Cùng key localStorage với sổ cũ để người đang dùng chuyển sang không mất gì.
import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import * as M from "./model.js";
import { shrink } from "./images.js";

const CACHE_KEY = "caulong_cache", PASS_KEY = "caulong_pass", ME_KEY = "caulong_me";
const SAVE_DELAY = 1200, RETRY_DELAY = 4000, MAX_RETRY = 3;
const AV_SIZE = 96, PHOTO_SIZE = 340;

const ls = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* đầy/khoá */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* */ } },
};

const BookCtx = createContext(null);
export const useBook = () => useContext(BookCtx);

export function BookProvider({ children }) {
  const st = useRef(null);                      // sổ (mutable, như `st` cũ); null = chưa tải
  const meta = useRef({
    rev: 0, updatedAt: null, dirty: false, saving: false, saveErr: "",
    savedAt: null, retries: 0, localSeq: 0, pass: "",
  });
  const timer = useRef(null);
  const pushRef = useRef(null);
  const [, setTick] = useState(0);
  const rerender = useCallback(() => setTick((t) => t + 1), []);

  const [status, setStatus] = useState({ online: true, loadErr: "", fromCache: false });
  const [isAdmin, setIsAdmin] = useState(false);
  const [previewing, setPreviewing] = useState(false);
  const [loginOpen, setLoginOpen] = useState(false);
  const [conflict, setConflict] = useState(null);
  const [toast, setToast] = useState(null);       // {msg, undo, key}
  const [picTarget, setPicTarget] = useState(null); // {k:"m"|"s", id}
  const [image, setImage] = useState(null);       // {canvas, filename}
  const [zoom, setZoom] = useState(null);         // session có ảnh
  const [me, setMeRaw] = useState(() =>
    new URLSearchParams(window.location.search).get("me") || ls.get(ME_KEY) || null);

  const setMe = (id) => { setMeRaw(id); if (id) ls.set(ME_KEY, id); else ls.del(ME_KEY); };
  const showToast = (msg, undo) => setToast({ msg, undo: undo || null, key: Date.now() + Math.random() });

  const writeCache = () => {
    const m = meta.current;
    ls.set(CACHE_KEY, JSON.stringify({ rev: m.rev, updatedAt: m.updatedAt, data: st.current, dirty: m.dirty }));
  };
  const schedule = (ms) => {
    clearTimeout(timer.current);
    timer.current = setTimeout(() => pushRef.current(), ms || SAVE_DELAY);
  };

  /* Lưu: đang gửi mà có thay đổi mới thì xếp hàng, không bao giờ vứt. Chỉ xoá cờ dirty
     khi localSeq không nhúc nhích trong lúc gửi (giống hệt sổ cũ). */
  const push = async (forceRev) => {
    const m = meta.current;
    if (!m.pass || m.saving) return;
    clearTimeout(timer.current);
    m.saving = true; m.saveErr = ""; rerender();
    const seq = m.localSeq;
    let conflictData = null;
    try {
      const r = await fetch("/api/data", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pass: m.pass, rev: forceRev === undefined ? m.rev : forceRev, data: st.current }),
      });
      const j = await r.json().catch(() => ({}));
      if (r.status === 409) conflictData = j.server || { rev: "?", updatedAt: null, data: null };
      else if (!r.ok) throw new Error(j.error || "HTTP " + r.status);
      else {
        m.rev = j.rev; m.updatedAt = j.updatedAt; m.savedAt = Date.now(); m.retries = 0;
        setStatus((s) => ({ ...s, online: true }));
        if (m.localSeq === seq) m.dirty = false;
        writeCache();
      }
    } catch (e) { m.saveErr = e.message || String(e); }
    m.saving = false; rerender();
    if (conflictData) { setConflict(conflictData); return; }
    if (m.saveErr) { if (m.retries < MAX_RETRY) { m.retries++; schedule(RETRY_DELAY); } return; }
    if (m.dirty) schedule(200);
  };
  pushRef.current = push;

  // Nhật ký sửa đổi: thao tác giống hệt lặp lại trong 1 phút thì gộp.
  const logAdd = (msg) => {
    const b = st.current;
    if (!Array.isArray(b.log)) b.log = [];
    const last = b.log[b.log.length - 1];
    if (last && last.m === msg && Date.now() - new Date(last.t).getTime() < 60000)