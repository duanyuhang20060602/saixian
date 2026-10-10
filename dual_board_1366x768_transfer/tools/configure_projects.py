"""Set portable TD project metadata to this checkout's absolute paths."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parent.parent
for path in sorted((ROOT/'projects').glob('*/src/td_project/*.al')):
 text=path.read_text()
 text,count=re.subn(r'(<Project[^>]*\bPath=")[^"]*',r'\g<1>'+path.parent.as_posix(),text,count=1)
 if count!=1:raise ValueError(f'Project Path missing: {path}')
 path.write_text(text)
 print(path)
