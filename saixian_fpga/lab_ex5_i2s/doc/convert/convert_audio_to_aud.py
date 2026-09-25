"""Convert PCM WAV to the FPGA's sector-aligned SXAUD001 audio format.

Requires Python 3.12 or earlier because the source snapshot uses audioop.
For a track that is already 48 kHz, stereo, signed 16-bit PCM, no sample
conversion is needed. Keep AUD files contiguous on a freshly prepared card.
"""

import argparse
import os
import struct
import wave

try:
    import audioop
except ImportError as exc:
    raise SystemExit("This converter requires Python 3.12 or earlier (audioop).") from exc

RATE = 48000
CHANNELS = 2
SAMPLE_WIDTH = 2
SECTOR = 512


def convert(src: str, dst: str) -> None:
    with wave.open(src, "rb") as wav:
        if wav.getcomptype() != "NONE":
            raise ValueError("Only uncompressed PCM WAV is supported")
        raw = wav.readframes(wav.getnframes())
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()

    if width not in (1, 2, 3, 4):
        raise ValueError("Only 8/16/24/32-bit PCM WAV is supported")
    # WAV's 8-bit PCM samples are unsigned; audioop's arithmetic is signed.
    if width == 1:
        raw = audioop.bias(raw, 1, -128)
    if channels == 1:
        raw = audioop.tostereo(raw, width, 1, 1)
    elif channels != 2:
        raise ValueError("Input WAV must be mono or stereo")
    if width != SAMPLE_WIDTH:
        raw = audioop.lin2lin(raw, width, SAMPLE_WIDTH)
    if rate != RATE:
        raw, _ = audioop.ratecv(raw, SAMPLE_WIDTH, CHANNELS, rate, RATE, None)

    raw = raw[: len(raw) - (len(raw) % 4)]
    header = bytearray(SECTOR)
    header[0:8] = b"SXAUD001"
    struct.pack_into("<I", header, 8, len(raw))
    struct.pack_into("<I", header, 12, RATE)
    struct.pack_into("<H", header, 16, 16)
    struct.pack_into("<H", header, 18, CHANNELS)

    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "wb") as out:
        out.write(header)
        out.write(raw)
        padding = (-len(raw)) % SECTOR
        if padding:
            out.write(b"\0" * padding)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="WAV -> FPGA SXAUD001 AUD")
    parser.add_argument("input", help="input PCM WAV file")
    parser.add_argument("output", help="output .AUD file")
    args = parser.parse_args()
    convert(args.input, args.output)
    print(f"Generated {args.output}")
