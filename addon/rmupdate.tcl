#!/bin/tclsh

#  RaspMatic update addon
#
#  Copyright (C) 2017  Jan Schneider <oss@janschneider.net>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

source /usr/local/addons/rmupdate/lib/rmupdate.tcl

proc usage {} {
	global argv0
	puts stderr ""
	puts stderr "usage: ${argv0} <module> <command>"
	puts stderr ""
	puts stderr "possible commands:"
	puts stderr "  firmware show_current      : show current firmware version"
	puts stderr "  firmware show_latest       : show latest available firmware version"
	puts stderr "  firmware install_latest    : install latest available firmware version"
	puts stderr "  firmware install <version> : install firmware VERSION"
	puts stderr "  addons list                : list installed addons and versions"
}

proc main {} {
	global argc
	global argv
	
	set mod [string tolower [lindex $argv 0]]
	set cmd [string tolower [lindex $argv 1]]
	
	if {$mod == "firmware"} {
		if {$cmd == "show_current"} {
			puts [rmupdate::get_current_firmware_version]
		} elseif {$cmd == "show_latest"} {
			puts [rmupdate::get_latest_firmware_version]
		} elseif {$cmd == "install_latest"} {
			rmupdate::install_firmware_version [rmupdate::get_latest_firmware_version]
		} elseif {$cmd == "install"} {
			if {$argc < 2} {
				usage
				exit 1
			}
			rmupdate::install_firmware_version [lindex $argv 1]
		} else {
			usage
			exit 1
		}
	} elseif {$mod == "addons"} {
		if {$cmd == "list"} {
			array set addons [rmupdate::get_addon_info]
			set keys [array names addons]
			set keys [lsort $keys]
			foreach key $keys {
				set tmp [split $key "::"]
				set addon_id [lindex $tmp 0]
				set opt [lindex $tmp 2]
				if {$opt == "version"} {
					puts "${addon_id}: $addons($key)"
				}
			}
		} else {
			usage
			exit 1
		}
	} else {
		usage
		exit 1
	}
}

if { [ catch {
	main
} err ] } {
	puts stderr "ERROR: $err"
	exit 1
}
exit 0


