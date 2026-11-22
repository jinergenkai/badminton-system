#!/usr/bin/env python3
"""Sinh web/src/components/badges/badges.gen.js — hình huy hiệu (khiên lục giác).

    python tools/gen_badges.py      (chạy trong web/)

BADGE_SHELL[tier]: vỏ theo cấp (dong/bac/vang/kim-cuong), số hạt dưới đáy = cấp 1..4.
  Chuỗi có "__ID__" ở id gradient: component thay bằng id riêng (tránh trùng id khi vẽ nhiều cái).
BADGE_ICON[key]: hình giữa (toạ độ quanh 0,0; viewBox chung BADGE_VIEWBOX).
Tên/điều kiện/ngưỡng nằm ở src/lib/badges.js. Sửa hình ở đây rồi chạy lại; đừng sửa tay .gen.js.
"""
import math
TIERS={"dong":("#E3A26B","#8A5228","#4A2A10"),"bac":("#F1F4F8","#9AA6B5","#46505D"),
       "vang":("#FFE38A","#D9A21E","#6B4700"),"kim-cuong":("#C9DCFF","#4F7FE8","#14286B")}
CREAM,GOLD,GD="#FFF4D6","#F2C94C","#0E3324"
def hexpts(r,rot=0): return " ".join(f"{r*math.cos(math.radians(60*i+rot+30)):.1f},{r*math.sin(math.radians(60*i+rot+30)):.1f}" for i in range(6))
def shell(t,uid,pips):  # uid = "__ID__" -> component thay bằng id riêng mỗi lần vẽ
    hi,mid,dk=TIERS[t]
    g=(f'<defs><linearGradient id="r{uid}" x1="0" y1="-1" x2="0" y2="1"><stop offset="0" stop-color="{hi}"/><stop offset=".55" stop-color="{mid}"/><stop offset="1" stop-color="{dk}"/></linearGradient>'
       f'<radialGradient id="f{uid}" cx=".5" cy=".35" r=".75"><stop offset="0" stop-color="#2F8A61"/><stop offset="1" stop-color="{GD}"/></radialGradient></defs>')
    s=(g+f'<polygon points="{hexpts(44)}" fill="url(#r{uid})" stroke="{dk}" stroke-width="2"/>'
       f'<polygon points="{hexpts(36)}" fill="url(#f{uid})" stroke="{dk}" stroke-width="1.5"/>'
       f'<polygon points="{hexpts(31)}" fill="none" stroke="{hi}" stroke-opacity=".35" stroke-width="1" stroke-dasharray="3 3"/>'
       f'<path d="M-30 -14 Q0 -30 30 -14 L30 -22 Q0 -38 -30 -22 Z" fill="#fff" opacity=".07"/>')
    # pips cấp độ dưới đáy
    w=pips*9
    s+=f'<rect x="{-w/2-5}" y="34" width="{w+10}" height="13" rx="6.5" fill="{dk}" stroke="{hi}" stroke-width="1"/>'
    s+="".join(f'<polygon points="{-w/2+4.5+9*i},{36.5} {-w/2+7+9*i},{40.5} {-w/2+4.5+9*i},{44.5} {-w/2+2+9*i},{40.5}" fill="{hi}"/>' for i in range(pips))
    return s
# ---- icon (vẽ trong ô ~ ±20) ----
def i_calendar():
    return (f'<rect x="-17" y="-13" width="34" height="30" rx="4" fill="{CREAM}"/><rect x="-17" y="-13" width="34" height="9" rx="4" fill="#E0533D"/>'
            f'<rect x="-11" y="-18" width="4" height="9" rx="2" fill="{GOLD}"/><rect x="7" y="-18" width="4" height="9" rx="2" fill="{GOLD}"/>'
            f'<path d="M-8 6 l5 5 l11 -11" fill="none" stroke="#256E4E" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>')
