"""Extract only mel filters and vocabulary; no tensor weights are retained."""
import argparse
import struct
from pathlib import Path


def extract(model: Path, output: Path):
    with model.open('rb') as source:
        magic, *hp = struct.unpack('<12i', source.read(48))
        if magic != 0x67676D6C or hp[0] != 51865 or hp[4] != 12 or hp[9] != 80:
            raise ValueError('Expected multilingual Whisper Small GGML model')
        mels, bins = struct.unpack('<2i', source.read(8))
        if (mels, bins) != (80, 201):
            raise ValueError('Invalid mel filters')
        source.seek(mels * bins * 4, 1)
        tokens, = struct.unpack('<i', source.read(4))
        if not 50257 <= tokens <= 51865:
            raise ValueError('Invalid vocabulary')
        for _ in range(tokens):
            length, = struct.unpack('<I', source.read(4))
            if length > 4096 or len(source.read(length)) != length:
                raise ValueError('Invalid token')
        length = source.tell()
        source.seek(0)
        data = source.read(length)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    print(f'Whisper audio metadata: {len(data):,} bytes; no model weights')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    extract(args.model, args.output)
