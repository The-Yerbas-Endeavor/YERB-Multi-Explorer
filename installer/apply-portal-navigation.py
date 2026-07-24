#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/opt/yerb-multi-explorer')
layout = root / 'views' / 'layout.pug'
if not layout.exists():
    raise SystemExit(f'Missing layout: {layout}')

text = layout.read_text(encoding='utf-8')

stylesheet = "    link(rel='stylesheet', href='/css/portal-navigation.css')"
style_anchor = "    link(rel='stylesheet', href='/css/style.min.css' + (styleHash == null ? '' : '?h=' + styleHash))"
if stylesheet not in text:
    if style_anchor not in text:
        raise SystemExit('Unable to locate stylesheet anchor in views/layout.pug')
    text = text.replace(style_anchor, style_anchor + '\n' + stylesheet, 1)

text = text.replace('div.navbar.navbar-expand-lg(', 'div.navbar.navbar-expand-xl(', 1)

assets_block = """              li#assets.nav-item
                a.nav-link(href='https://assetsviewer.yerbas.org/', title='Browse Yerbas Assets')
                  span.fas.fa-layer-group
                  span.margin-left-5 Assets
"""
markets_anchor = "              if settings.markets_page.enabled == true\n"
if "li#assets.nav-item" not in text:
    if markets_anchor not in text:
        raise SystemExit('Unable to locate markets navigation anchor in views/layout.pug')
    text = text.replace(markets_anchor, assets_block + markets_anchor, 1)

layout.write_text(text, encoding='utf-8')
print(f'Updated {layout}')
