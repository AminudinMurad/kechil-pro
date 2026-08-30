#!/usr/bin/env python3
"""
Validates the byte-level metadata-stripping algorithm that MetadataStripper.swift
is a direct port of. Two things must hold for every format:
  1. All metadata segments/chunks are gone.
  2. Decoded pixels are byte-identical to the original (proves NO recompression).
"""
import io, struct, sys
from PIL import Image
from PIL.PngImagePlugin import PngInfo

FAIL = []
def check(label, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + label + (("  -- " + detail) if detail else ""))
    if not cond:
        FAIL.append(label)

# ----------------------------------------------------------------- JPEG
def keep_jpeg_segment(marker, payload):
    """Keep rendering data only when the carrier has the expected signature."""
    if marker == 0xE0: return payload.startswith(b"JFIF\x00")
    if marker == 0xE2: return payload.startswith(b"ICC_PROFILE")
    if marker == 0xEE: return payload.startswith(b"Adobe")
    return False

def strip_jpeg(b):
    out = bytearray(b[0:2]); removed = []
    i = 2; n = len(b)
    while i < n:
        if b[i] != 0xFF:
            out += b[i:]; break
        m = b[i+1]
        if m == 0xFF:
            i += 1; continue
        if m == 0xD9:
            out += b[i:i+2]; i += 2
            if i < n: removed.append("trailing data after EOI")
            break
        if (0xD0 <= m <= 0xD7) or m == 0x01:
            out += b[i:i+2]; i += 2; continue
        ln = (b[i+2] << 8) | b[i+3]
        end = i + 2 + ln
        is_metadata = (0xE0 <= m <= 0xEF) or m == 0xFE
        payload = b[i+4:end]
        if is_metadata and not keep_jpeg_segment(m, payload):
            removed.append("APP%d/0x%02X" % (m - 0xE0, m)); i = end; continue
        out += b[i:end]; i = end
        if m == 0xDA:
            # Copy entropy-coded bytes verbatim until an unstuffed marker. FF00 is a
            # literal FF and FFD0..FFD7 are restart markers inside the scan.
            scan = i
            while i + 1 < n:
                if b[i] != 0xFF:
                    i += 1; continue
                j = i + 1
                while j < n and b[j] == 0xFF: j += 1
                if j >= n:
                    i = n; break
                nxt = b[j]
                if nxt == 0x00 or 0xD0 <= nxt <= 0xD7:
                    i = j + 1; continue
                out += b[scan:i]
                # Keep the first FF as the start of the marker; any repeated fill FFs
                # are harmless and will be handled by the main loop.
                break
            else:
                out += b[scan:]
                break
    return bytes(out), removed

def jpeg_markers(b):
    """List every APPn / COM marker present."""
    found = []; i = 2; n = len(b)
    while i < n:
        if b[i] != 0xFF: break
        m = b[i+1]
        if m == 0xFF: i += 1; continue
        if m in (0xD9,): break
        if m == 0xDA: break
        if (0xD0 <= m <= 0xD7) or m == 0x01: i += 2; continue
        ln = (b[i+2] << 8) | b[i+3]
        if (0xE0 <= m <= 0xEF) or m == 0xFE: found.append(m)
        i += 2 + ln
    return found

def seg(marker, payload):
    return bytes([0xFF, marker]) + struct.pack(">H", len(payload) + 2) + payload

