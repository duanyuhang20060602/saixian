import run_key2_tf as t
t.WORK=t.ROOT/'validation/key2_tf_20261010/preload_crc'
t.WORK.mkdir(parents=True,exist_ok=True)
folder=t.fixture()
t.run('tb_preload_crc',[t.ROOT/'tests/tb_preload_crc.v',t.HDL/'saixian_tf_preload.v',
 t.HDL/'delta_decoder.v',t.HDL/'delta_player.v',t.HDL/'delta_memory.v',t.HDL/'delta_loader.v',
 t.HDL/'delta_video.v',t.HDL/'delta_read_capture.v',t.HDL/'SD/frame_read_write.v',
 t.HDL/'SD/frame_fifo_read.v',t.HDL/'SD/frame_fifo_write.v',t.HDL/'saixian_shared_video_fifo.v',
 t.HDL/'IP/afifo_16_32_256.v'],
 args=[f'+package={(folder/"package_words.hex").as_posix()}',f'+folder={folder.as_posix()}','+package_words=1024'])
