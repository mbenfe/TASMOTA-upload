import collections
import hashlib
import json
import pathlib
import re

BASE = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).parent
results = {}
for path in sorted((BASE / 'config').glob('power_*.json')):
    if path.stem == 'power_shared_villes':
        continue  # Site/device sharing index, not a channel topology.
    issues = []
    def pairs(items):
        d = {}
        for k, v in items:
            if k in d:
                issues.append(f'Duplicate JSON key: {k}')
            d[k] = v
        return d
    data = json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=pairs)
    nodes = {}
    for device, definition in data.items():
        if 'channel' in definition and 'channels' in definition:
            issues.append(f'Ambiguous channel/channels: {device}')
        channels = definition.get('channels', [definition['channel']] if 'channel' in definition else [])
        for ch in channels:
            name = ch.get('name')
            if not name or name == '*':
                continue
            if name in nodes:
                issues.append(f'Duplicate node: {name}')
            nodes[name] = dict(ch, owner=device, product=definition.get('produit'))
    children = collections.defaultdict(list)
    for name, ch in nodes.items():
        parent = ch.get('parent') or None
        if parent == '*':
            issues.append(f'Real node has placeholder parent: {name}')
            parent = None
        ch['resolved_parent'] = parent
        children[parent].append(name)
        if parent and parent not in nodes:
            issues.append(f'Missing parent: {name} -> {parent}')
    for name, ch in nodes.items():
        chain = []
        current = name
        while current in nodes:
            if current in chain:
                issues.append(f'Cycle from {name}: {chain}')
                break
            chain.append(current)
            current = nodes[current]['resolved_parent']
        expected = 'root' if ch['resolved_parent'] is None else ('node' if children[name] else 'leaf')
        if ch.get('genre') != expected:
            issues.append(f'Role requires review: {name}: genre={ch.get("genre")}, graph={expected}')
        if 'children' in ch:
            if collections.Counter(ch['children']) != collections.Counter(children[name]):
                issues.append(f'Explicit children disagree with parent links: {name}: declared={ch["children"]}, linked={children[name]}')
    roots = children[None]
    if len(roots) != 1:
        issues.append(f'Multiple/no roots: {roots}')
    site = path.stem.removeprefix('power_')
    tree = BASE / 'config' / 'trees' / f'tree_{site}.md'
    differences, formatting = [], []
    entries = {}
    if tree.exists():
        content = tree.read_text(encoding='utf-8-sig')
        if content.splitlines().count('```text') != 1 or content.splitlines().count('```') != 1:
            formatting.append('Invalid code fences; expected ```text and ```')
        stack = []
        order = collections.defaultdict(list)
        for line_no, line in enumerate(content.splitlines(), 1):
            if not line.strip() or line.startswith('#') or line.startswith('`'):
                continue
            match = re.fullmatch(r'([ │]*)(?:[├└]── )?(.+?)\s+\[([^\]]+)\]\s*', line)
            if not match:
                formatting.append(f'Unparsed line {line_no}: {line}')
                continue
            prefix, label, owner = match.groups()
            branch = '── ' in line
            depth = len(prefix) // 4 + int(branch)
            if len(prefix) % 4 or depth > len(stack):
                formatting.append(f'Invalid indentation at line {line_no}')
            role_match = re.search(r'\s+\((root|node|virtual)\)$', label)
            role = role_match.group(1) if role_match else 'leaf'
            name = label[:role_match.start()].strip() if role_match else label.strip()
            parent = stack[depth-1] if depth and depth <= len(stack) else None
            stack[depth:] = [name]
            order[parent].append(name)
            if name in entries:
                differences.append(f'Duplicate tree node: {name} (line {line_no})')
            entries[name] = dict(parent=parent, owner=owner, role=role, line=line_no)
        for parent, names in order.items():
            if names != sorted(names):
                formatting.append(f'Siblings not lexicographically sorted under {parent or "<roots>"}')
        for name in sorted(nodes.keys() - entries.keys()):
            differences.append(f'Missing tree node: {name} [{nodes[name]["owner"]}], parent={nodes[name]["resolved_parent"]}')
        for name in sorted(entries.keys() - nodes.keys()):
            differences.append(f'Extra tree node: {name}, line {entries[name]["line"]}')
        for name in sorted(nodes.keys() & entries.keys()):
            ch, entry = nodes[name], entries[name]
            for key, expected in [('parent', ch['resolved_parent']), ('owner', ch['owner'])]:
                if entry[key] != expected:
                    differences.append(f'{name} line {entry["line"]}: {key} tree={entry[key]!r}, power={expected!r}')
            if entry['role'] == 'virtual' and ch['product'] == 'virtuel':
                formatting.append(f'{name}: (virtual) identifies product but omits graph role ({ch.get("genre")})')
            elif entry['role'] != ch.get('genre'):
                differences.append(f'{name} line {entry["line"]}: role tree={entry["role"]}, power={ch.get("genre")}')
    else:
        differences.append('Missing tree file')
    results[site] = dict(nodes=len(nodes), tree_nodes=len(entries), roots=roots, power_issues=issues,
                         differences=differences, formatting=formatting,
                         power_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                         tree_sha256=hashlib.sha256(tree.read_bytes()).hexdigest() if tree.exists() else None)
extra = [p.name for p in sorted((BASE/'config/trees').glob('tree_*.md')) if p.stem.removeprefix('tree_') not in results]
(OUT/'results.json').write_text(json.dumps(dict(sites=results, unmatched_trees=extra), indent=2), encoding='utf-8')
lines = ['# Power/tree consistency audit', '', 'Saved files only. No configuration or tree files changed.',
         'power_shared_villes.json is a sharing index, excluded from topology comparison.', '',
         '| Site | Power/tree nodes | Power issues | Tree differences | Presentation issues |',
         '| --- | --- | --- | --- | --- |']
for site, r in results.items():
    lines.append(f'| {site} | {r["nodes"]}/{r["tree_nodes"]} | {len(r["power_issues"])} | {len(r["differences"])} | {len(r["formatting"])} |')
for site,r in results.items():
    lines += ['', f'## {site}', '', f'Roots: {", ".join(r["roots"])}']
    for label,key in [('Power topology', 'power_issues'), ('Tree differences', 'differences'), ('Presentation', 'formatting')]:
        if r[key]:
            lines += ['', f'{label}:', ''] + [f'- {x}' for x in r[key]]
lines += ['', '## Unmatched trees', ''] + [f'- {x}: no matching power JSON; cannot validate.' for x in extra]
(OUT/'report.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
print(json.dumps(dict(sites=results, unmatched_trees=extra), indent=2))
