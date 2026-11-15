#!/usr/bin/env python3
"""Generate every asset of Matchday Eleven procedurally: textures (PNG) and
audio (WAV). No third-party or ripped content; everything is synthesized here.

Usage: python3 tools/gen_assets.py [--quick]
  --quick  short audio tracks, for fast iteration (not for release).
"""
import argparse
import math
import os
import struct
import sys
import wave
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
AUD_DIR = os.path.join(ROOT, "assets", "audio")
SR = 44100


# ------------------------------------------------------------------ PNG writer

def write_png(path, arr):
    assert arr.dtype == np.uint8
    h, w, c = arr.shape
    color_type = 6 if c == 4 else 2
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += arr[y].tobytes()
    comp = zlib.compress(bytes(raw), 6)

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return out

    ihdr = struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", comp) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    return os.path.getsize(path)


# -------------------------------------------------------------------- textures

def fractal(shape, beta=1.4, seed=0, tileable=True):
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(shape).astype(np.float32)
    F = np.fft.rfft2(white)
    fy = np.fft.fftfreq(shape[0])[:, None]
    fx = np.fft.rfftfreq(shape[1])[None, :]
    f = np.sqrt(fy * fy + fx * fx)
    f[0, 0] = 1.0
    F *= 1.0 / (f ** beta)
    n = np.fft.irfft2(F, s=shape).astype(np.float32)
    n = (n - n.mean()) / (n.std() + 1e-9)
    return n


def to_u8(x, lo=None, hi=None):
    lo = x.min() if lo is None else lo
    hi = x.max() if hi is None else hi
    return np.clip((x - lo) / (hi - lo + 1e-9) * 255.0, 0, 255).astype(np.uint8)


def grass_detail(size=4096):
    a = fractal((size, size), 1.5, seed=11)
    b = fractal((size, size), 2.2, seed=12)
    rgb = np.zeros((size, size, 3), np.uint8)
    rgb[..., 0] = to_u8(a)          # large detail (UV*28)
    rgb[..., 1] = to_u8(b)          # fine detail (UV*90)
    rgb[..., 2] = to_u8(fractal((size, size), 1.2, seed=13))
    return write_png(os.path.join(TEX_DIR, "grass_detail.png"), rgb)


