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

set version_url "https://github.com/j-a-n/raspberrymatic-addon-rmupdate/raw/master/VERSION"
set package_url "https://github.com/j-a-n/raspberrymatic-addon-rmupdate/raw/master/rmupdate.tar.gz"

set cmd ""
if {[info exists env(QUERY_STRING)]} {
	regexp {cmd=([^&]+)} $env(QUERY_STRING) match cmd
}
if {$cmd == "download"} {
	puts "<html><head><meta http-equiv=\"refresh\" content=\"0; url=${package_url}\" /></head><body><a href=\"${package_url}\">${package_url}</a></body></html>"
} else {
	puts [exec /usr/bin/wget -q --no-check-certificate -O- "${version_url}"]
}
