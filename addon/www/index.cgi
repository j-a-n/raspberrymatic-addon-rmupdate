#!/bin/tclsh

source /usr/local/addons/rmupdate/lib/querystring.tcl
source /usr/local/addons/rmupdate/lib/session.tcl

if {[info exists sid] && [check_session $sid]} {
    set fp [open "/usr/local/addons/rmupdate/www/rmupdate.html" r]
    puts -nonewline [read $fp]
    close $fp
} else {
    puts {error: invalid session}
}
