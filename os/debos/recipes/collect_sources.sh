#!/bin/bash

# SPDX-FileCopyrightText: 2017-2025 KUNBUS GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

# This script fetches and archives the source code of installed packages.

set -e

SOURCE_DIR="/sources"
BACKUP_DIR="/tmp/apt-backup"

export DEBIAN_FRONTEND=noninteractive

# try downloading the exact version of a package,
# fall back to latest version if not found
#
# $1: name of source package
# $2: version of source package
fetch_deb_src() {
    package="$1"
    version="$2"

    source_options='-qq -o APT::Sandbox::User=root --download-only'
    ver=latest
    # shellcheck disable=SC2086
    if apt-get $source_options source "$package=$version" 2>/dev/null; then
        ver="$version"
    else
        # shellcheck disable=SC2086
        if ! apt-get $source_options source "$package"; then
            return 1
        fi
    fi

    printf "%-20s %s\n" "$package" "$ver"
}

# Backup existing APT source files
mkdir "$BACKUP_DIR"
cp -R /etc/apt/sources.list /etc/apt/sources.list.d "$BACKUP_DIR"

echo "deb-src https://deb.debian.org/debian trixie main" >>/etc/apt/sources.list

# Enable deb-src for revpi repositories
sed -i -e '/Enabled/s/no/yes/g' /etc/apt/sources.list.d/*

apt-get update

# exclude binary-only RevolutionPi packages
EXCLUDE='raspberrypi-firmware|revpi-firmware'

mkdir "$SOURCE_DIR" && cd "$SOURCE_DIR" || exit 1

# Generate list of installed packages
package_list="packages.csv"
echo "package,version,source,source_version" >"$package_list"
dpkg-query -W -f='${binary:Package},${Version},${source:Package},${source:Version}\n' | sort -u >>"$package_list"

# Extract source packages and versions from list and filter excludes
source_packages=$(awk -F',' '{print $3, $4}' "$package_list" | sort -u | grep -Ev "^($EXCLUDE) ")

# Fetch source packages
while read -r item; do
    read -r package version <<< "$item"
    fetch_deb_src "$package" "$version" || :
done <<< "$source_packages"

mv "$package_list" /

cd /

# Create tarball of source packages
tar -cf "$SOURCE_DIR".tar "$SOURCE_DIR"

rm -r "$SOURCE_DIR"

# Restore original APT source files
cp -Rf "$BACKUP_DIR/sources.list" "$BACKUP_DIR/sources.list.d" /etc/apt

rm -r "$BACKUP_DIR"