def i_coins():
    c=""
    for i,y in enumerate((10,4,-2,-8)):
        c+=f'<ellipse cx="-4" cy="{y+4}" rx="13" ry="4.5" fill="#B07D10"/><ellipse cx="-4" cy="{y}" rx="13" ry="4.5" fill="{GOLD}" stroke="#7A5200" stroke-width="1"/>'
    c+=f'<circle cx="9" cy="-6" r="10" fill="{GOLD}" stroke="#7A5200" stroke-width="1.4"/><circle cx="9" cy="-6" r="6.5" fill="none" stroke="#7A5200" stroke-width="1"/><text x="9" y="-2.3" text-anchor="middle" font-size="10" font-weight="900" fill="#7A5200" font-family="sans-serif">đ</text>'
    return c
def i_flame():
    return ('<path d="M0 -22 C8 -12 16 -6 14 6 C13 15 6 20 0 20 C-7 20 -14 15 -14 6 C-14 -2 -8 -6 -7 -12 C-4 -8 -3 -5 -2 -3 C0 -10 -2 -16 0 -22 Z" fill="#FF7A1A" stroke="#7A2A00" stroke-width="1.2"/>'
            '<path d="M0 -4 C5 1 8 5 7 10 C6 15 3 17 0 17 C-4 17 -7 14 -7 10 C-7 6 -3 4 -2 0 C-1 3 0 4 0 4 Z" fill="#FFD45A"/>')
def i_trophy():
    return (f'<path d="M-12 -17 H12 V-6 C12 4 6 8 0 8 C-6 8 -12 4 -12 -6 Z" fill="{GOLD}" stroke="#7A5200" stroke-width="1.3"/>'
            f'<path d="M-12 -13 C-20 -13 -20 -2 -11 0 M12 -13 C20 -13 20 -2 11 0" fill="none" stroke="{GOLD}" stroke-width="3"/>'
            f'<rect x="-3" y="8" width="6" height="7" fill="#B07D10"/><rect x="-10" y="15" width="20" height="5" rx="1.5" fill="{GOLD}" stroke="#7A5200" stroke-width="1"/>'
            f'<polygon points="0,-13 2.2,-8 7.5,-7.6 3.5,-4.2 4.8,1 0,-1.8 -4.8,1 -3.5,-4.2 -7.5,-7.6 -2.2,-8" fill="#FFF4D6"/>')
def i_rings():
    return (f'<circle cx="-7" cy="0" r="11" fill="none" stroke="{GOLD}" stroke-width="5"/><circle cx="7" cy="0" r="11" fill="none" stroke="{CREAM}" stroke-width="5"/>'
            f'<path d="M-7 -11 A11 11 0 0 1 3.5 -3.4" fill="none" stroke="{GOLD}" stroke-width="5"/>')
def i_comeback():
    return (f'<path d="M-16 12 L-6 2 L0 8 L12 -6" fill="none" stroke="{CREAM}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<polygon points="16,-12 15,1 4,-9" fill="{GOLD}" stroke="#7A5200" stroke-width="1"/>'
            f'<path d="M-18 16 H18" stroke="{GOLD}" stroke-width="2" stroke-dasharray="3 3"/>')
def i_giant():
    return (f'<path d="M-14 -10 L-8 -18 L0 -12 L8 -18 L14 -10 L12 2 H-12 Z" fill="#9AA6B5" stroke="#46505D" stroke-width="1.2"/>'
            f'<path d="M-2 -20 L4 -6 L-1 -5 L5 10 L-6 -7 L-1 -8 Z" fill="{GOLD}" stroke="#7A5200" stroke-width="1"/>'
            f'<path d="M-8 6 L-12 16 M0 6 L0 17 M8 6 L12 16" stroke="{CREAM}" stroke-width="2.4" stroke-linecap="round"/>')
