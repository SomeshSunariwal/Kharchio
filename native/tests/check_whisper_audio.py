"""Compare native Whisper features with an independent NumPy STFT reference."""
import argparse
import struct
import subprocess
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cxx", required=True)
    parser.add_argument("--model", type=Path, default=ROOT / "assets/models/ggml-small-q5_1.bin")
    args = parser.parse_args()
    with args.model.open("rb") as model:
        model.seek(48)
        assert struct.unpack("<ii", model.read(8)) == (80, 201)
        filters = np.frombuffer(model.read(80 * 201 * 4), dtype="<f4").reshape(80, 201)
    with tempfile.TemporaryDirectory(prefix="whisper-audio-", dir=ROOT / ".tmp") as directory:
        work = Path(directory)
        exe = work / "probe.exe"
        subprocess.run([args.cxx, "-O3", "-std=c++17", "-static", "-I", str(ROOT / "native/src"),
                        str(ROOT / "native/tests/whisper_audio_probe.cpp"), "-o", str(exe)], check=True)
        rng = np.random.default_rng(197)
        # Silence, very short input, partial-second audio, and a full 30 s chunk
        # exercise reflection, zero padding, FFT, dynamic range and boundaries.
        for count in (1, 3201, 47839, 480000):
            audio = (rng.standard_normal(count) * 0.02).astype("<f4") if count != 1 else np.zeros(1, dtype="<f4")
            source, output = work / "pcm.f32", work / "mel.f32"
            audio.tofile(source)
            subprocess.run([str(exe), str(args.model), str(source), str(output)], check=True)
            padded = np.pad(audio, (0, 480000 - count))
            centered = np.pad(padded, (200, 200), mode="reflect")
            frames = np.lib.stride_tricks.sliding_window_view(centered, 400)[::160][:3000]
            hann = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(400) / 400)
            power = np.abs(np.fft.rfft(frames * hann, axis=1)) ** 2
            expected = np.log10(np.maximum(1e-10, filters.astype(np.float64) @ power.T))
            expected = (np.maximum(expected, expected.max() - 8) + 4) / 4
            actual = np.fromfile(output, dtype="<f4").reshape(80, 3000)
            error = float(np.abs(expected - actual).max())
            assert error < 2e-5, (count, error)
            print(f"PASS samples={count}: max mel error={error:.8f}; cancellation passed")


if __name__ == "__main__":
    main()
