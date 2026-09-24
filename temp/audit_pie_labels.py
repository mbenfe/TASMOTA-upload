import collections
import json
import re
from pathlib import Path

base = Path('config')
report = []
total_web = 0
mobile_count = 0
mobile_bad = 0
decoder = json.JSONDecoder()

def mobile_pies(obj):
    found = []
    if isinstance(obj, dict):
        if str(obj.get('shape', '')).lower() == 'pieconso':
            found.append(obj)
        for v in obj.values():
            found.extend(mobile_pies(v))
    elif isinstance(obj, list):
        for v in obj:
            found.extend(mobile_pies(v))
    return found

for path in sorted(base.glob('mobile_*.json')):
    site = path.stem.removeprefix('mobile_')
    pies = mobile_pies(json.loads(path.read_text(encoding='utf-8-sig')))
    power_path = base / f'power_{site}.json'
    children = collections.defaultdict(list)
    if power_path.exists():
        for entry in json.loads(power_path.read_text(encoding='utf-8-sig')).values():
            for n in entry.get('channels', [entry['channel']] if 'channel' in entry else []):
                if n.get('name') not in (None, '', '*'):
                    children[n.get('parent')].append(n['name'])
    for pie in pies:
        mobile_count += 1
        labels = pie.get('labels', pie.get('label', []))
        slaves = pie.get('slave', [])
        issues = []
        if not isinstance(labels, list) or len(labels) != len(slaves)+1:
            mobile_bad += 1
            issues.append(f'label count {len(labels)}; expected {len(slaves)+1} (master + slaves)')
        elif any(not isinstance(s, str) or not s.strip() for s in labels):
            mobile_bad += 1
            issues.append('empty or invalid label')
        if power_path.exists() and set(slaves) != set(children[pie['master']]):
            issues.append('tree mismatch: missing ' + repr(sorted(set(children[pie['master']])-set(slaves))) + '; extra ' + repr(sorted(set(slaves)-set(children[pie['master']]))))
        if issues:
            report.append(f'- {path.name}, `{pie["master"]}`: ' + '; '.join(issues))

for path in sorted(base.glob('web_*.json')):
    original = path.read_text(encoding='utf-8-sig')
    web = json.loads(original)
    site = path.stem.removeprefix('web_')
    apps = [a for a in web['applications'] if a.get('type') == 'iConsommation']
    names = {}
    mp = base / f'mobile_{site}.json'
    if mp.exists():
        for pie in mobile_pies(json.loads(mp.read_text(encoding='utf-8-sig'))):
            labels = pie.get('labels', pie.get('label', []))
            slaves = pie.get('slave', [])
            if isinstance(labels, list) and len(labels) in (len(slaves), len(slaves)+1):
                child_labels = labels
                if len(labels) == len(slaves)+1:
                    names.setdefault(pie['master'], labels[0])
                    child_labels = labels[1:]
                else:
                    names.setdefault(pie['master'], pie.get('location') or pie['master'])
                for name, label in zip(slaves, child_labels):
                    if isinstance(label, str) and label.strip():
                        names.setdefault(name, label)
    for app in apps:
        for kind in ('ConsoBar', 'PieChart'):
            for widget in app.get('data', {}).get(kind, []):
                names.setdefault(widget['master'], widget.get('location') or widget['master'])
    edits = []
    for match in re.finditer(r'\{', original):
        start = match.start()
        try:
            obj, end = decoder.raw_decode(original, start)
        except ValueError:
            continue
        if not isinstance(obj, dict) or obj.get('type') != 'iConsommation':
            continue
        for pie in obj.get('data', {}).get('PieChart', []):
            total_web += 1
            ids = [pie['master']] + pie['slave']
            pie['label'] = [names.get(name) or name for name in ids]
            pie.pop('labels', None)
            assert len(pie['label']) == len(pie['slave'])+1
        edits.append((start, end, json.dumps(obj, ensure_ascii=False, indent=2)))
    updated = original
    for start, end, replacement in reversed(edits):
        updated = updated[:start] + replacement + updated[end:]
    after = json.loads(updated)
    # Only label / labels keys on web pies may change.
    for doc in (web, after):
        for app in doc['applications']:
            if app.get('type') == 'iConsommation':
                for pie in app.get('data', {}).get('PieChart', []):
                    pie.pop('label', None)
                    pie.pop('labels', None)
    assert web == after
    path.write_text(updated, encoding='utf-8')

header = ['# Pie label audit', '',
          'Current Flutter mobile and web contract: label[0] is the master title; label[i+1] is slave[i].',
          'Names are matched by channel ID, using existing mobile labels when their alignment is unambiguous, then web locations, then the channel ID.',
          f'Web: {total_web} pies now have explicit label arrays. Mobile: {mobile_bad}/{mobile_count} pies have label alignment issues; mobile files were not changed.', '',
          '## Mobile findings', '']
Path('temp/pie_label_audit.md').write_text('\n'.join(header+report)+'\n', encoding='utf-8')
print(f'Web: {total_web} pies labeled. Mobile: {mobile_bad}/{mobile_count} label issues; {len(report)} pies with label or tree findings.')
