// initialisation
@lazyglobal off.
clearscreen.
set ship:control:pilotmainthrottle to 0.
wait 0.

wait until ag10. // The program will wait until you press the Action Group 10 button. If you don't want this, please delete/comment this line.
unlock all.
wait 0.

// default launch parameters can be changed while starting the program.
// You can do it by typing "run boot_testflight(250,90,1)."

parameter orbAlt is 200. // Default target altitude
parameter orbDir is 90.  // Default launch direction (landing only works on launching to 90 degrees)
parameter landReq is 1.  // Landing site

// requiring libraries

local storagePath is "Falcon9S2Storage:".
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

libDl(list("lib_navball", "telemetry", "flight_display", "functions", "falcon_functions")).

// setting the ship to a known state

rcs off.
sas off.

// declaring variables

set orbAlt to orbAlt * 1000.
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

// preparing PID loops

// --- ascending loops ---

local Roll_PID is pidloop(0.03, 0, 0.1, -1, 1).
//local Roll_PID is PID_init(0.1, 0, 0.05, -1, 1).
//local Yaw_PID is PID_init(0.1, 0, 0.05, -1, 1).

// --- END ascending loops ---

// final preparation

set startT to time:seconds.
set oldT to startT.
set lT to startT + 10.

log "set lT to " + lT + ". set lzPos to "+ landReq +"." to "Falcon9S1Storage:/stage1status.ks".

lock throttle to max(0, min(1, tval)).
lock steering to steer.

wait 0.001. // waiting 1 physics tick

// ----------------================ Main loop starts here ================----------------

until runmode = 0 {
	
	// stuff that needs to update before every iteration
	set mT to time:seconds.
	set dt to mT - oldT.
	set curAlt to ship:altitude.
	
	// runmodes
	
	if runmode = 1 // Engine ignition
	{
		if alt:radar > 200 {
			set runmode to 3.
		} else if mT >= lT - 3 {
			set tval to 1.
			stage.
			set runmode to 2.
		}
	}
	else if runmode = 2 // Liftoff!!
	{
		if mT >= lT {
			stage.
			set runmode to 3.
		}
	}
	else if runmode = 3 // Initiating pitch-over
	{
		if airspeed >= 180 {
			set runmode to 4.
		} else {
			//sas on.
			if airspeed >= 20 {
				set compass to orbDir.
			}
			if airspeed >= 60 {
				set pitch to max(0, 90 * (1 - ((airspeed - 60) / 120) / 7.5)).
			}
			set tval to 1.
		}
	}
	else if runmode = 4
	{
	
		if shipCurrentTWR() > 3 {
			if Merlin1D_3:ignition or Merlin1D_4:ignition {
				Engine["Stop"](list(
					Merlin1D_3,
					Merlin1D_4
				)).
			}
		}
	
		if ship:altitude > 150000 {
			set runmode to 10.
		}
	}
	else if runmode = 10
	{
		set runmode to 0.
	}
	
	// stuff that needs to update after every iteration
	if Fuel["Stage 1 DeltaV"]() <= deltaVatSep(1,1) and stageNumber = 1 {
		Engine["Stop"](list(
			Merlin1D_0,
			Merlin1D_1,
			Merlin1D_2,
			Merlin1D_3,
			Merlin1D_4,
			Merlin1D_5,
			Merlin1D_6,
			Merlin1D_7,
			Merlin1D_8
		)).
		set tval to 0.
		wait 1.
		log " " to "Falcon9S1Storage:/separated.ks".
		stage.
		rcs on.
		set tval to 1.
		wait 1.
		stage.
		set stageNumber to 2.
		rcs off.
	}
	if clearRequired {
		clearscreen.
		set clearRequired to false.
	}
	displayFlightData().
	displayLaunchData().
	if runmode > 3 {
		set steer to ship:velocity:surface.
	} else {
		set steer to heading(compass, pitch).
	}
	if airspeed > 20 or runmode > 3 {
		set Roll_PID:setpoint to 0.
		set ship:control:roll to Roll_PID:update(mT, roll_for(ship)).
	}
	
	set oldT to mT.
	wait 0. // waiting 1 physics tick
}

unlock all.