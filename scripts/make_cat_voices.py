#!/usr/bin/env python3
"""2.20: derive per-cat voices from the six original cat clips in CatLife/Audio.

Each voice replays a clip faster or slower (like a smaller or bigger cat): pitch and length change together,
which sounds more natural on short meows than a pitch shift. The standard voice is the original file.
Run again only if an original clip changes: python3 -B scripts/make_cat_voices.py
"""
import struct, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "CatLife/Audio"
CLIPS = ["cat-happy", "cat-hungry", "cat-coax", "cat-unwell", "cat-sleepy", "cat-purr"]
# Must match CatVoice in CatLife/AudioRuntime/GameAudioContent.swift.
VOICES = {"tiny": 1.26, "bright": 1.12, "warm": 0.89, "deep": 0.80}


def run(*args):
    subprocess.run(args, check=True, capture_output=True)


def main():
    with tempfile.TemporaryDirectory() as temp:
        for clip in CLIPS:
            source = AUDIO / f"{clip}.caf"
            wav = Path(temp) / f"{clip}.wav"
            run("afconvert", "-f", "WAVE", "-d", "LEI16@44100", str(source), str(wav))
            data = bytearray(wav.read_bytes())
            assert data[:4] == b"RIFF" and data[12:16] == b"fmt ", f"unexpected header in {wav}"
            channels, = struct.unpack_from("<H", data, 22)
            for voice, factor in VOICES.items():
                rate = round(44100 * factor)
                shifted = bytearray(data)
                struct.pack_into("<II", shifted, 24, rate, rate * channels * 2)
                retimed = Path(temp) / f"{clip}-{voice}.wav"
                retimed.write_bytes(shifted)
                target = AUDIO / f"{clip}-{voice}.caf"
                run("afconvert", "-f", "caff", "-d", "ima4@44100", "-r", "127", "--src-complexity", "bats",
                    str(retimed), str(target))
                print(target.relative_to(ROOT))


if __name__ == "__main__":
    sys.exit(main())
