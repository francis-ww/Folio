"""Create original MDict fixtures and FSRS golden results using the official py-fsrs.

python -m pip install --target .tools/fsrs-reference fsrs==6.3.2
python Scripts/generate_fixtures.py --fsrs-path .tools/fsrs-reference
"""
from pathlib import Path
import argparse
import base64
import io
import json
import random
import struct
import sys
import wave
import zlib
from datetime import datetime, timedelta, timezone
from importlib.metadata import version

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Tests/FolioCoreTests/Fixtures"


def u64(value):
    return struct.pack(">Q", value)


def block(data, compressed=True):
    return struct.pack("<I", 2 if compressed else 0) + struct.pack(">I", zlib.adler32(data)) + (zlib.compress(data) if compressed else data)


def archive(records, *, resource=False, compressed=True, encrypted="No", engine="2.0",
            block_transform=None, index_transform=None, metadata_transform=None, extra_attributes=""):
    encoding = "utf-16le" if resource else "utf-8"
    width = 2 if resource else 1
    attributes = f" {extra_attributes}" if extra_attributes else ""
    header = f'<Dictionary GeneratedByEngineVersion="{engine}" Encoding="UTF-8" Encrypted="{encrypted}" Title="Tiny original dictionary"{attributes}/>\0'.encode("utf-16le")
    result = struct.pack(">I", len(header)) + header + struct.pack("<I", zlib.adler32(header))
    keys, content, offset = [], bytearray(), 0
    for name, value in records:
        keys.append((offset, name))
        if value is not None:
            content.extend(value)
            offset += len(value)
    # None means an alias shares the next key's record offset.
    groups = [keys[:2], keys[2:]] if len(keys) > 2 else [keys]
    key_blocks, info = [], bytearray()
    for group in groups:
        raw = b"".join(u64(position) + key.encode(encoding) + b"\0" * width for position, key in group)
        packed = block(raw, compressed)
        if block_transform:
            packed = block_transform(packed)
        key_blocks.append(packed)
        info.extend(u64(len(group)))
        for name in [group[0][1], group[-1][1]]:
            encoded = name.encode(encoding)
            info.extend(struct.pack(">H", len(encoded) // width) + encoded + b"\0" * width)
        info.extend(u64(len(packed)) + u64(len(raw)))
    packed_info = block(bytes(info))
    if index_transform:
        packed_info = index_transform(packed_info)
    numbers = u64(len(groups)) + u64(len(keys)) + u64(len(info)) + u64(len(packed_info)) + u64(sum(map(len, key_blocks)))
    result += (metadata_transform(numbers) if metadata_transform else numbers) + struct.pack(">I", zlib.adler32(numbers)) + packed_info + b"".join(key_blocks)
    # Small blocks deliberately split individual records, including UTF-8 characters.
    records_blocks = [bytes(content[i:i+23]) for i in range(0, len(content), 23)]
    packed_records = [block(data, compressed) for data in records_blocks]
    if block_transform:
        packed_records = [block_transform(data) for data in packed_records]
    record_info = b"".join(u64(len(packed)) + u64(len(raw)) for packed, raw in zip(packed_records, records_blocks))
    result += u64(len(packed_records)) + u64(len(keys)) + u64(len(record_info)) + u64(sum(map(len, packed_records)))
    return result + record_info + b"".join(packed_records)


def make_archives():
    definitions = [
        ("alias", None),
        ("aurora", "<p>A ribbon of light — bright across the night sky.</p>\0".encode()),
        ("bloom", b"<p>A flower opening into its full shape.</p>\0"),
        ("redirect", b"@@@LINK=aurora\r\n\0"),
    ]
    valid = archive(definitions)
    (OUTPUT / "tiny.mdx").write_bytes(valid)
    (OUTPUT / "uncompressed.mdx").write_bytes(archive(definitions, compressed=False))
    (OUTPUT / "old-version.mdx").write_bytes(archive(definitions, engine="1.2"))
    corrupted = bytearray(valid)
    corrupted[-1] ^= 0xff
    (OUTPUT / "corrupt.mdx").write_bytes(corrupted)
    (OUTPUT / "truncated.mdx").write_bytes(valid[:-13])
    png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    audio = io.BytesIO()
    with wave.open(audio, "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(8000)
        sound.writeframes(b"\0" * 160)
    (OUTPUT / "tiny.mdd").write_bytes(archive([(r"\images\leaf.png", png), (r"\sound\word.wav", audio.getvalue())], resource=True))
    (OUTPUT / "revised.mdx").write_bytes(archive([
        ("aurora", b"<p>The first light of dawn.</p>\0"),
        ("zenith", b"<p>The highest point.</p>\0"),
    ]))
    (OUTPUT / "revised.mdd").write_bytes(archive([(r"\images\leaf.png", png)], resource=True))
    (OUTPUT / "broken.mdd").write_bytes(b"invalid archive")


def make_fsrs():
    from fsrs import Card, Rating, Scheduler
    origin = datetime(2024, 1, 1, tzinfo=timezone.utc)
    scheduler = Scheduler(enable_fuzzing=False)
    cases = []
    randomizer = random.Random(291)
    sequences = [[(grade, 0)] for grade in range(1, 5)]
    for first in range(1, 5):
        for second in range(1, 5):
            for third in range(1, 5):
                sequences.append([(first, 0), (second, 600), (third, 30 * 86400)])
    for _ in range(40):
        sequence, elapsed = [], 0
        for _ in range(16):
            elapsed += randomizer.choice([60, 330, 600, 900, 86399, 86400, 5*86400, 100*86400])
            sequence.append((randomizer.randint(1, 4), elapsed))
        sequences.append(sequence)
    for sequence in sequences:
        card = Card(due=origin)
        events = []
        for grade, elapsed in sequence:
            date = origin + timedelta(seconds=elapsed)
            card, _ = scheduler.review_card(card, Rating(grade), review_datetime=date)
            events.append(dict(rating=grade, elapsed=elapsed, stability=card.stability, difficulty=card.difficulty,
                               state={1: "learning", 2: "review", 3: "relearning"}[int(card.state)],
                               step=card.step or 0, due=card.due.timestamp(), retrievability=scheduler.get_card_retrievability(card, date + timedelta(days=10))))
        cases.append(events)
    payload = {"reference": f"py-fsrs {version('fsrs')}", "origin": origin.timestamp(), "cases": cases}
    (OUTPUT / "fsrs-reference.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(cases)} FSRS cases ({sum(map(len, cases))} review transitions).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fsrs-path", type=Path)
    args = parser.parse_args()
    if args.fsrs_path:
        sys.path.insert(0, str(args.fsrs_path.resolve()))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    make_archives()
    from generate_encryption_fixtures import make_encrypted_archives
    make_encrypted_archives()
    make_fsrs()
