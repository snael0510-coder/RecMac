#!/usr/bin/env python3
"""Build localized link preview images from the site's wallpaper and logo motif."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
import math

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'docs' / 'assets'
FONTS = Path.home() / 'Library' / 'Fonts'
WALLPAPER = Image.open(ASSETS / 'wallpaper.jpg').convert('RGB')
SIZE = (1200, 630)
INK = '#1d1d1f'
RED = '#d70015'


def font(name, size):
    path = FONTS / f'Pretendard-{name}.otf'
    fallback = Path('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    return ImageFont.truetype(str(path if path.exists() else fallback), size)


def logo(draw, cx, cy, radius):
    for i in range(20):
        angle = -math.pi / 2 + i * 2 * math.pi / 20
        x = cx + math.cos(angle) * radius
        y = cy + math.sin(angle) * radius
        dot = 3.1 + (i % 5) * 0.3
        draw.ellipse((x-dot, y-dot, x+dot, y+dot), fill=INK)
    draw.ellipse((cx-11, cy-11, cx+11, cy+11), fill='#ff3b30')


def make(lang):
    image = Image.new('RGB', SIZE, '#ffffff')
    draw = ImageDraw.Draw(image)

    # A Mac desktop window uses the same wallpaper as the landing page.
    frame = (590, 75, 1155, 545)
    shadow = Image.new('RGBA', SIZE)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((frame[0]+8, frame[1]+14, frame[2]+8, frame[3]+14),
                                  radius=31, fill=(0, 30, 80, 48))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    image.paste(shadow, (0, 0), shadow)

    width = frame[2] - frame[0]
    height = frame[3] - frame[1]
    desktop = ImageOps.fit(WALLPAPER, (width, height-45), method=Image.Resampling.LANCZOS)
    window = Image.new('RGB', (width, height), '#e8edf3')
    window.paste(desktop, (0, 45))
    wd = ImageDraw.Draw(window)
    wd.rectangle((0, 0, width, 45), fill='#f8f9fb')
    for x, color in ((28, '#ff5f57'), (50, '#febc2e'), (72, '#28c840')):
        wd.ellipse((x-6, 17, x+6, 29), fill=color)
    mask = Image.new('L', (width, height))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width-1, height-1), radius=28, fill=255)
    image.paste(window, frame[:2], mask)

    draw = ImageDraw.Draw(image)
    logo(draw, 87, 83, 29)
    draw.text((137, 62), 'RecMac', font=font('SemiBold', 39), fill=INK)
    if lang == 'ko':
        draw.text((58, 206), '맥 내부 소리까지,', font=font('Light', 57), fill=INK)
        draw.text((58, 288), '클릭 한 번으로.', font=font('Bold', 60), fill=INK)
        draw.text((62, 455), '무료 화면 녹화 앱', font=font('Medium', 28), fill='#55555a')
        draw.text((62, 500), 'macOS 15 이상  ·  Apple 실리콘', font=font('Regular', 20), fill='#77777d')
    else:
        draw.text((58, 206), 'Record your Mac.', font=font('Light', 55), fill=INK)
        draw.text((58, 288), 'Sound included.', font=font('Bold', 57), fill=INK)
        draw.text((62, 455), 'Free screen recorder', font=font('Medium', 27), fill='#55555a')
        draw.text((62, 500), 'macOS 15+  ·  Apple silicon', font=font('Regular', 21), fill='#77777d')
    target = ASSETS / f'social-{lang}.jpg'
    image.save(target, 'JPEG', quality=90, optimize=True, progressive=True)
    print(target.relative_to(ROOT))


for language in ('en', 'ko'):
    make(language)
