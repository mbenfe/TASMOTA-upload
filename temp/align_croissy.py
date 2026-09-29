import json,copy,pathlib
p=pathlib.Path('config/mobile_croissy.json'); w=pathlib.Path('config/web_croissy.json')
m=json.loads(p.read_text(encoding='utf-8')); before=copy.deepcopy(m)
backup=pathlib.Path('temp/croissy_alignment_before'); backup.mkdir(exist_ok=True)
for f in [p,w]: (backup/f.name).write_bytes(f.read_bytes())
pies=next(a['data'] for a in m['applications'] if a['type']=='iConso')
for pie in pies:
    pie['label']=['Froid positif total' if s=='v_froid_pos' else s for s in pie['label']]
    if pie['master']=='v_froid_pos': pie['location']='Froid positif total'
home=next(a for a in m['applications'] if a['type']=='Home')
cost=next(x for x in home['data'] if x['shape']=='iCoutsPareto')
cost['slave']=['c_ColonneA','c_ColonneB','c_fneg','c_v_froid_pos','c_gene_bureaux']
cost['location']='Total/Colonne A/Colonne B/Froid Negatif/Froid positif total/Bureaux'
night=next(a for a in m['night'] if a['type']=='iNightDay')
root=next(x for x in night['data'] if x['master']=='main_ND')
root['slave']=[x+'_ND' for x in ['ColonneA','ColonneB','fneg','v_froid_pos','gene_bureaux']]
v=copy.deepcopy(root); v.update(master='v_froid_pos_ND',slave=['fpos_ND','fpos2_ND'])
night['data'].insert(3,v)
for i,x in enumerate(night['data'],1): x['row']=i
setup=next(a for a in m['night'] if a['type']=='iSavingSetup')
v=copy.deepcopy(setup['data'][0]); v.update(master='virtuel_froid_pos',slave=['v_froid_pos'],color='YELLOW')
setup['data'].insert(10,v)
colors={'fpos':'YELLOW_LIGHT','fpos2':'YELLOW_LIGHT','gene_bureaux':'RED','onduleur':'RED_LIGHT','td_boulangerie':'RED_LIGHT'}
for i,x in enumerate(setup['data'],1):
    x['row']=i
    x['color']=colors.get(x['slave'][0],x['color'])
# Preserve unrelated applications byte-equivalent after JSON decoding.
for a,b in zip(before['applications'],m['applications']):
    if a['type'] not in ['Home','iConso']: assert a==b
p.write_text(json.dumps(m,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
# Preserve existing web formatting; replace only display-label array values.
s=w.read_text(encoding='utf-8')
s=s.replace('"Bureaux",\n          "v_froid_pos"','"Bureaux",\n          "Froid positif total"')
s=s.replace('"label": [\n          "v_froid_pos",','"label": [\n          "Froid positif total",')
old=json.loads(w.read_text(encoding='utf-8')); new=json.loads(s)
expected=copy.deepcopy(old)
for a in expected['applications']:
    if a['type']=='iConsommation':
        for pie in a['data']['PieChart']: pie['label']=['Froid positif total' if x=='v_froid_pos' else x for x in pie['label']]
assert new==expected
w.write_text(s,encoding='utf-8')
print('Updated mobile and web Croissy layouts; backups saved.')
