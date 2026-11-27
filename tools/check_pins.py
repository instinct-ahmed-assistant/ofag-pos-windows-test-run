#!/usr/bin/env python3
# l181 PIN-GUARD (extended: EVERY 64-hex value in a workflow must equal the zip sha, the exe sha inside it, or the sha of the seed exe it names; inline $pinZip/$pinExe values are checked and fixed too). l179 PIN-GUARD: every workflow's -Zip / -ExpectZipSha / -ExpectExeSha must match the real zip and the exe inside it. Usage: check_pins.py ROOT [--fix]
import sys,os,re,glob,zipfile,hashlib
root=sys.argv[1];fix="--fix" in sys.argv;bad=0;n=0
def sha(b):return hashlib.sha256(b).hexdigest()
for wf in sorted(glob.glob(os.path.join(root,".github","workflows","*.yml"))):
    t=open(wf,encoding="utf-8").read()
    for m in re.finditer(r'-Zip\s+\./(\S+\.zip)',t):
        zp=os.path.join(root,m.group(1))
        if not os.path.exists(zp):print("FAIL",os.path.basename(wf),"zip not found",m.group(1));bad+=1;continue
        zb=open(zp,"rb").read();zs=sha(zb)
        z=zipfile.ZipFile(zp);ex=[x for x in z.namelist() if x.lower().endswith(".exe")]
        es=sha(z.read(ex[0])) if ex else ""
        if fix:
            t=re.sub(r'-ExpectZipSha\b.*?(?=\s-Expect(?:Seed|Snap)Sha\b|\s-SeedExe\b)',"-ExpectZipSha "+zs+" -ExpectExeSha "+es,t,count=1,flags=re.S)
            t=re.sub(r"(\$pin\w*Zip\w*\s*=\s*')[0-9a-f]{64}(')",lambda m:m.group(1)+zs+m.group(2),t);t=re.sub(r"(\$pin\w*Exe\w*\s*=\s*')[0-9a-f]{64}(')",lambda m:m.group(1)+es+m.group(2),t)
            for fl in ("Seed","Snap"):
                sd=re.search(r'-'+fl+r'Exe\s+\./(\S+)',t)
                if sd and os.path.exists(os.path.join(root,sd.group(1))):t=re.sub(r'(-Expect'+fl+r'Sha\s+)[0-9a-f]{64}',lambda m,sd=sd:m.group(1)+sha(open(os.path.join(root,sd.group(1)),"rb").read()),t)
            open(wf,"w",encoding="utf-8").write(t)
        if True:
            a=re.search(r'-ExpectZipSha[ ]+([0-9a-f]{64})\b',t);b=re.search(r'-ExpectExeSha[ ]+([0-9a-f]{64})\b',t)
            if not a or a.group(1)!=zs:print("FAIL",os.path.basename(wf),"ExpectZipSha",a.group(1) if a else None,"!= zip",zs);bad+=1
            if not b or b.group(1)!=es:print("FAIL",os.path.basename(wf),"ExpectExeSha",b.group(1) if b else None,"!= exe in zip",es);bad+=1
        allowed={zs,es}
        for fl in ("SeedExe","SnapExe"):
            sd=re.search(r'-'+fl+r'\s+\./(\S+)',t)
            if sd and os.path.exists(os.path.join(root,sd.group(1))):allowed.add(sha(open(os.path.join(root,sd.group(1)),"rb").read()))
        for h in sorted(set(re.findall(r'(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])',t))):
            if h.lower() not in allowed:print("FAIL",os.path.basename(wf),"64-hex value matches no real zip, exe or seed exe:",h);bad+=1
        n+=1
print("PIN-GUARD checked",n,"workflow zip pin(s):","FAIL" if bad else "PASS");sys.exit(1 if bad else 0)
