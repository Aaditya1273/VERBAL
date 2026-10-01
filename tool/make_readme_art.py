#!/usr/bin/env python3
"""Draw the README's diagrams as SVG, in the app's own look.

Black ground, grey glass cards with a hairline, white type, the cloud as the
only character. Plain SVG so GitHub renders it and anyone can edit it.

    python3 tool/make_readme_art.py
"""
import base64
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/art"
FONT = "Inter, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
INK, MUTED, BG, CARD, LINE = "#F5F5F7", "#9B9BA4", "#09090B", "#18181B", "#2E2E33"


def mascot(name="neutre"):
    data = (ROOT / f"assets/mascot/{name}.png").read_bytes()
    return "data:image/png;base64," + base64.b64encode(data).decode()


def svg(w, h, body):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" font-family="{FONT}">
<defs>
  <radialGradient id="lamp" cx="0.5" cy="0" r="0.9"><stop offset="0" stop-color="#3A3A40"/><stop offset="1" stop-color="{BG}"/></radialGradient>
  <linearGradient id="card" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#202024"/><stop offset="1" stop-color="#141416"/></linearGradient>
  <linearGradient id="hair" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <marker id="arr" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{MUTED}"/></marker>
</defs>
<rect width="{w}" height="{h}" rx="28" fill="{BG}"/><rect width="{w}" height="{h}" rx="28" fill="url(#lamp)"/>
{body}
</svg>"""


def card(x, y, w, h, title, sub="", accent=False, size=22):
    fill = INK if accent else "url(#card)"
    tcol = BG if accent else INK
    scol = "#3A3A40" if accent else MUTED
    s = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="22" fill="{fill}" stroke="{LINE}"/>'
    if not accent:
        s += f'<rect x="{x+24}" y="{y}" width="{w-48}" height="1" fill="url(#hair)"/>'
    ty = y + h / 2 + (0 if sub else size * 0.35) - (8 if sub else 0)
    s += f'<text x="{x+w/2}" y="{ty}" text-anchor="middle" fill="{tcol}" font-size="{size}" font-weight="600">{title}</text>'
    if sub:
        s += f'<text x="{x+w/2}" y="{ty+26}" text-anchor="middle" fill="{scol}" font-size="15">{sub}</text>'
    return s


def arrow(x1, y1, x2, y2, label=""):
    s = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{MUTED}" stroke-width="2" marker-end="url(#arr)"/>'
    if label:
        s += f'<text x="{(x1+x2)/2}" y="{(y1+y2)/2-10}" text-anchor="middle" fill="{MUTED}" font-size="14">{label}</text>'
    return s


def label(x, y, text, size=13, anchor="start"):
    return f'<text x="{x}" y="{y}" fill="{MUTED}" font-size="{size}" font-weight="600" letter-spacing="2" text-anchor="{anchor}">{text}</text>'


def hero():
    b = f'<image href="{mascot()}" x="70" y="40" width="300" height="300"/>'
    b += f'<text x="420" y="150" fill="{INK}" font-size="92" font-weight="300" letter-spacing="-3">VERBAL</text>'
    b += f'<text x="424" y="205" fill="{INK}" font-size="30" font-weight="300">Rehearse the conversation</text>'
    b += f'<text x="424" y="243" fill="{INK}" font-size="30" font-weight="300">before you have it.</text>'
    b += f'<text x="424" y="300" fill="{MUTED}" font-size="18">Voice-first · pushes back on purpose · tells you what you did</text>'
    return svg(1200, 380, b)


def problem():
    b = label(60, 70, "THE PROBLEM")
    items = [("01", "No rehearsal", "You get one shot,", "with real stakes."),
             ("02", "Advice is text", "Reading a script is", "not saying it out loud."),
             ("03", "Chatbots agree", "They fold the moment", "you push. People don't.")]
    for i, (e, t, l1, l2) in enumerate(items):
        x = 60 + i * 370
        b += f'<rect x="{x}" y="100" width="340" height="230" rx="24" fill="url(#card)" stroke="{LINE}"/>'
        b += f'<rect x="{x+28}" y="100" width="284" height="1" fill="url(#hair)"/>'
        b += f'<text x="{x+36}" y="170" fill="{MUTED}" font-size="40" font-weight="300">{e}</text>'
        b += f'<text x="{x+36}" y="230" fill="{INK}" font-size="26" font-weight="600">{t}</text>'
        b += f'<text x="{x+36}" y="268" fill="{MUTED}" font-size="18">{l1}</text>'
        b += f'<text x="{x+36}" y="294" fill="{MUTED}" font-size="18">{l2}</text>'
    return svg(1200, 380, b)


def loop():
    b = label(60, 70, "THE LOOP · ONE SESSION, FIVE STEPS")
    steps = [("1", "Pick", "a hard talk"), ("2", "Speak", "out loud"), ("3", "Push back", "on schedule"),
             ("4", "Score", "with evidence"), ("5", "Keep", "lines that worked")]
    for i, (n, t, s) in enumerate(steps):
        x = 60 + i * 222
        accent = i == 2
        b += card(x, 120, 190, 150, t, s, accent=accent, size=26)
        b += f'<text x="{x+22}" y="150" fill="{BG if accent else MUTED}" font-size="16" font-weight="700">{n}</text>'
        if i < 4:
            b += arrow(x + 192, 195, x + 220, 195)
    b += f'<image href="{mascot("attentif") if False else mascot()}" x="1050" y="12" width="110" height="110"/>'
    b += f'<text x="600" y="330" text-anchor="middle" fill="{MUTED}" font-size="17">Step 3 is the product: the other person resists exactly where real people do.</text>'
    return svg(1200, 370, b)


def turn():
    b = label(60, 60, "ONE TURN · WHO DECIDES WHAT")
    lanes = [("YOU", 110), ("PHONE", 230), ("ENGINE", 350), ("GEMINI", 470)]
    for name, y in lanes:
        b += f'<rect x="40" y="{y-40}" width="1120" height="90" rx="18" fill="#111113" stroke="{LINE}"/>'
        b += label(64, y + 10, name, 14)
    b += card(180, 85, 200, 70, "Hold &amp; speak", size=19)
    b += card(180, 195, 200, 70, "On-device STT", "free, private", size=19)
    b += arrow(280, 157, 280, 193)
    b += card(430, 315, 210, 70, "peek directive", "raise · react · concede", accent=True, size=19)
    b += arrow(382, 230, 470, 313)
    b += card(690, 435, 210, 70, "Say it in character", "+ observe a pitfall", size=19)
    b += arrow(640, 350, 740, 433)
    b += card(690, 315, 210, 70, "commit &amp; adjudicate", "engine has final say", accent=True, size=19)
    b += arrow(800, 433, 800, 387)
    b += card(950, 195, 190, 70, "Gemini TTS", "device voice fallback", size=19)
    b += arrow(900, 330, 1000, 267)
    b += f'<image href="{mascot()}" x="990" y="62" width="110" height="110"/>'
    b += arrow(1045, 193, 1045, 168)
    return svg(1200, 540, b)


def architecture():
    b = label(60, 60, "ARCHITECTURE · FLUTTER, LOCAL-FIRST")
    b += card(60, 90, 1080, 80, "UI · Flutter + Riverpod", "Home · Scenarios · Practice cockpit · Review · Playbook · You · Paywall", size=22)
    b += arrow(600, 172, 600, 200)
    b += card(60, 205, 520, 110, "Conversation Engine", "deterministic · objections · pressure · emotion", accent=True, size=24)
    b += card(620, 205, 520, 110, "Pitfall Engine", "12 workplace pitfalls · contingent reaction · IRP", accent=True, size=24)
    b += arrow(320, 317, 200, 350)
    b += arrow(600, 317, 600, 350)
    b += arrow(880, 317, 1000, 350)
    b += card(60, 355, 330, 110, "Voice", "on-device STT · Gemini TTS", size=22)
    b += card(435, 355, 330, 110, "Gemini actor", "structured JSON · observes only", size=22)
    b += card(810, 355, 330, 110, "Analysis", "6 skills · DEAR MAN · evidence", size=22)
    b += arrow(600, 467, 600, 495)
    b += card(60, 500, 520, 90, "SQLite · on device", "transcripts never leave the phone", size=20)
    b += card(620, 500, 520, 90, "RevenueCat", "monthly · annual · lifetime", size=20)
    return svg(1200, 630, b)


def bench():
    b = label(60, 60, "VERBAL PITFALL BENCH · 23 PAIRED ITEMS · LIVE MODEL")
    rows = [("Detects the pitfall", 78), ("Stays quiet when there is none", 87), ("Reacts as instructed, unaided", 35)]
    for i, (t, v) in enumerate(rows):
        y = 110 + i * 80
        b += f'<text x="60" y="{y+28}" fill="{INK}" font-size="20">{t}</text>'
        b += f'<rect x="440" y="{y+8}" width="600" height="28" rx="14" fill="#1D1D21"/>'
        b += f'<rect x="440" y="{y+8}" width="{6*v}" height="28" rx="14" fill="{INK if v > 50 else MUTED}"/>'
        b += f'<text x="1060" y="{y+30}" fill="{INK}" font-size="22" font-weight="600">{v}%</text>'
    b += f'<text x="60" y="380" fill="{MUTED}" font-size="17">35% is why the engine, not the model, decides when to push back. Reproduce: dart run tool/pitfall_bench.dart</text>'
    return svg(1200, 410, b)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in [("hero", hero), ("problem", problem), ("loop", loop), ("turn", turn),
                     ("architecture", architecture), ("bench", bench)]:
        (OUT / f"{name}.svg").write_text(fn())
        print(f"  docs/art/{name}.svg")


if __name__ == "__main__":
    main()
