if {[catch {
 import_device eagle_s20.db -package EG4S20BG256
 import_db WATER_SINGLE_pr.db
 update_timing -mode final
 check_timing -verbose -file ../validation/timing_check.rpt
 report_timing_ignored -file ../validation/ignored.timing
} err]} {puts stderr $err;exit 1}
exit 0
