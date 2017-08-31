// Initialising the script
@lazyglobal off.
clearscreen.
set ship:control:pilotmainthrottle to 0.
wait 0.

// Setting up storage path and creating necessary directories
local storagePath is "1:".
if not exists(storagePath + "/libs") {
	createdir(storagePath + "/libs").
}

// List of libraries needed for the program to run
local libList is list( // Add .ks files to the list to be loaded (without extensions)
	"lib_navball",
	"telemetry",
	"flight_display",
	"maneuvers",
	"functions",
	"falcon_functions",
	"falcon_rcs"
).

// Loading required libraries
function libDl {
	parameter libs is list().
	
	for lib in libs {
		copypath("0:/libs/" + lib + ".ks", storagePath + "/libs/").
	}
	for lib in libs {
		runpath(storagePath + "/libs/" + lib + ".ks").
	}
}

libDl(libList).

// ---=== [**START**] [ DECLARING ALL NECESSARY VARIABLES ] [**START**] ===---

wait until ag10.

// Navigation and rocket systems

local compass is 0.
local pitch is 90.

local runmode is 1.
local cpuName is core:tag.
local reorienting is false.

// Ship positioning and velocity tracking

local posCur is 0.
local posPrev is ship:geoposition.
local altCur is 0.

local impPosCur is 0.
local impPosPrev is ship:geoposition.
local impPosFut is ship:geoposition. // may be redundant
local impDist is 0.
local lzDistCur is 0.
local lzDistImp is 0.

local velLatCur is 0.
local velLngCur is 0.
local velLatImp is 0.
local velLngImp is 0.
local velDir is 0. // surface prograde
local velDirFlat is 0. // horizontal direction

local sepDeltaV is 0.

// Offsets
local posOffset is 5000.
local landingOffset is 0.
local landingOffset2 is 0.
local dirRet is 0.
local dirVecOffset is 0.
local desiredDir is 0.

// Steering variables

local tval is 0.
local stable is false.

local steer is up.
local steerPitch is 0.
local steerYaw is 0.

local pidLimit is 900.

local rotCur is 0.
local rotPrev is 0.
local rotSpd is 0.

local Pitch_val is 0.
local Yaw_val is 0.
local Pitch_set is 0.
local Yaw_set is 0.

local engReady is true.
local engStartup is false.
local engThrust is 0.
	
// ---== PREPARING PID LOOPS ==--- //

// Throttle control
local AltVel_PID is pidloop(0.2, 0, 0.15, -600, 0.1).
local VelThr_PID is pidloop(2.1, 9, 0.15, 0.36, 1).

// Aerodynamic steering loops
local DescLatitudeChange_PID is pidloop(20, 0, 5, -0.1, 0.1).
local DescLatitude_PID is pidloop(300, 1, 150, -10, 10).

local DescLongitudeChange_PID is pidloop(20, 0, 5, -0.1, 0.1).
local DescLongitude_PID is pidloop(300, 1, 150, -10, 10).

// Powered steering loops
local LandLatitudeChange_PID is pidloop(60, 0, 10, -0.05, 0.05).
local LandLatitude_PID is pidloop(700, 0, 200, -5, 5).

local LandLongitudeChange_PID is pidloop(60, 0, 10, -0.05, 0.05).
local LandLongitude_PID is pidloop(700, 0, 200, -5, 5).

// ---== END PID LOOPS ==--- //

// Time tracking
local sT is time:seconds. // Start of program time
local dT is 0. // Delta time
local mT is 0. // Mission elapsed time
local lT is sT + 15. // Until/since launch
local pT is sT. // Previous tick time
local impT is 0.
local landBurnT is 0. // Landing burn time
local landBurnH is 0. // Landing burn height
local landBurnS is 0. // Landing burn speed target
local landBurnS2 is 0. // Landing burn speed target (touchdown)
local landBurnEngs is 1. // Number of ladning engines
local landBurnThr is 0.6.
local eventTime is 0.
local event is false.

