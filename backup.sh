#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    # Not root, restarting script with sudo
    # This is required for backing up directories like /etc
    # and opening/mounting the luks container
    exec sudo /bin/bash "$0" "$@"
fi

workdir=$(dirname $(realpath -s $0))
cd $workdir
source "$workdir/$(basename $0 .sh).conf"

# Check if required software is installed
command -v tar > /dev/null 2>&1 || { echo >&2 "tar is required, but it's not installed. Aborting"; exit 1; }

compression="none"
if [[ $* == *"--gzip"* ]]; then
    compression="gzip"
    command -v pigz > /dev/null 2>&1 || { echo >&2 "pigz is required, but it's not installed. Aborting"; exit 1; }
elif [[ $* == *"--bzip2"* ]]; then
    compression="bzip2"
    command -v pbzip2 > /dev/null 2>&1 || { echo >&2 "pbzip2 is required, but it's not installed. Aborting"; exit 1; }
fi

if [[ "$use_luks" == true ]]; then
    command -v cryptsetup > /dev/null 2>&1 || { echo >&2 "cryptsetup is required, but it's not installed. Aborting"; exit 1; }
fi

# Open luks container
if [[ "$use_luks" == true ]]; then
    echo "Creating luks mapping backed by device $disk_uuid as $container_name"
    cryptsetup luksOpen /dev/disk/by-uuid/$disk_uuid $container_name
    echo "Mounting luks container at $mount_dir"
    mkdir -p $mount_dir
    mount /dev/mapper/$container_name $mount_dir
else
    echo "Not using luks"
fi

# Create target directory
mkdir -p $target_dir
echo "Target backup directory is $target_dir"

# Write backup information text file
info_file="info.txt"
cat > "$info_file" << EOF
Identifier: $identifier
Timestamp: $(date "+%Y-%m-%d %H-%M-%S")
Compression: $compression
Sources: ${sources[@]}
Excludes: ${excludes[@]}
EOF

# Build tar arguments
tar_args="-cf - $info_file"

# Append all source paths
for i in "${sources[@]}"; do
    tar_args="$tar_args $i"
done

# Append all exclude arguments
for i in "${excludes[@]}"; do
    tar_args="$tar_args --exclude=$i"
done

tar_args="$tar_args --totals"

# Create tarball
date=$(date +%Y%m%d-%H%M%S)

if [[ $* == *"--gzip"* ]]; then
    target_file=$target_dir/$date.tar.gz
    echo "Creating gzip-compressed backup at $target_file"
    tar $tar_args | pigz -c > "$target_file"
elif [[ $* == *"--bzip2"* ]]; then
    target_file=$target_dir/$date.tar.bz2
    echo "Creating bzip2-compressed backup at $target_file"
    tar $tar_args | pbzip2 -c > "$target_file"
else
    target_file=$target_dir/$date.tar
    echo "Creating backup at $target_file"
    tar $tar_args > "$target_file"
fi

# Delete information text file
rm "$info_file"

# Close luks container
if [[ "$use_luks" == true ]]; then
    echo "Unmounting luks container"
    umount $mount_dir
    echo "Removing luks mapping"
    cryptsetup luksClose $container_name
fi