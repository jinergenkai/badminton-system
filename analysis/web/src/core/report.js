// HTML match report (Vietnamese), same content as analytics.to_markdown in analysis/badminton/analytics.py.
// Returns a string with semantic markup and class names only (no inline styles); the page styles it:
//   section.report > header.summary (.kpis > .kpi), section.players (table.players), ul.player-notes,
//   section.rallies (table.rallies), section.shots (table.shots; tr.unreliable when the speed is not
//   measurable), span.chip.p1..p4 for player tags, p.note for footnotes.
import { TYPES_VI } from './analytics.js';

export const ZONE_VI = { front: 'trước', mid: 'giữa', back: 'sau' };
export const SIDE_VI = { near: 'phía camera', far: 'phía xa' };
export const STROKE_VI = { forehand: 'thuận tay', backhand: 'trái tay', centre: 'giữa người' };
const HEIGHT_VI = { overhead: 'trên đầu', side: 'ngang người', underarm: 'dưới thấp' };

const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// Python '{:.Nf}'.format: round half to even on the exact binary value; toFixed is close enough for display.
const fx = (v, n = 0) => (v === null || v === undefined ? '—' : Number(v).toFixed(n));
const fmt = (v, n = 0, unit = '') => (v === null || v === undefined ? '—' : fx(v, n) + unit);
const signed = (v, n) => (v >= 0 ? '+' : '') + fx(v, n);
// Python str(float): 1.0 -> "1.0"
const pyStr = (v) => (Number.isInteger(v) ? v.toFixed(1) : String(v));
const chip = (key) => (key ? `<span class="chip ${esc(key.toLowerCase())}">${esc(key)}</span>` : '<span class="chip unknown">P?</span>');

function table(cls, head, rows) {
  return `<table class="${cls}"><thead><tr>${head.map((h) => `<th>${h}</th>`).join('')}</tr></thead>`
    + `<tbody>${rows.join('')}</tbody></table>`;
}

