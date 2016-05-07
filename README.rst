=============================
Webex on 64 bit Debian/Ubuntu
=============================

Introduction
============

Please don't read this document unless you've been forced to use webex_.
Life is too short for fighting badly written software which doesn't work out
of the box.  Pick a more Linux friendly videoconferencing software such as
bigbluebutton_, jitsi_, etc, or bluejeans_ if you badly need something
*enterprise*, and have a good day.

As of May 2016 Cisco is still unable to make a 64 bit Linux version of webex_,
therefore the only way to run webex_ on a x86_64 Linux machine is installing
32-bit Firefox, Java, which need 32-bit GTK, X11, dbus, and whatnot.
Although Debian (and Ubuntu) support multiarch_ so 64- and 32-bit libraries
can coexist just fine this doesn't work for binaries.
To avoid tedious manual download, setup, and dependency resolution and keep
things upgradable we are going to make an lxc container for running 32-bit
firefox (and possibly other 32-bit only applications).

.. _bigbluebutton: http://bigbluebutton.org
.. _jitsi: https://jitsi.org
.. _bluejeans: https://bluejeans.com
.. _webex: https://webex.com
.. _multiarch: https://wiki.debian.org/Multiarch/HOWTO


In a nutshell
=============

* Use ``make32.sh`` script to create a 32-bit (nonprivileged) container
  necessary for running 32-bit Firefox.
* ``firefox32.sh`` starts 32-bit Firefox in that container.


Technical details
=================

* pulseaudio is configured to accept connections via the UNIX domain
  socket (``/home/ubuntu/.pulse_socket`` in the container), so the processes
  in the container can use the host audio (with a negligible overhead).
* The host directories ``/tmp/.X11-unix``, ``/dev/dri`` are bind mounted
  into the container so the processes in the container can use the host
  video without extra overhead
* For this to work the ``ubuntu`` user in the container shares the UID
  with the host user (the one who started the ``make32.sh`` script).

The idea has been shamelessly stolen from here_.

.. _here: https://www.flockport.com/run-gui-apps-in-lxc-containers

Security implications
=====================

* The container provides no isolation: the user processes both in the host
  and in the container share the UID/GID.
* Since the container has the access to X11 the processes can lock up
  the graphics card, grab keypresses, and so on.
  
Put it another way the container is used as a convenient way to install, run
and upgrade 32-bit software available in the distribution. Those applications
are not isolated from the host just like ordinary GUI applications are not
isolated from each other.

