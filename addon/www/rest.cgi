#!/bin/tclsh

#  RaspMatic update addon
#
#  Copyright (C) 2018  Jan Schneider <oss@janschneider.net>
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

#lappend auto_path /www
#set env(TCLLIBPATH) [list /www /usr/local/addons/rmupdate/lib]
#source once.tcl
#source session.tcl
source /usr/local/addons/rmupdate/lib/rmupdate.tcl

proc process {} {
	global env
	if { [info exists env(QUERY_STRING)] } {
		set query $env(QUERY_STRING)
		set path [split $query {/}]
		set plen [expr [llength $path] - 1]
		
		if {[lindex $path 1] == "install_addon_archive"} {
			set archive_file "/tmp/uploaded_addon.tar.gz"
			catch {fconfigure stdin -translation binary}
			catch {fconfigure stdin -encoding binary}
			set out [open $archive_file w]
			catch {fconfigure $out -translation binary}
			catch {fconfigure $out -encoding binary}
			puts -nonewline $out [read stdin]
			close $out
			set res [rmupdate::install_addon "" "file://${archive_file}"]
			return "\"${res}\""
		}
		
		set data ""
		if { [info exists env(CONTENT_LENGTH)] } {
			set data [read stdin $env(CONTENT_LENGTH)]
		}
		
		if {[lindex $path 1] == "version"} {
			return "\"[rmupdate::version]\""
		} elseif {[lindex $path 1] == "get_firmware_info"} {
			return [rmupdate::get_firmware_info]
		} elseif {[lindex $path 1] == "get_system_info"} {
			set system_type [rmupdate::get_rpi_version]
			set uptime [exec /usr/bin/uptime]
			return "\{\"system_type\":\"${system_type}\",\"uptime\":\"${uptime}\"\}"
		} elseif {[lindex $path 1] == "get_partitions"} {
			return [array_to_json [rmupdate::get_partitions]]
		} elseif {[lindex $path 1] == "move_userfs_to_device"} {
			regexp {\"target_device\"\s*:\s*\"([^\"]+)\"} $data match target_device
			return [rmupdate::move_userfs_to_device $target_device 1 1]
		} elseif {[lindex $path 1] == "system_reboot"} {
			exec /sbin/reboot
			return "\"reboot initiated\""
		} elseif {[lindex $path 1] == "system_shutdown"} {
			exec /sbin/poweroff
			return "\"shutdown initiated\""
		} elseif {[lindex $path 1] == "get_addon_info"} {
			return [rmupdate::get_addon_info 1 1 1]
		} elseif {[lindex $path 1] == "start_install_firmware"} {
			regexp {\"version\"\s*:\s*\"([\d\.]+)\"} $data match version
			regexp {\"language\"\s*:\s*\"([^\"]+)\"} $data match lang
			regexp {\"reboot\"\s*:\s*(true|false)} $data match reboot
			regexp {\"dryrun\"\s*:\s*(true|false)} $data match dryrun
			regexp {\"keep_download\"\s*:\s*(true|false)} $data match keep_download
			if { [info exists version] && $version != "" } {
				if { ![info exists reboot] } {
					set reboot "true"
				}
				if {$reboot == "true"} {
					set reboot 1
				} else {
					set reboot 0
				}
				if { ![info exists dryrun] } {
					set dryrun "false"
				}
				if {$dryrun == "true"} {
					set dryrun 1
				} else {
					set dryrun 0
				}
				if { ![info exists keep_download] } {
					set keep_download "false"
				}
				if {$keep_download == "true"} {
					set keep_download 1
				} else {
					set keep_download 0
				}
				return "\"[rmupdate::install_firmware_version $version $lang $reboot $keep_download $dryrun]\""
			} else {
				error "Invalid version: ${data}"
			}
		} elseif {[lindex $path 1] == "install_addon"} {
			regexp {\"addon_id\"\s*:\s*\"([^\"]+)\"} $data match addon_id
			if { ![info exists addon_id] } {
				set addon_id ""
			}
			regexp {\"download_url\"\s*:\s*\"([^\"]+)\"} $data match download_url
			if { ![info exists download_url] } {
				set download_url ""
			}
			return "\"[rmupdate::install_addon $addon_id $download_url]\""
		} elseif {[lindex $path 1] == "uninstall_addon"} {
			regexp {\"addon_id\"\s*:\s*\"([^\"]+)\"} $data match addon_id
			if { [info exists addon_id] && $addon_id != "" } {
				return "\"[rmupdate::uninstall_addon $addon_id]\""
			} else {
				error "Invalid addon_id: ${addon_id}"
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
		} elseif {[lindex $path 1] == "wlan_scan"} {
			return [rmupdate::wlan_scan 1]
		} elseif {[lindex $path 1] == "wlan_connect"} {
			regexp {\"ssid\"\s*:\s*\"([^\"]+)\"} $data match ssid
			set password ""
			regexp {\"password\"\s*:\s*\"([^\"]+)\"} $data match password
			return [rmupdate::wlan_connect $ssid $password]
		} elseif {[lindex $path 1] == "wlan_disconnect"} {
			return [rmupdate::wlan_disconnect]
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
