import_device eagle_s20.db -package EG4S20BG256
import_db PHOTO_BOARD_A_pr.db
clear_sdc -user
read_sdc ../user_source/constraints_source/BOARD_A_RECEIVER_timing.sdc
update_timing
report_timing_status -file PHOTO_BOARD_A_phy.ts
report_timing_summary -file PHOTO_BOARD_A_pr.timing
report_timing_exception -file PHOTO_BOARD_A_exception.timing
report_area -io_info -file PHOTO_BOARD_A_phy.area
export_db PHOTO_BOARD_A_pr.db
bitgen -bit PHOTO_BOARD_A.bit
