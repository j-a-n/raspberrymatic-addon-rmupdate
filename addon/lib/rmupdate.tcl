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
	variable release_url "https://github.com/jens-maus/RaspberryMatic/releases"
	variable addon_dir "/usr/local/addons/rmupdate"
	variable img_dir "/usr/local/addons/rmupdate/var/img"
	variable mnt_cur "/usr/local/addons/rmupdate/var/mnt_cur"
	variable mnt_new "/usr/local/addons/rmupdate/var/mnt_new"
	variable sys_dev "/dev/mmcblk0"
	variable loop_dev "/dev/loop7"
	variable install_log "/usr/local/addons/rmupdate/var/install.log"
	variable install_lock "/usr/local/addons/rmupdate/var/install.lock"
	variable log_file ""
}

proc ::rmupdate::get_rpi_version {} {
	# Revison list from http://elinux.org/RPi_HardwareHistory
	set revision_map(0002)   "rpi0"
	set revision_map(0003)   "rpi0"
	set revision_map(0004)   "rpi0"
	set revision_map(0005)   "rpi0"
	set revision_map(0006)   "rpi0"
	set revision_map(0007)   "rpi0"
	set revision_map(0008)   "rpi0"
	set revision_map(0009)   "rpi0"
	set revision_map(000d)   "rpi0"
	set revision_map(000e)   "rpi0"
	set revision_map(000f)   "rpi0"
	set revision_map(0010)   "rpi0"
	set revision_map(0011)   "rpi0"
	set revision_map(0012)   "rpi0"
	set revision_map(0013)   "rpi0"
	set revision_map(0014)   "rpi0"
	set revision_map(0015)   "rpi0"
	set revision_map(900021) "rpi0"
	set revision_map(900032) "rpi0"
	set revision_map(900092) "rpi0"
	set revision_map(900093) "rpi0"
	set revision_map(920093) "rpi0"
	set revision_map(9000c1) "rpi0"
	set revision_map(a01040) "rpi3"
	set revision_map(a01041) "rpi3"
	set revision_map(a21041) "rpi3"
	set revision_map(a22042) "rpi3"
	set revision_map(a02082) "rpi3"
	set revision_map(a020a0) "rpi3"
	set revision_map(a22082) "rpi3"
	set revision_map(a32082) "rpi3"
	
	set fp [open /proc/cpuinfo r]
	set data [read $fp]
	foreach d [split $data "\n"] {
		regexp {^Revision\s*:\s*(\S+)\s*$} $d match revision
		if { [info exists revision] && [info exists revision_map($revision)] } {
			return $revision_map($revision)
		}
	}
	return ""
}

proc ::rmupdate::compare_versions {a b} {
	return [package vcompare $a $b]
}

proc ::rmupdate::write_log {str} {
	variable log_file
	puts stderr $str
	if {$log_file != ""} {
		set fd [open $log_file "a"]
		puts $fd $str
		close $fd
	}
}

proc ::rmupdate::read_install_log {} {
	variable install_log
	if { ![file exist $install_log] } {
		return ""
	}
	set fp [open $install_log r]
	set data [read $fp]
	close $fp
	return $data
}

proc ::rmupdate::version {} {
	variable addon_dir
	set fp [open "${addon_dir}/VERSION" r]
	set data [read $fp]
	close $fp
	return [string trim $data]
}

proc ::rmupdate::get_partion_start_and_size {device partition} {
	set data [exec /usr/sbin/parted $device unit B print]
	foreach d [split $data "\n"] {
		regexp {^\s*(\d)\s+(\d+)B\s+(\d+)B\s+(\d+)B.*} $d match num start end size
		if { [info exists num] && $num == $partition } {
			return [list $start $size]
		}
	}
	return [list -1 -1]
}

proc ::rmupdate::is_system_upgradeable {} {
	set ret [get_filesystem_size_and_usage "/"]
	set size [lindex $ret 0]
	set used [lindex $ret 1]
	if { [expr {$used*1.5}] > $size && [expr {$used+50*1024*1024}] >= $size } {
		return 0
	}
	return 1
}

