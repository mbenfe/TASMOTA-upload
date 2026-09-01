import json
from pathlib import Path

base = Path('config')
updated = []
failed = []

for p in sorted(base.glob('m_*.json')):
    try:
        obj = json.loads(p.read_text(encoding='utf-8'))
    except Exception as exc:
        failed.append((str(p), f'load_error:{exc}'))
        continue

    changed = False
    for app in obj.get('applications', []):
        data = app.get('data')
        if not isinstance(data, list):
            continue

        for idx, item in enumerate(data):
            if not isinstance(item, dict):
                continue
            if item.get('shape') != 'OpenWeather':
                continue

            if any(isinstance(v, dict) and v.get('shape') == 'iPwxComp' for v in data[idx + 1:]):
                changed = False
                break

            insert = {
                'shape': 'iPwxComp',
                'color': 'TRANSPARENT',
                'column': 1,
                'row': 2,
                'location': '',
                'master': 'pwx_comp_nd',
                'slave': []
            }
            data.insert(idx + 1, insert)
            for later in data[idx + 2:]:
                if isinstance(later, dict) and isinstance(later.get('row'), int):
                    later['row'] += 1
            changed = True
            break

        if changed:
            break

    if changed:
        try:
            p.write_text(json.dumps(obj, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')
            updated.append(str(p))
        except Exception as exc:
            failed.append((str(p), f'write_error:{exc}'))

print('UPDATED', len(updated))
for path in updated:
    print(path)
print('FAILED', len(failed))
for path, msg in failed:
    print(f'{path}: {msg}')

# verification check
count = 0
for p in sorted(base.glob('m_*.json')):
    try:
        obj = json.loads(p.read_text(encoding='utf-8'))
    except Exception as exc:
        failed.append((str(p), f'verify_error:{exc}'))
        continue
    for app in obj.get('applications', []):
        data = app.get('data')
        if isinstance(data, list):
            count += sum(1 for v in data if isinstance(v, dict) and v.get('shape') == 'iPwxComp')
print('TOTAL_IPWXCOMP', count)