def test_jpeg():
    print("\nJPEG")
    base = io.BytesIO()
    Image.linear_gradient("L").convert("RGB").resize((160, 120)).save(base, "JPEG", quality=88)
    orig = base.getvalue()

    # Hand-inject the exact segment types we claim to remove, right after SOI.
    exif = b"Exif\x00\x00" + b"MM\x00*\x00\x00\x00\x08" + b"\x00\x00" + b"GPSLAT3.14N" * 4
    xmp  = b"http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta>author=me</x:xmpmeta>"
    iptc = b"Photoshop 3.0\x008BIM\x04\x04" + b"\x00" * 12
    c2pa = b"JUMBF\x00\x0bc2pa-manifest-claim-signature"
    app5 = b"\x00thumbnail-junk" * 3
    com  = b"created with SecretSoftware 9"
    stuffed = orig[0:2] + seg(0xE1, exif) + seg(0xE1, xmp) + seg(0xED, iptc) \
            + seg(0xEB, c2pa) + seg(0xE5, app5) + seg(0xFE, com) + orig[2:]

    before = jpeg_markers(stuffed)
    check("test image carries metadata", set(before) >= {0xE1, 0xED, 0xEB, 0xE5, 0xFE},
          "markers=" + ",".join("0x%02X" % m for m in before))

    clean, removed = strip_jpeg(stuffed)
    after = jpeg_markers(clean)

    check("EXIF/GPS + XMP (APP1) removed", 0xE1 not in after)
    check("IPTC/Photoshop (APP13) removed", 0xED not in after)
    check("C2PA (APP11) removed", 0xEB not in after)
    check("APP5 maker junk removed", 0xE5 not in after)
    check("JPEG comment (COM) removed", 0xFE not in after)
    check("ICC/JFIF preserved", set(after) <= {0xE0, 0xE2, 0xEE},
          "kept=" + (",".join("0x%02X" % m for m in after) or "none"))
    check("no metadata strings survive",
          all(s not in clean for s in (b"GPSLAT", b"author=me", b"c2pa", b"SecretSoftware", b"8BIM")))

    a = Image.open(io.BytesIO(orig)); b_ = Image.open(io.BytesIO(clean))
    check("pixels byte-identical (no recompression)",
          a.tobytes() == b_.tobytes(), "%s vs %s" % (a.size, b_.size))
    check("smaller than stuffed input", len(clean) < len(stuffed),
          "%d -> %d bytes" % (len(stuffed), len(clean)))

    # Metadata is legal between progressive scans and is also seen immediately before
    # EOI in real-world files. The old first-SOS shortcut copied it through untouched.
    post_scan = orig[:-2] + seg(0xE1, b"Exif\x00\x00post-scan-secret-GPS") + orig[-2:]
    post_clean, post_removed = strip_jpeg(post_scan)
    check("metadata after the first SOS is removed", b"post-scan-secret" not in post_clean)
    check("post-scan removal is reported", bool(post_removed))
    check("post-scan pixels remain byte-identical",
          Image.open(io.BytesIO(orig)).tobytes() == Image.open(io.BytesIO(post_clean)).tobytes())

    trailing = orig + b"MotionPhoto Samsung SEF trailing private payload"
    trailing_clean, trailing_removed = strip_jpeg(trailing)
    check("data appended after JPEG EOI is dropped", b"MotionPhoto" not in trailing_clean)
    check("trailing-data removal is reported", bool(trailing_removed))

    # APP0 and APP2 are carriers, not guarantees. Keep only real JFIF/ICC signatures;
    # JFXX and MPF may embed thumbnails or complete secondary JPEGs with their own GPS.
    embedded = b"MPF\x00" + seg(0xE1, b"Exif\x00\x00embedded-secondary-GPS")
    deceptive = orig[:2] + seg(0xE0, b"JFXX\x00thumbnail-private") \
              + seg(0xE2, embedded) + seg(0xE2, b"ICC_PROFILE\x00\x01\x01profile") + orig[2:]
    deceptive_clean, deceptive_removed = strip_jpeg(deceptive)
    check("JFXX thumbnail carrier is removed", b"JFXX" not in deceptive_clean)
    check("MPF secondary-image carrier is removed", b"MPF" not in deceptive_clean)
    check("genuine ICC profile is preserved", b"ICC_PROFILE" in deceptive_clean)
    check("deceptive APP0/APP2 removal is reported", len(deceptive_removed) >= 2)
    return clean

# ----------------------------------------------------------------- PNG
PNG_KEEP = {
    b"IHDR", b"PLTE", b"IDAT", b"IEND",              # critical image data
    b"iCCP", b"gAMA", b"cHRM", b"sRGB", b"sBIT",   # colour / precision
    b"tRNS", b"bKGD", b"pHYs",                       # rendering / dimensions
    b"acTL", b"fcTL", b"fdAT",                       # animated PNG
}
PNG_STRIP = {b"tEXt", b"zTXt", b"iTXt", b"eXIf", b"tIME", b"caBX", b"dSIG"}

