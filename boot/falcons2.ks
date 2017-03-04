// initialisation
@lazyglobal off.
clearscreen.
set ship:control:pilotmainthrottle to 0.
wait 0.

// requiring libraries

local storagePath is "1:".
if not exists(storagePath + "/libs") {
	createdir(storagePath + "/libs").
}

function libDl {
	parameter libs is list().
	
	for lib in libs {
		copypath("0:/libs/" + lib + ".ks", storagePath + "/libs/").
	}
	for lib in libs {
		runpath(storagePath + "/libs/" + lib + ".ks").
	}
}

//libDl(list("lib_navball", "telemetry", "flight_display", "functions", "falcon_functions")).


// declaring variables

local expTWR is 0.
local compass is 0.
local pitch is 90.
local runmode is 1.
local tval is 0.
local clearRequired is false.
local dt is 0.
local steer is up.
local gearStatus is 0.
local targetAlt is 0.
local curAlt is 0.
local targetPos is 0.
local altParam is 0.
local targStatus is 0.
local mT is 0.
local startT is 0.
local lT is 0.
local oldT is 0.
local gravTurn is false.
local tempPitch is 0.
local stageNumber is 1.
local eventTime is 0.

// final preparation

set startT to time:seconds.
set oldT to startT.
set lT to startT + 10.

print 1.
wait until exists(storagePath + "/separated.ks").
print 2.
wait 0.5.

lock throttle to max(0, min(1, tval)).
lock steering to steer.

wait 0. // waiting 1 physics tick

// ----------------================ Main loop starts here ================----------------

until runmode = 0 {
	
	// stuff that needs to update before every iteration
	set mT to time:seconds.
	set dt to mT - oldT.
	set curAlt to ship:altitude.
	
	// runmodes
	
	if runmode = 1
	{
		rcs on.
		set tval to 1.
		set steer to ship:velocity:orbit.
		set eventTime to mT + 1.
		set runmode to 2.
	}
	else if runmode = 2
	{
		if mT > eventTime {
			set eventTime to mT + 10.
			set runmode to 3.
		}
	}
	else if runmode = 3
	{
		if ship:obt:altitude > 100000 {
			stage.
			set runmode to 4.
		}
	}
	else if runmode = 4
	{
		
	}
	
	set oldT to mT.
	wait 0. // waiting 1 physics tick
}

unlock all.