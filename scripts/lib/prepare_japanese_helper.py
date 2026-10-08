"""Build-time package resolver. User installations never run this Python script."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,posixpath,shutil,stat,subprocess,sys,urllib.request,zipfile

root=Path(__file__).resolve().parents[2]
lock=json.loads((root/'assets/japanese/tools.lock.json').read_text())
base=root/'_work/japanese-tools';archive=base/'JapaneseTools.zip';package=base/'JapaneseTools'
base.mkdir(parents=True,exist_ok=True)
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(65536),b''):h.update(chunk)
 return h.hexdigest()
if not archive.exists() or digest(archive)!=lock['sha256']:
 stage=base/'archive.download'
 try:
  with urllib.request.urlopen(lock['url'],timeout=60) as response,stage.open('wb') as f:shutil.copyfileobj(response,f,65536)
  assert stage.stat().st_size==lock['bytes'] and digest(stage)==lock['sha256'],'Japanese package checksum mismatch'
  stage.replace(archive)
 finally:stage.unlink(missing_ok=True)
if not (package/'japanese-helper').is_file():
 with zipfile.ZipFile(archive) as z:
  for info in z.infolist():
   p=PurePosixPath(info.filename)
   assert not p.is_absolute() and '..' not in p.parts and p.parts[0]=='JapaneseTools'
   if stat.S_ISLNK(info.external_attr>>16):
    target=z.read(info).decode();joined=posixpath.normpath(posixpath.join(str(p.parent),target))
    assert not target.startswith('/') and joined.startswith('JapaneseTools/')
 subprocess.run(['/usr/bin/ditto','-x','-k',str(archive),str(base)],check=True)
manifest=json.loads((package/'FILES.json').read_text())
for item in manifest:
 p=package/item['path']
 assert p.is_file() and p.stat().st_size==item['bytes'] and digest(p)==item['sha256'],item['path']
subprocess.run([str(package/'japanese-helper'),'--self-test'],check=True,stdout=subprocess.DEVNULL)
print(package)
