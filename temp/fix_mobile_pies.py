import copy
import json
import re
from pathlib import Path

base = Path('config')
backup = Path('temp/mobile_before_pie_fix')
backup.mkdir(exist_ok=True)
decoder = json.JSONDecoder()
changes = []
for path in sorted(base.glob('mobile_*.json')):
    site = path.stem.removeprefix('mobile_')
    power_path = base / f'power_{site}.json'
    web_path = base / f'web_{site}.json'
    if not power_path.exists():
        continue
    original = path.read_text(encoding='utf-8-sig')
    before = json.loads(original)
    web = json.loads(web_path.read_text(encoding='utf-8-sig'))
    web_pies = next(a for a in web['applications'] if a.get('type') == 'iConsommation')['data']['PieChart']
    edits = []
    for match in re.finditer(r'\{', original):
        try:
            app, end = decoder.raw_decode(original, match.start())
        except ValueError:
            continue
        if not isinstance(app, dict) or app.get('type') != 'iConso':
            continue
        old_widgets = app['data']
        assert isinstance(old_widgets, list)
        old_pies = {w['master']: w for w in old_widgets if w.get('shape') == 'PieConso'}
        pies = []
        for reference in web_pies:
            master = reference['master']
            pie = copy.deepcopy(old_pies.get(master, dict(shape='PieConso', color='TRANSPARENT', column=1, row=1)))
            pie.update(master=master, slave=reference['slave'], label=reference['label'], location=reference['label'][0])
            pie.pop('labels', None)
            pies.append(pie)
        # Keep all non-pie widgets and their relative order; insert the canonical
        # branch sequence where the first pie used to be.
        widgets = []
        inserted = False
        for widget in old_widgets:
            if widget.get('shape') == 'PieConso':
                if not inserted:
                    widgets.extend(pies)
                    inserted = True
            else:
                widgets.append(widget)
        if not inserted:
            widgets = pies + widgets
        for row, widget in enumerate(widgets, 1):
            widget['row'] = row
        app['data'] = widgets
        edits.append((match.start(), end, json.dumps(app, ensure_ascii=False, separators=(',', ':'))))
    assert len(edits) == 1, (path, 'Expected one Conso tab')
    updated = original
    for start, end, replacement in reversed(edits):
        updated = updated[:start]+replacement+updated[end:]
    after = json.loads(updated)
    def without_conso(doc):
        doc = copy.deepcopy(doc)
        doc['applications'] = [a for a in doc['applications'] if a.get('type') != 'iConso']
        return doc
    assert without_conso(before) == without_conso(after)
    def nonpies(doc):
        app = next(a for a in doc['applications'] if a.get('type') == 'iConso')
        result = copy.deepcopy([w for w in app['data'] if w.get('shape') != 'PieConso'])
        for w in result:
            w.pop('row', None)
        return result
    assert nonpies(before) == nonpies(after)
    if before != after:
        saved = backup / path.name
        if not saved.exists():
            saved.write_bytes(path.read_bytes())
        path.write_text(updated, encoding='utf-8')
        changes.append(path.name)
    print(f'{site}: {len(web_pies)} pies, labels synchronized by channel ID')
print('Files changed:', len(changes))