def strip_png(b):
    out = bytearray(b[0:8]); removed = []
    i = 8; n = len(b)
    while i + 12 <= n:
        ln = struct.unpack(">I", b[i:i+4])[0]
        t = b[i+4:i+8]
        end = min(i + 12 + ln, n)
        if t not in PNG_KEEP:
            removed.append(t.decode("latin1")); i = end; continue
        out += b[i:end]; i = end
        if t == b"IEND": break
    return bytes(out), removed

def png_chunks(b):
    found = []; i = 8; n = len(b)
    while i + 12 <= n:
        ln = struct.unpack(">I", b[i:i+4])[0]
        t = b[i+4:i+8]
        found.append(t)
        i = min(i + 12 + ln, n)
        if t == b"IEND": break
    return found

def png_chunk(t, payload):
    import zlib
    return struct.pack(">I", len(payload)) + t + payload + \
           struct.pack(">I", zlib.crc32(t + payload) & 0xFFFFFFFF)

def test_png():
    print("\nPNG")
    info = PngInfo()
    info.add_text("Software", "SecretSoftware 9")
    info.add_itxt("XML:com.adobe.xmp", "<x:xmpmeta>prompt=a cat</x:xmpmeta>")
    buf = io.BytesIO()
    Image.linear_gradient("L").convert("RGB").resize((140, 100)).save(buf, "PNG", pnginfo=info)
    stuffed = buf.getvalue()

    # add eXIf + tIME + caBX (C2PA) by hand, before IEND
    idx = stuffed.rfind(png_chunk(b"IEND", b"")[:8])
    extra = png_chunk(b"eXIf", b"MM\x00*\x00\x00\x00\x08GPSDATA-1.234") \
          + png_chunk(b"tIME", struct.pack(">HBBBBB", 2024, 5, 1, 12, 0, 0)) \
          + png_chunk(b"caBX", b"jumbf-c2pa-manifest")
    stuffed = stuffed[:idx] + extra + stuffed[idx:]

    plain = io.BytesIO()
    Image.open(io.BytesIO(stuffed)).save(plain, "PNG")   # reference for pixels

    before = png_chunks(stuffed)
    check("test image carries metadata",
          any(t in PNG_STRIP for t in before),
          "chunks=" + ",".join(t.decode("latin1") for t in before))

    clean, removed = strip_png(stuffed)
    after = png_chunks(clean)
    check("text/XMP chunks removed", not any(t in (b"tEXt", b"zTXt", b"iTXt") for t in after))
    check("eXIf removed", b"eXIf" not in after)
    check("tIME removed", b"tIME" not in after)
    check("caBX (C2PA) removed", b"caBX" not in after)
    check("IHDR/IDAT/IEND intact",
          b"IHDR" in after and b"IDAT" in after and b"IEND" in after,
          "kept=" + ",".join(t.decode("latin1") for t in after))
    check("no metadata strings survive",
          all(s not in clean for s in (b"SecretSoftware", b"prompt=a cat", b"GPSDATA", b"c2pa")))

    a = Image.open(io.BytesIO(stuffed)); b_ = Image.open(io.BytesIO(clean))
    check("pixels byte-identical (no recompression)", a.tobytes() == b_.tobytes())

    # A denylist cannot anticipate vendor preview chunks. An allowlist drops unknown
    # ancillary chunks while preserving the chunks needed to render the image.
    idx = stuffed.rfind(png_chunk(b"IEND", b"")[:8])
    preview_stuffed = stuffed[:idx] + png_chunk(b"prVW", b"photoshop-private-preview") + stuffed[idx:]
    preview_clean, preview_removed = strip_png(preview_stuffed)
    check("unknown PNG preview chunk is removed", b"prVW" not in png_chunks(preview_clean))
    check("unknown PNG removal is reported", bool(preview_removed))
    check("PNG allowlist preserves decoded pixels",
          Image.open(io.BytesIO(preview_stuffed)).tobytes() ==
          Image.open(io.BytesIO(preview_clean)).tobytes())
    return clean

