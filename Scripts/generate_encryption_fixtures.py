"""Generate original encrypted archives and crypto goldens with independent references.

python Scripts/generate_encryption_fixtures.py
Pinned upstream Python sources are cached only in ignored .tools/mdict-reference.
They are test-generation dependencies, never compiled into Folio or required by tests.
"""
from pathlib import Path
from urllib.request import urlopen
import base64
import hashlib
import html
import importlib
import io
import json
import struct
import sys
import types
import wave

from generate_fixtures import ROOT, OUTPUT, archive

REFERENCES = {
    "ripemd128.py": ("csarron/mdict-analysis", "e99cfca7a969cc8020d6f92d76c254e075f4110a", "c0abdebd73b5eebeada430c6236502c9d7ccbf220a022aa627d421602901749c"),
    "pureSalsa20.py": ("csarron/mdict-analysis", "e99cfca7a969cc8020d6f92d76c254e075f4110a", "0bc5e69e440945d26a43d65227067af09af98c8752c2669de4cbe1e64869fee7"),
    "writemdict.py": ("zhansliu/writemdict", "f0240b30cabd2f0470d3ee1a0641fc7f8c38dcf5", "f47452af9296b79d8f4fc39e0432d72278079857482bc6d74b1b5e35e4b65081"),
    "readmdict.py": ("hehonghui/mdict-analysis", "373ef1835d7eb47be699e3f333aa9008a7076236", "2dbdd44ab5ff0687ebd637664b26cea19fcf6110ef21bbb738b5053fe1f86e33"),
}


def references():
    cache = ROOT / ".tools/mdict-reference"
    cache.mkdir(parents=True, exist_ok=True)
    for name, (repo, commit, checksum) in REFERENCES.items():
        path = cache / name
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            data = urlopen(f"https://raw.githubusercontent.com/{repo}/{commit}/{name}", timeout=30).read()
            if hashlib.sha256(data).hexdigest() != checksum:
                raise RuntimeError(f"Reference checksum mismatch: {name}")
            path.write_bytes(data)
    sys.path.insert(0, str(cache))
    # writemdict uses cgi.escape, removed in recent Python. Adapt its import only.
    shim = types.ModuleType("cgi")
    shim.escape = html.escape
    sys.modules["cgi"] = shim
    writer = importlib.import_module("writemdict")
    reader = importlib.import_module("readmdict")
    return writer, reader


