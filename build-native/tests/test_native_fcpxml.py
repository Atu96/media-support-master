"""Compare native FCPXML against the established converter's actual output."""
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
from fractions import Fraction

root,converter=map(Path,sys.argv[1:])
def canonical(element):
    attrs=dict(element.attrib)
    if element.tag=='effect':attrs.pop('src',None) # Native resolver uses the actual installed template.
    for key in ('frameDuration','offset','duration','tcStart'):
        if key in attrs and attrs[key].endswith('s'):
            attrs[key]=str(Fraction(attrs[key][:-1]))+'s'
    text=element.text or ''
    if element.tag!='text-style':text=text.strip()
    return element.tag,sorted(attrs.items()),text,[canonical(x) for x in element]
count=0
for native in sorted(root.glob('*.fcpxml')):
    args=json.loads(native.with_suffix('.json').read_text())
    legacy=native.with_suffix('.legacy.xml')
    subprocess.run([sys.executable,str(converter),str(native.with_suffix('.srt')),str(legacy),*args],check=True,stdout=subprocess.DEVNULL)
    old=ET.parse(legacy).getroot();new=ET.parse(native).getroot()
    old.find('.//project').set('name','sample')
    assert canonical(old)==canonical(new),f'FCPXML contract changed: {native.name}'
    count+=1
assert count==21
print(f'✓ Native FCPXML matches established converter: {count} FPS/style/multilingual fixtures')
