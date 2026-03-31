foreach cmd [lsort [info commands *cursor*]] { puts $cmd }
foreach cmd [lsort [info commands *goto*]] { puts "G:$cmd" }
foreach cmd [lsort [info commands *seek*]] { puts "S:$cmd" }
foreach cmd [lsort [info commands *jump*]] { puts "J:$cmd" }
foreach cmd [lsort [info commands *marker*]] { puts "M:$cmd" }
quit