proc ::rmupdate::get_part_id {device} {
	#set data [exec blkid $device]
	#foreach d [split $data "\n"] {
	#	# recent busybox version needed
	#	regexp {PARTUUID="([^"]+)"} $d match partuuid
	#	if { [info exists partuuid] } {
	#		return $partuuid
	#	}
	#}
	foreach f [glob /dev/disk/by-partuuid/*] {
		set d ""
		catch {
			set d [file readlink $f]
		}
		if { [file tail $d] == [file tail $device] } {
			return [file tail $f]
		}
	}
	return ""
}

proc ::rmupdate::update_cmdline {cmdline root} {
	set fd [open $cmdline r]
	set data [read $fd]
	close $fd
	
	regsub -all "root=\[a-zA-Z0-9\=/\-\]+ " $data "root=${root} " data
	
	set fd [open $cmdline w]
	puts $fd $data
	close $fd
}

proc ::rmupdate::update_fstab {fstab {boot ""} {root ""} {user ""}} {
	set ndata ""
	set fd [open $fstab r]
	set data [read $fd]
	foreach d [split $data "\n"] {
		set filesystem ""
		regexp {^([^#]\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+).*} $d match filesystem mountpoint type options dump pass
		if { [info exists filesystem] } {
			if {$filesystem != ""} {
				if {$mountpoint == "/" && $root != ""} {
					regsub -all $filesystem $d $root d
				} elseif {$mountpoint == "/boot" && $boot != ""} {
					regsub -all $filesystem $d $boot d
				} elseif {$mountpoint == "/usr/local" && $user != ""} {
					regsub -all $filesystem $d $user d
				}
			}
		}
		append ndata "${d}\n"
	}
	close $fd
	
	set fd [open $fstab w]
	puts $fd $ndata
	close $fd
}

proc ::rmupdate::mount_image_partition {image partition mountpoint} {
	variable loop_dev
	variable sys_dev
	
	write_log "Mounting parition ${partition} of image ${image}."

	set p [get_partion_start_and_size $image $partition]
	#write_log "Partiton start=[lindex $p 0], size=[lindex $p 1]."
	
	file mkdir $mountpoint
	catch {exec /bin/umount "${mountpoint}"}
	catch {exec /sbin/losetup -d $loop_dev}
	exec /sbin/losetup -o [lindex $p 0] $loop_dev "${image}"
	exec /bin/mount $loop_dev -o ro "${mountpoint}"
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
	catch {exec /bin/umount "${mountpoint}"}
	exec /bin/mount -o bind $partition_or_filesystem "${mountpoint}"
	exec /bin/mount -o remount,rw "${mountpoint}"
}

proc ::rmupdate::umount {device_or_mountpoint} {
	exec /bin/umount "${device_or_mountpoint}"
}

proc ::rmupdate::get_filesystem_size_and_usage {device_or_mountpoint} {
	set data [exec /bin/df]
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
		
		if { [expr {$new_used*1.5}] > $cur_size && [expr {$new_used+50*1024*1024}] >= $cur_size } {
			error "Current filesystem of partition $partition (${cur_size} bytes) not big enough (new usage: ${new_used} bytes)."
		}
	}
	write_log "Sizes of filesystems checked successfully."
}

proc ::rmupdate::update_filesystems {image {dryrun 0}} {
	variable mnt_new
	variable mnt_cur
	variable sys_dev
	
	set extra_args ""
	if {$dryrun != 0} {
		set extra_args "--dry-run"
	}
	
	write_log "Updating filesystems."
	
	file mkdir $mnt_new
	file mkdir $mnt_cur
	
	foreach partition [list 1 2] {
		write_log "Updating partition ${partition}."
		
		mount_image_partition $image $partition $mnt_new
		mount_system_partition $partition $mnt_cur
		
		write_log "Rsyncing filesystem of partition ${partition}."
		if {$partition == 2} {
			exec rsync ${extra_args} --progress --archive --delete --exclude=/lib "${mnt_new}/" "${mnt_cur}"
			exec rsync ${extra_args} --progress --archive --delete "${mnt_new}/lib/" "${mnt_cur}/lib.rmupdate"
		} else {
			exec rsync ${extra_args} --progress --archive --delete "${mnt_new}/" "${mnt_cur}"
		}
		write_log "Rsync finished."
		
		if {$partition == 1} {
			write_log "Update cmdline."
			if {$dryrun == 0} {
				update_cmdline "${mnt_cur}/cmdline.txt" "${sys_dev}p2"
				#set partid [get_part_id "${sys_dev}p2"]
				#if { $partid != "" } {
				#	set_root_in_cmdline "${mnt_cur}/cmdline.txt" "PARTUUID=${partid}"
				#}
			}
		} elseif {$partition == 2} {
			write_log "Update fstab."
			if {$dryrun == 0} {
				update_fstab "${mnt_cur}/etc/fstab" "${sys_dev}p1" "/dev/root" "${sys_dev}p3"
			}
		}
		
		umount $mnt_new
		umount $mnt_cur
	}
}

#proc ::rmupdate::is_firmware_up_to_date {} {
#	set latest_version [get_latest_firmware_version]
#	write_log "Latest firmware version: ${latest_version}"
#	
#	set current_version [get_current_firmware_version]
#	write_log "Current firmware version: ${current_version}"
#	
#	if {[compare_versions $current_version $latest_version] >= 0} {
#		return 1
#	}
#	return 0
#}

proc ::rmupdate::get_current_firmware_version {} {
	set fp [open "/boot/VERSION" r]
	set data [read $fp]
	close $fp
	regexp {\s*VERSION\s*=s*([\d\.]+)\s*$} $data match current_version
	return $current_version
}

proc ::rmupdate::get_available_firmware_downloads {} {
	variable release_url
	set rpi_version [get_rpi_version]
	set download_urls [list]
	set data [exec /usr/bin/wget "${release_url}" --no-check-certificate -q -O-]
	foreach d [split $data ">"] {
		set href ""
		regexp {<\s*a\s+href\s*=\s*"([^"]+/releases/download/[^"]+)\.zip"} $d match href
		if { [info exists href] && $href != ""} {
			set fn [lindex [split $href "/"] end]
			set tmp [split $fn "-"]
			if { [llength $tmp] == 3 } {
				if { $rpi_version != [lindex $tmp 2] } {
					continue
				}
			}
			#write_log $href
			lappend download_urls "https://github.com${href}.zip"
		}
	}
	return $download_urls
}

proc ::rmupdate::get_latest_firmware_version {} {
	set versions [list]
	foreach e [get_available_firmware_downloads] {
		lappend versions [get_version_from_filename $e]
	}
	set versions [lsort -decreasing -command compare_versions $versions]
	return [lindex $versions 0]
}

proc ::rmupdate::download_firmware {version} {
	variable img_dir
	variable log_file
	set image_file "${img_dir}/RaspberryMatic-${version}.img"
	set download_url ""
	foreach e [get_available_firmware_downloads] {
		set v [get_version_from_filename $e]
		if {$v == $version} {
			set download_url $e
			break
		}
	}
	if {$download_url == ""} {
		error "Failed to get url for firmware ${version}"
	}
	write_log "Downloading firmware from ${download_url}."
	regexp {/([^/]+)$} $download_url match archive_file
	set archive_file "${img_dir}/${archive_file}"
	file mkdir $img_dir
	if {$log_file != ""} {
		exec /usr/bin/wget "${download_url}" --show-progress --progress=dot:giga --no-check-certificate --quiet --output-document=$archive_file 2>>${log_file}
		write_log ""
	} else {
		exec /usr/bin/wget "${download_url}" --no-check-certificate --quiet --output-document=$archive_file
	}
	write_log "Download completed."
	
	write_log "Extracting firmware ${archive_file}."
	set data [exec /usr/bin/unzip -ql "${archive_file}"]
	set img_file ""
	foreach d [split $data "\n"] {
		regexp {\s+(\S+\.img)\s*$} $d match img_file
		if { $img_file != "" } {
			break
		}
	}
	if { $img_file == "" } {
		error "Failed to extract image from archive."
	}
	exec /usr/bin/unzip "${archive_file}" "${img_file}" -o -d "${img_dir}"
	set img_file "${img_dir}/${img_file}"
	puts "${img_file} ${image_file}"
	if {$img_file != $image_file} {
		file rename $img_file $image_file
	}
	file delete $archive_file
	return $image_file
}

proc ::rmupdate::get_available_firmware_images {} {
	variable img_dir
	file mkdir $img_dir
	return [glob -nocomplain "${img_dir}/*.img"]
}

proc ::rmupdate::get_version_from_filename {filename} {
	set fn [file rootname [file tail $filename]]
	set tmp [split $fn "-"]
	return [lindex $tmp 1]
	#regexp {\-([\d\.]+)\.[^\.]+-*.*$} $filename match version
	#return $version
}

proc ::rmupdate::get_firmware_info {} {
	variable release_url
	set current [get_current_firmware_version]
	set versions [list $current]
	foreach e [get_available_firmware_downloads] {
		set version [get_version_from_filename $e]
		set downloads($version) $e
		if {[lsearch $versions $version] == -1} {
			lappend versions $version
		}
	}
	foreach e [get_available_firmware_images] {
		set version [get_version_from_filename $e]
		set images($version) $e
		if {[lsearch $versions $version] == -1} {
			lappend versions $version
		}
	}
	set versions [lsort -decreasing -command compare_versions $versions]
	
	set json "\["
	set latest "true"
	foreach v $versions {
		set installed "false"
		if {$v == $current} {
			set installed "true"
		}
		set image ""
		catch { set image $images($v) }
		set url ""
		catch { set url $downloads($v) }
		set info_url "${release_url}/tag/${v}"
		append json "\{\"version\":\"${v}\",\"installed\":${installed},\"latest\":${latest}\,\"url\":\"${url}\"\,\"info_url\":\"${info_url}\",\"image\":\"${image}\"\},"
		set latest "false"
	}
	if {[llength versions] > 0} {
		set json [string range $json 0 end-1]
	}
	append json "\]"
	return $json
}

proc ::rmupdate::install_process_running {} {
	variable install_lock
	
	if {! [file exists $install_lock]} {
		return 0
	}
	
	set fp [open $install_lock "r"]
	set lpid [string trim [read $fp]]
	close $fp
	
	if {[file exists "/proc/${lpid}"]} {
		return 1
	}
	
	file delete $install_lock
	return 0
}

proc ::rmupdate::delete_firmware_image {version} {
	variable img_dir
	eval {file delete [glob "${img_dir}/*${version}.img"]}
}

proc ::rmupdate::install_firmware_version {version {reboot 1} {dryrun 0}} {
	if {[rmupdate::install_process_running]} {
		error "Another install process is running."
	}
	
	variable install_lock
	variable log_file
	variable install_log
	
	set fd [open $install_lock "w"]
	puts $fd [pid]
	close $fd
	
	file delete $install_log
	set log_file $install_log
	set firmware_image ""
	
	foreach e [get_available_firmware_images] {
		set v [get_version_from_filename $e]
		if {$v == $version} {
			set firmware_image $e
			break
		}
	}
	if {$firmware_image == ""} {
		set firmware_image [download_firmware $version]
	}
	
	check_sizes $firmware_image
	update_filesystems $firmware_image $dryrun
	
	file delete $install_lock
	
	if {$reboot} {
		if { [file exist /lib.rmupdate] } {
			write_log "Replacing /lib and rebooting system."
		} else {
			write_log "Rebooting system."
		}
	}
	# Write success marker for web interface
	write_log "INSTALL_FIRMWARE_SUCCESS"
	after 3000
	
	if {$reboot} {
		if { [file exist /lib.rmupdate] } {
			exec mount -o remount,rw /
			exec rsync --archive --delete /lib.rmupdate/ /lib
			
			set fd [open /proc/sys/kernel/sysrq "a"]
			puts $fd "1"
			close $fd
			set fd [open /proc/sysrq-trigger "a"]
			puts $fd "s"
			close $fd
			set fd [open /proc/sysrq-trigger "a"]
			puts $fd "u"
			close $fd
			set fd [open /proc/sysrq-trigger "a"]
			puts $fd "b"
			close $fd
		} else {
			exec /bin/sh -c "sleep 5; reboot -f " &
		}
	}
}

#puts [rmupdate::get_latest_firmware_version]
#puts [rmupdate::get_firmware_info]
#puts [rmupdate::get_available_firmware_images]
#puts [rmupdate::get_available_firmware_downloads]
#rmupdate::download_latest_firmware
#puts [rmupdate::is_firmware_up_to_date]
#puts [rmupdate::get_latest_firmware_download_url]
#rmupdate::check_sizes "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img"
#set res [rmupdate::get_partion_start_and_size "/dev/mmcblk0" 1]
#rmupdate::mount_image_partition "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img" 1 $rmupdate::mnt_new
#rmupdate::umount $rmupdate::mnt_new
#rmupdate::mount_system_partition "/boot" $rmupdate::mnt_cur
#rmupdate::umount $rmupdate::mnt_cur
#puts [rmupdate::get_rpi_version]

