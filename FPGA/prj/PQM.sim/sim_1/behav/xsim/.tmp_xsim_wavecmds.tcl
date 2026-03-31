foreach cmd [lsort [info commands *wave*]] { puts $cmd }
foreach cmd [lsort [info commands *db*]] { puts "DB:$cmd" }
quit
