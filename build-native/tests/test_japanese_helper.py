"""Exact legacy-vs-packaged output comparison on synthetic Japanese fixtures."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

helper=Path(sys.argv[1]).resolve()
legacy=Path(sys.argv[2]).resolve()
python=Path(sys.argv[3]).absolute() # Keep venv location; resolving its symlink discards site-packages.
dictionary=Path(sys.argv[4]).resolve()
root=Path(__file__).resolve().parents[2]
cases=[
    '日本の人口は減っています。働く人々が暮らす場所を考えています。',
    '肉そぼろは五分の一です。あなた自身がニンジン一本を用意します。',
    '眠る場所を探しています。東京には三万人の若者がいます。',
    '皆さんこんにちは。今日は字幕と音声の時間を確認します。',
    '【見出し】日本のニュースです。**新しい仕事**を始めます。',
    'これは長い文章です。' * 18,
]
with tempfile.TemporaryDirectory(prefix='msm-japanese-equivalence-') as tmp:
    tmp=Path(tmp)
    fresh=dict(HOME=str(tmp/'new user'),PATH='/usr/bin:/bin:/usr/sbin:/sbin')
    subprocess.run([str(helper),'--self-test'],env=fresh,check=True,stdout=subprocess.DEVNULL)
    for i,text in enumerate(cases):
        script=tmp/'script.txt';script.write_text(text)
        clean=text.replace('【見出し】','').replace('*','')
        whisper=tmp/'whisper.srt'
        blocks=[]
        for n,char in enumerate(clean):
            start=n*0.18;end=start+0.18
            def tc(s):
                ms=round(s*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
            blocks.append(f'{n+1}\n{tc(start)} --> {tc(end)}\n{char}\n')
        whisper.write_text('\n'.join(blocks))
        expected=tmp/'legacy.srt';final=tmp/'legacy-abut.srt';actual=tmp/'packaged.srt'
        env=dict(os.environ,MECAB_DICDIR=str(dictionary))
        subprocess.run([str(python),str(legacy),str(whisper),str(script),str(expected)],env=env,check=True)
        subprocess.run([str(python),str(root/'engines/SRT_Refine/force_abut_srt.py'),'--in',str(expected),'--out',str(final)],check=True,stdout=subprocess.DEVNULL)
        subprocess.run([str(helper),str(whisper),str(script),str(actual)],env=fresh,check=True)
        assert final.read_bytes()==actual.read_bytes(),f'Japanese behavior changed: fixture {i}'
    print(f'✓ Packaged Japanese helper exactly matches legacy alignment/wrap/abut: {len(cases)} fixtures; fresh HOME/PATH')
