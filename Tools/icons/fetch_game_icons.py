#!/usr/bin/env python3
"""Downloads original EVE client icons into Canopus/Assets.xcassets/GameIcons, the way the desktop app
gets them: the client build from eveclient_TQ.json → its app index → resfileindex → resources CDN.

    python3 Tools/icons/fetch_game_icons.py win:skills win:wallet attr:164:res:/ui/texture/icons/22_32_1.png

`win:<name>` is res:/ui/texture/windowicons/<name>.png; `attr:<attributeID>:<res path>` is an attribute's
icon by the SDE iconID's resource path.
"""
import gzip
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'Canopus/Assets.xcassets/GameIcons')
UA = {'User-Agent': 'Canopus iOS build tool (https://github.com/GERCOG1390/Canopus)'}


def get(url):
    b = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
    return gzip.decompress(b) if b[:2] == b'\x1f\x8b' else b


def resource_index():
    build = json.loads(get('https://binaries.eveonline.com/eveclient_TQ.json'))['build']
    app = get(f'https://binaries.eveonline.com/eveonline_{build}.txt').decode()
    entry = next(l for l in app.splitlines() if l.startswith('app:/resfileindex.txt,'))
    res = get('https://binaries.eveonline.com/' + entry.split(',')[1]).decode()
    return {l.split(',')[0].lower(): l.split(',')[1] for l in res.splitlines() if l.startswith('res:/ui/texture/')}


def main():
    index = resource_index()
    for spec in sys.argv[1:]:
        kind, rest = spec.split(':', 1)
        if kind == 'win':
            name, res = f'win_{rest}', f'res:/ui/texture/windowicons/{rest}.png'
        else:
            attr, res = rest.split(':', 1)
            name = f'attr_{attr}'
        path = index.get(res.lower())
        if not path:
            print('not in the client:', res)
            continue
        folder = os.path.join(OUT, f'{name}.imageset')
        os.makedirs(folder, exist_ok=True)
        open(os.path.join(folder, f'{name}.png'), 'wb').write(get('https://resources.eveonline.com/' + path))
        json.dump({'images': [{'filename': f'{name}.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}},
                  open(os.path.join(folder, 'Contents.json'), 'w'))
        print('ok', name)


if __name__ == '__main__':
    main()