// Vectors to be displayed
local vec1 is 0.
local vec2 is 0.
local vec3 is 0.

// Other variables
local clearRequired is false.
local bodyRotation is 360 / body:rotationperiod.
local tr is addons:tr.

// Landing parameters
local lzPos is 0.
local lzPosFut is 0.
local lzAlt is 0.
local reentryBurnDeltaV is 0.

// ---=== [**END**] [ DECLARING ALL NECESSARY VARIABLES ] [**END**] ===---

// ---=== [**START**] [ GETTING NECESSARY DATA ] [**START**] ===---

// Final preparation

if landing <> 0 { // Temporary, plannign to load a landing config file with this data
	if landing = 1 {
		set lzPos to KSCLaunchPad.
		tr:settarget(KSCLaunchPad).
	}
	
	set lzAlt to lzPos:terrainheight.
	when (altCur - lzAlt) < 200 and runmode > 2 then { gear on. }
}

// ---=== [**END**] [ GETTING NECESSARY DATA ] [**END**] ===---

wait 0. // waiting 1 physics tick so that everything updates

if landing <> 0 { // If there is a landing position then proceed with the program

	until runmode = 0 {
		
	// ---=== [**START**] [ UPDATING VARIABLES BEFORE EVERY ITERATION ] [**START**] ===--- //
		
		set mT to time:seconds.
		set dT to mT - pT.
		set altCur to body:altitudeof(Merlin1D_0:position) - 3.9981.
		
		if merlinData[0] = false {
			if tval = 1 and Merlin1D_0:ignition = true and Merlin1D_0:flameout = false {
				set merlinData to list( true, Merlin1D_0:maxthrustat(1), Merlin1D_0:maxthrustat(0), Merlin1D_0:slisp, Merlin1D_0:visp).
			}
		}
		set posCur to ship:geoposition.
		set rotCur to list(pitch_for(ship), compass_for(ship), rollConvert()).
		set velLatCur to (mod(180 + posPrev:lat - posCur:lat, 360) - 180)/dT.
		set velLngCur to (mod(180 + posPrev:lng - posCur:lng, 360) - 180)/dT.
		
		set impT to timeToAltitude(lzAlt, altCur).
		set lzPosFut to latlng(lzPos:lat, mod(lzPos:lng + 180 + (impT * bodyRotation), 360) - 180).
		
		set impPosCur to latlng(body:geopositionof(positionat(ship, mT + impT)):lat, body:geopositionof(positionat(ship, mT + impT)):lng - 0.0000801).
		if tr:hasimpact {
			set impPosFut to tr:impactpos.
		}
		set velLatImp to (mod(180 + impPosPrev:lat - impPosFut:lat, 360) - 180)/dT. // TODO: convert these velocity values to vectors
		set velLngImp to (mod(180 + impPosPrev:lng - impPosFut:lng, 360) - 180)/dT.
		
		set lzDistCur to lzPos:position - ship:geoposition:altitudeposition(lzAlt).
		set lzDistImp to lzPos:position - impPosFut:position.
		set sepDeltaV to Fuel["Stage 1 DeltaV"]().
		
		set landingOffset to vxcl(lzDistImp - body:position, lzDistImp):normalized * posOffset.
		set landingOffset2 to (vxcl(lzPos:position - body:position, lzPos:position):normalized * min(200,lzDistCur:mag/4)) + landingOffset.
		
		if runmode >= 4 {
			set velDir to ship:velocity:surface:normalized * 25.
			set velDirFlat to vxcl(ship:velocity:surface - body:position, ship:velocity:surface):normalized * 25.
			if runmode < 7 {
				set desiredDir to (vxcl((velDir - (velDir - (landingOffset:normalized * 25))*2) - body:position, (velDir - (velDir - (landingOffset:normalized * 25))*2)):normalized * 25) - (body:position:normalized * 1).
			} else {
				set dirRet to (velDirFlat - (landingOffset:normalized * 25)*2):normalized * 25.
				set dirVecOffset to dirRet - velDirFlat.
				set desiredDir to (-dirVecOffset - velDir):normalized * 25.
			}
		}
		
		if runmode = 9 {
			set landBurnT to landingBurnTime(ship:velocity:surface:mag, landBurnEngs, landBurnThr).
			if tval = 0 {
				set landBurnH to landBurnHeight().
			}
			if landBurnEngs = 3 {
				set landBurnS to landBurnSpeed() + 50.
			} else {
				set landBurnS to landBurnSpeed().
			}
			set landBurnS2 to ((1/max(0.01, altCur - lzAlt)^0.25 * ((altCur - lzAlt) * 1.5))* -1) -1.
		}
		
		// [<<IDEA>>] - Might move all the runmodes to a separate file and just load it here
		// Main logic
		
		if runmode = 1 // Wait until separation
		{
			// Separation logic
			// if separated {
			wait 0.
			lock throttle to max(0, min(1, tval)).
			lock steering to steer.
			set runmode to 2.
			// }
		}
		else if runmode = 2 // Decide whether boostback burn is needed - might be in the config
		{
			
		}
		else if runmode = 3.1 // Booster reorienting.
		{
			if mT > eventTime {
				log " " to "Falcon9S2:/separated.ks".
				stage.
				set eventTime to mT + 2.
				set clearRequired to true.
				set runmode to 4.
			} else {
				stabilize().
			}
		}
		else if runmode = 4 // Booster reorienting.
		{
			if mT > eventTime {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip(12).
				}
				if rotCur[0] > 75 {
					set runmode to 4.1.
				}
			} else {
				stabilize().
			}
		}
		else if runmode = 4.1
		{
			if rotCur[0] < 30 {
				set ship:control:neutralize to true.
				set stable to false.
				lock steering to steer.
				set steer to heading(lzPosFut:heading, 0).
				set engStartup to true.
				set runmode to 5.
			} else {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip(12).
				}
			}
		}
		else if runmode = 5 // boostback burn
		{
		
			if 	rotCur[0] < 30 // making sure we point in the right direction before boostback burn
				and rotCur[0] > -30
			{
				set steeringmanager:maxstoppingtime to 2.
				set steeringmanager:rolltorquefactor to 3.
				
				if lzDistImp:mag < posOffset {
					Engine["Stop"](list(
						Merlin1D_1,
						Merlin1D_2
					)).
					if impPosFut:position:mag > lzPos:position:mag {
						Engine["Throttle"](
						list(
							list(Merlin1D_0, max(36, min(100, ((posOffset - lzDistImp:mag)/65) + 36 )))
						)).
					}
				} else {
					Engine["Throttle"](
					list(
						list(Merlin1D_0, 100),
						list(Merlin1D_1, 100),
						list(Merlin1D_2, 100)
					)).
				}
				
				set tval to 1.
				
				if engStartup {
					Engine["Start"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set engStartup to false.
				}
				if ullageReq {
					rcs on.
					set ship:control:fore to 1.
					set engStartup to true.
				} else {
					rcs off.
					set ship:control:fore to 0.
					set engStartup to false.
				}
			}
			
			if lzDistImp:mag > posOffset {
				set steer to desiredDir. // steering towards the target
			}
			
			if (lzDistImp:mag >= posOffset) and (lzDistImp:mag < (posOffset * 2)) and (impPosFut:position:mag > lzPos:position:mag) {
				Engine["Stop"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				set tval to 0.
				unlock steering.
				set runmode to 6.
			}
		}
		else if runmode = 6 // Reorienting for reentry
		{
			rcs on.
			stabilize().
			set eventTime to mT + 3.
			set runmode to 6.1.
			set clearRequired to true.
		}
		else if runmode = 6.1
		{
			if mT > eventTime {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip2(1).
				}
				if rotCur[0] > 75 {
					ag5 on.
					set runmode to 6.2.
				}
			} else {
				stabilize().
			}
		}
		else if runmode = 6.2
		{
			if rotCur[0] < 60 {
				set ship:control:neutralize to true.
				set stable to false.
				set steeringmanager:maxstoppingtime to 3.
				set steeringmanager:rollts to 5.
				set steeringmanager:pitchts to 5.
				set steeringmanager:yawts to 5.
				lock steering to steer.
				set steer to -ship:velocity:surface.
				set engStartup to true.
				set runmode to 7.
			} else {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip(1).
				}
			}
		}
		else if runmode = 7 // Reentry burn
		{
			if altCur <= 55000 { // ------====<<<< Need to change logic to aero drag force or dynamic pressure
				set ship:control:fore to 0.
				set posOffset to 500.
				
				set reorienting to false.
				set tval to 1.
				
				if lzDistImp:mag > (posOffset * 1.1) {
					Engine["Throttle"](list(
						list(Merlin1D_0, 75),
						list(Merlin1D_1, 75),
						list(Merlin1D_2, 75)
					)).
				} else {
					Engine["Throttle"](list(
						list(Merlin1D_0, 36),
						list(Merlin1D_1, 36),
						list(Merlin1D_2, 36)
					)).
				}
				
				if engStartup {
					Engine["Start"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set engStartup to false.
				}
				
				if (lzDistImp:mag <= posOffset) or (sepDeltaV <= 400) {
					Engine["Stop"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set tval to 0.
					set runmode to 8.
					rcs off.
				}
				
				set steer to desiredDir.
			} else {
				set steer to -ship:velocity:surface.
			}
		}
		else if runmode = 8
		{
			set steer to -ship:velocity:surface.
			if altCur < 45000
			{
				set runmode to 9.
				configureLandingBurn().
				when timeToAltitude(landBurnH + lzAlt, altCur) < 3 and altCur - lzAlt < 6000 then {
					set tval to 1.
					if landBurnEngs = 1 {
						Engine["Start"](list(
							Merlin1D_0
						)).
					} else {
						Engine["Start"](list(
							Merlin1D_0,
							Merlin1D_1,
							Merlin1D_2
						)).
						set Merlin1D_1:gimbal:lock to true.
						set Merlin1D_2:gimbal:lock to true.
					}
				}
			}
		}
		else if runmode = 9
		{
			if landBurnEngs = 1 {
				if landBurnS < landBurnS2 {
					set event to true.
				}
			} else {
				set event to true.
			}
			if ship:velocity:surface:mag < 75 and event = true {
				set VelThr_PID:setpoint to landBurnS2.
				Engine["Stop"](list(
					Merlin1D_1,
					Merlin1D_2
				)).
			} else {
				set VelThr_PID:setpoint to landBurnS.
			}
			
			set engThrust to (VelThr_PID:update(mT, verticalspeed)*100)/cos(vang(up:vector, ship:facing:forevector)).
			Engine["Throttle"](
			list(
				list(Merlin1D_0, engThrust),
				list(Merlin1D_1, landBurnThr),
				list(Merlin1D_2, landBurnThr)
			)).
			
			set DescLatitudeChange_PID:kp to max(5, min(60, 60-((altCur/1000)*4))).
			set DescLongitudeChange_PID:kp to max(5, min(60, 60-((altCur/1000)*4))).
			
			if tval = 0 {
				
				set posOffset to max(-500, min(500, lzDistImp:mag/2)).
				
				set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lat. // steering
				set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosFut:lat).
				set steerPitch to -DescLatitude_PID:update(mT, velLatImp).
				
				set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lng.
				set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosFut:lng).
				set steerYaw to -DescLongitude_PID:update(mT, velLngImp).
				
			} else {
				
				set posOffset to max(-200, min(200, lzDistImp:mag/2)).
				
				set LandLatitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lat.
				set LandLatitude_PID:setpoint to LandLatitudeChange_PID:update(mT, impPosFut:lat).
				set steerPitch to -LandLatitude_PID:update(mT, velLatImp).
				
				set LandLongitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lng.
				set LandLongitude_PID:setpoint to LandLongitudeChange_PID:update(mT, impPosFut:lng).
				set steerYaw to -LandLongitude_PID:update(mT, velLngImp).
				
			}
			
			if shipCurrentTWR() < 1.6 and ship:velocity:surface:mag > 120 {
				set steerPitch to -steerPitch.
				set steerYaw to -steerYaw.
			}
			
			if altCur < lzAlt + 20 or verticalspeed > 0 {
				set steer to up + r(0, 0, 90).
			} else {
				set steer to (-ship:velocity:surface):direction + r(steerPitch, steerYaw, 90).
			}
			
			if verticalspeed >= 0 {
				set runmode to 0.
				Engine["Stop"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				set tval to 0.
				set steer to up.
			}
		}
		
		// stuff that needs to update after every iteration
		if clearRequired {
			clearscreen.
			set clearRequired to false.
		}
		
		
		displayFlightData().
		if runmode < 4 {
			displayLaunchData().
		}
		
		if runmode >= 8 {
			
			set vec1 to vecdraw(ship:position, impPosFut:position, rgb(1,0,0), "Imp", 1, true).
			set vec2 to vecdraw(ship:position, posCur:position, rgb(0,1,0), "Pos", 1, true).
			set vec3 to vecdraw(ship:position, lzPos:position + landingOffset2, rgb(1,1,1), "LO2", 1, true).
		}
		
		if runmode >= 4 {
			print "Current Position:          " + round(longitude, 3) + ", " + round(latitude, 3) + "             " at (3,20).
			print "Impact Position:           " + round(impPosFut:lng, 3) + ", " + round(impPosFut:lat, 3) + "             " at (3,21).
			
			print "Impact Time:               " + round(impT, 2) + "     " at (3, 23).
			print "Impact Distance:           " + round(lzDistImp:mag, 2) + "          " at (3, 25).
			
			if runmode >= 9 {
			print "Position offset:           " + round(landingOffset2:mag, 2) + "           " at (3, 27).
			} else {
			print "Position offset:           " + round(posOffset, 2) + "           " at (3, 27).
			}
			print "Distance to LZ:            " + round(lzDistCur:mag, 2) + "           " at (3, 28).
			
			print "Steer Latitude:            " + round(steerPitch, 2) + "     " at (3, 30).
			print "Steer Longitude:           " + round(steerYaw, 2) + "     " at (3, 31).
			
			print "Latitude Velocity          " + round(velLatImp, 4) + "         " at (3, 33).
			print "Longitude Velocity         " + round(velLngImp, 4) + "         " at (3, 34).
		
			
		}
		print "Runmode:                   " + runmode + "     " at (3, 36).
		print "DeltaV remaining:          " + round(sepDeltaV) + "     " at (3, 37).
		print "PID loop KP:               " + round(DescLatitudeChange_PID:kp, 2) + "     " at (3, 38).
		
		if runmode = 9 {
			print "Time:                    " + round(landBurnT, 5) + "     " at (3, 42).
			
			print "Height:                   " + round(landBurnH, 5) + "     " at (3, 46).
			
			print "landBurnS:                " + round(landBurnS, 2) + "     " at (3, 48).
			print "landBurnS2:               " + round(landBurnS2, 2) + "     " at (3, 49).
		}
		
		// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
		
		set pT to mT.
		set posPrev to posCur.
		set impPosPrev to impPosFut.

		// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
		
		wait 0.
	}
	set vec1:show to false.
	set vec2:show to false.
	set vec3:show to false.
}

unlock all.