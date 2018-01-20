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

proc process {} {
	global env
	if { [info exists env(QUERY_STRING)] } {
		set query $env(QUERY_STRING)
		set data ""
		if { [info exists env(CONTENT_LENGTH)] } {
			set data [read stdin $env(CONTENT_LENGTH)]
		}
		set path [split $query {/}]
		set plen [expr [llength $path] - 1]
		
		if {[lindex $path 1] == "version"} {
			return "\"[rmupdate::version]\""
		} elseif {[lindex $path 1] == "get_firmware_info"} {
			return [rmupdate::get_firmware_info]
		} elseif {[lindex $path 1] == "get_system_info"} {
			set root_partition [rmupdate::get_current_root_partition]
			return "\{\"root_partition\":${root_partition}\}"
		} elseif {[lindex $path 1] == "get_addon_info"} {
			return [rmupdate::get_addon_info 1 1 1]
		} elseif {[lindex $path 1] == "start_install_firmware"} {
			regexp {\"version\"\s*:\s*\"([\d\.]+)\"} $data match version
			regexp {\"reboot\"\s*:\s*(true|false)} $data match reboot
			regexp {\"dryrun\"\s*:\s*(true|false)} $data match dryrun
			if { [info exists version] && $version != "" } {
				if { ![info exists reboot] } {
					set reboot "true"
				}
				if {$reboot == "true"} {
					set reboot 1
				} else {
					set reboot 0
				}
				if { ![info exists reboot] } {
					set dryrun "false"
				}
				if {$dryrun == "true"} {
					set dryrun 1
				} else {
					set dryrun 0
				}
				return "\"[rmupdate::install_firmware_version $version $reboot $dryrun]\""
			} else {
				error "Invalid version: ${data}"
			}
		} elseif {[lindex $path 1] == "delete_firmware_image"} {
			regexp {\"version\"\s*:\s*\"([\d\.]+)\"} $data match version
			if { [info exists version] && $version != "" } {
				return "\"[rmupdate::delete_firmware_image $version]\""
			} else {
				error "Invalid version: ${data}"
			}
		} elseif {[lindex $path 1] == "is_system_upgradeable"} {
			if {[rmupdate::is_system_upgradeable]} {
				return "true"
			} else {
				return "false"
			}
		} elseif {[lindex $path 1] == "get_running_installation"} {
			return "\"[rmupdate::get_running_installation]\""
		} elseif {[lindex $path 1] == "read_install_log"} {
			variable content_type "text/html"
			return [rmupdate::read_install_log]
		}
	}
	error "invalid request" "Not found" 404
}

variable content_type "application/json"

if [catch {process} result] {
	set status 500
	if { [info exists $errorCode] } {
		set status $errorCode
	}
	puts "Content-Type: ${content_type}"
	puts "Status: $status";
	puts ""
	set result [json_string $result]
	puts -nonewline "\{\"error\":\"${result}\"\}"
} else {
	puts "Content-Type: ${content_type}"
	puts "Status: 200 OK";
	puts ""
	puts -nonewline $result
}
