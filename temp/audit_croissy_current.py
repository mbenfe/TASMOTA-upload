import json, pathlib, collections, hashlib
base=pathlib.Path('.')
out=base/'temp/croissy_audit_2026-09-29'
out.mkdir(parents=True,exist_ok=True)
# Reuse established topology/tree checker, restricted to Croissy and this report directory.
s=(base/'temp/power_tree_audit/check.py').read_text(encoding='utf-8')
s=s[:s.index('extra = [')]
s=s.replace("BASE = pathlib.Path(__file__).resolve().parents[2]", "BASE = pathlib.Path('.').resolve()")
s=s.replace("OUT = pathlib.Path(__file__).parent", "OUT = pathlib.Path('temp/croissy_audit_2026-09-29')")
s=s.replace("glob('power_*.json')", "glob('power_croissy.json')")
ctx={}; exec(s,ctx)
result={'tree':ctx['results']['croissy']}
nodes=ctx['nodes']; children=ctx['children']
def read(name):
    def pairs(items):
        d={}
        for k,v in items:
            assert k not in d, 'Duplicate key '+k
            d[k]=v
        return d
    return json.loads((base/'config'/name).read_text(encoding='utf-8-sig'),object_pairs_hook=pairs)
m=read('mobile_croissy.json'); w=read('web_croissy.json')
mp=[x for a in m['applications'] for x in (a['data'] if isinstance(a['data'],list) else [a['data']]) if x.get('shape')=='PieConso']
wa=next(a for a in w['applications'] if a['type']=='iConsommation'); wp=wa['data']['PieChart']; bars=wa['data']['ConsoBar']
expected={n for n in nodes if children[n]}
for kind,pies in [('mobile_pies',mp),('web_pies',wp)]:
    issues=[]
    assert collections.Counter(p['master'] for p in pies)==collections.Counter({n:1 for n in expected})
    for p in pies:
        assert collections.Counter(p['slave'])==collections.Counter(children[p['master']])
        assert len(p['label'])==len(p['slave'])+1
    result[kind]={'count':len(pies),'direct_children_and_labels':'PASS'}
assert {p['master']:(p['slave'],p['label']) for p in mp}=={p['master']:(p['slave'],p['label']) for p in wp}
result['cross_app_pie_parity']='PASS: exact masters, ordered slaves and labels'
assert collections.Counter(b['master'] for b in bars)==collections.Counter({n:1 for n in nodes})
for b in bars: assert b['slave']==['main']+[b['master']+s for s in ['_H','_D','_M']]
rects=[]
for x in wp+bars:
    cx,cy,ww,hh=[x[k] for k in ['column','row','width','height']]
    assert cx>=0 and cy>=0 and ww>0 and hh>0 and cx+ww<=wa['width'] and cy+hh<=wa['height']
    for xx,yy,www,hhh in rects: assert not(cx<xx+www and xx<cx+ww and cy<yy+hhh and yy<cy+hh)
    rects.append((cx,cy,ww,hh))
result['web_bars']={'count':len(bars),'coverage_history_geometry':'PASS'}
night=[x for a in m['night'] for x in a['data'] if x['shape']=='NighDayNodes']
cards=[x for a in m['night'] for x in a['data'] if x['shape']=='savingSetupCard']
result['night']={'count':len(night),'missing_groups':sorted(expected-{x['master'].removesuffix('_ND') for x in night}),'mismatches':[]}
for x in night:
    n=x['master'].removesuffix('_ND'); actual=[c.removesuffix('_ND') for c in x['slave']]
    if collections.Counter(actual)!=collections.Counter(children[n]): result['night']['mismatches'].append({'master':n,'actual':actual,'expected':children[n]})
result['settings']={'count':len(cards),'missing_channels':sorted(set(nodes)-{x['slave'][0] for x in cards})}
for x in cards: assert len(x['slave'])==1 and nodes[x['slave'][0]]['owner']==x['master']
result['settings']['existing_owners']='PASS'
result['hashes']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [base/'config'/n for n in ['power_croissy.json','mobile_croissy.json','web_croissy.json','trees/tree_croissy.md']]}
(out/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
