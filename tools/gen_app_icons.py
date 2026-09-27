"""Generate Android, Windows and Web app icons from one source image.

Usage: python tools/gen_app_icons.py [source-image]
Default source: assets/k_icon_clean.png
Requires Pillow (PIL).
"""
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / 'assets' / 'k_icon_clean.png'
PNG_TARGETS = {
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
}
ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def main() -> None:
    source = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.is_file():
        raise SystemExit(f'Source image not found: {source}')

    with Image.open(source) as opened:
        image = opened.convert('RGBA')
    width, height = image.size
    if width != height:
        side = min(width, height)
        left, top = (width - side) // 2, (height - side) // 2
        image = image.crop((left, top, left + side, top + side))

    for relative_path, size in PNG_TARGETS.items():
        target = ROOT / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(target)
        print(f'{size:>4}px -> {relative_path}')

    ico_path = ROOT / 'windows/runner/resources/app_icon.ico'
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(ico_path, format='ICO', sizes=ICO_SIZES)
    print(f'ICO -> {ico_path.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
