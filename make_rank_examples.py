from pathlib import Path
import importlib.util,json,zipfile
p=Path('5.0project/tools/send_serial_title.py');spec=importlib.util.spec_from_file_location('send',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
out=Path('rank-serial-examples');out.mkdir(exist_ok=True);rows=[]
for i,name,score in [(1,'张三','12.34'),(2,'李四','12.56'),(3,'王五','12.78'),(4,'赵六','13.02'),(5,'钱七','13.15'),(6,'孙八','13.30'),(7,'周九','13.44'),(8,'吴十','13.68')]:
 data=m.encode_line('rank'+str(i),name,score);(out/f'R{i}.bin').write_bytes(data);rows.append({'rank':i,'name':name,'score':score,'hex':data.hex(' ').upper()})
(out/'examples.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8');(out/'show-ranking.bin').write_bytes(bytes.fromhex('55 22 00 00 FF FF FF'))
print(rows[0]['hex'])
