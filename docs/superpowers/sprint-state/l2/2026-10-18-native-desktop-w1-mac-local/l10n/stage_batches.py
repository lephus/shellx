# Controller staging tool (not a repo file): export English units of macOS catalogs to translation batches.
import json,glob,os,sys
OUT=os.path.dirname(os.path.abspath(__file__))
paths=["Resources/Localizable.xcstrings","Resources/InfoPlist.xcstrings","Resources/ConfigPackErrors.xcstrings","TunnelExtension/InfoPlist.xcstrings"]+sorted(glob.glob("Packages/macOS/*/Sources/**/*.xcstrings",recursive=True))
units=[]
for p in paths:
    c=json.load(open(p))
    for k,v in c["strings"].items():
        if v.get("shouldTranslate") is False: continue
        en=v.get("localizations",{}).get("en")
        cm=v.get("comment","")
        if en is None:
            units.append((f"{p}::{k}::value",k,cm)); continue
        if "stringUnit" in en: units.append((f"{p}::{k}::value",en["stringUnit"]["value"],cm))
        pl=en.get("variations",{}).get("plural")
        if pl:
            src=pl.get("other") or pl.get("one")
            units.append((f"{p}::{k}::plural.other",src["stringUnit"]["value"],cm))
        for sn,sv in en.get("substitutions",{}).items():
            spl=sv.get("variations",{}).get("plural",{})
            src=spl.get("other") or spl.get("one")
            if src: units.append((f"{p}::{k}::sub.{sn}.other",src["stringUnit"]["value"],cm))
# dedupe by English text: translate each distinct English string once
by_en={}
for uid,en,cm in units:
    by_en.setdefault(en,{"en":en,"comment":cm,"ids":[]})["ids"].append(uid)
uniq=list(by_en.values())
json.dump({u["en"]:u["ids"] for u in uniq},open(os.path.join(OUT,"en-to-ids.json"),"w"),ensure_ascii=False)
N=int(sys.argv[1]) if len(sys.argv)>1 else 300
batches=[uniq[i:i+N] for i in range(0,len(uniq),N)]
for i,b in enumerate(batches):
    json.dump([{"i":j,"en":u["en"],"comment":u["comment"][:200]} for j,u in enumerate(b)],open(os.path.join(OUT,f"batch-{i:02d}.en.json"),"w"),ensure_ascii=False,indent=0)
print(len(units),"units",len(uniq),"unique",len(batches),"batches")
