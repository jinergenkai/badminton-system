// Store sổ tiền cho React — port logic §2 của sổ cũ: đọc/ghi /api/data, lưu gộp,
// chống đè theo rev (409 -> conflict), cache localStorage, nhật ký, hàng đợi lưu.
// Quyền admin lấy từ AuthProvider dùng chung (mật khẩu chung cả app).
import { useCallback, useEffect, useRef, useState } from "react";
import { migrate, EMPTY_BOOK, LOG_MAX } from "./model.js";
import { useAuth } from "./auth.jsx";

const CACHE_KEY = "bmw_book_cache";
const SAVE_DELAY = 1200, RETRY_DELAY = 4000, MAX_RETRY = 3;

const clone = (o) => JSON.parse(JSON.stringify(o));

function readCache() {
  try { const raw = localStorage.getItem(CACHE_KEY); return raw ? JSON.parse(raw) : null; }
  catch { return null; }
}

async function apiGet() {
  const r = await fetch("/api/data", { cache: "no-store" });
  if (!r.ok) { let e = ""; try { e = (await r.json()).error; } catch { /* */ } throw new Error("HTTP " + r.status + (e ? " — " + e : "")); }
  return r.json();
}

export function useBook() {
  const auth = useAuth();
  const [book, setBook] = useState(null);
  const [rev, setRev] = useState(0);
  const [updatedAt, setUpdatedAt] = useState(null);
  const [online, setOnline] = useState(true);
  const [loadErr, setLoadErr] = useState("");
  const [save, setSave] = useState({ dirty: false, saving: false, err: "", savedAt: null, retries: 0 });
  const [conflict, setConflict] = useState(null); // {rev,updatedAt,data}

  // refs cho giá trị thay đổi nhanh, tránh stale closure trong push()
  const ref = useRef({ book: null, rev: 0, localSeq: 0, saving: false, dirty: false, timer: null });
  const pass = auth.pass;
  const isAdmin = auth.isAdmin;

  const writeCache = useCallback((b, r, u, dirty) => {
    try { localStorage.setItem(CACHE_KEY, JSON.stringify({ rev: r, updatedAt: u, data: b, dirty })); } catch { /* */ }
  }, []);

  const push = useCallback(async function push(forceRev) {
    const c = ref.current;
    const pw = auth.passRef.current;
    if (!pw || c.saving) return;
    clearTimeout(c.timer);
    c.saving = true;
    setSave((s) => ({ ...s, saving: true, err: "" }));
    const seq = c.localSeq;
    let conflictData = null, err = "";
    try {
      const r = await fetch("/api/data", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pass: pw, rev: forceRev === undefined ? c.rev : forceRev, data: c.book }),
      });
      const j = await r.json().catch(() => ({}));
      if (r.status === 409) conflictData = j.server || null;
      else if (!r.ok) throw new Error(j.error || "HTTP " + r.status);
      else {
        c.rev = j.rev; setRev(j.rev); setUpdatedAt(j.updatedAt); setOnline(true);
        const stillDirty = c.localSeq !== seq;
        c.dirty = stillDirty;
        setSave({ dirty: stillDirty, saving: false, err: "", savedAt: Date.now(), retries: 0 });
        writeCache(c.book, j.rev, j.updatedAt, stillDirty);
      }
    } catch (e) { err = e.message || String(e); }
    c.saving = false;
    if (conflictData) { setSave((s) => ({ ...s, saving: false })); setConflict(conflictData); return; }
    if (err) {
      setSave((s) => {
        const retries = s.retries;
        if (retries < MAX_RETRY) { clearTimeout(c.timer); c.timer = setTimeout(() => push(), RETRY_DELAY); return { ...s, saving: false, err, retries: retries + 1 }; }
        return { ...s, saving: false, err };
      });
      return;
    }
    if (c.dirty) { clearTimeout(c.timer); c.timer = setTimeout(() => push(), 200); }
  }, [writeCache, auth.passRef]);

  const schedulePush = useCallback((ms) => {
    const c = ref.current; clearTimeout(c.timer); c.timer = setTimeout(() => push(), ms ?? SAVE_DELAY);
  }, [push]);

  // Sửa sổ: fn(draft) đổi tại chỗ; ghi nhật ký msg; lưu gộp.
  const mutate = useCallback((fn, msg) => {
    setBook((prev) => {
      const next = clone(prev);
      fn(next);
      if (msg) {
        if (!Array.isArray(next.log)) next.log = [];
        const last = next.log[next.log.length - 1];
        if (last && last.m === msg && Date.now() - new Date(last.t).getTime() < 60000) last.t = new Date().toISOString();
        else next.log.push({ t: new Date().toISOString(), m: msg });
        if (next.log.length > LOG_MAX) next.log = next.log.slice(-LOG_MAX);
      }
      ref.current.book = next;
      ref.current.localSeq++;
      ref.current.dirty = true;
      writeCache(next, ref.current.rev, updatedAt, true);
      return next;
    });
    setSave((s) => ({ ...s, dirty: true }));
    schedulePush();
  }, [schedulePush, writeCache, updatedAt]);

  // boot
  useEffect(() => {
    let unsaved = false;
    const c = readCache();
    if (c) { try { const b = migrate(c.data); setBook(b); setRev(c.rev || 0); setUpdatedAt(c.updatedAt || null); ref.current.book = b; ref.current.rev = c.rev || 0; unsaved = !!c.dirty; } catch { /* */ } }
    const savedPass = auth.passRef.current;
    (async () => {
      try {
        const j = await apiGet();
        if (unsaved && savedPass && JSON.stringify(j.data) !== JSON.stringify(ref.current.book)) {
          setOnline(true); setLoadErr(""); setConflict({ rev: j.rev || 0, updatedAt: j.updatedAt || null, data: j.data }); return;
        }
        const b = migrate(j.data); setBook(b); setRev(j.rev || 0); setUpdatedAt(j.updatedAt || null);
        ref.current.book = b; ref.current.rev = j.rev || 0;
        setOnline(true); setLoadErr(""); setSave((s) => ({ ...s, dirty: false })); ref.current.dirty = false;
        writeCache(b, j.rev || 0, j.updatedAt || null, false);
      } catch (e) {
        setOnline(false); setLoadErr(e.message || String(e));
        setBook((prev) => prev || migrate(EMPTY_BOOK()));
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // giữ ref.current.book/rev đồng bộ với state hiện tại
  useEffect(() => { ref.current.book = book; ref.current.rev = rev; });

  // Đăng nhập: xác thực qua auth rồi lấy bản mới nhất trước khi sửa.
  const login = useCallback(async (pw) => {
    await auth.login(pw);
    try { const j = await apiGet(); const b = migrate(j.data); setBook(b); setRev(j.rev || 0); setUpdatedAt(j.updatedAt || null); ref.current.book = b; ref.current.rev = j.rev || 0; } catch { /* */ }
  }, [auth]);

  const logout = useCallback(() => { auth.logout(); }, [auth]);

  const resolveConflict = useCallback((take) => {
    const srv = conflict; setConflict(null);
    if (!srv) return;
    if (take) { const b = migrate(srv.data); setBook(b); setRev(srv.rev); setUpdatedAt(srv.updatedAt); ref.current.book = b; ref.current.rev = srv.rev; ref.current.dirty = false; setSave((s) => ({ ...s, dirty: false })); writeCache(b, srv.rev, srv.updatedAt, false); }
    else push(srv.rev);
  }, [conflict, push, writeCache]);

  return { book, rev, updatedAt, online, loadErr, isAdmin, pass, save, conflict,
    mutate, login, logout, resolveConflict, saveNow: () => push() };
}
