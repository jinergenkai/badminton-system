#!/usr/bin/env python3
"""Sinh web/src/components/rank/frames.gen.js — khung avatar theo HẠNG (Elo hiện tại).

    python tools/gen_rank_frames.py      (chạy trong web/)

Mỗi hạng vẽ quanh tâm (0,0), avatar r=30 đặt giữa (component RankFrame lo phần avatar).
Hạng: Đồng · Bạc · Vàng · Bạch kim · Kim cương · Cao thủ (2 vợt chéo).
Sửa hình ở đây rồi chạy lại; đừng sửa tay file .gen.js.
"""
import math
out=[]
P=out.append
def avatar(cx,cy,r=30):
    P(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#256E4E"/>')
    P(f'<circle cx="{cx}" cy="{cy-7}" r="{r*0.33:.1f}" fill="#D5EDE1"/>')
    P(f'<path d="M{cx-r*0.62:.1f} {cy+r*0.72:.1f} Q{cx} {cy+r*0.05:.1f} {cx+r*0.62:.1f} {cy+r*0.72:.1f} Z" fill="#D5EDE1"/>')
def ring(cx,cy,dark,mid,light,dots=None,r=41):
    P(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{dark}" stroke-width="8"/>')
    P(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{mid}" stroke-width="4.5"/>')
    P(f'<circle cx="{cx}" cy="{cy}" r="{r-6}" fill="none" stroke="{light}" stroke-width="1.5"/>')
    if dots:
        n,col,rad=dots
        for i in range(n):
            a=math.radians(360*i/n); P(f'<circle cx="{cx+r*math.cos(a):.1f}" cy="{cy+r*math.sin(a):.1f}" r="{rad}" fill="{col}"/>')
def wreath(cx,cy,n,step,c1,c2,stroke,R=47,size=22,start=18):
    # vòng lá kiểu khung Vàng: 2 nhánh từ đáy vòng lên
    for side in (1,-1):
        for k in range(n):
            ang=90+side*(start+k*step)
            x=cx+R*math.cos(math.radians(ang)); y=cy+R*math.sin(math.radians(ang))
            rot=ang+side*65
            w=size*0.32
            P(f'<g transform="translate({x:.1f} {y:.1f}) rotate({rot:.1f})"><path d="M0 0 Q{size*0.45:.1f} {-w:.1f} {size} 0 Q{size*0.45:.1f} {w:.1f} 0 0 Z" fill="{c1 if k%2==0 else c2}" stroke="{stroke}" stroke-width="1"/></g>')
def bow(cx,cy,c,stroke):  # nơ buộc 2 nhánh ở đáy
    P(f'<path d="M{cx} {cy+44} l-10 -5 l2 10 Z M{cx} {cy+44} l10 -5 l-2 10 Z" fill="{c}" stroke="{stroke}" stroke-width="1" stroke-linejoin="round"/>')
    P(f'<circle cx="{cx}" cy="{cy+44}" r="3.5" fill="{c}" stroke="{stroke}" stroke-width="1"/>')
def gem(cx,cy,s,fill,light,stroke):
    P(f'<polygon points="{cx},{cy-s} {cx+s*0.75:.1f},{cy} {cx},{cy+s} {cx-s*0.75:.1f},{cy}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>')
    P(f'<polygon points="{cx},{cy-s} {cx+s*0.75:.1f},{cy} {cx},{cy}" fill="{light}"/>')
def round_gem(cx,cy,r,fill,light,stroke):
    P(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>'); P(f'<circle cx="{cx-r*0.3:.1f}" cy="{cy-r*0.3:.1f}" r="{r*0.35:.1f}" fill="{light}"/>')
def plume(cx,cy,n,spread,length,fill,stroke):  # chùm lông cầu toả lên sau viên đá
    for i in range(n):
        a=-90+(i-(n-1)/2)*spread
        P(f'<g transform="translate({cx} {cy}) rotate({a})"><path d="M0 0 Q{length*0.5:.1f} -6 {length} 0 Q{length*0.5:.1f} 6 0 0 Z" fill="{fill}" stroke="{stroke}" stroke-width="1"/><line x1="2" y1="0" x2="{length-3}" y2="0" stroke="{stroke}" stroke-width="0.7"/></g>')
def label(cx,y,t): P(f'<text class="ts" x="{cx}" y="{y}" text-anchor="middle">{t}</text>')

C=[(0,0)]*6
MARK=[]

# 1 Đồng — nhánh lá ngắn (3 lá/bên), nút tròn trên đỉnh
cx,cy=C[0]
wreath(cx,cy,3,20,"#C8864F","#A86B3A","#5C3A1E",start=22,size=20)
ring(cx,cy,"#5C3A1E","#B5763F","#E8B98C")
round_gem(cx,cy-43,5.5,"#C8864F","#F1D2B3","#5C3A1E")
MARK.append(len(out))

# 2 Bạc — 5 lá/bên, đá nhỏ, chấm sáng trên viền
cx,cy=C[1]
wreath(cx,cy,5,19,"#DDE3EA","#B7C2CD","#55616E",start=20,size=21)
ring(cx,cy,"#55616E","#B7C2CD","#F4F7FA",dots=(8,"#FFFFFF",1.6))
gem(cx,cy-46,8,"#C9D2DB","#FFFFFF","#55616E")
MARK.append(len(out))

# 3 Vàng — giữ nguyên tinh thần bản bạn thích
cx,cy=C[2]
wreath(cx,cy,7,19,"#F2C94C","#E3B23C","#8A6200",start=18,size=22)
ring(cx,cy,"#8A6200","#E3B23C","#FFE8A3",dots=(12,"#FFF4CC",1.8))
gem(cx,cy-46,10,"#E3B23C","#FFF4CC","#8A6200")
MARK.append(len(out))

# 4 Bạch kim — vòng lá kín tới đỉnh + nơ đáy + chùm lông cầu sau đá
cx,cy=C[3]
plume(cx,cy-50,5,22,22,"#F2FFFB","#0B6B5C")
wreath(cx,cy,8,18.5,"#8FE3D0","#4CC3A9","#0B6B5C",start=16,size=23)
ring(cx,cy,"#0B5A4E","#3BBFA3","#E6FBF5",dots=(12,"#E6FBF5",1.8))
bow(cx,cy,"#3BBFA3","#0B5A4E")
gem(cx,cy-47,11,"#3BBFA3","#E6FBF5","#0B5A4E")
MARK.append(len(out))

# 5 Kim cương — vòng lá kép (lá pha lê ngoài + lá trong), đá lớn + 2 đá nhỏ
cx,cy=C[4]
wreath(cx,cy,8,18.5,"#8FB4FF","#5A8DF2","#14275E",R=53,size=20,start=22)
wreath(cx,cy,8,18.5,"#3B6FE0","#2A57C9","#14275E",start=14,size=22)
ring(cx,cy,"#14275E","#4F82EE","#DCE8FF",dots=(16,"#DCE8FF",1.7))
bow(cx,cy,"#4F82EE","#14275E")
gem(cx-17,cy-41,6,"#8FB4FF","#FFFFFF","#14275E"); gem(cx+17,cy-41,6,"#8FB4FF","#FFFFFF","#14275E")
gem(cx,cy-49,13,"#3B6FE0","#BFD4FF","#14275E")
MARK.append(len(out))

# 6 Vua sân — vòng lá vàng kép kín, viền đỏ ngọc, vương miện trên đỉnh, 2 vợt chéo mảnh phía sau
cx,cy=C[5]
for rot in (-38,38):
    P(f'<g transform="translate({cx} {cy}) rotate({rot})"><line x1="0" y1="46" x2="0" y2="66" stroke="#3A2A1A" stroke-width="5" stroke-linecap="round"/><ellipse cx="0" cy="-62" rx="14" ry="18" fill="#FFF6E0" stroke="#7A5200" stroke-width="3"/><path d="M-9 -68 H9 M-11 -62 H11 M-9 -56 H9 M-5 -77 V-47 M0 -79 V-45 M5 -77 V-47" stroke="#C9952B" stroke-width="0.7" fill="none"/></g>')
wreath(cx,cy,8,18.5,"#FFD66B","#E3B23C","#7A5200",R=53,size=20,start=22)
wreath(cx,cy,8,18.5,"#F2C94C","#D9A21E","#7A5200",start=14,size=22)
ring(cx,cy,"#5A0F14","#D6303A","#FFD0C2")
for i in range(12):
    a=math.radians(30*i); P(f'<circle cx="{cx+41*math.cos(a):.1f}" cy="{cy+41*math.sin(a):.1f}" r="2.2" fill="#F2C94C" stroke="#7A5200" stroke-width="0.6"/>')
bow(cx,cy,"#D6303A","#5A0F14")
gem(cx,cy-48,12,"#D6303A","#FFD0C2","#5A0F14")
MARK.append(len(out))


import json, os
keys = ["dong", "bac", "vang", "bach-kim", "kim-cuong", "cao-thu"]
parts, start = {}, 0
for k, m in zip(keys, MARK):
    parts[k] = "".join(out[start:m]); start = m
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "components", "rank", "frames.gen.js")
js = ("// TỰ SINH từ tools/gen_rank_frames.py — đừng sửa tay.\n"
      "// Khung hạng (SVG, tâm 0,0; avatar r=30 nằm giữa). viewBox chung: RANK_VIEWBOX.\n"
      'export const RANK_VIEWBOX = "-68 -82 136 152";\n'
      "export const RANK_FRAME_SVG = " + json.dumps(parts, ensure_ascii=False, indent=1) + ";\n")
open(dst, "w", encoding="utf-8", newline="\n").write(js)
print("ghi", os.path.normpath(dst), {k: len(v) for k, v in parts.items()})
