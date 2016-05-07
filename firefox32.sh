#!/bin/sh
container='webex'

if ! lxc-wait -n "$container" -s RUNNING -t 0; then
	lxc-start -d -n "$container"
	lxc-wait -n "$container" -s RUNNING
fi

exec lxc-attach -n "$container" --clear-env -- \
	/bin/su -l ubuntu -c '/usr/bin/env \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		DISPLAY=:0 \
		PULSE_SERVER=/home/ubuntu/.pulse_socket \
		firefox -no-remote &'

