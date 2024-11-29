#This file mount a volume to the destination where we later install LXD
lsblk
sudo mkfs.btrfs /dev/sdb -f
sudo mkdir /var/snap/lxd
sudo mount /dev/sdb /var/snap/lxd

