#!/bin/sh -e

version=$(cat VERSION)
addon_file="$(pwd)/rmupdate.tar.gz"
tmp_dir=$(mktemp -d)

for f in VERSION update_script update_addon addon ccu1 ccu2 ccurm rmupdate; do
	[ -e  $f ] && cp -a $f "${tmp_dir}/"
done
chmod 755 "${tmp_dir}/update_script"

(cd ${tmp_dir}; tar --owner=root --group=root --exclude ".*~" -czvf "${addon_file}" .)
rm -rf "${tmp_dir}"
