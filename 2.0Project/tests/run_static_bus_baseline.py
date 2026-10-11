"""Expected failure: reproduce the released pre-fix photo-bus takeover."""
import run_key2_tf as t

t.WORK = t.ROOT / 'validation/key2_tf_20261010/static_fix_baseline'
t.WORK.mkdir(parents=True, exist_ok=True)
try:
    t.run('tb_static_bus_ownership', [t.ROOT / 'tests/tb_static_bus_ownership.v',
          t.HDL / 'SD/frame_fifo_read.v',
          t.ROOT / 'tests/reference/key2_tf/pre_fix_delta_memory.v'], defines=['PRE_FIX'])
except RuntimeError as exc:
    assert str(exc) == 'tb_static_bus_ownership failed', str(exc)
    log = (t.WORK / 'tb_static_bus_ownership.log').read_text(encoding='utf-8')
    assert 'TF stole an issued photo read' in log, log
    print('PASS pre-fix reproduction: expected photo read takeover detected')
else:
    raise AssertionError('Pre-fix RTL unexpectedly passed the ownership regression')
