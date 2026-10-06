import json,re,copy,tempfile
from pathlib import Path
src=Path('D:/Programming/embedded/STM32/Groupe SNX/auto_bezons/Core/Src/generated_registers.cpp').read_text()
block=src.split('static config_froid_kv kConfigFroidData[] = {')[1].split('\n};')[0]
rows=re.findall(r'\{(\d+), \{"([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)", "([^"]+)", (\d+),',block)
a={int(i):dict(genre=g,name=n,device=d,brand=b,model=m,volume=int(v)) for i,g,n,d,b,m,v in rows}
paths={k:Path('config/'+k+'_bezons.json') for k in ['f','mobile','web']}
old={k:json.loads(p.read_text(encoding='utf-8-sig')) for k,p in paths.items()};new=copy.deepcopy(old)
backup=Path(tempfile.mkdtemp(prefix='bezons-config-before-'))
for k,p in paths.items(): (backup/p.name).write_bytes(p.read_bytes())
new['f']={str(i):{**copy.deepcopy(old['f'].get(str(i),old['f']['9'])),**r} for i,r in a.items()}
# Match unchanged equipment IDs and genres first, then reuse vacant slots of the correct type.
slots=old['web']['applications'][0]['data']['Froid'];used=set();assigned={}
for i,r in a.items():
 match=next((j for j,s in enumerate(slots) if s['id']==i and s['genre']==r['genre']),None)
 if match is not None: assigned[i]=match;used.add(match)
for i,r in a.items():
 if i not in assigned:
  match=next(j for j,s in enumerate(slots) if j not in used and s['genre']==r['genre'])
  assigned[i]=match;used.add(match)
widgets=[]
for i,r in a.items():
 s=copy.deepcopy(slots[assigned[i]])
 s.update(id=i,master=r['name'],genre=r['genre'],details='details_'+r['name'],label=r['name'])
 widgets.append(s)
new['web']['applications'][0]['data']['Froid']=widgets
apps=new['mobile']['applications'];neg=next(x for x in apps if x['type']=='iFroidNegatif');pos=next(x for x in apps if x['type']=='iFroidPositif')
equipment={d['master']:d for app in [neg,pos] for d in app['data'] if d['master'] in {r['name'] for r in a.values()}}
for app,sign in [(neg,'-'),(pos,'+')]:
 summary=next(d for d in app['data'] if d['shape']=='iFroidSummary');summary.update(row=1,column=1)
 data=[summary];row=2
 for genre,columns in [('CF'+sign,2),('vitrine'+sign,4)]:
  banner=copy.deepcopy(next(d for d in app['data'] if d['shape']=='banner' and d['values'][0]=='cout_'+genre.lower()))
  banner.update(row=row,column=1);data.append(banner);row+=1
  group=[r for r in a.values() if r['genre']==genre]
  for index,r in enumerate(group):
   d=copy.deepcopy(equipment[r['name']]);d.update(shape=genre.upper(),master=r['name'],details='details_'+r['name'],row=row+index//columns,column=1+index%columns);data.append(d)
  row+=(len(group)+columns-1)//columns
 app['data']=data
# Coverage, case-sensitive bindings and mobile grid checks.
assert len(a)==32
assert set(new['f'])=={str(i) for i in a}
assert {d['master'] for d in widgets}=={r['name'] for r in a.values()}
for d in widgets:
 r=a[d['id']];assert d['master']==r['name'] and d['genre']==r['genre'] and d['details']=='details_'+r['name']
assert len({(d['column'],d['row']) for d in widgets})==32
for app,sign in [(neg,'-'),(pos,'+')]:
 for row in {d['row'] for d in app['data']}:
  cols=sorted(d['column'] for d in app['data'] if d['row']==row);assert cols==list(range(1,len(cols)+1))
 for d in app['data']:
  if d['master'] in equipment:
   r=next(r for r in a.values() if r['name']==d['master']);assert r['genre'].endswith(sign) and d['shape'].lower()==r['genre'].lower() and d['details']=='details_'+r['name']
assert new['web']['applications'][1:]==old['web']['applications'][1:]
assert new['web']['applications'][0]['data']['Meteo']==old['web']['applications'][0]['data']['Meteo']
for before,after in zip(old['mobile']['applications'],new['mobile']['applications']):
 if before['type'] not in ['iFroidNegatif','iFroidPositif']:assert before==after
assert new['mobile']['night']==old['mobile']['night']
for k,p in paths.items():
 text=json.dumps(new[k],ensure_ascii=False,indent=2) if k!='mobile' else json.dumps(new[k],ensure_ascii=False,separators=(',',':'))
 p.write_text(text+'\n',encoding='utf-8')
print('Validated 32 units across inventory, mobile and web. Unrelated sections unchanged.')
print('Backup:',backup)
print('Web reassigned slots:',[(i,slots[j]['id'],a[i]['genre']) for i,j in assigned.items() if i!=slots[j]['id']])
