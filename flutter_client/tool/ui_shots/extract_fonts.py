#!/usr/bin/env python3
"""Extract PingFang SC faces for the UI screenshot harness.

Usage: python3 tool/ui_shots/extract_fonts.py OUT_DIR   (requires `pip install fonttools`)
Then:  RDESK_SHOT_FONTS=OUT_DIR flutter test tool/ui_shots/shots_test.dart --update-goldens
The system collection has no Bold face; Semibold is re-tagged as 700/800 so bold
text does not fall back to the test font.
"""
import glob
import sys
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
source = next(iter(glob.glob('/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc')), None)
if source is None:
    sys.exit('PingFang.ttc not found; open a Chinese font once in Font Book to download it.')
collection = TTCollection(source)
for face in collection.fonts:
    name = face['name'].getDebugName(4) or ''
    weight = face['OS/2'].usWeightClass
    if name.startswith('PingFang SC') and weight in (300, 400, 500, 600):
        face.save(out / f'PingFangSC-{weight}.ttf')
for weight in (700, 800):
    bold = TTFont(out / 'PingFangSC-600.ttf')
    bold['OS/2'].usWeightClass = weight
    bold.save(out / f'PingFangSC-{weight}.ttf')
print(f'PingFang SC faces written to {out}')
