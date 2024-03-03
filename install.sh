#!/usr/bin/bash
# Installation script for the bechele software from the git clone to the required destinations
# written By Rolf Jethon March 2024

base=$(dirname "$0")
cd $base
if [ `whoami` != "root" ]; then
	echo "You must be logged in as root or use sudo to run this script"
	exit 
fi
if [ `uname -s` != "Linux" ]; then
	echo "Your platform ($(uname -a)) is not supported."
	exit
fi
#-------------------------------------------------------------------------------------------------
# Copy the executables of bechele
#-------------------------------------------------------------------------------------------------
if [ -f /usr/local/bin/bechele/live.pl ]; then
	read -p "Some perhaps older file(s) of the bechele package already exist in /usr/localbin/bechele - overwrite (yes/no) ?" -n 1 -r
	echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
		cp  -R --no-preserve=ownership usr/local/bin/* /usr/local/bin
		echo "Bechele executables overwritten in /usr/local/bin"
        fi
else
	cp  -R --no-preserve=ownership usr/local/bin/* /usr/local/bin
	echo "Bechele executables written to /usr/local/bin"
fi
#-------------------------------------------------------------------------------------------------
# Inastall the autostart service file (does not start the service)
#-------------------------------------------------------------------------------------------------
if [ -f /usr/lib/systemd/system/runlive.service ]; then
	read -p "Bechele runlive.service already exist in /usr/lib/systemd/system - overwrite (yes/no) ?" -n 1 -r
	echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
		cp --no-preserv=ownership usr/lib/systemd/system/runlive.service /usr/lib/systemd/system
		echo "Existing runlive.service overwritten !"
	fi
else
	if [ -n "$(ls -A /usr/lib/systemd/system 2>/dev/null)" ]; then
		cp --no-preserve=ownership usr/lib/systemd/system/runlive.service /usr/lib/systemd/system
		echo "runlive.service copied to /usr/lib/systemd/system"
	fi
fi
#------------------------------------------------------------------------------------------------
# copies the example mp3 and servo files
# -----------------------------------------------------------------------------------------------
read -p "Do you want to install the Bechele example MP3 and servo files to /home/bechele3 (yes/no) ?" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	cp -p -R home/* /home
	echo "All sample files have been copied to /home/bechele3"
fi
