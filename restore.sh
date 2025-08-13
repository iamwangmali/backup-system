#!/bin/bash

# check dependences
echo "check dependences"
if ! command -v sfdisk &> /dev/null || ! command -v lsblk &> /dev/null; then
    echo "depends on: sfdisk and lsblk."
    echo "please install: sudo apt-get install util-linux"
    exit 1
fi


TARGETDISK=""
TARGETDISKCAP=""
EFISIZE=""
ROOTSIZE=""
ROOTUSELEFT=""
SWAPSIZE=""
EFIPATH=""
ROOTPATH=""
MNTPT="/mnt/disk_root"

get_root_disk() {
    local root_disk=""
    local root_device=$(df / | awk 'NR==2 {print $1}')
    if [[ "$root_device" != "/cow" ]]; then
        root_disk=$(lsblk -no PKNAME "$root_device")
		echo "/dev/$root_disk"
    fi
}

# =================================================================
# step 1: select the target disk.
# =================================================================
choose_disk() {
	# get current root disk
	local root_disk=$(get_root_disk)
	if [[ root_disk == "" ]]; then
		echo "current root disk is /cow"
	else
		echo "current root disk is $root_disk"
	fi
	
	echo "scanning available disks..."
	
    # get disk list without loop and ramdisk
    local disks_info=$(lsblk -d -o NAME,SIZE,TYPE -n -p -e 7,11)
    
    local menu_items=()
    while read -r name size type; do
		# only disk, and without root disk
        if [[ "$type" == "disk" && "$name" != "$root_disk" ]]; then
            menu_items+=("$name ($size)")
        fi
    done <<< "$disks_info"

    if [[ ${#menu_items[@]} -eq 0 ]]; then
        echo "no disk device found!!!!"
        exit 1
    fi

    echo "please select an disk on which to install:"
    # use select loop to interactive
	PS3="please input:"
    select choice in "${menu_items[@]}"; do
        if [[ -n "$choice" ]]; then
            local chosen_device_name=$(echo "$choice" | awk '{print $1}')
			local chosen_device_cap=$(echo "$choice" | awk '{print $2}')
			TARGETDISK=$chosen_device_name
			echo "you will use $chosen_device_name $chosen_device_cap to install the system."
			break
        else
            echo -n "invalid input, again:"
        fi
    done
}

# =================================================================
# step 2: check partition size
# =================================================================
get_partition_sizes() {
    local device_path=$1
    local total_size_bytes=$(lsblk -dbno SIZE "$device_path")
    local total_size_mib=$((total_size_bytes / 1024 / 1024))

    local recommended_efi=512
    local recommended_swap=4096
    local recommended_root=$((total_size_mib - efi_size - 2))
    
    # recommended size: efi=512MiB, swapfile=4096MiB (4GiB)
    echo ""
    echo "the total cap: $total_size_mib MiB"
    echo "recommended size: efi=${recommended_efi}MiB, swap=${recommended_swap}MiB, /=${recommended_root}MiB"

    local efi_size
    read -p "please input EFI partition size (in MiB, default value: $recommended_efi): " efi_size
    efi_size=${efi_size:-$recommended_efi}

    #as we use GPT, we need reserve 1MB(use 17KB actually) for GPT backup
    local recommended_root=$((total_size_mib - efi_size - 2))
    local root_size
    read -p "please input / partition size(in MiB, default value: $recommended_root): " root_size
    root_size=${root_size:-$recommended_root}

    read -p "please input swapfile size in / (in MiB, default $recommended_swap): " swap_size
    swap_size=${swap_size:-$recommended_swap}


    if ! [[ "$efi_size" =~ ^[0-9]+$ && "$swap_size" =~ ^[0-9]+$ ]]; then
        echo "must an integrate value" >&2
        exit 1
    fi

    local allocated_size=$((efi_size + root_size))
    if [[ "$allocated_size" -gt "$total_size_mib" ]]; then
		echo "$efi_size, $root_size, $allocated_size, $total_size_mib"
        echo "input total size exceed the disk size." >&2
        exit 1
    fi
	
	if [[ "$swap_size" -ge "$root_size" ]]; then
		echo "swapfile size is too large." >&2
		exit 1
	fi
    
	EFISIZE=$efi_size
	ROOTSIZE=$root_size
	SWAPSIZE=$swap_size
}

# =================================================================
# step 3: partition
# =================================================================
confirm_and_partition() {
    local device_path=$1
    local efi_size=$2
    local swap_size=$3
    local root_size=$4

    echo "device: ${device_path}"
    echo "efi: ${efi_size}MiB"
    echo "swap: ${swap_size}MiB"
    echo "/   : ${root_size}MiB"
    echo "-------------------------------------"
    echo "disk data will be distroyed."
    read -p "would you continue(y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo "aborted."
        exit 1
    fi
	
    echo "erase old disk info"
	# delete all the partitions on the disk, and reload partition table
	#sfdisk --delete $device_path
	wipefs -a -f $device_path
	partprobe $device_path
	sleep 1

    echo "parting...."
	# now only sectors is supports
	# each sector is 512 bytes
	local efi_start_sector=$((1024 * 1024 / 512))
	local efi_sectors=$((efi_size * 1024 * 1024 / 512))
	
	#for GPT, reserve an 1M in tail
	local root_start_sector=$((efi_start_sector + efi_sectors))
	local root_sectors=$((root_size * 1024 * 1024 / 512))
	
    # usr sfdisk and Here Document to partition
    sfdisk -f "$device_path" << EOF
label: gpt
unit: sectors

#efi partition
${device_path}1 : start=${efi_start_sector}, size=${efi_sectors}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=efi

#root partition
${device_path}2 : start=${root_start_sector}, size=${root_sectors}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root
EOF

    if [ $? -eq 0 ]; then
    	partprobe $device_path
        mkfs.fat ${device_path}1
	echo format ${device_path}1 to fat32 finished
        mkfs.ext4 -F -q ${device_path}2
	echo format ${device_path}2 to ext4 finished
    fi
    EFIPATH=${device_path}1
    ROOTPATH=${device_path}2
    echo "efi partion is $EFIPATH"
    echo "root partion is $ROOTPATH"

}

mount_partitions() {

	#mount root /
	mkdir -p $MNTPT
	mount -o rw $ROOTPATH $MNTPT

	#mount efi
	mkdir -p $MNTPT/boot/efi
	mount -o rw $EFIPATH $MNTPT/boot/efi

	#create swapfile
	fallocate -l 4G $MNTPT/swapfile
	chmod 600 $MNTPT/swapfile
	mkswap $MNTPT/swapfile

	#mount others
	mkdir -p $MNTPT/{dev,proc,sys}

	mount -o bind /proc $MNTPT/proc
	mount -o bind /dev  $MNTPT/dev
	mount -o bind /sys  $MNTPT/sys

	mkdir -p $MNTPT/{cdrom,lost+found,media,mnt,opt}
}

update_fstab() {
	local EFIUUID=$(lsblk -no UUID $EFIPATH)
	local ROOTUUID=$(lsblk -no UUID $ROOTPATH)

	local old_root_uuid=$(cat $MNTPT/etc/fstab  | grep UUID | grep ext4 | awk '{print $1}')
	local old_efi_uuid=$(cat $MNTPT/etc/fstab  | grep UUID | grep efi | awk '{print $1}')

	sed -i "s/$old_root_uuid/UUID=$ROOTUUID/" $MNTPT/etc/fstab
	sed -i "s/$old_efi_uuid/UUID=$EFIUUID/" $MNTPT/etc/fstab
}

sync_files() {
	rsync -aAXv / $MNTPT --ignore-existing \
		--exclude=/{proc,sys,dev} \
		--exclude=/{etc,run,var,tmp} \
		--exclude=/{cdrom,media,mnt,rofs,swapfile} \
		--exclude=/{*_1} \
		--exclude=/{etc*,run*,var*,tmp*}

	#restore backup info 
	rsync -aAXv /etc-backup/ $MNTPT/etc/
	rsync -aAXv /run-backup/ $MNTPT/run/
	rsync -aAXv /var-backup/ $MNTPT/var/
	rsync -aAXv /tmp-backup/ $MNTPT/tmp/

	update_fstab

	#SETHOSTNAME
}


update_boot() {
	chroot /mnt/disk_root update-initramfs -t -c -k $(uname -r)

	chroot /mnt/disk_root grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu
	chroot /mnt/disk_root update-grub
}

reboot_liveOS() {
	# delete resmatersys service

	#umount somethion
	umount $MNTPT/proc
	umount $MNTPT/sys
	umount $MNTPT/dev

	umount $MNTPT/boot/efi
	umount $MNTPT

	#reboot
}

# =================================================================
# entry point
# =================================================================
choose_disk
get_partition_sizes "$TARGETDISK"
confirm_and_partition "$TARGETDISK" "$EFISIZE" "$SWAPSIZE" "$ROOTSIZE"
mount_partitions
sync_files
update_boot
reboot_liveOS
