#!/bin/sh

# SPDX-FileCopyrightText: 2026 KUNBUS GmbH
# SPDX-FileCopyrightText: 2026 Silitics GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -e

usage()
{
	cat <<- __EOF__
	usage: $(basename "$0") ARTIFACT_DIR IMAGE_NAME BOOT_PART SYSTEM_PART
	__EOF__

	exit "${1:-0}"
}

extract_partition() {
	local image_name="$1"
	local partition="$2"
	local output="$3"
	local parted_output sector_size dd_args

	if ! parted_output="$(parted -sm "$image_name" -- unit s print)"; then
		printf "Error getting partition offsets\n" >&2
		return 1
	fi

	sector_size="$(echo "$parted_output" | awk -F':' 'FNR==2 { print $4 }')"
	if [ -z "$sector_size" ]; then
		printf "Error getting sector size for %s\n" "$image_name" >&2
		return 1
	fi

	dd_args="$(echo "$parted_output" \
		| awk -v partition="$partition" -F':' '
			$6 == partition {
				print "skip=" substr($2, 1, length($2)-1), \
					"count=" substr($4, 1, length($4)-1)
			}')"
	if [ -z "$dd_args" ]; then
		printf "Error finding partition %s in %s\n" "$partition" "$image_name" >&2
		return 1
	fi

	dd if="$image_name" of="$output" bs="$sector_size" $dd_args status=none
}

if [ $# -ne 4 ]; then
	printf "Incorrect number of arguments\n" >&2
	usage 1 >&2
fi

ARTIFACT_DIR="$1"
IMAGE_NAME="$2"
BOOT_PART="$3"
SYSTEM_PART="$4"

BUNDLE_DIR="$ARTIFACT_DIR"/bundle-"$IMAGE_NAME"
PAYLOADS_DIR="$BUNDLE_DIR"/payloads

BOOT_PART_OUTPUT="$BOOT_PART-$IMAGE_NAME"
SYSTEM_PART_OUTPUT="$SYSTEM_PART-$IMAGE_NAME"

mkdir -p "$PAYLOADS_DIR"
extract_partition "$ARTIFACT_DIR/$IMAGE_NAME".img "$BOOT_PART" \
	"$PAYLOADS_DIR/$BOOT_PART_OUTPUT"
extract_partition "$ARTIFACT_DIR/$IMAGE_NAME".img "$SYSTEM_PART" \
	"$PAYLOADS_DIR/$SYSTEM_PART_OUTPUT"

cat > "$BUNDLE_DIR"/rugix-bundle.toml <<- __EOF__
update-type = "full"
hash-algorithm = "sha512-256"

[[payloads]]
filename = "$BOOT_PART_OUTPUT"
[payloads.delivery]
type = "slot"
slot = "boot"
[payloads.block-encoding]
hash-algorithm = "sha512-256"
chunker = "casync-64"
compression = { type = "xz", level = 9 }
deduplication = true

[[payloads]]
filename = "$SYSTEM_PART_OUTPUT"
[payloads.delivery]
type = "slot"
slot = "system"
[payloads.block-encoding]
hash-algorithm = "sha512-256"
chunker = "casync-64"
compression = { type = "xz", level = 9 }
deduplication = true
__EOF__

rugix-bundler bundle "$BUNDLE_DIR" "$ARTIFACT_DIR/$IMAGE_NAME".rugixb
rugix-bundler hash "$ARTIFACT_DIR/$IMAGE_NAME".rugixb \
	> "$ARTIFACT_DIR/$IMAGE_NAME".rugixb-hash

cp "$ARTIFACT_DIR/$IMAGE_NAME".rugixb "$BUNDLE_DIR".rugixb
cp "$ARTIFACT_DIR/$IMAGE_NAME".rugixb-hash "$BUNDLE_DIR".rugixb-hash
