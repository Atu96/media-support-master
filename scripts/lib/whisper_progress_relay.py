#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Relay stdout/stderr whisper-cli → MSM_PROGRESS (stderr, unbuffered).

whisper.cpp --print-progress ghi ``progress = 42%`` bằng \\r (không \\n).
Đọc binary, emit % ngay khi đổi.

Quan trọng: in MSM_PROGRESS ra **stderr** — khi app bắt pipe, stderr
thường unbuffered (stdout shell hay bị dồn → % nhảy cuối / heartbeat giả).
"""
from __future__ import annotations

import re
import sys

PROG = re.compile(rb"progress\s*=\s*(\d+)\s*%", re.I)


def map_pct(raw: int) -> int:
    # Whisper 0…100 → [LOW, HIGH] (env tùy job: whisper mặc định 10–85; script-align 15–72).
    import os

    low = int(os.environ.get("MSM_PROG_LOW", "10"))
    high = int(os.environ.get("MSM_PROG_HIGH", "85"))
    if high <= low:
        low, high = 10, 85
    span = high - low
    return min(high, max(low, low + int(raw * span / 100)))


def emit_progress(mapped: int) -> None:
    # stderr + flush cứng — app đọc pipe stderr ngay.
    line = f"MSM_PROGRESS:{mapped}\n".encode("ascii")
    try:
        sys.stderr.buffer.write(line)
        sys.stderr.buffer.flush()
    except Exception:
        print(f"MSM_PROGRESS:{mapped}", file=sys.stderr, flush=True)


def main() -> int:
    stdin = sys.stdin.buffer
    last = -1
    buf = b""
    # Audio ngắn đôi khi chỉ in 0% rồi 100% — emit mốc trung gian khi thấy “đang chạy”.
    saw_any = False

    while True:
        chunk = stdin.read(256)
        if not chunk:
            break
        buf += chunk

        for m in PROG.finditer(buf):
            try:
                val = int(m.group(1))
            except ValueError:
                continue
            if 0 <= val <= 100 and val != last:
                # Nếu nhảy cót (0→100) trên file ngắn: chèn mốc giữa để UI không đứng.
                if last >= 0 and val - last >= 40:
                    mid = last + (val - last) // 2
                    if mid != last and mid != val:
                        emit_progress(map_pct(mid))
                last = val
                saw_any = True
                emit_progress(map_pct(val))

        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.replace(b"\r", b"")
            if not line.strip() or PROG.search(line):
                continue
            try:
                text = line.decode("utf-8", "replace")
            except Exception:
                continue
            low = text.lower()
            if low.startswith("ggml_") or low.startswith("whisper_"):
                continue
            if "system_info:" in low or ("metal" in low and "ggml" in low):
                continue
            if text.startswith("main:") and "processing" not in low:
                if not any(k in low for k in ("error", "failed", "done", "load", "model")):
                    continue
            # Một số build in “processing …” không kèm progress= — đẩy nhẹ %
            if "processing" in low and last < 20:
                last = 20
                saw_any = True
                emit_progress(map_pct(20))
            print(text, flush=True)

        if b"\r" in buf:
            parts = buf.split(b"\r")
            buf = parts[-1]

        if len(buf) > 65_536:
            buf = buf[-8192:]

    # EOF: bảo đảm có mốc cuối phase whisper nếu đã từng thấy progress
    if saw_any and last < 100:
        emit_progress(map_pct(min(100, max(last, 95))))
    elif not saw_any:
        # File cực ngắn / không print-progress — vẫn báo “gần xong phase whisper”
        emit_progress(map_pct(90))

    if buf.strip() and not PROG.search(buf):
        try:
            print(buf.replace(b"\r", b"").decode("utf-8", "replace"), flush=True)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
