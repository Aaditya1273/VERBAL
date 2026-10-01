#!/usr/bin/env python3
"""Build VERBAL's demo film from real device captures, the mascot and narration.

Every layer is a transparent PNG (type rendered from SVG so light weights work,
phone captures framed with ImageMagick); ffmpeg does the motion: fades, rises,
crossfades, a growing bar chart, the mascot's blink. Scenes are cut together
with crossfades; narration is placed on the same clock; a synthesized ambient
pad sits underneath and ducks under the voice.

    python3 tool/make_demo_video.py <workdir>

<workdir> holds cap/*.png (device screenshots) and c_s1..c_s9.wav (narration).
"""
import subprocess, sys, html
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
W = Path(sys.argv[1]).resolve()
L = W / "layers"; L.mkdir(exist_ok=True)
SC = W / "scenes"; SC.mkdir(exist_ok=True)
FPS, VW, VH = 30, 1920, 1080
INK, MUTED, BG = "#F5F5F7", "#9B9BA4", "#09090B"
FONT = "Adwaita Sans"
LEAD, TAIL, XF = 0.7, 0.9, 0.6


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def dur(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(p)], capture_output=True, text=True).stdout
    return float(out.strip())


_n = [0]
def text(lines, size, weight=300, color=INK, w=1600, anchor="start", spacing=-0.02, lh=1.12):
    """Render one or more lines of type to a tight transparent PNG."""
    _n[0] += 1
    out = L / f"t{_n[0]:03d}.png"
    if isinstance(lines, str):
        lines = [lines]
    h = int(size * lh * len(lines) + size * 0.5)
    x = {"start": 0, "middle": w / 2, "end": w}[anchor]
    spans = "".join(
        f'<text x="{x}" y="{size * (1 + i * lh):.0f}" text-anchor="{anchor}">{html.escape(t)}</text>'
        for i, t in enumerate(lines))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">'
           f'<g font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{color}" '
           f'letter-spacing="{size * spacing:.2f}">{spans}</g></svg>')
    sp = out.with_suffix(".svg"); sp.write_text(svg)
    run(["rsvg-convert", str(sp), "-o", str(out)])
    return out