def make_encrypted_archives():
    writer, reader = references()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    definitions = [
        ("alias", None),
        ("aurora", "<p>A ribbon of light — bright across the night sky.</p>\0".encode()),
        ("bloom", b"<p>A flower opening into its full shape.</p>\0"),
        ("redirect", b"@@@LINK=aurora\r\n\0"),
    ]

    def cipher_block(method, prefix):
        def transform(block):
            checksum = block[4:8]
            key = writer.ripemd128(checksum)
            data = block[8:]
            first = data[:prefix]
            encrypted = (writer._fast_encrypt(first, key) if method == 1 else
                         writer.Salsa20(key=key, IV=bytes(8), rounds=8).encryptBytes(first))
            descriptor = struct.unpack("<I", block[:4])[0] | method << 4 | prefix << 8
            return struct.pack("<I", descriptor) + checksum + encrypted + data[prefix:]
        return transform

    (OUTPUT / "encrypted.mdx").write_bytes(archive(definitions, encrypted="2", index_transform=writer._mdx_encrypt))
    for name, method in [("fast", 1), ("salsa", 2)]:
        for compressed in [True, False]:
            suffix = "encrypted" if compressed else "uncompressed"
            (OUTPUT / f"{name}-{suffix}.mdx").write_bytes(archive(
                definitions, compressed=compressed, encrypted="2", index_transform=writer._mdx_encrypt,
                block_transform=cipher_block(method, 16 if method == 1 else 255)))

    png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    audio = io.BytesIO()
    with wave.open(audio, "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(8000)
        sound.writeframes(bytes(160))
    resources = [(r"\images\leaf.png", png), (r"\sound\word.wav", audio.getvalue())]
    sequence = 0

    def alternating(block):
        nonlocal sequence
        sequence += 1
        return cipher_block(1 if sequence % 2 else 2, 16)(block)

    (OUTPUT / "encrypted.mdd").write_bytes(archive(resources, resource=True, encrypted="2",
                                                  index_transform=writer._mdx_encrypt, block_transform=alternating))
    # Real registration-bound encryption: identity is deliberately external to the archive.
    owner = "fixture-owner@example.com"
    password = b"fixture-private-passcode"
    regcode = writer.encrypt_key(password, email=owner)
    attrs = f'RegisterBy="EMail" RegCode="{regcode}"'
    for name, flag in [("registered", "1"), ("registered-both", "3"), ("registered-yes", "Yes")]:
        (OUTPUT / f"{name}.mdx").write_bytes(archive(
            definitions, encrypted=flag, extra_attributes=attrs,
            metadata_transform=lambda data: writer._salsa_encrypt(data, password),
            index_transform=writer._mdx_encrypt if flag == "3" else None))
        verified = reader.MDX(str(OUTPUT / f"{name}.mdx"), passcode=(bytes.fromhex(regcode), owner))
        assert len(verified_records(verified)) == 4
    (OUTPUT / "registered.mdd").write_bytes(archive(
        resources, resource=True, encrypted="1", extra_attributes=attrs,
        metadata_transform=lambda data: writer._salsa_encrypt(data, password)))

    # Verify using the independent reader's block decoder. Its items() iterator does
    # not reassemble records crossing blocks, which these fixtures deliberately test.
    for name in ["encrypted", "fast-encrypted", "salsa-encrypted", "fast-uncompressed", "salsa-uncompressed"]:
        decoded = verified_records(reader.MDX(str(OUTPUT / f"{name}.mdx")))
        assert len(decoded) == 4 and decoded[1][0] == b"aurora"
        assert "—" in decoded[1][1].decode("utf-8")
    decoded = verified_records(reader.MDD(str(OUTPUT / "encrypted.mdd")))
    assert [item[1] for item in decoded] == [item[1] for item in resources]
    make_vectors(writer)
    print("Generated and independently verified encrypted MDX/MDD fixtures and crypto vectors.")


def verified_records(reference):
    with open(reference._fname, "rb") as source:
        source.seek(reference._record_block_offset)
        count, entries, info_size, packed_size = struct.unpack(">QQQQ", source.read(32))
        assert info_size == count * 16
        blocks = [struct.unpack(">QQ", source.read(16)) for _ in range(count)]
        content = b"".join(reference._decode_block(source.read(packed), expanded) for packed, expanded in blocks)
    keys = reference._key_list
    decoded = []
    for i, (start, name) in enumerate(keys):
        end = next((offset for offset, _ in keys[i + 1:] if offset > start), len(content))
        decoded.append((name, content[start:end]))
    return decoded


def make_vectors(writer):
    hashes = []
    for data in [b"", b"a", b"abc", b"message digest", b"abcdefghijklmnopqrstuvwxyz",
                 b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
                 b"1234567890" * 8, b"a" * 1_000_000] + [bytes(range(n)) for n in [55, 56, 63, 64, 65, 120, 128]]:
        # Avoid a 2MB hex string for the million-byte standard test.
        hashes.append(dict(input=data.hex() if len(data) < 1000 else "", repeatA=len(data) if len(data) >= 1000 else 0,
                           digest=writer.ripemd128(data).hex()))
    salsa = []
    for key_size in [16, 32]:
        for count in [0, 1, 63, 64, 65, 127, 128, 255, 257]:
            key = bytes(range(key_size))
            nonce = bytes(range(8))
            plain = bytes(i % 256 for i in range(count))
            for counter in [0, 2**32 - 1, 2**64 - 2]:
                cipher = writer.Salsa20(key=key, IV=nonce, rounds=8)
                cipher.setCounter(counter)
                salsa.append(dict(key=key.hex(), nonce=nonce.hex(), counter=counter,
                                  input=plain.hex(), output=cipher.encryptBytes(plain).hex()))
    fast = []
    key = writer.ripemd128(b"Folio independent fixture")
    for count in [0, 1, 16, 255, 256, 257, 513]:
        plain = bytes(i % 256 for i in range(count))
        fast.append(dict(key=key.hex(), plain=plain.hex(), cipher=writer._fast_encrypt(plain, key).hex()))
    (OUTPUT / "crypto-reference.json").write_text(json.dumps(
        dict(references=REFERENCES, ripemd=hashes, salsa=salsa, fast=fast), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    make_encrypted_archives()
