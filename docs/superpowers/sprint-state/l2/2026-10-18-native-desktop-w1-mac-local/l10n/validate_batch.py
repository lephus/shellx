# usage: python3 validate_batch.py NN  -> checks batch-NN.vi.json against batch-NN.en.json
import json,re,sys,os
D=os.path.dirname(os.path.abspath(__file__))
FMT=re.compile(r"%%|%(?:\d+\$)?#@[^@]+@|%(?:\d+\$)?[-+ #0']*(?:\d+|\*(?:\d+\$)?)?(?:\.(?:\d+|\*(?:\d+\$)?))?(?:hh|ll|[hlLqjzt])?[diouxXfFeEgGaAcCsSp@]")
def ph(s): return FMT.findall(s)
bad=0
for n in sys.argv[1:]:
    en=json.load(open(f"{D}/batch-{n}.en.json"))
    try: vi=json.load(open(f"{D}/batch-{n}.vi.json"))
    except Exception as e: print(n,"INVALID JSON",e); bad+=1; continue
    for u in en:
        k=str(u["i"]); v=vi.get(k)
        if not isinstance(v,str) or (not v.strip() and u["en"].strip()):
            print(n,k,"MISSING"); bad+=1; continue
        if ph(v)!=ph(u["en"]):
            print(n,k,"PLACEHOLDERS",ph(u["en"]),"vs",ph(v)); bad+=1
        if u["en"].count("\n")!=v.count("\n"):
            print(n,k,"NEWLINES differ"); bad+=1
    extra=set(vi)-{str(u["i"]) for u in en}
    if extra: print(n,"EXTRA keys",sorted(extra)[:5]); bad+=1
print("OK" if bad==0 else f"{bad} problems")
sys.exit(1 if bad else 0)
