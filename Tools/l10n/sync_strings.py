#!/usr/bin/env python3
"""Keeps Localizable.xcstrings in step with the code.

Collects every localizable key Xcode extracted in the last build (*.stringsdata in DerivedData), adds the
missing ones to the app / widget catalogs, applies Russian translations from a JSON file ({"en key": "ru"}),
and prints the keys that still have no Russian. Existing translations are kept.

    python3 Tools/l10n/sync_strings.py <DerivedData path> [translations.json]
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOGS = {
    'app': os.path.join(ROOT, 'Canopus/Resources/Localizable.xcstrings'),
    'widget': os.path.join(ROOT, 'CanopusWidget/Localizable.xcstrings'),
}


def extracted(dd):
    keys = {'app': [], 'widget': []}
    for f in sorted(glob.glob(f'{dd}/Build/Intermediates.noindex/Canopus.build/*/*/Objects-normal/arm64/*.stringsdata')):
        d = json.load(open(f))
        target = 'widget' if '/CanopusWidget' in d['source'] else 'app'
        for items in d.get('tables', {}).values():
            for it in items:
                if it['key'] not in keys[target]:
                    keys[target].append(it['key'])
    return keys


def main():
    dd = sys.argv[1]
    ru = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else {}
    keys = extracted(dd)
    for target, path in CATALOGS.items():
        cat = json.load(open(path)) if os.path.exists(path) else {'sourceLanguage': 'en', 'strings': {}, 'version': '1.0'}
        strings = cat['strings']
        for k in keys[target] + [k for k in ru if k in strings or target == 'app']:
            strings.setdefault(k, {})
        for k, entry in strings.items():
            if not any(c.isalpha() for c in k):
                entry.clear()
                entry['shouldTranslate'] = False
            elif k in ru and ru[k] != k:
                entry['localizations'] = {'ru': {'stringUnit': {'state': 'translated', 'value': ru[k]}}}
        missing = [k for k, e in strings.items() if 'localizations' not in e and e.get('shouldTranslate') is not False and k in keys[target]]
        json.dump(cat, open(path, 'w'), ensure_ascii=False, indent=2, sort_keys=True)
        print(f'{target}: {len(strings)} keys, without Russian: {len(missing)}')
        for k in missing:
            print('   ', repr(k))


if __name__ == '__main__':
    main()