# ----------------------------------------------------------------- WebP
def strip_webp(b):
    removed = []; kept = []; vp8x = -1
    allowed = {b"VP8 ", b"VP8L", b"VP8X", b"ALPH", b"ANIM", b"ANMF", b"ICCP"}
    i = 12; n = len(b)
    while i + 8 <= n:
        fourcc = b[i:i+4]
        size = struct.unpack("<I", b[i+4:i+8])[0]
        end = min(i + 8 + size + (size & 1), n)
        if fourcc not in allowed:
            removed.append(fourcc.decode("latin1")); i = end; continue
        if fourcc == b"VP8X":
            vp8x = len(kept)
        kept.append(bytearray(b[i:end])); i = end
    if vp8x >= 0:
        kept[vp8x][8] &= ~0x08 & ~0x04      # clear EXIF (0x08) and XMP (0x04) flag bits
    body = b"".join(bytes(k) for k in kept)
    return b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WEBP" + body, removed

def webp_chunks(b):
    found = []; i = 12; n = len(b)
    while i + 8 <= n:
        fourcc = b[i:i+4]
        size = struct.unpack("<I", b[i+4:i+8])[0]
        found.append(fourcc)
        i += 8 + size + (size & 1)
    return found

def test_webp():
    print("\nWebP")
    buf = io.BytesIO()
    Image.linear_gradient("L").convert("RGB").resize((120, 90)).save(
        buf, "WEBP", lossless=True,
        exif=b"Exif\x00\x00MM\x00*\x00\x00\x00\x08GPSHERE-9.99",
        xmp=b"<x:xmpmeta>author=me</x:xmpmeta>")
    stuffed = buf.getvalue()

    before = webp_chunks(stuffed)
    check("test image carries metadata",
          b"EXIF" in before or b"XMP " in before,
          "chunks=" + ",".join(c.decode("latin1") for c in before))

    clean, removed = strip_webp(stuffed)
    after = webp_chunks(clean)
    check("EXIF chunk removed", b"EXIF" not in after)
    check("XMP chunk removed", b"XMP " not in after)
    check("image data chunk intact",
          any(c in (b"VP8 ", b"VP8L", b"VP8X", b"ANMF") for c in after),
          "kept=" + ",".join(c.decode("latin1") for c in after))
    check("RIFF size field correct",
          struct.unpack("<I", clean[4:8])[0] == len(clean) - 8,
          "declared=%d actual=%d" % (struct.unpack("<I", clean[4:8])[0], len(clean) - 8))
    check("no metadata strings survive",
          all(s not in clean for s in (b"GPSHERE", b"author=me")))

    a = Image.open(io.BytesIO(stuffed)); b_ = Image.open(io.BytesIO(clean))
    check("pixels byte-identical (no recompression)", a.tobytes() == b_.tobytes())
    check("Pillow reports no exif on output",
          not Image.open(io.BytesIO(clean)).info.get("exif"),
          repr(Image.open(io.BytesIO(clean)).info.get("exif"))[:40])

    # WebP Content Credentials use a C2PA RIFF chunk. Unknown private chunks fail
    # closed as well; neither is rendering data.
    c2pa_payload = b"jumbf-c2pa-manifest-private"
    c2pa_chunk = b"C2PA" + struct.pack("<I", len(c2pa_payload)) + c2pa_payload
    if len(c2pa_payload) & 1: c2pa_chunk += b"\x00"
    private_payload = b"vendor-private"
    private_chunk = b"ZZZZ" + struct.pack("<I", len(private_payload)) + private_payload
    if len(private_payload) & 1: private_chunk += b"\x00"
    body = stuffed[12:] + c2pa_chunk + private_chunk
    c2pa_stuffed = b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WEBP" + body
    c2pa_clean, c2pa_removed = strip_webp(c2pa_stuffed)
    after_private = webp_chunks(c2pa_clean)
    check("WebP C2PA chunk is removed", b"C2PA" not in after_private)
    check("unknown WebP private chunk is removed", b"ZZZZ" not in after_private)
    check("WebP private removals are reported", len(c2pa_removed) >= 2)
    check("WebP allowlist preserves decoded pixels",
          Image.open(io.BytesIO(c2pa_stuffed)).tobytes() ==
          Image.open(io.BytesIO(c2pa_clean)).tobytes())
    return clean

# ----------------------------------------------------------------- run
if __name__ == "__main__":
    test_jpeg(); test_png(); test_webp()
    print("\n" + ("ALL CHECKS PASSED" if not FAIL else "FAILURES: " + ", ".join(FAIL)))
    sys.exit(1 if FAIL else 0)
