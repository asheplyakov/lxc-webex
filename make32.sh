#!/bin/sh
set -e
# Create a 32-bit container for running broken GUI apps.
# Based on https://www.flockport.com/run-gui-apps-in-lxc-containers

CNAME="trusty32"
my_uid=`id -u`
my_gid=`id -g`
subuid_start=100000
subgid_start=100000
subuid_count=65536

maybe_install_lxc () {
	local pkg_status
	local lxc_installed='yes'
	local config="$HOME/.config/lxc/default.conf"
	set +e
	pkg_status=`dpkg-query -Wf '${Status}' lxc`
	set -e
	if [ "$pkg_status" != 'install ok installed' ]; then
		lxc_installed=''
		sudo apt-get install -y lxc
		cat >&2 <<-EOF
		Please re-login in GUI session to make dbus magic work
		EOF
		exit 1
	fi
	if ! grep -e "`whoami`" /etc/lxc/lxc-usernet; then
		echo "`whoami` veth lxcbr0 128" | sudo tee -a /etc/lxc/lxc-usernet
	fi
	if [ ! -e "$config" ]; then
		mkdir -p "${config%/*}"
	fi
	cat > "$config" <<-EOF
	lxc.id_map = u 0 $subuid_start $subuid_count
	lxc.id_map = g 0 $subgid_start $subuid_count
	lxc.network.type = veth
	lxc.network.link = lxcbr0
	EOF
	if [ -z "$lxc_installed" ]; then
		return 1
	fi
}

create_32bit_container () {
	lxc-create -n "$CNAME" -t download -- \
		--dist ubuntu --release trusty --arch i386
}


setup_uid_mapping () {
	local config="$HOME/.local/share/lxc/$CNAME/config"
	sed -i "$config" -re '/^\s*lxc\.id_map/ d'
	cat >> "$config" <<-EOF
	# Make UID ${my_uid} same in the host and the container
	lxc.id_map = u 0 ${subuid_start} ${my_uid}
	lxc.id_map = u ${my_uid} ${my_uid} 1
	lxc.id_map = u $((my_uid+1)) $((subuid_start+my_uid+1)) $((subuid_count-my_uid-1))
	# Make GID ${my_gid} same in the host and the container
	lxc.id_map = g 0 ${subgid_start} ${my_gid}
	lxc.id_map = g ${my_gid} ${my_gid} 1
	lxc.id_map = g $((my_gid+1)) $((subgid_start+my_gid+1)) $((subuid_count-my_gid-1))
	EOF
}

expose_video_snd () {
	local config="$HOME/.local/share/lxc/$CNAME/config"
	sed -i "$config" -re '/^\s*lxc\.mount\.entry/ d'
	cat >> "$config" <<-EOF
	lxc.mount.entry = /dev/dri dev/dri none bind,optional,create=dir
	lxc.mount.entry = /dev/snd dev/snd none bind,optional,create=dir
	lxc.mount.entry = /tmp/.X11-unix tmp/.X11-unix none bind,optional,create=dir
	lxc.mount.entry = /tmp/.ICE-unix tmp/.ICE-unix none bind,optional,create=dir
	EOF
}

fix_sources_list () {
	lxc-attach -n "$CNAME" --clear-env -- \
		sed -i /etc/apt/sources.list -re 's/(archive)/ru.archive/'
	lxc-attach -n "$CNAME" --clear-env -- \
		/bin/sh -c 'echo deb http://archive.canonical.com/ubuntu trusty partner >> /etc/apt/sources.list'
	lxc-attach -n "$CNAME" --clear-env -- \
		/bin/sh -c 'echo Acquire::http::proxy \"http://10.66.0.1:3128/\"\; > /etc/apt/apt.conf.d/90_use_proxy'
}

install_pkgs () {
	# wait until the networking is up
	lxc-attach -n "$CNAME" --clear-env -- \
		/bin/sh -c 'while true; do if ping -c5 ru.archive.ubuntu.com >/dev/null 2>&1; then break; fi; done'
	lxc-attach -n "$CNAME" --clear-env -- \
		env PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		apt-get update
	lxc-attach -n "$CNAME" --clear-env -- \
		env PATH=/bin:/sbin:/usr/bin:/usr/sbin \
		apt-get install -y firefox pulseaudio icedtea-7-plugin adobe-flashplugin ubuntu-restricted-extras
}

create_pulse_hook () {
	local cdir="$HOME/.local/share/lxc/$CNAME"
	local rootfs="$cdir/rootfs"
	local hook="$cdir/setup-pulse.sh"
	cat > "${hook}.tmp" <<-EOF
	#!/bin/sh
	PULSE_PATH=\$LXC_ROOTFS_PATH/home/ubuntu/.pulse_socket
	if [ ! -e "\$PULSE_PATH" ] || [ -z "\$(lsof -n \$PULSE_PATH 2>&1)" ]; then
		pactl load-module module-native-protocol-unix \
			auth-anonymous=1 \
			socket=\$PULSE_PATH
	fi
	if [ -e "\$HOME/.Xauthority" ]; then
		cp "\$HOME/.Xauthority" "\$LXC_ROOTFS_PATH/home/ubuntu"
	fi
	EOF
	chmod 755 "${hook}.tmp"
	mv "${hook}.tmp" "${hook}"
}


if ! maybe_install_lxc; then
	echo "restart display manager, login again and re-run this script" >&2
	exit 1
fi

create_32bit_container
setup_uid_mapping
create_pulse_hook
sudo chown -R "${my_uid}:${my_gid}" $HOME/.local/share/lxc/$CNAME/rootfs/home/ubuntu
lxc-start -n "$CNAME" -d
lxc-wait -n "$CNAME" -s RUNNING

fix_sources_list
install_pkgs
# Note: x11-common postinst tries to manipulate /tmp/.X11-unix
# permissions/ownership which will fail if that dir has been bind mounted
# from the host. Therefore configure bind mounts after installing
# the packages
lxc-stop -n "$CNAME"
lxc-wait -n "$CNAME" -s STOPPED
expose_video_snd

lxc-start -d -n "$CNAME"
lxc-wait -n "$CNAME" -s RUNNING
lxc-attach -n "$CNAME" --clear-env -- \
	/bin/su -l ubuntu -c '/usr/bin/env \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		DISPLAY=:0 \
		PULSE_SERVER=/home/ubuntu/.pulse_socket \
		firefox -no-remote'



