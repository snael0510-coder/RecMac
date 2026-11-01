#!/usr/bin/env python3
"""Convert the approved Design Canvas layouts into static GitHub Pages HTML."""
from pathlib import Path
import hashlib
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / 'web-design'
DOCS = ROOT / 'docs'
KAKAO_URL = 'https://qr.kakaopay.com/FdctrGdJx1f401718'
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
    wallpaper_path = 'assets/wallpaper.jpg' if lang == 'en' else '../assets/wallpaper.jpg'
    canvas = canvas.replace('background: #141417; overflow: hidden;',
                            f'background: #082d84 url({wallpaper_path}) center / cover no-repeat; overflow: hidden;')
    canvas = canvas.replace('<div style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">',
                            '<div class="rm-demo-toolbar" style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">')
    canvas = canvas.replace('data-action="thanks"', 'data-action="thanks" target="_blank" rel="noopener"')
    canvas = canvas.replace('[SIZE]', '1 MB').replace('[VERSION]', 'v1.0')
    canvas = canvas.replace('Ko.dc.html', 'ko/').replace('Main.dc.html', '../')
    donation_label = '카카오페이로 후원' if lang == 'ko' else 'Support with Kakao Pay'
    donation_style = ('text-decoration:none;background:#1d1d1f;color:#ffffff;'
                      'padding:0 1.125rem;height:2.75rem;border-radius:999px;'
                      'font-size:.9375rem;font-weight:600;display:inline-flex;'
                      'align-items:center;justify-content:center')
    donation_link = (f'<a href="{KAKAO_URL}" target="_blank" rel="noopener noreferrer" '
                     f'style="{donation_style}">{donation_label}</a>')
    canvas, coffee_count = re.subn(
        r'<a href="https://buymeacoffee.com/\[YOUR-ID\]"[^>]*>.*?</a>',
        donation_link, canvas, flags=re.S)
    canvas, toss_count = re.subn(
        r'<a href="https://toss.me/\[TOSS-ID\]"[^>]*>.*?</a>',
        '', canvas, flags=re.S)
    assert coffee_count == 2 and toss_count == (2 if lang == 'ko' else 0)
    canvas = canvas.replace(
        'RecMac은 무료이고, 한 사람이 만들어요. 도움이 됐다면 커피 한 잔으로 응원해 주세요.',
        'RecMac은 무료이고, 한 사람이 만들어요. 도움이 됐다면 카카오페이로 응원해 주세요.')
    canvas = canvas.replace(
        'RecMac is free and made by one person. If it saves you time, a coffee keeps it going.',
        'RecMac is free and made by one person. If it saves you time, you can support it with Kakao Pay.')
    canvas = canvas.replace(
        'max-width: 26rem; box-sizing: border-box; padding: 2.25rem 2rem 1.75rem;',
        'max-width: 34rem; max-height: calc(100vh - 3rem); overflow-y: auto; box-sizing: border-box; padding: 2rem 2rem 1.75rem;')
    if lang == 'ko':
        canvas = canvas.replace('다운로드해 주셔서 고마워요!', '다운로드가 시작됐어요')
        canvas = canvas.replace('경고가 뜨면 시스템 설정 › 개인정보 보호 및 보안 › ‘그래도 열기’.',
                                '‘열 수 없음’ 경고에서 ‘완료’를 누른 뒤, 시스템 설정 › 개인정보 보호 및 보안 › ‘그래도 열기’.')
        warning = '처음 실행할 때 “RecMac을 열 수 없음” 경고가 나타날 수 있어요.'
        steps = ('<li><strong>1.</strong> 경고창에서 <strong>휴지통으로 이동</strong> 대신 <strong>완료</strong>를 누르세요.</li>'
                 '<li><strong>2.</strong> <strong>시스템 설정 → 개인정보 보호 및 보안</strong>을 열고 '
                 '<strong>그래도 열기</strong>를 누르세요.</li>')
        trust = '공식 GitHub 릴리스에서 받은 앱에만 이 단계를 진행하세요.'
        apple_url = 'https://support.apple.com/ko-kr/102445'
        apple_label = 'Apple 안내 보기'
    else:
        canvas = canvas.replace('Thanks for downloading!', 'Your download has started')
        canvas = canvas.replace('If warned, open System Settings › Privacy &amp; Security › Open Anyway.',
                                'If the warning appears, click Done, then System Settings › Privacy &amp; Security › Open Anyway.')
        warning = 'On first launch, macOS may say “RecMac Not Opened.”'
        steps = ('<li><strong>1.</strong> Click <strong>Done</strong>, not Move to Trash.</li>'
                 '<li><strong>2.</strong> Open <strong>System Settings → Privacy &amp; Security</strong> '
                 'and click <strong>Open Anyway</strong>.</li>')
        trust = 'Follow these steps only for the app from the official GitHub release.'
        apple_url = 'https://support.apple.com/en-us/102445'
        apple_label = 'Apple’s instructions'
    guide = (f'<div style="width:100%;text-align:left;background:#f5f5f7;border-radius:1rem;padding:1.1rem 1.25rem;box-sizing:border-box">'
             f'<p style="margin:0 0 .7rem;font-size:.9375rem;font-weight:600;line-height:1.45">{warning}</p>'
             f'<ol style="margin:0;padding:0;list-style:none;display:grid;gap:.5rem;font-size:.875rem;line-height:1.5">{steps}</ol>'
             f'<p style="margin:.85rem 0 0;font-size:.75rem;line-height:1.5;color:#6e6e73">{trust} '
             f'<a href="{apple_url}" target="_blank" rel="noopener noreferrer">{apple_label} ↗</a></p></div>'
             '<div style="width:100%;border-top:1px solid #e5e5ea;margin:.25rem 0 0"></div>')
    canvas, guide_count = re.subn(r'(<h2 id="thanks-title"[^>]*>.*?</h2>)',
                                  lambda m: m.group(1) + guide, canvas, count=1, flags=re.S)
    assert guide_count == 1
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
    script_path = 'site.js' if lang == 'en' else '../site.js'
    script_version = hashlib.sha256((DOCS / 'site.js').read_bytes()).hexdigest()[:8]
    script = f'{script_path}?v={script_version}'
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
