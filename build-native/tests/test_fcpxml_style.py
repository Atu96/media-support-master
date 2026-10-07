#!/usr/bin/env python3
"""Regression test: style panel values must survive into exported FCPXML."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


def require(xml: str, fragment: str) -> None:
    if fragment not in xml:
        raise AssertionError(f"Missing FCPXML style fragment: {fragment}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_fcpxml_style.py CONVERTER")
    converter = Path(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="msm-fcpxml-test-") as temp:
        root = Path(temp)
        srt = root / "sample.srt"
        output = root / "sample.fcpxml"
        srt.write_text(
            # Dài hơn project Motion gốc (~10s): title vẫn phải giữ nội dung tới hết cue.
            "1\n00:00:00,000 --> 00:00:15,000\nMàu và nền\n",
            encoding="utf-8",
        )
        subprocess.run(
            [
                sys.executable,
                str(converter),
                str(srt),
                str(output),
                "--font-color",
                "1 0 0 1",
                "--outline-color",
                "0 1 0 0.8",
                "--outline-width",
                "5",
                "--shadow-color",
                "0 0 0 0.75",
                "--shadow-distance",
                "7",
                "--shadow-angle",
                "315",
                "--bg-color",
                "0 0 1 1",
                "--bg-opacity",
                "0.65",
                "--box-width-percent",
                "73",
                "--box-corner-radius",
                "11",
                "--fade-in-ms",
                "200",
                "--fade-out-ms",
                "300",
            ],
            check=True,
        )
        xml = output.read_text(encoding="utf-8")
        ET.parse(output)
        require(xml, 'fontColor="1 0 0 1"')
        require(xml, 'strokeColor="0 1 0 0.8"')
        require(xml, 'strokeWidth="-5"')
        require(xml, 'shadowColor="0 0 0 0.75"')
        require(xml, 'shadowOffset="7 315"')
        require(xml, 'key="9999/10003/10043/2/353/113/111" value="0 0 1 1"')
        require(xml, 'key="9999/10003/10043/2/353/113/141" value="0.6500"')
        require(xml, 'key="9999/10003/10043/1/100/105/1" value="0.8174"')
        require(xml, 'key="9999/10003/10043/2/353/144" value="11"')
        require(xml, '<fadeIn type="easeInOut" duration="1/5s"/>')
        require(xml, '<fadeOut type="easeInOut" duration="3/10s"/>')
        require(xml, 'key="9999/10000/2/101" value="0"')
        require(xml, 'key="9999/10000/2/102" value="0"')
        require(xml, 'key="9999/10003/12450/200" value="0"')
        require(xml, 'key="9999/10003/12450/201" value="0"')
        require(xml, 'duration="15s"')
        if 'key="9999/10000/2/101" value="0"' not in xml or \
           'key="9999/10000/2/102" value="0"' not in xml:
            raise AssertionError(
                "FCPXML must disable Final Cut Motion Build In/Out options."
            )

        no_fade = root / "no-fade.fcpxml"
        subprocess.run(
            [
                sys.executable,
                str(converter),
                str(srt),
                str(no_fade),
                "--fade-in-ms",
                "0",
                "--fade-out-ms",
                "0",
            ],
            check=True,
        )
        no_fade_xml = no_fade.read_text(encoding="utf-8")
        ET.parse(no_fade)
        if "<fadeIn " in no_fade_xml or "<fadeOut " in no_fade_xml:
            raise AssertionError("Fade off must not create any FCPXML fade animation.")
        require(no_fade_xml, 'key="9999/10003/12450/200" value="0"')
        require(no_fade_xml, 'key="9999/10003/12450/201" value="0"')
    print("✓ FCPXML style regression OK — màu, nền, viền, bóng, kích thước, bo góc và fade")


if __name__ == "__main__":
    main()
