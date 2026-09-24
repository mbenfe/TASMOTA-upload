import collections
import copy
import json
import re
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--site', help='Update only this site')
args = parser.parse_args()
base = Path('config')
backup = Path('temp/web_conso_before_update')
backup.mkdir(exist_ok=True)
decoder = json.JSONDecoder()

def application_spans(text):
    match = re.search(r'"applications"\s*:\s*\[', text)
    assert match
    pos = match.end()
    spans = []
    while True:
        while text[pos].isspace() or text[pos] == ',':
            pos += 1
        if text[pos] == ']':
            return spans
        obj, end = decoder.raw_decode(text, pos)
        spans.append((pos, end, obj))
        pos = end

for power_path in sorted(base.glob('power_*.json')):
    site = power_path.stem.removeprefix('power_')
    if args.site and site != args.site:
        continue
    if site == 'egly':
        continue
    power = json.loads(power_path.read_text(encoding='utf-8-sig'))
    nodes = {}
    children = collections.defaultdict(list)
    for device in power.values():
        for node in device.get('channels', [device['channel']] if 'channel' in device else []):
            name = node.get('name')
            if name in (None, '', '*'):
                continue
            assert name not in nodes
            nodes[name] = node
            children[node.get('parent') or None].append(name)
    for names in children.values():
        names.sort()
    roots = children[None]
    order = []
    root_for = {}
    def walk(name, root):
        assert name not in root_for, 'Cycle or duplicate node'
        root_for[name] = root
        order.append(name)
        for child in children[name]:
            walk(child, root)
    for root in roots:
        walk(root, root)
    assert set(order) == set(nodes), 'Unresolved parents'
    path = base / f'web_{site}.json'
    original = path.read_text(encoding='utf-8-sig') if path.exists() else None
    if original is not None:
        saved = backup / path.name
        if not saved.exists():
            saved.write_bytes(path.read_bytes())
        web = json.loads(original)
        spans = [s for s in application_spans(original) if s[2].get('type') == 'iConsommation']
        assert len(spans) == 1
        start, end, old = spans[0]
        app = copy.deepcopy(old)
    else:
        web = {'applications': []}
        app = {'type': 'iConsommation', 'label': 'Conso', 'level': 1, 'virtuel': 0, 'data': {}}
    labels = {}
    for kind in ('ConsoBar', 'PieChart'):
        for widget in app.get('data', {}).get(kind, []):
            if widget.get('master') in nodes and widget.get('location'):
                labels.setdefault(widget['master'], widget['location'])
    def label(name):
        return labels.get(name, name)
    pies, bars = [], []
    def widget(name, index, x, y, size):
        return dict(id=index, location=label(name), column=x, row=y,
                    master=name, slave=[], color=0, etage=2 if site == 'aulnay' else 0, rotate=0,
                    width=size, height=size)
    y = 50
    seen_bars = set()
    for name in order:
        if not children[name] and name not in roots:
            continue
        if children[name]:
            pie = widget(name, len(pies)+1, 50, y, 1500)
            pie['slave'] = children[name]
            pie['label'] = [label(name)] + [label(child) for child in children[name]]
            pies.append(pie)
        band = ([name] if name in roots else []) + children[name]
        for index, child in enumerate(band):
            assert child not in seen_bars
            seen_bars.add(child)
            bar = widget(child, len(bars)+1, 1600+(index%3)*750, y+(index//3)*750, 700)
            bar['slave'] = [root_for[child]] + [child+suffix for suffix in ('_H', '_D', '_M')]
            bars.append(bar)
        y += max(1500, ((len(band)+2)//3)*750-50) + 50
    assert seen_bars == set(nodes)
    app.setdefault('data', {}).update(PieChart=pies, ConsoBar=bars)
    app.update(width=3850, height=y)
    if original is not None:
        updated = original[:start] + json.dumps(app, ensure_ascii=False, indent=2) + original[end:]
        before_other = [a for a in web['applications'] if a.get('type') != 'iConsommation']
        after_other = [a for a in json.loads(updated)['applications'] if a.get('type') != 'iConsommation']
        assert before_other == after_other
    else:
        updated = json.dumps({'applications': [app]}, ensure_ascii=False, indent=2) + '\n'
    path.write_text(updated, encoding='utf-8')
    print(f'{site}: {len(pies)} pies, {len(bars)} bars; ' + ('created' if original is None else 'updated'))