def crowd_texture(w=2048, h=512):
    """Seated crowd seen from the pitch: dark seats, row shadows and small
    coloured figures so the texture stays readable when mipmapped down."""
    rng = np.random.default_rng(42)
    img = np.zeros((h, w, 3), np.float32)
    img[:, :] = (30, 34, 44)
    palette = np.array([
        [190, 60, 55], [55, 80, 170], [225, 215, 190], [60, 140, 90],
        [230, 180, 60], [120, 120, 130], [200, 90, 150], [70, 70, 80],
        [240, 240, 240], [40, 40, 50], [100, 60, 40], [30, 90, 160],
    ], np.float32)
    cell_w, cell_h = 10, 16
    for r in range(h // cell_h):
        y0 = r * cell_h
        # Step shadow between rows.
        img[y0:y0 + 3, :] *= 0.55
        for c in range(w // cell_w):
            if rng.random() < 0.10:
                continue
            x0 = c * cell_w + 1
            col = palette[rng.integers(0, len(palette))]
            shade = 0.55 + 0.45 * rng.random()
            img[y0 + 5:y0 + 14, x0:x0 + 7] = col * shade        # torso
            img[y0 + 1:y0 + 5, x0 + 2:x0 + 6] = np.array([205, 170, 150], np.float32) * (0.6 + 0.4 * shade)  # head
    # Concrete aisles.
    for x in range(0, w, 128):
        img[:, x:x + 7] = (78, 80, 86)
    return write_png(os.path.join(TEX_DIR, "crowd.png"), np.clip(img, 0, 255).astype(np.uint8))


FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "J": ["00001", "00001", "00001", "00001", "10001", "10001", "01110"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}


def draw_text(img, text, x, y, scale, color):
    cx = x
    for ch in text.upper():
        glyph = FONT.get(ch)
        if glyph is None:
            cx += 6 * scale
            continue
        for r, row in enumerate(glyph):
            for c, bit in enumerate(row):
                if bit == "1":
                    y0 = y + r * scale
                    x0 = cx + c * scale
                    img[y0:y0 + scale, x0:x0 + scale] = color
        cx += 6 * scale
    return cx


def ad_board(idx, name, bg, fg, accent, w=2048, h=512):
    img = np.zeros((h, w, 3), np.uint8)
    img[:, :] = bg
    # Design elements per board (all original geometric marks).
    rng = np.random.default_rng(100 + idx)
    if idx % 3 == 0:
        for i in range(0, w, 64):
            img[:, i:i + 16] = accent
    elif idx % 3 == 1:
        yy, xx = np.mgrid[0:h, 0:w]
        chev = ((xx + yy) // 90) % 2 == 0
        img[chev] = (np.array(accent) * 0.6).astype(np.uint8)
    else:
        cx, cy, r = w // 2, h // 2, h // 2 - 20
        yy, xx = np.mgrid[0:h, 0:w]
        ring = (np.abs(np.hypot(xx - cx, yy - cy) - r) < 18)
        img[ring] = accent
    text_scale = 10
    tw = len(name) * 6 * text_scale
    draw_text(img, name, (w - tw) // 2, h // 2 - 3 * text_scale, text_scale, fg)
    return write_png(os.path.join(TEX_DIR, "ad_%d.png" % idx), img)


def ball_texture(size=1024):
    img = np.full((size, size, 3), 235, np.uint8)
    img[..., 0] = 238
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx / size * 2 * math.pi
    v = yy / size * math.pi
    # Classic panel look: dark pentagon-ish patches on a icosahedral-ish grid.
    rng = np.random.default_rng(5)
    img_final = img
    for k in range(14):
        cu, cv = rng.random() * 2 * math.pi, rng.random() * math.pi
        d = np.arccos(np.clip(math.sin(cv) * np.sin(v) + math.cos(cv) * np.cos(v) * np.cos(u - cu), -1, 1))
        img_final[d < 0.55] = (40, 40, 44)
    # Seam lines.
    seams = np.abs(np.sin(u * 5 + v * 3)) < 0.03
    img_final[seams] = (70, 70, 75)
    return write_png(os.path.join(TEX_DIR, "ball.png"), img_final)


def kit_fabric(size=1024):
    yy, xx = np.mgrid[0:size, 0:size]
    weave = (np.sin(xx * 0.7) * np.sin(yy * 0.7) * 0.5 + 0.5)
    g = (150 + weave * 60).astype(np.uint8)
    rgb = np.stack([g, g, g], axis=-1)
    return write_png(os.path.join(TEX_DIR, "kit_fabric.png"), rgb)


def net_texture(size=512):
    img = np.zeros((size, size, 4), np.uint8)
    step = 16
    img[:, ::step] = (240, 240, 240, 200)
    img[::step, :] = (240, 240, 240, 200)
    return write_png(os.path.join(TEX_DIR, "net.png"), img)


def scoreboard_texture(w=1024, h=256):
    """Stadium big screen: original wordmark, live score block and clock."""
    img = np.zeros((h, w, 3), np.uint8)
    img[:, :] = (8, 12, 20)
    img[::4, :] = (12, 18, 30)          # scanlines
    frame = (60, 78, 104)
    img[:8, :] = frame
    img[-8:, :] = frame
    img[:, :8] = frame
    img[:, -8:] = frame
    draw_text(img, "MATCHDAY ELEVEN", 40, 26, 5, (238, 240, 244))
    draw_text(img, "LIVE", 880, 26, 5, (232, 64, 58))
    # Score block.
    img[88:240, 26:556] = (16, 22, 34)
    draw_text(img, "0", 56, 100, 14, (250, 250, 250))
    draw_text(img, "-", 152, 100, 14, (150, 160, 175))
    draw_text(img, "0", 248, 100, 14, (250, 250, 250))
    # Side panel: half indicator and a simple possession bar (original design).
    draw_text(img, "1ST HALF", 600, 100, 6, (200, 208, 220))
    img[170:190, 600:720] = (210, 90, 70)
    img[170:190, 720:840] = (70, 130, 210)
    img[170:190, 840:960] = (40, 44, 52)
    draw_text(img, "00:00", 600, 198, 5, (120, 220, 160))
    return write_png(os.path.join(TEX_DIR, "scoreboard.png"), img)


# ---------------------------------------------------------------------- audio

def write_wav(path, data):
    """data: float32 array [frames, 2], -1..1"""
    data = np.clip(data, -1, 1)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    return os.path.getsize(path)


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    # Vectorized one-pole via lfilter-free chunked recurrence is slow in pure
    # python; use FFT band shaping instead for long signals.
    F = np.fft.rfft(x, axis=0)
    n = x.shape[0]
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    F *= 1.0 / (1.0 + (freqs[:, None] / alpha) ** 2)
    return np.fft.irfft(F, n=n, axis=0).astype(np.float32)


def brown(shape, seed, beta=2.0):
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(shape).astype(np.float32)
    F = np.fft.rfft(white, axis=0)
    n = shape[0]
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    F *= 1.0 / (freqs[:, None] ** (beta * 0.5) + 1.0)
    out = np.fft.irfft(F, n=n, axis=0).astype(np.float32)
    out /= (np.abs(out).max() + 1e-9)
    return out


def crowd_ambience(seconds, seed, excitement=0.55, hum=0.15):
    n = int(seconds * SR)
    base = brown((n, 2), seed, 2.0)
    # Slow swell modulation (several overlapping periods).
    t = np.arange(n) / SR
    mod = (0.6 + 0.4 * np.sin(2 * math.pi * t / 37.0 + seed) * np.sin(2 * math.pi * t / 53.0 + seed * 0.3))
    base *= (0.35 + excitement * mod)[:, None].astype(np.float32)
    # Occasional roar bumps.
    rng = np.random.default_rng(seed + 1)
    for _ in range(int(seconds / 22)):
        c = rng.integers(int(4 * SR), n - int(4 * SR))
        length = int(rng.uniform(1.5, 4.0) * SR)
        env = np.hanning(length).astype(np.float32)
        base[c:c + length] += env[:, None] * rng.uniform(0.25, 0.6)
    # Airy high layer.
    air = brown((n, 1), seed + 2, 1.2) * 0.12
    base += air
    base /= (np.abs(base).max() + 1e-9)
    return (base * 0.85).astype(np.float32)


def chants_track(seconds, seed):
    """Rhythmic claps + low choir hum, an original chant bed."""
    n = int(seconds * SR)
    out = np.zeros((n, 2), np.float32)
    bpm = 96.0
    beat = 60.0 / bpm
    rng = np.random.default_rng(seed)
    # Clap pattern on beats 1, 2& , 3, 4& (offsprings of an original groove).
    steps = [0.0, 1.5, 2.0, 3.5]
    t_beat = 0.0
    while t_beat < seconds - 2:
        for s in steps:
            c = int((t_beat + s * beat) * SR)
            if c + int(0.12 * SR) >= n:
                continue
            length = int(0.12 * SR)
            clap = brown((length, 1), int(rng.integers(1, 2 ** 30)), 1.0) * np.hanning(length)[:, None].astype(np.float32)
            out[c:c + length] += clap * rng.uniform(0.35, 0.55)
        t_beat += beat * 4
    # Choir hum: slow 3-note loop.
    notes = [110.0, 123.47, 146.83, 123.47]
    seg = int(4.0 * SR)
    i = 0
    while i < n:
        length = min(seg, n - i)
        f = notes[(i // seg) % len(notes)]
        tt = np.arange(length) / SR
        tone = (np.sin(2 * math.pi * f * tt) + 0.5 * np.sin(2 * math.pi * f * 1.5 * tt) + 0.3 * np.sin(2 * math.pi * f * 0.5 * tt))
        env = (0.5 - 0.5 * np.cos(2 * math.pi * tt / (length / SR) * 1.0)).astype(np.float32)
        out[i:i + length, 0] += tone * env * 0.12
        out[i:i + length, 1] += tone[::-1] * env * 0.10
        i += length
    out = lowpass(out, 4000)
    out /= (np.abs(out).max() + 1e-9)
    return (out * 0.8).astype(np.float32)


def goal_roar(seconds=14):
    n = int(seconds * SR)
    base = brown((n, 2), 77, 2.0)
    t = np.arange(n) / SR
    env = np.clip(t / 1.2, 0, 1) * np.clip((seconds - t) / 6.0, 0, 1)
    base *= env[:, None].astype(np.float32) * 1.6
    out = lowpass(base, 3500)
    out /= (np.abs(out).max() + 1e-9)
    return (out * 0.95).astype(np.float32)


def whistle():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    warble = 1 + 0.06 * np.sin(2 * math.pi * 28 * t)
    tone = np.sin(2 * math.pi * 2093 * t * warble) + 0.7 * np.sin(2 * math.pi * 2794 * t * warble)
    env = np.zeros(n, np.float32)
    for c in [0.05, 0.45, 0.95]:
        c0 = int(c * SR)
        length = int(0.28 * SR)
        env[c0:c0 + length] = np.hanning(length)
    out = (tone * env)[:, None] * np.ones((1, 2), np.float32)
    return (out * 0.5).astype(np.float32)


def thump(freq, seconds, punch=0.5):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 22).astype(np.float32)
    tone = np.sin(2 * math.pi * freq * t * (1 - 0.3 * t / seconds))
    noise = brown((n, 1), 9, 0.6) * np.exp(-t * 60).astype(np.float32) * punch
    out = ((tone * env * 0.8 + noise[:, 0] * 0.5)[:, None] * np.ones((1, 2), np.float32)).astype(np.float32)
    return (out * 0.8).astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--skip-textures", action="store_true")
    args = ap.parse_args()
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(AUD_DIR, exist_ok=True)
    total = 0
    print("textures:")
    if args.skip_textures:
        print("  skipped")
    else:
        total += grass_detail()
        total += crowd_texture()
        brands = [("VOLTA", (18, 60, 120), (240, 240, 240), (255, 200, 40)),
                  ("AERON", (20, 20, 24), (230, 230, 230), (80, 200, 160)),
                  ("PIXELBANK", (30, 70, 40), (240, 240, 220), (200, 90, 40)),
                  ("MATCHDAY", (90, 20, 30), (240, 230, 200), (240, 200, 60)),
                  ("PITCHSIDE", (24, 40, 70), (220, 230, 240), (60, 160, 220)),
                  ("ORBITA", (40, 24, 60), (235, 220, 240), (180, 120, 240))]
        for i, (name, bg, fg, acc) in enumerate(brands):
            total += ad_board(i, name, bg, fg, acc)
        total += ball_texture()
        total += kit_fabric()
        total += net_texture()
        total += scoreboard_texture()
    print("  texture bytes so far:", total)
    print("audio:")
    if args.quick:
        durs = {"crowd_home": 30, "crowd_away": 20, "crowd_chants": 20, "goal_roar": 14}
    else:
        durs = {"crowd_home": 480, "crowd_away": 400, "crowd_chants": 240, "goal_roar": 14}
    tracks = {
        "crowd_home.wav": lambda: crowd_ambience(durs["crowd_home"], 3, 0.5),
        "crowd_away.wav": lambda: crowd_ambience(durs["crowd_away"], 8, 0.4, 0.25),
        "crowd_chants.wav": lambda: chants_track(durs["crowd_chants"], 21),
        "goal_roar.wav": goal_roar,
        "whistle.wav": whistle,
        "kick.wav": lambda: thump(85, 0.25, 0.6),
        "bounce.wav": lambda: thump(140, 0.12, 0.35),
    }
    for name, fn in tracks.items():
        data = fn()
        if data.ndim == 1:
            data = np.stack([data, data], axis=-1)
        sz = write_wav(os.path.join(AUD_DIR, name), data)
        total += sz
        print("  %-20s %8.1f MB" % (name, sz / 1e6))
    print("TOTAL asset bytes: %d (%.1f MB)" % (total, total / 1e6))


if __name__ == "__main__":
    main()
