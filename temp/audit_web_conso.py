import collections
import hashlib
import json
from pathlib import Path

BASE = Path('config')
results = {}
hashes = {}

def read(path, issues):
    hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                issues.append('Duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=pairs)

for path in sorted(BASE.glob('power_*.json')):
    site = path.stem.removeprefix('power_')
    power_issues, issues, geometry, review = [], [], [], []
    power = read(path, power_issues)
    nodes = {}
    children = collections.defaultdict(list)
    for device, entry in power.items():
        if not isinstance(entry, dict):
            power_issues.append('Unknown device schema: ' + device)
            continue
        if 'channel' in entry and 'channels' in entry:
            power_issues.append('Both channel and channels: ' + device)
        for channel in entry.get('channels', [entry['channel']] if 'channel' in entry else []):
            name = channel.get('name')
            if name in (None, '', '*'):
                continue
            if name in nodes:
                power_issues.append('Duplicate electrical node: ' + name)
            nodes[name] = channel
            children[channel.get('parent') or None].append(name)
    roots = sorted(children[None])
    for name, node in nodes.items():
        parent = node.get('parent')
        if parent and parent not in nodes:
            power_issues.append(f'{name}: unresolved parent {parent}')
        seen = set()
        current = name
        while current in nodes:
            if current in seen:
                power_issues.append('Cycle from ' + name)
                break
            seen.add(current)
            current = nodes[current].get('parent')
        role = 'root' if not parent else ('node' if children[name] else 'leaf')
        if node.get('genre') != role:
            power_issues.append(f'{name}: genre={node.get("genre")}, graph role={role}')
        if 'children' in node and collections.Counter(node['children']) != collections.Counter(children[name]):
            power_issues.append(name + ': declared children disagree with parent links')
    if len(roots) != 1:
        power_issues.append('Multiple/no roots: ' + ', '.join(roots))
    expected_pies = sorted(n for n in nodes if children[n])
    webpath = BASE / f'web_{site}.json'
    result = dict(expected_pies=len(expected_pies), expected_bars=len(nodes), roots=roots,
                  power_issues=power_issues, issues=issues, geometry=geometry, review=review,
                  current_pies=0, current_bars=0, web_exists=webpath.exists(), conso_tabs=0)
    results[site] = result
    if not webpath.exists():
        issues.append('Missing web layout')
        continue
    web = read(webpath, issues)
    apps = web.get('applications', [])
    if isinstance(apps, dict):
        apps = [apps]
    tabs = [(i,a) for i,a in enumerate(apps) if a.get('type')=='iConsommation']
    result['conso_tabs'] = len(tabs)
    if len(tabs)!=1:
        issues.append(f'Expected one iConsommation tab; found {len(tabs)}')
    for tab_index, app in tabs:
        data = app.get('data', {})
        if not isinstance(data, dict):
            issues.append('Conso data is not an object')
            continue
        pies, bars = data.get('PieChart', []), data.get('ConsoBar', [])
        result['current_pies'] += len(pies)
        result['current_bars'] += len(bars)
        for title, widgets, expected in [('PieChart', pies, expected_pies), ('ConsoBar', bars, nodes)]:
            masters = [w.get('master') for w in widgets]
            for name in sorted(set(expected)-set(masters)):
                issues.append(f'Missing {title}: {name}')
            for name,count in collections.Counter(masters).items():
                if count>1:
                    issues.append(f'Duplicate {title} master: {name} ({count} widgets)')
            ids = [w['id'] for w in widgets if 'id' in w]
            if len(ids)!=len(set(ids)):
                issues.append(f'Duplicate {title} ids')
        for index, w in enumerate(pies):
            name, slaves = w.get('master'), w.get('slave', [])
            at = f'PieChart[{index}] master={name}'
            if name not in nodes:
                if isinstance(name,str) and ':' in name:
                    review.append(at + ': composite master supported by widget; review against canonical aggregate')
                else:
                    issues.append(at + ': master absent from power')
            else:
                if not children[name]:
                    issues.append(at + ': no configured children')
                missing = sorted(set(children[name])-set(slaves))
                extra = sorted(set(slaves)-set(children[name]))
                if missing:
                    issues.append(at + ': missing direct children ' + ', '.join(missing))
                if extra:
                    issues.append(at + ': not direct children ' + ', '.join(extra))
                if not missing and not extra and slaves!=sorted(children[name]):
                    review.append(at + ': differs from alphabetical tree order')
            if len(slaves)!=len(set(slaves)):
                issues.append(at + ': duplicate slaves')
        for index,w in enumerate(bars):
            name, slaves = w.get('master'), w.get('slave', [])
            at = f'ConsoBar[{index}] master={name}'
            if name not in nodes:
                issues.append(at + ': master absent from power')
            if len(slaves)!=4:
                issues.append(at + f': expected comparison reference plus H/D/M (4 slaves), found {len(slaves)}')
            if slaves:
                reference = slaves[0]
                if reference not in nodes:
                    issues.append(at + ': comparison reference absent from power: ' + str(reference))
                elif len(roots)==1 and reference!=roots[0]:
                    review.append(at + ': comparison uses ' + reference + ' instead of site root ' + roots[0])
                elif len(roots)>1 and name in roots and reference!=name:
                    review.append(at + ': comparison crosses configured roots')
            wanted = [str(name)+suffix for suffix in ('_H','_D','_M')]
            if slaves[1:]!=wanted:
                issues.append(at + ': history references ' + repr(slaves[1:]) + '; expected ' + repr(wanted))
        widgets = [('PieChart',i,w) for i,w in enumerate(pies)] + [('ConsoBar',i,w) for i,w in enumerate(bars)]
        rects = []
        for kind,index,w in widgets:
            at = f'{kind}[{index}] {w.get("master")}'
            coords = [w.get(k) for k in ('column','row','width','height')]
            if not all(isinstance(v,(int,float)) for v in coords):
                review.append(at + ': explicit geometry incomplete; runtime defaults not audited')
                continue
            x,y,width,height = coords
            if width<=0 or height<=0 or x<0 or y<0:
                geometry.append(at + ': invalid geometry')
            if isinstance(app.get('width'),(int,float)) and x+width>app['width']:
                geometry.append(at + ': extends beyond declared canvas width')
            if isinstance(app.get('height'),(int,float)) and y+height>app['height']:
                geometry.append(at + ': extends beyond declared canvas height')
            for other,ox,oy,ow,oh,floor in rects:
                if floor==w.get('etage') and x<ox+ow and ox<x+width and y<oy+oh and oy<y+height:
                    geometry.append(at + ': rectangle overlaps ' + other)
            rects.append((at,x,y,width,height,w.get('etage')))
        if 'width' not in app or 'height' not in app:
            review.append('Canvas dimensions absent; runtime sizing not verified')

extra_web = [p.name for p in BASE.glob('web_*.json') if p.stem.removeprefix('web_') not in results]
for path,digest in hashes.items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest, 'File changed during audit: '+path
Path('temp/web_conso_audit.json').write_text(json.dumps({'sites':results,'unmatched_web':extra_web,'hashes':hashes},indent=2),encoding='utf-8')
lines = ['# Web Conso audit against power configurations', '',
         'Full-coverage rule: one pie per node with children, one ConsoBar per real electrical node, including virtual aggregates; ignore empty/* placeholders.',
         'ConsoBar contract checked against local Flutter web code: slave[0] is a comparison total; slave[1:4] are the master H/D/M history references.',
         'These are static configuration checks. Historical MQTT data availability, rendering, and semantic display-label accuracy are not verified. Geometry findings use explicit rectangles on the same etage; missing bounds are unverified. Alphabetical ordering is reported separately from membership errors.',
         'Current web PieChart uses label[0] for the master title and label[i+1] for slave[i]; label alignment is audited separately in pie_label_audit.md.', '',
         '| Site | Pies actual/expected | Bars actual/expected | Mapping issues | Geometry | Power issues |',
         '| --- | --- | --- | --- | --- | --- |']
for site,r in results.items():
    present=r['web_exists']
    lines.append(f'| {site} | {str(r["current_pies"])+"/"+str(r["expected_pies"]) if present else "No web"} | {str(r["current_bars"])+"/"+str(r["expected_bars"]) if present else "—"} | {len(r["issues"])} | {len(r["geometry"])} | {len(r["power_issues"])} |')
for site,r in results.items():
    lines += ['', '## '+site, '']
    for label,key in [('Power source', 'power_issues'),('Mapping/coverage','issues'),('Geometry','geometry'),('Review','review')]:
        if r[key]:
            lines += [label+':',''] + ['- '+x for x in r[key]] + ['']
    if not any(r[k] for k in ['power_issues','issues','geometry','review']):
        lines.append('All static checks passed.')
if extra_web:
    lines += ['', 'Web files without matching power reference: '+', '.join(extra_web)]
Path('temp/web_conso_audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
for site,r in results.items():
    print(site, 'web='+str(r['web_exists']),f'pies={r["current_pies"]}/{r["expected_pies"]}',f'bars={r["current_bars"]}/{r["expected_bars"]}',f'mapping={len(r["issues"])} geometry={len(r["geometry"])} power={len(r["power_issues"])}')
