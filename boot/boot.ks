@lazyglobal off.
set ship:control:pilotmainthrottle to 0.

clearscreen.

// Initialisation
local archivePath is "".
local startT is time:seconds.
local counter is 0.
local timeout is false.

if volume(1):name <> core:tag or not exists("0:/Updates/" + volume(1):name) {
	set volume(1):name to core:tag.
	set archivePath to "0:/Updates/" + volume(1):name.
	if not exists("1:/lib") {
		createdir("1:/lib").
	}
	if not exists(archivePath + "/Update") {
		createdir(archivePath + "/Update").
	}
	if not exists(archivePath + "/Uploads") {
		createdir(archivePath + "/Uploads").
	}
	notify("Initialisation successful!", 3).
	notify("Waiting for further instructions...", 6).
}

set archivePath to "0:/Updates/" + volume(1):name.

// display a message

function notify {
	parameter message.
	parameter delay.
	hudtext("kOS: " + message, delay, 2, 30, yellow, false).
}

// signal delay between sending and receiving a command

function rt_delay {
	local dTime is 0.
	local accTime is 0.
	local start is 0.
	
	set dTime to addons:rt:delay(ship) * 2.
	until accTime >= dTime {
		set start to time:seconds.
		wait until (time:seconds - start) > (dTime - accTime) or not addons:rt:hasconnection(ship).
		set accTime to accTime + time:seconds - start.
	}
}

// download file from ksc

function download {
	parameter name.
	
	rt_delay().
	if exists("1:/" + name) { deletepath("1:/" + name). }
	copypath(archivePath + "/Update/" + name, "1:/").
}

// upload file to ksc

function upload {
	parameter name.
	
	rt_delay().
	if exists(archivePath + "/Uploads/" + name) { deletepath(archivePath + "/Uploads/" + name). }
	if exists("1:/" + name) { copypath("1:/" + name, archivePath + "/Uploads/" + name). }
	notify("File Uploaded!", 3).
}

// run a library, download if necessary

function require {
	parameter name.
	
	rt_delay().
	if exists("0:/Libraries/" + name) {
		if exists("1:/lib/" + name) {
			if open("0:/Libraries/" + name):readall():length <> open("1:/lib" + name):readall():length {
				deletepath("1:/lib" + name).
				copypath("0:/Libraries/" + name, "1:/lib/" + name).
				notify("Library Updated!", 3).
			}
		} else {
			copypath("0:/Libraries/" + name, "1:/lib/" + name).
			notify("Library Downloaded!", 3).
		}
	}
}

// Done up until this point!

// boot process

local updateScript is "update.ks".

if addons:rt:hasconnection(ship) {
	if exists(archivePath + "/Update/" + updateScript) {
		set warp to 0.
		notify("Downloading new updates...", 3).
		if exists("1:/update.ks") { deletepath("1:/update.ks"). }
		download(updateScript).
		deletepath(archivePath + "/Update/" + updateScript).
		wait 5.
		run update.ks.
		deletepath("1:/update.ks").
	}
}

clearscreen.
print " ".

until timeout {
	print "Standby mode... " + floor(time:seconds - startT) + "          " at(0,0).
	
	if exists("1:/startup.ks") {
		run startup.ks.
	} else {
		if addons:rt:hasconnection(ship) {
			if counter = 0 {
				set counter to time:seconds.
			} else if (time:seconds - counter) > 10 {
				set timeout to true.
			}
		}
	}
}
reboot.