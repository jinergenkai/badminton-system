// Quyền quản trị DÙNG CHUNG cho cả app (tạm thời 1 mật khẩu): mở khoá là bật
// admin cho Tiền cầu + nút cào Sân trống + Pickup. Kiểm mật khẩu qua /api/data
// (cùng ADMIN_PASS của sổ). Lưu ở localStorage "caulong_pass" — khớp bản gốc.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";

const PASS_KEY = "caulong_pass";
const AuthCtx = createContext(null);

export function AuthProvider({ children }) {
  const [pass, setPass] = useState("");
  const [isAdmin, setIsAdmin] = useState(false);
  const passRef = useRef("");

  // Khởi động: có mật khẩu đã lưu thì bật admin luôn (lần lưu sẽ tự xác thực lại).
  useEffect(() => {
    try { const p = localStorage.getItem(PASS_KEY); if (p) { setPass(p); setIsAdmin(true); passRef.current = p; } } catch { /* */ }
  }, []);

  const login = useCallback(async (pw) => {
    const r = await fetch("/api/data", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pass: pw, check: 1 }),
    });
    if (!r.ok) { const j = await r.json().catch(() => ({})); throw new Error(j.error || "Sai mật khẩu."); }
    setPass(pw); setIsAdmin(true); passRef.current = pw;
    try { localStorage.setItem(PASS_KEY, pw); } catch { /* */ }
  }, []);

  const logout = useCallback(() => {
    setPass(""); setIsAdmin(false); passRef.current = "";
    try { localStorage.removeItem(PASS_KEY); } catch { /* */ }
  }, []);

  const value = useMemo(() => ({ pass, isAdmin, login, logout, passRef }), [pass, isAdmin, login, logout]);
  return <AuthCtx.Provider value={value}>{children}</AuthCtx.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthCtx);
  if (!ctx) throw new Error("useAuth phải nằm trong <AuthProvider>");
  return ctx;
}
