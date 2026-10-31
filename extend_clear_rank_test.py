from pathlib import Path
p=Path('5.0project/tests/tb_editable_rank_uart.v');s=p.read_text();needle=' $display("PASS editable rankings';idx=s.index(needle);s=s[:idx]+''' start_rank(2);score_send(0);end_line;
 if(rank_cache.lengths[2+rank_cache.banks[1]]!=0 || rank_cache.scores[2+rank_cache.banks[1]]!=16'h1230)$fatal(1,"empty-name update did not commit once");
 repeat(100)@(negedge ac);
 if(rank_cache.lengths[2+rank_cache.banks[1]]!=0 || rank_cache.scores[2+rank_cache.banks[1]]!=16'h1230)$fatal(1,"empty-name bank oscillated");
 check_rank(0);check_rank(7);
'''+s[idx:];p.write_text(s,newline='\n')
