#!/usr/bin/env python3
"""2.21: turn the raw Suno WAVs in ArtSource/Music220 into seamless game loops in CatLife/Audio.

For each song it
- skips the leading silence;
- finds where the ending fade starts and keeps everything before it;
- picks the jump point whose beat pattern best matches the start of the song (onset-envelope correlation);
- crossfades the tail into the start, so the file plays end-to-start with no gap;
- lowers the level to the -23 dBFS RMS the existing background music uses;
- writes caff ima4 @ 44.1 kHz stereo, like the other bgm files.

Run again only if a source WAV changes: python3 -B scripts/make_bgm_loops.py
"""
import array, math, subprocess, sys, tempfile, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "ArtSource/Music220"
AUDIO = ROOT / "CatLife/Audio"
# Must match GameMusicTrack raw values in CatLife/AudioRuntime/GameAudioContent.swift.
SONGS = ["rainy-window", "garden-afternoon", "starlit-hearth"]
TARGET_RMS_DB = -23.0
HOP = 0.01          # envelope resolution, seconds
CROSSFADE = 2.0     # seconds
MATCH = 6.0         # seconds of beat pattern compared at the jump
SEARCH = 30.0       # how far before the fade the jump may sit
MIN_LOOP = 120.0


def db(x):
    return 20 * math.log10(x) if x > 0 else -120.0


def pearson(a, b):
    n = len(a)
    ma, mb = sum(a) / n, sum(b) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = math.sqrt(sum((x - ma) ** 2 for x in a))
    dbb = math.sqrt(sum((y - mb) ** 2 for y in b))
    return num / (da * dbb) if da and dbb else 0.0


def make(song, temp):
    path = SOURCE / f"bgm-{song}.wav"
    with wave.open(str(path)) as w:
        rate, channels, frames = w.getframerate(), w.getnchannels(), w.getnframes()
        assert channels == 2 and w.getsampwidth() == 2, f"{path} must be 16-bit stereo"
        pcm = array.array("h")
        pcm.frombytes(w.readframes(frames))
    left, right = pcm[0::2], pcm[1::2]

    hop = int(rate * HOP)
    rms = []
    for i in range(0, frames - hop, hop):
        s = 0
        for j in range(i, i + hop, 4):
            m = (left[j] + right[j]) * 0.5
            s += m * m
        rms.append(math.sqrt(s / (hop / 4)) / 32768)
    loud = [db(r) for r in rms]
    onset = [0.0] + [max(0.0, loud[i] - loud[i - 1]) for i in range(1, len(loud))]

    start = next(i for i, v in enumerate(loud) if v > -45)
    # Ending fade: the last moment the 2 s average is still within 4 dB of the song's typical level.
    body = sorted(loud[start:])
    typical = body[len(body) // 2]
    win = int(2 / HOP)
    avg = [sum(loud[i:i + win]) / win for i in range(len(loud) - win)]
    fade = max(i for i, v in enumerate(avg) if v >= typical - 4)

    match, cross = int(MATCH / HOP), int(CROSSFADE / HOP)
    latest = fade - max(match, cross)
    earliest = max(start + int(MIN_LOOP / HOP), latest - int(SEARCH / HOP))
    head = onset[start:start + match]
    head_level = sum(loud[start:start + match]) / match
    best = None
    for jump in range(earliest, latest):
        level = sum(loud[jump:jump + match]) / match
        score = pearson(head, onset[jump:jump + match]) - 0.03 * abs(level - head_level)
        if best is None or score > best[0]:
            best = (score, jump)
    score, jump = best

    s0, j0, x = start * hop, jump * hop, cross * hop
    end = j0 + x
    out_l, out_r = left[s0 + x:end], right[s0 + x:end]
    # Equal-power crossfade: the tail fades out while the song's start fades in, ending exactly where the file begins.
    n = len(out_l)
    for k in range(x):
        t = k / x
        fo, fi = math.cos(t * math.pi / 2), math.sin(t * math.pi / 2)
        out_l[n - x + k] = int(left[j0 + k] * fo + left[s0 + k] * fi)
        out_r[n - x + k] = int(right[j0 + k] * fo + right[s0 + k] * fi)

    total = math.sqrt(sum(v * v for v in out_l[::8]) / len(out_l[::8]) / 2
                      + sum(v * v for v in out_r[::8]) / len(out_r[::8]) / 2) / 32768
    gain = 10 ** ((TARGET_RMS_DB - db(total)) / 20)
    mixed = array.array("h", bytes(4 * n))
    for k in range(n):
        mixed[2 * k] = max(-32767, min(32767, round(out_l[k] * gain)))
        mixed[2 * k + 1] = max(-32767, min(32767, round(out_r[k] * gain)))

    wav = Path(temp) / f"{song}.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(mixed.tobytes())
    target = AUDIO / f"bgm-{song}.caf"
    subprocess.run(["afconvert", "-f", "caff", "-d", "ima4@44100", "-r", "127", "--src-complexity", "bats",
                    str(wav), str(target)], check=True, capture_output=True)
    print(f"{target.relative_to(ROOT)}: start {start * HOP:.2f}s, fade {fade * HOP:.2f}s, "
          f"jump {jump * HOP:.2f}s -> {start * HOP + CROSSFADE:.2f}s, loop {n / rate:.2f}s, "
          f"match {score:.2f}, gain {db(gain):+.1f} dB")


def main():
    with tempfile.TemporaryDirectory() as temp:
        for song in SONGS:
            make(song, temp)


if __name__ == "__main__":
    sys.exit(main())
