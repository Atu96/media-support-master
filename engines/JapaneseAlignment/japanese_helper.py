"""Packaged Japanese alignment entry point; no host Python/Tools lookup."""
from pathlib import Path
import os
import sys
import tempfile
import legacy_core

def run():
    base=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))
    dictionary=base/'dictionary'
    if not dictionary.is_dir():raise RuntimeError('Bundled UniDic dictionary missing')
    os.environ['MECAB_DICDIR']=str(dictionary)
    quoted=str(dictionary).replace('\\','\\\\').replace('"','\\"')
    legacy_core._MECAB_TAGGER=legacy_core.MeCab.Tagger(f'-r /dev/null -d "{quoted}"')
    if sys.argv[1:]==['--self-test']:
        tokens=legacy_core.tokenize_mecab('日本語の字幕を確認します。')
        assert ''.join(t['surface'] for t in tokens)=='日本語の字幕を確認します。'
        print('JAPANESE_HELPER_OK');return
    if len(sys.argv)!=4:raise SystemExit('usage: japanese-helper whisper.srt script.txt output.srt')
    output=Path(sys.argv[3])
    with tempfile.TemporaryDirectory(prefix='msm-japanese-') as tmp:
        intermediate=Path(tmp)/'aligned.srt'
        original=sys.argv[:]
        try:
            sys.argv=[original[0],original[1],original[2],str(intermediate)]
            legacy_core.main()
        finally:sys.argv=original
        # Exact repository force-abut operation: retain text, close cue ends.
        blocks=legacy_core.read_whisper_srt(str(intermediate))
        ordered=sorted(blocks,key=lambda b:(b['start'],b['end']))
        result=[]
        for i,cur in enumerate(ordered):
            end=ordered[i+1]['start'] if i+1<len(ordered) else cur['end']
            if end<=cur['start']:end=cur['start']+0.01
            result.append(dict(cur,end=end))
        for i in range(len(result)-1):
            cur,nxt=result[i],result[i+1]
            if abs(cur['end']-nxt['start'])<1e-9:continue
            end=nxt['start']
            if end<=cur['start']:
                end=cur['start']+0.01
                nxt['start']=end;nxt['end']=max(nxt['end'],end+0.01)
            cur['end']=end
        # Keep legacy wrap exactly; read_whisper_srt joins lines, so use the
        # repo SRT parser for final serialization rather than losing wraps.
        import re
        raw=intermediate.read_text()
        texts=[]
        for block in re.split(r'\n\s*\n',raw.strip()):
            lines=block.splitlines()
            if len(lines)>=3:texts.append('\n'.join(lines[2:]))
        payload=''.join(f"{i+1}\n{legacy_core.format_srt_time(b['start'])} --> {legacy_core.format_srt_time(b['end'])}\n{texts[i]}\n\n" for i,b in enumerate(result))
        output.write_text(payload,encoding='utf-8')

if __name__=='__main__':run()
