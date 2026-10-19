-- SQLite schema cho backend/api. Một file badminton.db trong volume.
-- id người chơi = id GỐC lấy từ sổ tiền (Blob) -> không remap dữ liệu tiền cầu.

PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS players (
  id         TEXT PRIMARY KEY,            -- = member.id của sổ tiền
  name       TEXT NOT NULL,
  short      TEXT NOT NULL DEFAULT '',    -- tên ngắn hiển thị trên band/bảng
  avatar     TEXT NOT NULL DEFAULT '',    -- data URL / base64 (giống 'av' sổ tiền)
  active     INTEGER NOT NULL DEFAULT 1,  -- 0 = ẩn khỏi roster/pickup
  phone_id   TEXT NOT NULL DEFAULT '',    -- alias id phía Flutter (nếu khác id gốc)
  elo        REAL NOT NULL DEFAULT 1000,  -- tính lại từ matches mỗi lần sync
  wins       INTEGER NOT NULL DEFAULT 0,
  losses     INTEGER NOT NULL DEFAULT 0,
  played     INTEGER NOT NULL DEFAULT 0,
  source     TEXT NOT NULL DEFAULT 'billbook',  -- billbook | phone
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_players_phone ON players(phone_id);

CREATE TABLE IF NOT EXISTS sessions (
  id         TEXT PRIMARY KEY,            -- có thể = session.id của sổ tiền
  played_on  TEXT NOT NULL DEFAULT '',    -- YYYY-MM-DD
  court_cost REAL NOT NULL DEFAULT 0,
  note       TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS matches (
  id            TEXT PRIMARY KEY,         -- = Match.id của Flutter (idempotent sync)
  session_id    TEXT NOT NULL DEFAULT '',
  played_at     TEXT NOT NULL DEFAULT '', -- ISO startTime (thứ tự để tính Elo)
  ended_at      TEXT NOT NULL DEFAULT '',
  team_a_score  INTEGER NOT NULL DEFAULT 0,
  team_b_score  INTEGER NOT NULL DEFAULT 0,
  winner        TEXT NOT NULL DEFAULT '', -- 'A' | 'B' | ''
  rally_sequence TEXT NOT NULL DEFAULT '',
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  video_url     TEXT NOT NULL DEFAULT '',
  source        TEXT NOT NULL DEFAULT 'phone',
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_matches_session ON matches(session_id);
CREATE INDEX IF NOT EXISTS idx_matches_time ON matches(played_at);

CREATE TABLE IF NOT EXISTS match_players (
  match_id  TEXT NOT NULL,
  player_id TEXT NOT NULL,
  team      TEXT NOT NULL,                -- 'A' | 'B'
  PRIMARY KEY (match_id, player_id)
);
CREATE INDEX IF NOT EXISTS idx_mp_player ON match_players(player_id);
CREATE INDEX IF NOT EXISTS idx_mp_match ON match_players(match_id);
