#90Gb is probably to mugh, but it's better to have more space than less.
lxc storage create docker btrfs size=90GB
sleep 10

#90Gb is probably to mugh, but it's better to have more space than less.
lxc storage volume create docker chap-core size=90GB
lxc config device add chap-core docker disk pool=docker source=chap-core path=/var/lib/docker