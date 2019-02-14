#!/bin/bash
#
# A script to extend an LVM volume by adding a new partition on a grown virtual disk
# or format and mount additional virtual disks.
# Designed and tested for Virtual Machines on ESXi 5.5
#
# vm_resize_disk.sh
# 2017 Michael Brown <strictly.sysops@gmail.com>


echo -e "\nChecking system for unallocated storage..."

function eval_disks()
{
# rescan scsi adapters
echo "Forcing refresh of SCSI host bus adapters..."
for adapter in /sys/class/scsi_device/*; do
   echo 1 > "${adapter}/device/rescan"
done
echo "done!"

# refresh all LVM information
echo "Forcing refresh of LVM info..."
{
pvscan
lvscan
vgscan
} &> /dev/null
echo "done!"

# set variables
num_disks=$(fdisk -l | grep "Disk /dev/sd" | wc -l)
mounted_disks=$(df -h | grep "/dev/sd" | wc -l)
sda_disk_size=$(fdisk -l | grep "Disk /dev/sda" | awk '{print $3}' | cut -d . -f 1)
vg_name=$(lvdisplay | grep "VG Name" | awk '{print $3}')
vg_start_size=$(fdisk -l | grep "Disk /dev/mapper/"$vg_name"-rootvol" | awk '{print $3}' | cut -d . -f 1)

if [[ "$sda_disk_size" -gt "$((vg_start_size + 2 ))" ]]; then
   echo -e "\nFound unallocated space on /dev/sda, will now extend LVM"
   extend_lvm;
elif [[ "$num_disks" -gt 1 ]] && [[ "$num_disks" -ne "$mounted_disks" ]] && [[ "$sda_disk_size" -le "$((vg_start_size + 2 ))" ]]; then
   echo -e "\nFound additional unmounted disks, will now partition and mount"
   add_mount;
else
   echo -e "\nNo unused disk space found... exiting"
   exit 0;
fi
}


function extend_lvm()
{
sda_part_count=$(fdisk -l | egrep "/dev/sda[0-9]" | wc -l)
next_part=$((sda_part_count + 1 ))
new_part=/dev/sda${next_part}
lv_path=$(lvdisplay | grep "LV Path" | awk '{print $3}')
cyl_start=$(fdisk -l | grep /dev/sda${sda_part_count} | awk '{print $3}') && (( cyl_start++ ))
cyl_end=$(fdisk -l /dev/sda | egrep "/dev/sda:|cylinders" | tr -d '\n' | awk '{print $10}')

# create new partition with fdisk
echo "Creating new partition "$new_part""
{
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/sda
  n
  p
  ${cyl_start}"\n"
  ${cyl_end}"\n"
  t
  ${next_part}"\n"
  8e
  w
  q
EOF
} &> /dev/null

# check to make sure the partition was added correctly
if [[ -z $(fdisk -l | grep /dev/sda${next_part}) ]]; then
   exit 1;
else
   echo "Partition created successfully"
fi

# force partition table update into kernel
partx -v -a /dev/sda

# add the newly created partition to the LVM
echo -e "\nAdding "$new_part" to Volume Group "$vg_name""
pvcreate "$new_part"
vgextend "$vg_name" "$new_part"
pvscan > /dev/null
echo -e "\nExtending Logical Volume "$lv_path"..."
lvextend "$lv_path" "$new_part"

# resize teh filesystem to use the new space
resize2fs "$lv_path"

# loop routine to cover additional changes
echo "LVM extended sucessfully, will now refresh disk info..."
eval_disks;
}


function add_mount()
{
dev_range=({a..z})
INDEX=1

until [[ "$INDEX" == "$num_disks" ]]; do
   new_disk=sd$(echo ${dev_range[$INDEX]})
   cyl_start=1
   cyl_end=$(fdisk -l /dev/${new_disk} | egrep "/dev/${new_disk}:|cylinders" | tr -d '\n' | awk '{print $10}')
   echo "Creating new primary partition on "$new_disk""
{
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/${new_disk}
  n
  p
  1
  ${cyl_start}"\n"
  ${cyl_end}"\n"
  w
  q
EOF
} &> /dev/null
   if [[ -z $(fdisk -l | grep /dev/${new_disk}1) ]]; then
      exit 1;
   else
      echo "Partition created successfully"
   fi
   echo "Formatting "$new_disk" to EXT4 file system"
   mkfs.ext4 /dev/${new_disk}1
   echo "mounting "$new_disk"1 to /local0"$INDEX""
   mkdir /local0${INDEX}
   echo "/dev/${new_disk}1		/local0${INDEX}		ext4	defaults 0 0" >> /etc/fstab
   mount -a
   echo "Done adding "$new_disk""
   eval INDEX=$((INDEX+1))
done

echo "$num_disks now partitioned, formatted and mounted to server"
eval_disks;
}


# start program
eval_disks;