def card(title, sub, w=500, h=300):
    _n[0] += 1
    out = L / f"c{_n[0]:03d}.png"
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#232327"/><stop offset="1" stop-color="#141416"/></linearGradient>
<linearGradient id="hl" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".5"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>
<rect x="1" y="1" width="{w-2}" height="{h-2}" rx="34" fill="url(#g)" stroke="#2E2E33" stroke-width="2"/>
<rect x="40" y="1" width="{w-80}" height="1.5" fill="url(#hl)"/>
<g font-family="{FONT}"><text x="44" y="{h*0.46:.0f}" font-size="44" font-weight="400" fill="{INK}">{html.escape(title)}</text>
<text x="44" y="{h*0.46+56:.0f}" font-size="27" font-weight="300" fill="{MUTED}">{html.escape(sub)}</text></g></svg>'''
    sp = out.with_suffix(".svg"); sp.write_text(svg)
    run(["rsvg-convert", str(sp), "-o", str(out)])
    return out


def phone(src, h=900):
    """A device capture, status and gesture bars cropped, in a rounded bezel."""
    out = L / f"p_{Path(src).stem}.png"
    if out.exists():
        return out
    sw = int(h * 1080 / (2400 - 120 - 60))
    r, bz = 46, 12
    scr, mask, bez = (L / f"_{n}.png" for n in ("scr", "mask", "bez"))
    run(["magick", str(src), "-alpha", "off", "-crop", "1080x2220+0+120", "+repage",
         "-resize", f"{sw}x{h}!", str(scr)])
    run(["magick", "-size", f"{sw}x{h}", "xc:black", "-fill", "white",
         "-draw", f"roundrectangle 0,0,{sw-1},{h-1},{r},{r}", str(mask)])
    W2, H2 = sw + 2 * bz, h + 2 * bz
    run(["magick", "-size", f"{W2}x{H2}", "xc:none", "-fill", "#1E1E22", "-stroke", "#3A3A40",
         "-draw", f"roundrectangle 0,0,{W2-1},{H2-1},{r+bz},{r+bz}", str(bez)])
    run(["magick", str(bez),
         "(", str(scr), str(mask), "-alpha", "off", "-compose", "CopyOpacity", "-composite", ")",
         "-geometry", f"+{bz}+{bz}", "-compose", "over", "-composite",
         "(", "+clone", "-background", "black", "-shadow", "60x28+0+22", ")", "+swap",
         "-background", "none", "-compose", "over", "-layers", "merge", "+repage", str(out)])
    return out


def mascot(name, size):
    out = L / f"m_{name}_{size}.png"
    if not out.exists():
        run(["magick", str(ROOT / f"assets/mascot/{name}.png"), "-resize", f"{size}x{size}", str(out)])
    return out


def blink(size):
    """The resting face with its eyes closed, for a 140 ms blink."""
    out = L / f"m_blink_{size}.png"
    if not out.exists():
        s = size / 1.0
        boxes = [(0.496, 0.316, 0.609, 0.461), (0.648, 0.270, 0.746, 0.410)]
        draw = []
        for (a, b, c, d) in boxes:
            draw += ["-draw", f"roundrectangle {a*s-2},{b*s-2},{c*s+2},{d*s+2},{(c-a)*s/2},{(c-a)*s/2}"]
        run(["magick", str(mascot("neutre", size)), "-fill", "#F5F5F3", *draw, str(out)])
    return out


def bar(length, h=34, color=INK, track=900):
    """A bar canvas for the crop-reveal trick: bar at [0,length], transparent after."""
    out = L / f"bar_{length}_{color[1:]}.png"
    run(["magick", "-size", f"{track + length}x{h}", "xc:none", "-fill", color,
         "-draw", f"roundrectangle 0,0,{length-1},{h-1},{h/2},{h/2}", str(out)])
    return out


def track_img(track=900, h=34):
    out = L / "track.png"
    run(["magick", "-size", f"{track}x{h}", "xc:none", "-fill", "#1D1D21",
         "-draw", f"roundrectangle 0,0,{track-1},{h-1},{h/2},{h/2}", str(out)])
    return out


def background():
    out = L / "bg.png"
    run(["magick", "-size", f"{VW}x{VH}", f"xc:{BG}",
         "(", "-size", f"{VW*2}x{VH*2}", "radial-gradient:#3A3A41-#09090B", "-crop", f"{VW}x{VH}+{VW//2}+{int(VH*0.95)}", "+repage", ")",
         "-compose", "over", "-composite",
         "(", "-size", f"{VW}x{VH}", "xc:gray50", "+noise", "Gaussian", "-colorspace", "gray",
         "-evaluate", "multiply", "0.06", ")", "-compose", "plus", "-composite", str(out)])
    return out


# ---- a scene is a duration and a list of layers -----------------------------
# layer: dict(img, x, y, t0, t1=None, rise=True, gif=False, reveal=None)
def render_scene(name, d, layers):
    inputs = ["-loop", "1", "-framerate", str(FPS), "-t", f"{d}", "-i", str(L / "bg.png")]
    chain, last = [], "0:v"
    for i, ly in enumerate(layers, start=1):
        if ly.get("gif"):
            inputs += ["-ignore_loop", "0", "-i", str(ly["img"])]
        else:
            inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{d}", "-i", str(ly["img"])]
        t0, t1 = ly["t0"], ly.get("t1") or d
        f = [f"[{i}:v]format=rgba"]
        if ly.get("scale"):
            f.append(f"scale={ly['scale']}:-1")
        if ly.get("reveal"):
            L_, tr, dd = ly["reveal"]
            f.append(f"crop=w={tr}:h=ih:x='{L_}*(1-min(1,max(0,(t-{t0})/{dd})))*(1-min(1,max(0,(t-{t0})/{dd})))':y=0")
        fin = ly.get("fin", 0.5)
        f.append(f"fade=t=in:st={t0}:d={fin}:alpha=1")
        if t1 < d - 0.01:
            f.append(f"fade=t=out:st={t1 - 0.4}:d=0.4:alpha=1")
        chain.append(",".join(f) + f"[l{i}]")
        y = str(ly["y"])
        if ly.get("rise", True):
            y = f"{ly['y']}+36*pow(max(0,1-(t-{t0})/0.7),3)"
        x = ly["x"]
        chain.append(f"[{last}][l{i}]overlay=x={x}:y='{y}':enable='between(t,{t0},{t1})':eof_action=pass:shortest=0[v{i}]")
        last = f"v{i}"
    chain.append(f"[{last}]format=yuv420p,fps={FPS}[out]")
    out = SC / f"{name}.mp4"
    run(["ffmpeg", "-y", *inputs, "-filter_complex", ";".join(chain), "-map", "[out]",
         "-t", f"{d}", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-r", str(FPS), str(out)])
    return out


def centre_x(img):
    w = int(subprocess.run(["magick", "identify", "-format", "%w", str(img)], capture_output=True, text=True).stdout)
    return (VW - w) // 2


def size_of(img):
    w, h = subprocess.run(["magick", "identify", "-format", "%w %h", str(img)], capture_output=True, text=True).stdout.split()
    return int(w), int(h)


def blinks(size, x, y, times):
    b = blink(size)
    return [dict(img=b, x=x, y=y, t0=t, t1=t + 0.14, rise=False, fin=0.01) for t in times]


def main():
    background()
    cap = sorted((W / "cap").glob("*.png"))
    pick = lambda tag, k=0: [p for p in cap if tag in p.name][k]
    narr = {f"s{i}": W / f"c_s{i}.wav" for i in range(1, 10)}
    D = {k: dur(v) + LEAD + TAIL for k, v in narr.items()}
    D["s1"] = max(D["s1"], 6.5); D["s9"] = max(D["s9"], 7.5)
    scenes = []

    # 1. Intro ---------------------------------------------------------------
    m = mascot("neutre", 360); mx, my = centre_x(m), 150
    t_v = text("VERBAL", 150, 300, w=1200, anchor="middle")
    t_tag = text("Rehearse the conversation before you have it.", 46, 300, color=MUTED, w=1400, anchor="middle")
    scenes.append(render_scene("s1", D["s1"], [
        dict(img=m, x=mx, y=my, t0=0.2, fin=0.8),
        *blinks(360, mx, my, [2.4, 5.2]),
        dict(img=t_v, x=centre_x(t_v), y=560, t0=0.9),
        dict(img=t_tag, x=centre_x(t_tag), y=760, t0=2.2),
    ]))

    # 2. Problem -------------------------------------------------------------
    d = D["s2"]
    st = text(["The conversations that shape", "a career happen once."], 84, 300, w=1500, anchor="middle")
    a1 = text("Asking for a raise.", 64, 300, w=1200, anchor="middle")
    a2 = text("Giving hard feedback.", 64, 300, w=1200, anchor="middle")
    a3 = text("Letting someone go.", 64, 300, w=1200, anchor="middle")
    big = text("7 in 10", 230, 200, w=1200, anchor="middle")
    bsub = text("employees avoid difficult conversations at work", 46, 300, color=MUTED, w=1400, anchor="middle")
    src = text("Source: Bravely workplace survey, reported by CNBC (2019)", 24, 400, color="#6B6B73", w=1200, anchor="middle")
    ai = text(["And today's AI folds", "the moment you push back."], 84, 300, w=1500, anchor="middle")
    scenes.append(render_scene("s2", d, [
        dict(img=st, x=centre_x(st), y=400, t0=0.5, t1=3.9),
        dict(img=a1, x=centre_x(a1), y=330, t0=3.9, t1=7.9),
        dict(img=a2, x=centre_x(a2), y=470, t0=5.0, t1=7.9),
        dict(img=a3, x=centre_x(a3), y=610, t0=6.1, t1=7.9),
        dict(img=big, x=centre_x(big), y=250, t0=8.0, t1=12.4),
        dict(img=bsub, x=centre_x(bsub), y=560, t0=8.5, t1=12.4),
        dict(img=src, x=centre_x(src), y=960, t0=8.5, t1=12.4, rise=False),
        dict(img=ai, x=centre_x(ai), y=400, t0=12.5),
    ]))

    # 3. Painkiller ----------------------------------------------------------
    d = D["s3"]
    gif = ROOT / "assets/mascot/attentif.gif"
    h1 = text(["A practice partner", "that pushes back."], 84, 300, w=1100)
    i1 = text("Speak out loud.", 50, 400, w=1000)
    i2 = text("It resists like a real person.", 50, 400, w=1000)
    i3 = text("It catches your mistakes as you make them.", 50, 400, w=1100)
    scenes.append(render_scene("s3", d, [
        dict(img=gif, gif=True, scale=520, x=200, y=280, t0=0.2, fin=0.8),
        dict(img=h1, x=820, y=230, t0=0.6),
        dict(img=i1, x=824, y=520, t0=5.6),
        dict(img=i2, x=824, y=620, t0=8.2),
        dict(img=i3, x=824, y=720, t0=10.6),
    ]))

    # 4-6. Demo --------------------------------------------------------------
    def demo(name, d, num, title, sub, frames):
        n_ = text(num, 34, 600, color=MUTED, w=400)
        t_ = text(title, 76, 300, w=900)
        s_ = text(sub, 36, 300, color=MUTED, w=900)
        ph = [phone(f) for f in frames.values()]
        pw, _ = size_of(ph[0])
        px = 1920 - 260 - pw
        lay = [dict(img=n_, x=200, y=380, t0=0.3), dict(img=t_, x=196, y=430, t0=0.5),
               dict(img=s_, x=200, y=560, t0=0.9)]
        times = list(frames.keys())
        for k, (t0, p) in enumerate(zip(times, ph)):
            t1 = times[k + 1] + 0.5 if k + 1 < len(times) else None
            lay.append(dict(img=p, x=px, y=50, t0=t0, t1=t1, rise=(k == 0), fin=0.5))
        return render_scene(name, d, lay)

    scenes.append(demo("s4", D["s4"], "01", "Pick a conversation.", "Five of the hardest.",
                       {0.2: pick("home"), 2.6: pick("_scen."), 4.6: pick("scen2")}))
    pr = [p for p in cap if "practice" in p.name]
    rp = [p for p in cap if "reply" in p.name]
    scenes.append(demo("s5", D["s5"], "02", "Say it out loud.", "The other person pushes back.",
                       {0.2: pr[-1], 3.4: rp[0], 5.2: rp[min(8, len(rp) - 1)]}))
    scenes.append(demo("s6", D["s6"], "03", "Get scored, with evidence.", "Six skills. Your own words.",
                       {0.2: pick("review1"), 3.4: pick("review2"), 6.0: pick("review4")}))

    # 7. Research -------------------------------------------------------------
    d = D["s7"]
    hd = text(["The model observes.", "The engine decides."], 84, 300, w=1500)
    sub = text("VERBAL Pitfall Bench · 23 paired items · live model", 30, 400, color=MUTED, w=1300)
    tr = track_img()
    rows = [("Spots the mistake", 78, INK, 6.6), ("Stays quiet when there is none", 87, INK, 8.0),
            ("Reacts on its own, unaided", 35, MUTED, 10.4)]
    lay = [dict(img=hd, x=200, y=150, t0=0.5), dict(img=sub, x=204, y=380, t0=1.2)]
    for k, (lab, v, col, t0) in enumerate(rows):
        y = 520 + k * 130
        lt = text(lab, 38, 400, w=700)
        vt = text(f"{v}%", 46, 500, color=col, w=200)
        L_ = int(900 * v / 100)
        lay += [dict(img=lt, x=200, y=y - 12, t0=t0 - 0.3),
                dict(img=tr, x=820, y=y, t0=t0 - 0.3, rise=False),
                dict(img=bar(L_, color=col), x=820, y=y, t0=t0, rise=False, fin=0.2, reveal=(L_, 900, 1.0)),
                dict(img=vt, x=1750, y=y - 14, t0=t0 + 0.6)]
    scenes.append(render_scene("s7", d, lay))

    # 8. Impact --------------------------------------------------------------
    d = D["s8"]
    h8 = text("Built to be trusted.", 84, 300, w=1500, anchor="middle")
    c1 = card("Private", "Transcripts stay on your phone.")
    c2 = card("On-device", "Speech recognition, free and local.")
    c3 = card("Playbook", "Every line that worked, kept.")
    scenes.append(render_scene("s8", d, [
        dict(img=h8, x=centre_x(h8), y=230, t0=0.4),
        dict(img=c1, x=160, y=500, t0=0.9),
        dict(img=c2, x=710, y=500, t0=3.3),
        dict(img=c3, x=1260, y=500, t0=6.4),
    ]))

    # 9. Outro ---------------------------------------------------------------
    m = mascot("neutre", 300); mx, my = centre_x(m), 150
    o1 = text("VERBAL", 130, 300, w=1200, anchor="middle")
    o2 = text("Practise until it is automatic.", 46, 300, color=MUTED, w=1400, anchor="middle")
    o3 = text("github.com/Aaditya1273/VERBAL  ·  Flutter  ·  Gemini  ·  RevenueCat", 28, 400, color="#6B6B73", w=1600, anchor="middle")
    scenes.append(render_scene("s9", D["s9"], [
        dict(img=m, x=mx, y=my, t0=0.2, fin=0.8),
        *blinks(300, mx, my, [2.0, 5.0]),
        dict(img=o1, x=centre_x(o1), y=480, t0=0.6),
        dict(img=o2, x=centre_x(o2), y=660, t0=1.4),
        dict(img=o3, x=centre_x(o3), y=920, t0=2.2, rise=False),
    ]))

    # ---- cut: crossfade scenes, place narration on the same clock ----------
    keys = [f"s{i}" for i in range(1, 10)]
    starts, t = [], 0.0
    for k in keys:
        starts.append(t); t += D[k] - XF
    total = t + XF
    inp, fc, last = [], [], "0:v"
    for i, s in enumerate(scenes):
        inp += ["-i", str(s)]
    for i in range(1, len(scenes)):
        off = starts[i]
        fc.append(f"[{last}][{i}:v]xfade=transition=fade:duration={XF}:offset={off:.3f}[x{i}]")
        last = f"x{i}"
    fc.append(f"[{last}]fade=t=in:st=0:d=0.6,fade=t=out:st={total-1.2:.3f}:d=1.2,format=yuv420p[v]")
    a0 = len(scenes)
    for k_, k in enumerate(keys):
        inp += ["-i", str(narr[k])]
        ms = int((starts[k_] + LEAD) * 1000)
        fc.append(f"[{a0+k_}:a]adelay={ms}|{ms}[n{k_}]")
    fc.append("".join(f"[n{k}]" for k in range(9)) + f"amix=inputs=9:normalize=0,apad=whole_dur={total:.2f}[voice]")
    # Ambient pad: an open A-minor-add9 voicing, slow swells, low-passed.
    pad = ("aevalsrc='0.07*sin(2*PI*110*t)*(0.6+0.4*sin(2*PI*0.05*t))"
           "+0.05*sin(2*PI*164.81*t)*(0.6+0.4*sin(2*PI*0.07*t+1))"
           "+0.04*sin(2*PI*220*t)*(0.6+0.4*sin(2*PI*0.06*t+2))"
           "+0.03*sin(2*PI*246.94*t)*(0.5+0.5*sin(2*PI*0.04*t+3))"
           "+0.025*sin(2*PI*329.63*t)*(0.5+0.5*sin(2*PI*0.09*t+4))"
           f"|0.07*sin(2*PI*110.4*t)*(0.6+0.4*sin(2*PI*0.05*t+0.5))"
           "+0.05*sin(2*PI*165.2*t)*(0.6+0.4*sin(2*PI*0.07*t+1.5))"
           "+0.04*sin(2*PI*220.5*t)*(0.6+0.4*sin(2*PI*0.06*t+2.5))"
           "+0.03*sin(2*PI*247.3*t)*(0.5+0.5*sin(2*PI*0.04*t+3.5))"
           "+0.025*sin(2*PI*330.1*t)*(0.5+0.5*sin(2*PI*0.09*t+4.5))'"
           f":s=48000:d={total:.2f}")
    fc.append(f"{pad},lowpass=f=1800,aecho=0.8:0.7:120|240:0.25|0.18,volume=0.55,"
              f"afade=t=in:st=0:d=2,afade=t=out:st={total-2.5:.2f}:d=2.5[pad]")
    fc.append("[voice]asplit=2[vk][vm]")
    fc.append("[pad][vk]sidechaincompress=threshold=0.03:ratio=6:attack=40:release=600[ducked]")
    fc.append("[ducked][vm]amix=inputs=2:normalize=0,alimiter=limit=0.9[a]")
    out = W / "VERBAL_demo.mp4"
    run(["ffmpeg", "-y", *inp, "-filter_complex", ";".join(fc), "-map", "[v]", "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", f"{total:.2f}", str(out)])
    print(out, f"{total:.1f}s")


if __name__ == "__main__":
    main()
