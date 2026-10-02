import json,re,copy
from pathlib import Path
p=Path('temp/snx_field_audit.json');a=json.loads(p.read_text())
assert a['subscription_granted'] and not a['error']
rows=[];updated=0
for path in sorted(Path('config/produits').glob('produits_*.json')):
    city=path.stem.removeprefix('produits_');data=json.loads(path.read_text());before=copy.deepcopy(data)
    gateways=[r for r in a['records'] if r['tenant']=='inter' and r['city']==city and re.match(r'^snx(?:[-_]|$)',r['device']) and any(k in r['kinds'] for k in ('HEARTBEAT','LWT','INFO1'))]
    endpoints=[r for r in a['records'] if r['tenant']=='inter' and r['city']==city and re.fullmatch(r'snx-\d+',r['device'])]
    if gateways:
        data.setdefault('snx',{})
        for r in gateways:data['snx'].setdefault(r['device'],{})
        path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
        saved=json.loads(path.read_text());assert saved['pwx']==before['pwx'];assert all(v=={} for v in saved['snx'].values());updated+=1
    refs=[k for k in a['layouts'] if k in ('mobile_'+city+'.json','web_'+city+'.json')]
    status=', '.join(r['device']+': '+r.get('lwt','no LWT')+' (retained status)' for r in gateways) or 'not observed'
    live=sum(r['live']>0 for r in endpoints)
    rows.append(f"| {city} | {status} | {len(endpoints)} | {live} | {', '.join(refs) or '-'} |")
text=['# SNX city inventory audit','',f"Capture UTC: {a['checked_utc']}; 40 seconds. Read-only TLS MQTT subscriptions; no publication or command.",'','Gateway identities require SNX naming plus HEARTBEAT/LWT/INFO1 evidence. Numeric snx-N topics are downstream regulator endpoints, not additional gateways. Layout snx_config and snx_config_ND are logical configuration Names, not physical devices.','', '| City | Gateway identities / retained status | Numeric regulator topics | Topics with fresh traffic | Layout configuration references |','| --- | --- | ---: | ---: | --- |',*rows,'','Retained records can be stale. No fresh gateway heartbeat arrived in this window; fresh regulator messages establish topic traffic only, not direct physical-device publication. Aulnay and Bezons were retained Offline. Absence in this limited capture does not prove a city has no SNX.','', 'Egly snx-mbjc is an additional endpoint identity; its physical implementation is not established by MQTT. Egly also exposes 91 non-SNX-named refrigeration identities, kept out of the gateway inventory. Demo/invite aliases are excluded.','',f'Added gateway/endpoint names with empty objects to {updated} existing city product files. Preserved all PWX entries. Full metadata: temp/snx_field_audit.json.']
Path('config/produits/SNX_AUDIT.md').write_text('\n'.join(text)+'\n',encoding='utf-8')
print('UPDATED',updated);print('\n'.join(rows))