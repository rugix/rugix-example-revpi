#!/bin/bash

# SPDX-FileCopyrightText: 2024 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

# List all packages with their version and origin repository

set -e

SHOW_DUPLICATE="false"

usage() {
	cat <<- EOF
	usage: $(basename "$0") [-d]

	List all installed packages from different origin.

	Options:
	  -d    List installed packages from Raspberry Pi repository that are
	        also available for installation from the Debian repository
	EOF

	exit "${1:-0}"
}

while getopts "dh" opts; do
	case "$opts" in
	d) SHOW_DUPLICATE="true" ;;
	h) usage 0 ;;
	?) usage 1 >&2 ;;
	esac
done

pkgs="$(dpkg-query --show --showformat='${Package} ')"
for pkg in $pkgs; do
	pkg_info="$(apt-cache policy "$pkg")"
	installed_pkg="$(echo "$pkg_info" | grep -EA1 "^[[:space:]]\*{3}" \
		| awk -F' ' '{print $2}' \
		| tr '\n' ' ' \
		| awk -F ' ' -v pkg="$pkg" '{print pkg, $1, $2}')"

	if [ "$SHOW_DUPLICATE" = "true" ]; then
		if echo "$pkg_info" | grep -q "raspberrypi" \
			&& echo "$pkg_info" | grep -q "deb.debian"; then
			echo "$pkg"
		fi
	else
		echo "$installed_pkg"
	fi
done
