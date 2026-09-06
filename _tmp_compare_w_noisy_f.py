import json
from pathlib import Path


def main() -> None:
    w_path = Path(r"d:\Programming\upload\config\w_noisy.json")
    f_path = Path(r"d:\Programming\upload\config\f_noisy.json")

    w = json.loads(w_path.read_text(encoding="utf-8-sig"))
    f = json.loads(f_path.read_text(encoding="utf-8-sig"))

    iplan = next(a for a in w["applications"] if a.get("type") == "iPlan")
    w_froid = [x for x in iplan["data"] if isinstance(x, dict) and x.get("shape") == "Froid"]

    f_by_id = {}
    f_by_name = {}
    for k, v in f.items():
        if isinstance(v, dict) and "name" in v:
            f_by_id[str(k)] = v
            f_by_name[v["name"]] = v

    w_names = [x.get("master", "") for x in w_froid]
    f_names = sorted(f_by_name.keys())

    missing = sorted([n for n in f_names if n not in w_names])
    extra = sorted(set([n for n in w_names if n and n not in f_by_name]))

    id_mismatch = []
    for x in w_froid:
        kid = str(x.get("id"))
        if kid in f_by_id:
            c = f_by_id[kid]
            if x.get("master") != c.get("name") or x.get("genre") != c.get("genre"):
                id_mismatch.append(
                    {
                        "id": x.get("id"),
                        "w_master": x.get("master"),
                        "f_name": c.get("name"),
                        "w_genre": x.get("genre"),
                        "f_genre": c.get("genre"),
                    }
                )

    print("W_FROID_COUNT", len(w_froid))
    print("F_CANON_COUNT", len(f_by_name))
    print("MISSING_COUNT", len(missing))
    for n in missing:
        print("MISSING", n)
    print("EXTRA_COUNT", len(extra))
    for n in extra:
        print("EXTRA", n)
    print("ID_MISMATCH_COUNT", len(id_mismatch))
    for m in id_mismatch:
        print(
            "ID_MISMATCH",
            m["id"],
            m["w_master"],
            "=>",
            m["f_name"],
            "|",
            m["w_genre"],
            "=>",
            m["f_genre"],
        )


if __name__ == "__main__":
    main()
import json
from pathlib import Path

w_path = Path(r'd:\Programming\upload\config\w_noisy.json')
f_path = Path(r'd:\Programming\upload\config\f_noisy.json')

w = json.loads(w_path.read_text(encoding='utf-8-sig'))
f = json.loads(f_path.read_text(encoding='utf-8-sig'))

iplan = next(a for a in w['applications'] if a.get('type') == 'iPlan')
w_froid = [x for x in iplan['data'] if isinstance(x, dict) and x.get('shape') == 'Froid']

f_by_id = {}
f_by_name = {}
for k, v in f.items():
    if isinstance(v, dict) and 'name' in v:
        f_by_id[str(k)] = v
        f_by_name[v['name']] = v

w_names = [x.get('master', '') for x in w_froid]
f_names = sorted(f_by_name.keys())

missing = sorted([n for n in f_names if n not in w_names])
extra = sorted(set([n for n in w_names if n and n not in f_by_name]))

id_mismatch = []
for x in w_froid:
    kid = str(x.get('id'))
    if kid in f_by_id:
        c = f_by_id[kid]
        if x.get('master') != c.get('name') or x.get('genre') != c.get('genre'):
            id_mismatch.append({
                'id': x.get('id'),
                'w_master': x.get('master'),
                'f_name': c.get('name'),
                'w_genre': x.get('genre'),
                'f_genre': c.get('genre'),
            })

print('W_FROID_COUNT', len(w_froid))
print('F_CANON_COUNT', len(f_by_name))
print('MISSING_COUNT', len(missing))
for n in missing:
    print('MISSING', n)
print('EXTRA_COUNT', len(extra))
for n in extra:
    print('EXTRA', n)
print('ID_MISMATCH_COUNT', len(id_mismatch))
for m in id_mismatch:
    print('ID_MISMATCH', m['id'], m['w_master'], '=>', m['f_name'], '|', m['w_genre'], '=>', m['f_genre'])
