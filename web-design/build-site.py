#!/usr/bin/env python3
"""Convert the approved Design Canvas layouts into static GitHub Pages HTML."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / 'web-design'
DOCS = ROOT / 'docs'
DOCS.mkdir(exist_ok=True)
(DOCS / 'ko').mkdir(exist_ok=True)
shutil.copyfile(DESIGN / 'recmac-logo.svg', DOCS / 'logo.svg')

for lang, source, target in (
    ('en', DESIGN / 'landing-en.dc.html', DOCS / 'index.html'),
    ('ko', DESIGN / 'landing-ko.dc.html', DOCS / 'ko' / 'index.html'),
):
    page = source.read_text()
    title = re.search(r'<title>(.*?)</title>', page).group(1)
    canvas = page.split('<x-dc>', 1)[1].split('</x-dc>', 1)[0]
    helmet = re.search(r'<helmet>(.*?)</helmet>', canvas, re.S).group(1)
    canvas = re.sub(r'<helmet>.*?</helmet>', '', canvas, count=1, flags=re.S)
    canvas = re.sub(r'<sc-if value="\{\{\s*(\w+)\s*\}\}"[^>]*>',
                    lambda m: f'<div class="rm-if" data-if="{m.group(1)}">', canvas)
    canvas = canvas.replace('</sc-if>', '</div>')
    actions = {'onClick': 'data-action', 'onMouseEnter': 'data-mouseenter',
               'onMouseLeave': 'data-mouseleave', 'onFocus': 'data-focus'}
    for old, new in actions.items():
        canvas = re.sub(r'\b' + old + r'="\{\{\s*(\w+)\s*\}\}"',
                        lambda m: f'{new}="{m.group(1)}"', canvas)
    def bind_attribute(match):
        template = match.group(2).replace('{{', '[[').replace('}}', ']]')
        return f'data-bind-{match.group(1)}="{template}"'

    canvas = re.sub(r'\b(style|aria-pressed|fill|stroke|opacity)="([^"]*\{\{[^\"]+\}\}[^\"]*)"',
                    bind_attribute, canvas)
    canvas = re.sub(r'\{\{\s*(\w+)\s*\}\}',
                    lambda m: f'<span data-text="{m.group(1)}"></span>', canvas)
    assert '{{' not in canvas and 'sc-if' not in canvas
    canvas = canvas.replace('[ACCOUNT]', 'snael0510-coder')
    canvas = canvas.replace('<div style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">',
                            '<div class="rm-demo-toolbar" style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">')
    canvas = canvas.replace('data-action="thanks"', 'data-action="thanks" target="_blank" rel="noopener"')
    canvas = canvas.replace('[SIZE]', '1 MB').replace('[VERSION]', 'v1.0')
    canvas = canvas.replace('Ko.dc.html', 'ko/').replace('Main.dc.html', '../')
    canvas = canvas.replace('href="https://buymeacoffee.com/[YOUR-ID]"',
                            'hidden data-support="coffee" href="#"')
    canvas = canvas.replace('href="https://toss.me/[TOSS-ID]"',
                            'hidden data-support="toss" href="#"')
    canvas = canvas.replace('href="mailto:[YOUR EMAIL]"',
                            'hidden data-support="email" href="#"')
    assert '[YOUR-ID]' not in canvas and '[TOSS-ID]' not in canvas and '[YOUR EMAIL]' not in canvas
    if lang == 'ko':
        terminal_note = ('<details style="width:100%;max-width:44rem;text-align:left;color:#424245;font-size:.875rem;line-height:1.6">'
                         '<summary style="cursor:pointer">터미널 대안</summary>'
                         '<p>공식 릴리스에서 받은 앱을 응용 프로그램 폴더로 옮긴 뒤에도 열리지 않는 경우:</p>'
                         '<code style="display:block;overflow-x:auto;padding:.75rem 1rem;background:#f5f5f7;border-radius:.5rem;user-select:all">'
                         'xattr -dr com.apple.quarantine /Applications/RecMac.app</code></details>')
    else:
        terminal_note = ('<details style="width:100%;max-width:44rem;text-align:left;color:#424245;font-size:.875rem;line-height:1.6">'
                         '<summary style="cursor:pointer">Terminal alternative</summary>'
                         '<p>If the app from the official release still will not open after moving it to Applications:</p>'
                         '<code style="display:block;overflow-x:auto;padding:.75rem 1rem;background:#f5f5f7;border-radius:.5rem;user-select:all">'
                         'xattr -dr com.apple.quarantine /Applications/RecMac.app</code></details>')
    canvas = canvas.replace('</ol>', '</ol>\n' + terminal_note, 1)
    # Inline design keyframes stay intact, with the approved Pretendard CDN added.
    favicon = 'logo.svg' if lang == 'en' else '../logo.svg'
    script = 'site.js' if lang == 'en' else '../site.js'
    description = ('Record your Mac screen with system audio. Free for Apple silicon Macs.'
                   if lang == 'en' else '맥 내부 소리까지 함께 녹화하는 무료 macOS 앱. Apple 실리콘용.')
    head = (f'<!doctype html>\n<html lang="{lang}">\n<head>\n<meta charset="utf-8">\n'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f'<meta name="description" content="{description}">\n'
            f'<title>{title}</title>\n<link rel="icon" type="image/svg+xml" href="{favicon}">\n'
            '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">\n'
            + helmet.replace('<link rel="preconnect" href="https://fonts.googleapis.com">', '')
            + '\n<style>.rm-if{display:contents}.rm-if[hidden],[hidden]{display:none!important}'
              '@media(max-width:600px){.rm-demo-toolbar{transform:translateX(-50%) scale(.84)!important;transform-origin:bottom center}}</style>\n'
            '</head>\n<body>\n')
    target.write_text(head + canvas + f'\n<script src="{script}" defer></script>\n</body>\n</html>\n')
    print(target.relative_to(ROOT))
