// Initialising the script
@lazyglobal off.
clearscreen.
set ship:control:pilotmainthrottle to 0.
wait 0.

// The below will make it possible to exit the program if errors occur
local once is false.
until once { // This loop will only work once and breaking it will end the program
set once to true.

function errorExit {
	parameter msg is "ERROR: AN ERROR HAS OCCURED".
	clearscreen.
	print msg at(3, 5).
	break.
}

// Setting up storage path and creating necessary directories
local libsDir is "1:/libs/".
local configDir is "1:/config/".
if not exists(libsDir) and not exists(configDir) {
	if not exists(libsDir) {
		createdir(libsDir).
	}
	if not exists(configDir) {
		createdir(configDir).
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
		local error is false.
		
		for lib in libs {
			if not exists("0:/libs/" + lib + ".ks") {
				set error to true.
			}
		}
		if error {
			errorExit("ERROR: A LIBRARY IS NOT AVAILBLE").
		}
		for lib in libs {
			copypath("0:/libs/" + lib + ".ks", libsDir).
		}
		for lib in libs {
			runpath(libsDir + lib + ".ks").
		}
	}

	libDl(libList).

	// Loading the config file
	if exists("0:/config/landing_config.json") {
		copypath("0:/config/landing_config.json", configDir).
	} else {
		errorExit("ERROR: A CONFIG FILE IS NOT AVAILBLE").
	}
}

// ---=== [**START**] [ DECLARING ALL NECESSARY VARIABLES ] [**START**] ===---

wait until ag10.

// Rocket systems
local runmode is 1.
local cpuName is core:tag.

// Ship positioning and velocity tracking
local posCur is 0.
local posPrev is ship:geoposition.
local altCur is 0.

local impPosPrev is ship:geoposition.
local impPosFut is ship:geoposition.
local lzDistCur is 0.
local lzDistImp is 0.

local velImp is 0.

local boosterDeltaV is 0.

// Offsets
local lzOffsetDist is 5000.
local lzBoosterOffset is 0.
local lzImpactOffset is 0.
local landingOffset is 0.

// Steering variables
local tval is 0.
local stable is false.

local steer is up.
local steerAngle is 0.

local rotCur is 0.

local engReady is true.
local engStartup is false.
local engThrust is 0.
	
// ---== PREPARING PID LOOPS ==--- //

// Throttle control
local AltVel_PID is pidloop(0.2, 0, 0.15, -600, 0.1).
local VelThr_PID is pidloop(2.1, 9, 0.15, 0.36, 1).

// Aerodynamic steering loops -------==================================<<<<<<<<<<<<<<< Gains need to be properly tuned
local AeroSteeringVel_PID is pidloop(20, 0, 5, 0, 100).
local AeroSteering_PID is pidloop(300, 1, 150, -10, 10).

// Powered steering loops -----------==================================<<<<<<<<<<<<<<< Gains need to be properly tuned
local PoweredSteeringVel_PID is pidloop(60, 0, 10, 0, 5).
local PoweredSteering_PID is pidloop(700, 0, 200, -5, 5).

// ---== END PID LOOPS ==--- //

// Time tracking
local sT is time:seconds. // Start of program time
local dT is 0. // Delta time
local mT is 0. // Mission elapsed time
local lT is 0. // Until/since launch
local pT is sT. // Previous tick time
local impT is 0.
local landBurnT is 0. // Landing burn time
local landBurnH is 0. // Landing burn height
local landBurnS is 0. // Landing burn speed target
local landBurnS2 is 0. // Landing burn speed target (touchdown)
local landBurnEngs is 0. // Number of ladning engines
local landBurnThr is 0.
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
local landing is readjson(configDir + "landing_config.json").
local lzPos is 0.
local lzAlt is 0.
local landingBurnDeltaV is 0.
local reentryBurnDeltaV is 0.
<<<<<<< HEAD
local reentryBurnThr is 60.
local flipDir is 0.
=======
local reentryBurnThr is 0.4.
>>>>>>> dev-rew-geo_to_vec

// Pattern tracking
local newValue is 0.
local oldValue is 0.

// ---=== [**END**] [ DECLARING ALL NECESSARY VARIABLES ] [**END**] ===---

// ---=== [**START**] [ GETTING NECESSARY DATA ] [**START**] ===---

if landing["landing"] { // Getting landing data
	for loc in landing["list_of_locations"] {
		if loc["name"] = landing["landing_location"] {
			set lzPos to latlng(loc["lat"], loc["lng"]).
			break.
		}
	}
	set landBurnEngs to landing["engines"].
	set landBurnThr to landing["throttle"].
	if lzPos = 0 {
		errorExit("ERROR: LANDING REQUIRED BUT NO LOCATION SELECTED").
	}
	set landingBurnDeltaV to (1/(landBurnThr + (landBurnEngs-1) * landBurnThr * 0.75) - 0.5) * 155 + 350. // Temporary formula
	tr:settarget(lzPos). // Setting target for Trajectories mod
	set lzAlt to lzPos:terrainheight.
	when (altCur - lzAlt) < 200 and runmode > 2 then { gear on. } // Setting trigger for landing legs
}

// Check if lift-off time has been provided by Pegas
when not ship:messages:empty then {
	local msg is ship:messages:peek:content.
	if msg:haskey("liftoffTime") {
		set lT to msg["liftoffTime"].
	}
}

// ---=== [**END**] [ GETTING NECESSARY DATA ] [**END**] ===---

if landing["landing"] { // If landing is required then proceed with the program otherwise end
	
	wait 0. // Waiting 1 physics tick so that everything updates

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

		set rotCur to list(pitch_for(ship), compass_for(ship), rollConvert()).
		set posCur to ship:geoposition.
		
		set impT to timeToAltitude(lzAlt, altCur). // Time to altitude, needs to be changed in the atmosphere
		
		if tr:hasimpact {
			set impPosFut to tr:impactpos.
		}

		set velImp to (impPosFut:altitudeposition(lzAlt) - impPosPrev:altitudeposition(lzAlt))/dT.
		
		set lzDistCur to lzPos:position - ship:geoposition:altitudeposition(lzAlt). // Vector from ship to LZ
		set lzDistImp to lzPos:position - impPosFut:altitudeposition(lzAlt). // Vector from impact point to LZ
		set boosterDeltaV to Fuel["Stage 1 DeltaV"]().
		
		set lzBoosterOffset to vxcl(lzDistCur - body:position, lzDistCur):normalized * lzOffsetDist. // Flattened and sized <lzDistCur>
		set lzImpactOffset to vxcl(lzDistImp - body:position, lzDistImp):normalized * lzOffsetDist. // Flattened and sized <lzDistImp>
		// Changing the offset logic [Will need testing]
		set landingOffset to lzPos:position + lzBoosterOffset - impPosFut:altitudeposition(lzAlt). // Pos behind the LZ to aim at during descent
		
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
			set landBurnS2 to ((1/max(0.01, altCur - lzAlt)^0.25 * ((altCur - lzAlt) * 1.5))* -1) -1. // Formula that makes the booster touch down gently at minimum thrust
		}
		
		// [<<IDEA>>] - Might move all the runmodes to a separate file and just load it here
		// Main logic
		
		if runmode = 1 // Wait until separation
		{
			set newValue to landingOffset:mag. // Tracking changes in distance to target position
			if mT - lT > 20 {
				if landing["boostback"] {
					// Get required deltaV at separation, landing deltaV + reentry deltaV + boostback deltaV
					local deltaVatSep is landingBurnDeltaV + (ship:velocity:surface:mag/4) + (groundspeed * 1.4).

					if deltaVatSep > boosterDeltaV {
						set runmode to 1.1.
					}
				} else {
					// No-boostback separation code

					// This will need to be developed, may be necessary to modify the launch script to make sure it will fly close enough to the ASDS, a temporary solution below
					if newValue > oldValue {
						set runmode to 1.1.
					}
				}
			}
		}
		else if runmode = 1.1 // Send separation request to launch script
		{			
			local msg is lexicon("stagingTime", mT - lT).
			if processor("Falcon9S2"):connection:sendmessage(msg) {
				wait 0.
				set runmode to 1.2.
			}
		}
		else if runmode = 1.2 // Take control of booster after separation
		{
			lock throttle to max(0, min(1, tval)).
			set eventTime to mT + 2.
			set clearRequired to true.
			if landing["boostback"] {
				set runmode to 2. // Go to boostback
			} else {
				set runmode to 3. // Skip boostback and go straight to reentry
			}
		}
		else if runmode = 2 // Stabilizing and reorienting for boostback burn [optional]
		{
			if mT > eventTime {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip(16).
				}
				if rotCur[0] > 75 {
					set runmode to 2.1.
				}
			} else {
				stabilize().
			}
		}
		else if runmode = 2.1 // Reorienting and proceeding to boostback
		{
			if rotCur[0] < 60 {
				set ship:control:neutralize to true.
				set stable to false.
				set steer to lzImpactOffset.
				lock steering to steer.
				set engStartup to true.
				set eventTime to mT + 2.
				Engine["Throttle"](list(
					list(Merlin1D_0, 100),
					list(Merlin1D_1, 100),
					list(Merlin1D_2, 100)
				)).
				set runmode to 2.2.
			} else {
				if stable = false {
					if stabilize() = true {
						set stable to true.
					}
				} else {
					startFlip(16).
				}
			}
		}
		else if runmode = 2.2 // Boostback burn
		{
			// The below values need reviewing
			set steeringmanager:maxstoppingtime to 2.
			set steeringmanager:rolltorquefactor to 3.

			set newValue to landingOffset:mag. // Tracking changes in distance to target position

			set tval to 1.
			
			if engStartup or mT > eventTime { // Start the engines (center first then two side engines)
				if mT > eventTime {
					Engine["Start"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set engStartup to false.
				} else {
					Engine["Start"](list(
						Merlin1D_0
					)).
					set engStartup to false
					set eventTime to mT + 2.
				}
			}

			if ullageReq { // If ullage is required, switch RCS on and thrust forward until fuel is settled
				rcs on.
				set ship:control:fore to 1.
				set engStartup to true. // Keep trying to start the engines
			} else {
				rcs off.
				set ship:control:fore to 0.
				set engStartup to false.
			}

			if landingOffset:mag > lzOffsetDist * 3 { // If far from target position point in its direction
				set steer to landingOffset.
			} else {
				if newValue > oldValue { // If went past the target position
					Engine["Stop"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set tval to 0.
					unlock steering.
					set runmode to 3. 
				} else { // If close to the target position stop 2 engines and adjust throttle of center engine
					Engine["Stop"](list(
						Merlin1D_1,
						Merlin1D_2
					)).
					set Merlin1D_1:gimbal:lock to true.
					set Merlin1D_2:gimbal:lock to true.
					set Merlin1D_3:gimbal:lock to true.
					set Merlin1D_4:gimbal:lock to true.
					set Merlin1D_5:gimbal:lock to true.
					set Merlin1D_6:gimbal:lock to true.
					set Merlin1D_7:gimbal:lock to true.
					set Merlin1D_8:gimbal:lock to true.
					Engine["Throttle"](list(
						list(Merlin1D_0, max(36, min(100, landingOffset:mag/(lzOffsetDist*0.03) )))
					)).
				}
			}
		}
		else if runmode = 3 // Reorienting for reentry
		{
			rcs on.
			stabilize().
			set eventTime to mT + 3.
			set runmode to 3.1.
			set clearRequired to true.
		}
		else if runmode = 3.1
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
					set runmode to 3.2.
				}
			} else {
				stabilize().
			}
		}
		else if runmode = 3.2
		{
			if rotCur[0] < 60 {
				set ship:control:neutralize to true.
				set stable to false.
				set steeringmanager:maxstoppingtime to 0.5. // Steer very gently to save RCS fuel
				lock steering to steer.
				set steer to -ship:velocity:surface.
				set engStartup to true.
				set eventTime to mT + 600.
				getReentryAngle("new").
				set runmode to 3.3.
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
		else if runmode = 3.3 // Reentry burn
		{
			if reentryBurnDeltaV = 0 {
				local landingDeltaV is (1/(landBurnThr + (landBurnEngs-1) * landBurnThr * 0.75) - 0.5) * 155 + 350. // Temporary formula
				set reentryBurnDeltaV to boosterDeltaV - landingDeltaV.
				if landing["boostback"] {
					set lzOffsetDist to 500.
				} else {
					set lzOffsetDist to 1000.
				}
			}

			if (nd:eta < 0 and engStartup) or mT > eventTime { // Start the engines (center first then two side engines)
				if mT > eventTime {
					Engine["Start"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set engStartup to false.
				} else {
					Engine["Start"](list(
						Merlin1D_0
					)).
					set engStartup to false
				}
			}

			if ullageReq { // If ullage is required, switch RCS on and thrust forward until fuel is settled
				rcs on.
				set ship:control:fore to 1.
				set engStartup to true. // Keep trying to start the engines
			} else {
				rcs off.
				set ship:control:fore to 0.
				set engStartup to false.
			}
			
			if reentryAngle["fou"] {
				set steer to nd:deltav.
				set eventTime to mT + nd:eta + 2.
				if nd:eta < 0 { // If time for reentry, start the engines
					set tval to 1.
					if (nd:deltav:mag-100) > 64 {
						Engine["Throttle"](list(
							list(Merlin1D_0, reentryBurnThr),
							list(Merlin1D_1, reentryBurnThr),
							list(Merlin1D_2, reentryBurnThr)
						)).
					} else { // If less than 64m/s maneuver deltav remaining, use only 1 engine
						Engine["Stop"](list(
							Merlin1D_1,
							Merlin1D_2
						)).
						Engine["Throttle"](list( // Gradually lower the throttle once burn almost complete
							list(Merlin1D_0, max(36, min(reentryBurnThr, nd:deltav:mag-64)))
						)).
						if (nd:deltav:mag-100) < 0 { // Reentry burn complete
							Engine["Stop"](list(
								Merlin1D_0,
								Merlin1D_1,
								Merlin1D_2
							)).
							set tval to 0.
							remove nd.
							set runmode to 4.
						}
					}
				}
			} else {
				set steer to -ship:velocity:surface.
				if DragForce() > 1 { // Once drag has at least 1kN of force, create a meneuver node with eta of 15 secods
					getReentryAngle().
				}
			}
			
			if shipCurrentTWR() > 0.1 {
				rcs off.
			} else {
				rcs on.
			}
		}
		else if runmode = 8
		{
			set steer to -ship:velocity:surface.
			if altCur < 45000
			{
				set runmode to 9.
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
			
			// This will need to be revised
			set AeroSteeringVel_PID:kp to max(5, min(60, 60-((altCur/1000)*4))).

			if shipCurrentTWR() < 1.6 and ship:velocity:surface:mag > 120 {

				set lzOffsetDist to max(0, min(500, lzDistImp:mag/2)).

				set AeroSteeringVel_PID:setpoint to 0.
				set AeroSteering_PID:setpoint to AeroSteeringVel_PID:update(mT, landingOffset:mag).
				set steerAngle to AeroSteering_PID:update(mT, velImp:mag). // This velocity may not be very useful (can be different direction) but will test it to check

			} else {
				
				set lzOffsetDist to max(0, min(50, lzDistImp:mag/2)).
				
				set PoweredSteeringVel_PID:setpoint to 0.
				set PoweredSteering_PID:setpoint to PoweredSteeringVel_PID:update(mT, landingOffset:mag).
				set steerAngle to PoweredSteering_PID:update(mT, velImp:mag).
				
			}

			if altCur < lzAlt + 20 or verticalspeed > 0 {
				set steer to up.
			} else {
				// May need to tweak this in the future
				if shipCurrentTWR() < 1.6 and ship:velocity:surface:mag > 120 { // If TWR over 1.6 or speed below 120m/s then engines have more steering power than aerodynamics
					set lzImpactOffset to -lzImpactOffset. // If aerodynamics have more steering power, reverse the steering
				}
				set steer to ship:srfretrograde * angleaxis(steerAngle, lzImpactOffset). // Not sure if this will work correctly, needs testing
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
			set vec3 to vecdraw(ship:position, lzPos:position + landingOffset, rgb(1,1,1), "LO2", 1, true).
		}
		
		if runmode >= 4 {
			print "Current Position:          " + round(longitude, 3) + ", " + round(latitude, 3) + "             " at (3,20).
			print "Impact Position:           " + round(impPosFut:lng, 3) + ", " + round(impPosFut:lat, 3) + "             " at (3,21).
			
			print "Impact Time:               " + round(impT, 2) + "     " at (3, 23).
			print "Impact Distance:           " + round(lzDistImp:mag, 2) + "          " at (3, 25).
			
			if runmode >= 9 {
			print "Position offset:           " + round(landingOffset:mag, 2) + "           " at (3, 27).
			} else {
			print "LZ offset distance:        " + round(lzOffsetDist, 2) + "           " at (3, 27).
			}
			print "Distance to LZ:            " + round(lzDistCur:mag, 2) + "           " at (3, 28).
			
			print "Steering Angle:            " + round(steerAngle, 1) + "     " at (3, 30).
			
			print "Impact Velocity            " + round(velImp:mag, 1) + "         " at (3, 33).
		
			
		}
		print "Runmode:                   " + runmode + "     " at (3, 36).
		print "DeltaV remaining:          " + round(boosterDeltaV) + "     " at (3, 37).
		print "PID loop KP:               " + round(DescLatitudeChange_PID:kp, 2) + "     " at (3, 38).
		
		if runmode = 9 {
			print "Time:                    " + round(landBurnT, 5) + "     " at (3, 42).
			
			print "Height:                   " + round(landBurnH, 5) + "     " at (3, 46).
			
			print "landBurnS:                " + round(landBurnS, 2) + "     " at (3, 48).
			print "landBurnS2:               " + round(landBurnS2, 2) + "     " at (3, 49).
		}
		
		// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
		
		set pT to mT.
		set impPosPrev to impPosFut.
		set oldValue to newValue.

		// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
		
		wait 0.
	}
	set vec1:show to false.
	set vec2:show to false.
	set vec3:show to false.
}

unlock all.
}