/** reportHtml(report, name?) -> HTML string for an analyse() result. */
export function reportHtml(rep, name = '') {
  const s = rep.summary;
  const players = Object.keys(rep.players).sort();
  const H = ['<section class="report">'];
  H.push(`<h1>Báo cáo trận${name ? ` — ${esc(name)}` : ''}</h1>`);
  H.push('<header class="summary"><div class="kpis">'
    + [[s.players, 'người chơi'], [s.rallies, 'pha cầu'], [s.shots, 'cú đánh có đường bay 3D'], [s.landings, 'điểm rơi']]
      .map(([v, l]) => `<div class="kpi"><span class="value">${esc(v)}</span><span class="label">${l}</span></div>`).join('')
    + '</div>');
  if (Object.keys(s.shot_types).length) {
    H.push('<p class="shot-types"><strong>Các loại cú:</strong> '
      + Object.entries(s.shot_types).map(([k, v]) => `<span class="type ${esc(k)}">${esc(TYPES_VI[k] ?? k)} ${v}</span>`).join(', ')
      + '</p>');
  }
  H.push('</header>');

  // players
  const prow = players.map((k) => {
    const p = rep.players[k], z = p.zones_pct, a = p.at_opponent_contact, sm = p.smash_kmh;
    const smash = sm.mean === null ? '—' : `${fx(sm.mean)} / ${fx(sm.max)} km/h`;
    return `<tr class="${esc(k.toLowerCase())}"><th scope="row">${chip(k)}</th><td>${esc(SIDE_VI[p.side] ?? p.side)}</td>`
      + `<td>${fx(p.height_m, 2)} m</td><td>${fx(p.distance_m)} m</td>`
      + `<td>${fx(p.mean_speed_ms, 1)} / ${fx(p.top_speed_ms, 1)} m/s</td>`
      + `<td>${fx(z.front)} / ${fx(z.mid)} / ${fx(z.back)} %</td><td>${p.shots}</td><td>${smash}</td>`
      + `<td>${fmt(a.ready_stance_pct, 0, '%')}</td><td>${fmt(a.reaction_s, 2, ' s')}</td><td>${fmt(p.recovery_s, 2, ' s')}</td></tr>`;
  });
  H.push('<section class="players"><h2>Người chơi</h2>');
  H.push(table('players', ['', 'Bên', 'Cao', 'Quãng đường', 'Tốc độ TB / tối đa', 'Trước / giữa / sau', 'Cú',
    'Đập TB / max', 'Tư thế chờ', 'Phản ứng', 'Về vị trí'], prow));
  H.push('<p class="note">Đập TB / max chỉ tính các cú đo được tốc độ với sai số &lt; 10% (cú bay dọc hướng nhìn của camera,'
    + ' từ cuối sân xa về phía camera, chỉ đo được độ cao/hướng; tốc độ của chúng có dấu ~ ở bảng dưới).</p>');
  H.push('<p class="note">Tư thế chờ: % số lần đối thủ chạm cầu mà người này đang dang chân ≥ 22% chiều cao và chùng gối '
    + '(góc gối ≤ 160°). Phản ứng: từ lúc đối thủ chạm cầu đến lúc bắt đầu di chuyển &gt; 1.5 m/s. Về vị trí: '
    + 'từ cú đánh của mình đến lúc về trong 1 m quanh vị trí trung tâm.</p>');

  const notes = players.filter((k) => Object.keys(rep.players[k].shot_types).length).map((k) => {
    const p = rep.players[k];
    const types = Object.entries(p.shot_types).map(([t, n]) => `${esc(TYPES_VI[t] ?? t)} ${n}`).join(', ');
    const strokes = Object.entries(p.strokes).map(([t, n]) => `${esc(STROKE_VI[t] ?? t)} ${n}`).join(', ');
    const hand = { R: 'tay phải', L: 'tay trái' }[p.dominant_hand] ?? 'tay ?';
    const jump = p.jump_shots ? ` ${p.jump_shots} cú bật nhảy.` : '';
    return `<li class="${esc(k.toLowerCase())}">${chip(k)} (${hand}): ${types}. ${strokes}.${jump}`
      + ` Điểm chạm cầu cao trung vị ${pyStr(p.contact_height_m)} m.</li>`;
  });
  if (notes.length) H.push(`<ul class="player-notes">${notes.join('')}</ul>`);
  H.push('</section>');

  // rallies
  H.push('<section class="rallies"><h2>Pha cầu</h2>');
  H.push(table('rallies', ['Pha', 'Bắt đầu', 'Thời lượng', 'Số cú', 'Bên thắng'], rep.rallies.map((r) =>
    `<tr${r.winner_side ? ` class="won-${esc(r.winner_side)}"` : ''}><td>${r.rally}</td><td>${pyStr(r.start_s)} s</td>`
    + `<td>${pyStr(r.duration_s)} s</td><td>${r.shots}</td><td>${esc(SIDE_VI[r.winner_side] ?? '—')}</td></tr>`)));
  H.push('</section>');

  // shots
  const srow = rep.shots.map((c) => {
    const net = c.net_clearance_m === null || c.net_clearance_m === undefined ? '—' : `${signed(c.net_clearance_m, 2)} m`;
    const kind = esc(c.type_vi) + (c.jump ? ' <span class="jump">(nhảy)</span>' : '');
    const sd = c.speed_sd_kmh;
    let speed = sd !== null && sd !== undefined ? `${fx(c.speed_kmh)} ± ${fx(sd)} km/h` : `${fx(c.speed_kmh)} km/h`;
    const unreliable = c.speed_reliable === false;
    if (unreliable) speed = `~${speed}`;
    const pk = c.player ? `P${c.player}` : null;
    const cls = [`type-${c.type}`, unreliable ? 'unreliable' : '', c.jump ? 'jump' : ''].filter(Boolean).join(' ');
    return `<tr class="${esc(cls)}" data-frame="${c.frame}"><td>${pyStr(c.time_s)} s</td><td>${c.rally}.${c.shot_in_rally}</td>`
      + `<td>${chip(pk)}</td><td>${kind}</td><td class="speed">${speed}</td><td>${fx(c.mean_speed_kmh)}</td>`
      + `<td>${fx(c.launch_angle_deg)}°</td>`
      + `<td>${pyStr(c.contact_height_m)} m <span class="stroke-height ${esc(c.stroke_height)}">(${esc(HEIGHT_VI[c.stroke_height] ?? c.stroke_height)})</span></td>`
      + `<td>${pyStr(c.apex_m)} m</td><td>${net}</td><td>${c.direction === 'cross' ? 'chéo' : 'thẳng'}</td>`
      + `<td>${esc(ZONE_VI[c.to_zone] ?? c.to_zone)}</td><td class="confidence ${esc(c.confidence)}">${esc(c.confidence)}</td></tr>`;
  });
  H.push('<section class="shots"><h2>Từng cú</h2>');
  H.push(table('shots', ['t', 'Pha', 'Người', 'Loại', 'Tốc độ rời vợt', 'TB', 'Góc', 'Điểm chạm', 'Đỉnh', 'Qua lưới',
    'Hướng', 'Tới', 'Độ tin'], srow));
  H.push('</section></section>');
  return H.join('\n');
}
