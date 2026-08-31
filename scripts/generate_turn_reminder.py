#!/usr/bin/env python3
"""Reproduce the original, gently enveloped two-note turn reminder (no external samples)."""

import math
from pathlib import Path
import struct
import wave

SAMPLE_RATE = 44_100
DURATION = 0.48
OUTPUT = Path(__file__).resolve().parents[1] / "BattleLine/Resources/turn-reminder.wav"


def note(time, start, duration, frequency, gain):
    elapsed = time - start
    if elapsed < 0 or elapsed >= duration:
        return 0.0
    attack = min(elapsed / 0.018, 1.0)
    release = min((duration - elapsed) / 0.08, 1.0)
    envelope = attack * release * math.exp(-3.0 * elapsed / duration)
    fundamental = math.sin(2 * math.pi * frequency * elapsed)
    overtone = 0.12 * math.sin(4 * math.pi * frequency * elapsed)
    return gain * envelope * (fundamental + overtone)


frames = bytearray()
for index in range(round(SAMPLE_RATE * DURATION)):
    time = index / SAMPLE_RATE
    sample = note(time, 0, 0.29, 659.255, 0.23)
    sample += note(time, 0.17, 0.29, 880.0, 0.2)
    frames.extend(struct.pack("<h", round(max(-1, min(1, sample)) * 32_767)))

with wave.open(str(OUTPUT), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(SAMPLE_RATE)
    output.writeframes(frames)