def i_meal():
    return (f'<path d="M-18 0 H18 C17 12 9 18 0 18 C-9 18 -17 12 -18 0 Z" fill="{CREAM}" stroke="#7A5200" stroke-width="1"/>'
            f'<path d="M-18 0 H18" stroke="#E0533D" stroke-width="3"/>'
            f'<path d="M-6 -3 C-8 -8 -4 -10 -6 -15 M1 -3 C-1 -8 3 -10 1 -15 M8 -3 C6 -8 10 -10 8 -15" fill="none" stroke="#BFD9CC" stroke-width="2" stroke-linecap="round"/>'
            f'<path d="M6 -21 L18 -2 M11 -22 L21 -5" stroke="{GOLD}" stroke-width="2.4" stroke-linecap="round"/>')
def i_moon():
    return (f'<path d="M6 -18 A18 18 0 1 0 16 10 A14 14 0 1 1 6 -18 Z" fill="{GOLD}" stroke="#7A5200" stroke-width="1.2"/>'
            f'<polygon points="12,-14 13.5,-10.5 17,-10 14.3,-7.6 15,-4 12,-5.8 9,-4 9.7,-7.6 7,-10 10.5,-10.5" fill="{CREAM}"/>'
            f'<circle cx="17" cy="2" r="1.6" fill="{CREAM}"/>')
def i_hourglass():
    return (f'<rect x="-13" y="-20" width="26" height="4" rx="2" fill="{GOLD}"/><rect x="-13" y="16" width="26" height="4" rx="2" fill="{GOLD}"/>'
            f'<path d="M-10 -16 H10 C10 -6 2 -3 2 0 C2 3 10 6 10 16 H-10 C-10 6 -2 3 -2 0 C-2 -3 -10 -6 -10 -16 Z" fill="{CREAM}" fill-opacity=".9" stroke="#BFD9CC" stroke-width="1"/>'
            f'<path d="M-6 -10 H6 L0 -2 Z M-7 15 C-5 8 5 8 7 15 Z" fill="#E0A31E"/>')
def i_net():
    pts=[(0,-15),(14,-4),(9,13),(-9,13),(-14,-4)]
    l="".join(f'<line x1="0" y1="0" x2="{x}" y2="{y}" stroke="{GOLD}" stroke-width="2"/>' for x,y in pts)
    return l+"".join(f'<circle cx="{x}" cy="{y}" r="4.5" fill="{CREAM}" stroke="#7A5200" stroke-width="1"/>' for x,y in pts)+f'<circle r="6.5" fill="{GOLD}" stroke="#7A5200" stroke-width="1.2"/>'
def i_square():
    return (f'<circle cx="0" cy="-2" r="16" fill="{GOLD}" stroke="#7A5200" stroke-width="1.4"/>'
            f'<path d="M-8 -2 l5 5 l11 -11" fill="none" stroke="{GD}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="M-20 12 C-14 8 -8 12 -2 16 M20 12 C14 8 8 12 2 16" fill="none" stroke="{CREAM}" stroke-width="3" stroke-linecap="round"/>')

ICONS={"chuyen-can":i_calendar,"dai-gia":i_coins,"song-phang":i_square,"keo-an":i_meal,
       "chuoi-thang":i_flame,"bach-thang":i_trophy,"nguoc-dong":i_comeback,"ha-guc":i_giant,
       "cap-bai-trung":i_rings,"xa-giao":i_net,"marathon":i_hourglass,"cu-dem":i_moon}
LEVEL={"dong":1,"bac":2,"vang":3,"kim-cuong":4}
import json, os
shells={t:shell(t,"__ID__",n) for t,n in LEVEL.items()}
icons={k:f() for k,f in ICONS.items()}
dst=os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","src","components","badges","badges.gen.js")
os.makedirs(os.path.dirname(dst),exist_ok=True)
js=("// TỰ SINH từ tools/gen_badges.py — đừng sửa tay.\n"
    'export const BADGE_VIEWBOX = "-48 -48 96 98";\n'
    "export const BADGE_SHELL = "+json.dumps(shells,ensure_ascii=False,indent=1)+";\n"
    "export const BADGE_ICON = "+json.dumps(icons,ensure_ascii=False,indent=1)+";\n")
open(dst,"w",encoding="utf-8",newline="\n").write(js)
print("ghi",os.path.normpath(dst),len(js))
