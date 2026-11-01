#!/usr/bin/env python3
"""Convert the approved Design Canvas layouts into static GitHub Pages HTML."""
from pathlib import Path
import hashlib
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / 'web-design'
DOCS = ROOT / 'docs'
DOWNLOAD_URL = 'https://github.com/snael0510-coder/RecMac/releases/latest/download/RecMac.dmg'
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
    assert canvas.count('href="#download"') == 1
    canvas = canvas.replace('href="#download"', f'href="{DOWNLOAD_URL}" data-action="thanks"', 1)
    wallpaper_path = 'assets/wallpaper.jpg' if lang == 'en' else '../assets/wallpaper.jpg'
    canvas = canvas.replace('background: #141417; overflow: hidden;',
                            f'background: #082d84 url({wallpaper_path}) center / cover no-repeat; overflow: hidden;')
    canvas = canvas.replace('<div style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">',
                            '<div class="rm-demo-toolbar" style="position: absolute; left: 50%; bottom: 9%; transform: translateX(-50%)">')
    canvas = canvas.replace('data-action="thanks"', 'data-action="thanks" target="_blank" rel="noopener"')
    canvas = canvas.replace('[SIZE]', '1 MB').replace('[VERSION]', 'v1.0.1')
    canvas = canvas.replace('Ko.dc.html', 'ko/').replace('Main.dc.html', '../')
    assert canvas.count('data-action="sendHeart"') == 2
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
        alert_alt = 'RecMac을 열 수 없음 경고창과 완료 버튼'
        security_alt = '개인정보 보호 및 보안의 그래도 열기 버튼'
        alert_caption = '1 · 경고창에서 완료'
        security_caption = '2 · 설정에서 그래도 열기'
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
        alert_alt = 'RecMac Not Opened alert with the Done button'
        security_alt = 'Open Anyway button in Privacy and Security settings'
        alert_caption = '1 · Click Done'
        security_caption = '2 · Click Open Anyway'
    asset_prefix = 'assets/' if lang == 'en' else '../assets/'
    alert_image = f'{asset_prefix}gatekeeper-alert.jpg'
    security_image = f'{asset_prefix}privacy-security-open-anyway.jpg'
    guide_images = (
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,11rem),1fr));gap:.65rem;margin-top:.9rem">'
        f'<figure style="margin:0"><a href="{alert_image}" target="_blank" rel="noopener">'
        f'<img src="{alert_image}" alt="{alert_alt}" style="display:block;width:100%;height:9rem;object-fit:cover;object-position:center 58%;border-radius:.55rem;border:1px solid #dedee3;box-sizing:border-box"></a>'
        f'<figcaption style="margin-top:.35rem;font-size:.75rem;font-weight:600">{alert_caption}</figcaption></figure>'
        f'<figure style="margin:0"><a href="{security_image}" target="_blank" rel="noopener" style="display:block;height:9rem;overflow:hidden;border-radius:.55rem;border:1px solid #dedee3;box-sizing:border-box">'
        f'<img src="{security_image}" alt="{security_alt}" style="display:block;width:100%;height:100%;object-fit:cover;object-position:center 48%;transform:scale(2);transform-origin:85% 58%"></a>'
        f'<figcaption style="margin-top:.35rem;font-size:.75rem;font-weight:600">{security_caption}</figcaption></figure></div>'
    )
    guide = (f'<div style="width:100%;text-align:left;background:#f5f5f7;border-radius:1rem;padding:1.1rem 1.25rem;box-sizing:border-box">'
             f'<p style="margin:0 0 .7rem;font-size:.9375rem;font-weight:600;line-height:1.45">{warning}</p>'
             f'<ol style="margin:0;padding:0;list-style:none;display:grid;gap:.5rem;font-size:.875rem;line-height:1.5">{steps}</ol>'
             f'{guide_images}'
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
    page_url = 'https://snael0510-coder.github.io/RecMac/' + ('ko/' if lang == 'ko' else '')
    image_file = DOCS / 'assets' / f'social-{lang}.jpg'
    image_version = hashlib.sha256(image_file.read_bytes()).hexdigest()[:8]
    image_url = f'https://snael0510-coder.github.io/RecMac/assets/social-{lang}.jpg?v={image_version}'
    image_alt = ('RecMac — 맥 내부 소리까지, 클릭 한 번으로. 파란 macOS 화면.'
                 if lang == 'ko' else 'RecMac — Record your Mac. Sound included. Blue macOS desktop.')
    locale = 'ko_KR' if lang == 'ko' else 'en_US'
    alternate_locale = 'en_US' if lang == 'ko' else 'ko_KR'
    head = (f'<!doctype html>\n<html lang="{lang}">\n<head>\n<meta charset="utf-8">\n'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f'<meta name="description" content="{description}">\n'
            f'<link rel="canonical" href="{page_url}">\n'
            f'<meta property="og:type" content="website">\n'
            f'<meta property="og:site_name" content="RecMac">\n'
            f'<meta property="og:locale" content="{locale}">\n'
            f'<meta property="og:locale:alternate" content="{alternate_locale}">\n'
            f'<meta property="og:url" content="{page_url}">\n'
            f'<meta property="og:title" content="{title}">\n'
            f'<meta property="og:description" content="{description}">\n'
            f'<meta property="og:image" content="{image_url}">\n'
            f'<meta property="og:image:type" content="image/jpeg">\n'
            f'<meta property="og:image:width" content="1200">\n'
            f'<meta property="og:image:height" content="630">\n'
            f'<meta property="og:image:alt" content="{image_alt}">\n'
            f'<meta name="twitter:card" content="summary_large_image">\n'
            f'<meta name="twitter:title" content="{title}">\n'
            f'<meta name="twitter:description" content="{description}">\n'
            f'<meta name="twitter:image" content="{image_url}">\n'
            f'<title>{title}</title>\n<link rel="icon" type="image/svg+xml" href="{favicon}">\n'
            '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css">\n'
            + helmet.replace('<link rel="preconnect" href="https://fonts.googleapis.com">', '')
            + '\n<style>.rm-if{display:contents}.rm-if[hidden],[hidden]{display:none!important}'
              '@media(max-width:600px){.rm-demo-toolbar{transform:translateX(-50%) scale(.84)!important;transform-origin:bottom center}}</style>\n'
            '</head>\n<body>\n')
    target.write_text(head + canvas + f'\n<script src="{script}" defer></script>\n</body>\n</html>\n')
    print(target.relative_to(ROOT))
