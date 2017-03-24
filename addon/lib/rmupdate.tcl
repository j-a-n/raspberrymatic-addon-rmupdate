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
#

namespace eval rmupdate {
	variable addon_dir "/usr/local/addons/raspmatic-update"
	variable tmp_dir "/usr/local/addons/raspmatic-update/tmp"
	variable mnt_cur "/usr/local/addons/raspmatic-update/mnt_cur"
	variable mnt_new "/usr/local/addons/raspmatic-update/mnt_new"
	variable sys_dev "/dev/mmcblk0"
	variable loop_dev "/dev/loop7"
}

proc ::rmupdate::write_log {str} {
	puts stderr $str
	#set fd [open "/tmp/rmupdate.log" "a"]
	#puts $fd $str
	#close $fd
}

proc ::rmupdate::version {} {
	variable version_file
	set fp [open "${addon_dir}/VERSION" r]
	set data [read $fp]
	close $fp
	return [string trim $data]
}

proc ::rmupdate::get_partion_start_and_size {device partition} {
	set data [exec parted $device unit B print]
	foreach d [split $data "\n"] {
		regexp {^\s*(\d)\s+(\d+)B\s+(\d+)B\s+(\d+)B.*} $d match num start end size
		if { [info exists num] && $num == $partition } {
			return [list $start $size]
		}
	}
	return [list -1 -1]
}

proc ::rmupdate::mount_image_partition {image partition mountpoint} {
	variable loop_dev
	variable sys_dev
	
	write_log "Mounting parition ${partition} of image ${image}."

	set p [get_partion_start_and_size $sys_dev $partition]
	
	file mkdir $mountpoint
	catch {exec umount "${mountpoint}"}
	catch {exec losetup -d $loop_dev}
	exec losetup -o [lindex $p 0] $loop_dev "${image}"
	exec mount $loop_dev -o ro "${mountpoint}"
}

proc ::rmupdate::mount_system_partition {partition_or_filesystem mountpoint} {
	if {$partition_or_filesystem == 1} {
		set partition_or_filesystem "/boot"
	} elseif {$partition_or_filesystem == 2} {
		set partition_or_filesystem "/"
	} elseif {$partition_or_filesystem == 3} {
		set partition_or_filesystem "/usr/local"
	}
	
	write_log "Remounting filesystem ${partition_or_filesystem} (rw)."
	
	file mkdir $mountpoint
	catch {exec umount "${mountpoint}"}
	exec mount -o bind $partition_or_filesystem "${mountpoint}"
	exec mount -o remount,rw "${mountpoint}"
}

proc ::rmupdate::umount {device_or_mountpoint} {
	exec umount "${device_or_mountpoint}"
}

proc ::rmupdate::get_filesystem_size_and_usage {device_or_mountpoint} {
	set data [exec df]
	foreach d [split $data "\n"] {
		regexp {^(\S+)\s+\d+\s+(\d+)\s+(\d+)\s+\d+%\s(\S+)\s*$} $d match device used available mountpoint
		if { [info exists device] } {
			if {$device == $device_or_mountpoint || $mountpoint == $device_or_mountpoint} {
				return [list [expr {$used*1024+$available*1024}] [expr {$used*1024}]]
			}
		}
	}
	return [list -1 -1]
}

proc ::rmupdate::check_sizes {image} {
	variable mnt_new
	variable mnt_cur
	
	write_log "Checking size of filesystems."
	
	file mkdir $mnt_new
	file mkdir $mnt_cur
	
	foreach partition [list 1 2] {
		mount_image_partition $image $partition $mnt_new
		mount_system_partition $partition $mnt_cur
		
		set su_new [get_filesystem_size_and_usage $mnt_new]
		set new_used [lindex $su_new 1]
		set su_cur [get_filesystem_size_and_usage $mnt_cur]
		set cur_size [lindex $su_cur 0]
		
		write_log "Current filesystem (${partition}) size: ${cur_size}, new filesystem used bytes: ${new_used}."
		
		umount $mnt_new
		umount $mnt_cur
		
		# Minimum free space 100 MB
		if { [expr {$new_used+100*1024*1024}] >= $cur_size } {
			error "Current filesystem of partition $partition (${cur_size} bytes) not big enough (new usage: ${new_used} bytes)."
		}
	}
}

proc ::rmupdate::update_filesystems {image} {
	variable mnt_new
	variable mnt_cur
	
	write_log "Updating filesystems."
	
	file mkdir $mnt_new
	file mkdir $mnt_cur
	
	foreach partition [list 1 2] {
		write_log "Updating partition ${partition}."
		
		mount_image_partition $image $partition $mnt_new
		mount_system_partition $partition $mnt_cur
		
		write_log "Rsyncing filesystem."
		set data [exec rsync --progress --archive --delete "${mnt_new}/" "${mnt_cur}"]
		
		umount $mnt_new
		umount $mnt_cur
	}
}

proc ::rmupdate::get_latest_firmware_download_url {} {
	set data [exec wget "https://github.com/jens-maus/RaspberryMatic/releases/latest" --no-check-certificate -q -O-]
	foreach d [split $data "\n"] {
		set href ""
		regexp {<\s*a\s+href\s*=\s*"([^"]+/releases/download/[^"]+.zip)"} $d match href
		if { [info exists href] && $href != ""} {
			return "https://github.com${href}"
		}
	}
	error "Failed to get latest firmware download url"
}

proc ::rmupdate::download_latest_firmware {} {
	variable tmp_dir
	
	set download_url [get_latest_firmware_download_url]
	write_log "Downloading latest firmware from ${download_url}."
	regexp {/([^/]+)$} $download_url match archive_file
	set archive_file "${tmp_dir}/${archive_file}"
	file mkdir $tmp_dir
	exec wget "${download_url}" --no-check-certificate -q --output-document=$archive_file
	return $archive_file
}

proc ::rmupdate::get_latest_firmware_version {} {
	set download_url [get_latest_firmware_download_url]
	regexp {\-([\d\.]+).zip$} $download_url match latest_version
	return $latest_version
}

proc ::rmupdate::get_current_firmware_version {} {
	set fp [open "/boot/VERSION" r]
	set data [read $fp]
	close $fp
	regexp {\s*VERSION\s*=s*([\d\.]+)\s*$} $data match current_version
	return $current_version
}

proc ::rmupdate::is_firmware_up_to_date {} {
	set latest_version [get_latest_firmware_version]
	write_log "Latest firmware version: ${latest_version}"
	
	set current_version [get_current_firmware_version]
	write_log "Current firmware version: ${current_version}"
	
	if {[string compare $current_version $latest_version] >= 0} {
		return 1
	}
	return 0
}

rmupdate::download_latest_firmware

#puts [rmupdate::is_firmware_up_to_date]

#puts [rmupdate::get_latest_firmware_download_url]

#rmupdate::check_sizes "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img"

#set res [rmupdate::get_partion_start_and_size "/dev/mmcblk0" 1]

#rmupdate::mount_image_partition "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img" 1 $rmupdate::mnt_new
#rmupdate::umount $rmupdate::mnt_new

#rmupdate::mount_system_partition "/boot" $rmupdate::mnt_cur
#rmupdate::umount $rmupdate::mnt_cur











