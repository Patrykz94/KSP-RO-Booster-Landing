CLEARSCREEN.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

//	If necessary, print an error message and crash the program by trying to use undefined variables.
FUNCTION ForceCrash {
	PARAMETER msg.
	CLEARSCREEN.
	PRINT " ".
	PRINT "ERROR!".
	PRINT " ".
	PRINT msg.
	PRINT " ".
	PRINT "Crashing...".
	PRINT " ".
	LOCAL error IS undefinedVariable.
}

IF NOT ADDONS:TR:AVAILABLE {
	ForceCrash("Trajectories mod not found. Please install Trajectories and try again.").
}

//	Loading libraries
RUNPATH("1:/landing.ks").
RUNPATH("1:/recovery_utils.ks").
RUNPATH("1:/aero_functions.ks").
RUNPATH("1:/lib_navball.ks").

//	Declare variables
LOCAL runmode IS 1.
LOCAL currentPosition IS 0.
LOCAL currentAltitude IS 0.
LOCAL impactPosition IS 0.
LOCAL impactVelcity IS 0.	//	Velocity of impact point, not booster velocity at impact
LOCAL lzImpactDistance IS 0.
LOCAL lzCurrentDistance IS 0.
LOCAL lzPosition IS 0.
LOCAL lzAltitude IS 0.
LOCAL boosterDeltaV IS 0.
LOCAL TR IS ADDONS:TR.
//	Offsets
LOCAL lzOffsetDistance IS 3000.
LOCAL lzBoosterOffset IS 0.
LOCAL lzImpactOffset IS 0.
LOCAL landingOffset IS 0.
//	Steering variables
LOCAL tval IS 0.
LOCAL steer IS up.
LOCAL steerAngle IS 0.
//	Engine variables
LOCAL engineReady IS FALSE.
LOCAL engineStartup IS FALSE.
LOCAL engineThrust IS 0.
LOCAL stable IS FALSE.
//	Time tracking variables
LOCAL dT IS 0.				//	Delta time
LOCAL mT IS TIME:SECONDS.	//	Current time
LOCAL lT IS 0.				//	Until/since launch
LOCAL pT IS 0.				//	Previous tick time
LOCAL eventTime IS 0.
LOCAL event IS FALSE.
//	Landing burn variables
LOCAL impactTime IS 0.
//	Landing parameters
LOCAL reentryBurnDeltaV IS 0.
LOCAL flipDirection IS 0.
LOCAL flipSpeed IS 24.
LOCAL partCount IS 0. // Used to determine if upper stage has separated already
//	Messaging variables
LOCAL lastResponse IS LEXICON("data", LEXICON()).
//	Vectors to be displayed
LOCAL vec1 IS 0.
LOCAL vec2 IS 0.
LOCAL vec3 IS 0.
//	Other variables
LOCAL clearRequired IS FALSE.
LOCAL bodyRotation IS 360 / BODY:ROTATIONPERIOD.
//	Change-tracking variables
LOCAL previousPosition IS SHIP:GEOPOSITION.
LOCAL previousImpactPosition IS SHIP:GEOPOSITION.
LOCAL currentValues IS LEXICON().
LOCAL previousValues IS LEXICON().
//	Throttle control
LOCAL AltVel_PID IS PIDLOOP(0.2, 0, 0.15, -600, 0.1).
LOCAL VelThr_PID IS PIDLOOP(2.1, 9, 0.15, 0.36, 1).
//	Aerodynamic steering loops
LOCAL AeroSteeringVel_PID IS PIDLOOP(20, 0, 5, 0, 100).
LOCAL AeroSteering_PID IS PIDLOOP(300, 1, 150, -10, 10).
//	Powered steering loops
LOCAL PoweredSteeringVel_PID IS PIDLOOP(60, 0, 10, 0, 5).
LOCAL PoweredSteering_PID IS PIDLOOP(700, 0, 200, -5, 5).

//	Setting things up
SET TERMINAL:WIDTH TO 60.
SET TERMINAL:HEIGHT TO 50.

//	Landing setup
IF landing["required"] {
	IF landing["listOfLocations"]:HASKEY(landing["location"]) { SET lzPosition TO landing["listOfLocations"][landing["location"]]. }
	ELSE { ForceCrash("Landing location not found. Please make sure the spceified location has been added to list of locations."). }
	CalculateLandingBurn(50).	//	Calculate the landing burn details iteratively
	TR:SETTARGET(lzPosition).	//	Setting target for Trajectories mod
	SET lzAltitude TO lzPosition:TERRAINHEIGHT.
}

//	Request a lift-off time from PEGAS
IF SendMessage("request", "liftoffTime") {
	WHEN lastResponse:LENGTH > 0 THEN {
		IF NOT lastResponse["data"]:ISTYPE("String") { SET lT TO lastResponse["data"]["liftoffTime"] }
		ELSE { ForceCrash(lastResponse["data"]). }
		WHEN mT > lT - 15 THEN { AG9 ON. }
	}
} ELSE {
	ForceCrash("Failed to send a message. Check message receiver and try again.").
}

//	A wrapper function that calls all other functions and 
FUNCTION Main {
	UpdateVars().//To be finished...
}

//	Waiting 1 physics tick so that everything updates
WAIT 0.

until runmode = 0 {
	
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
		if mT - lT > 20 {
			if landing["boostback"] {
				// Get required deltaV at separation, landing deltaV + reentry deltaV + boostback deltaV
				LOCAL deltaVatSep IS landingBurnDeltaV + (ship:velocity:surface:mag/4) + (groundspeed * 1.4).
				if deltaVatSep > boosterDeltaV - 60 and newValue[0] = 0 {
					sendMessage("command", list("engineShutdown",
						"Merlin1D-1", "Merlin1D-2", "Merlin1D-3", "Merlin1D-4", "Merlin1D-5", "Merlin1D-6", "Merlin1D-7", "Merlin1D-8"
					)).
					set newValue[0] to 1.
				}
				if deltaVatSep > boosterDeltaV - 12 and newValue[0] = 1 { sendMessage("command", list("setThrottle", 0.6, 0.36)). set newValue[0] to 2. }
				if deltaVatSep > boosterDeltaV - 6 and newValue[0] = 2 { sendMessage("command", list("setThrottle", 0.45, 0.36)). set newValue[0] to 3. }
				if deltaVatSep > boosterDeltaV - 2 and newValue[0] = 3 { sendMessage("command", list("setThrottle", 0.36, 0.36)). set newValue[0] to 4. }
				if deltaVatSep > boosterDeltaV and newValue[0] = 4 {
					LOCAL p IS list().
					list parts in p.
					set partCount to p:length.
					set runmode to 1.1.
				}
			} else {
				// No-boostback separation code
				set newValue[0] to landingOffset:mag.
				// This will need to be developed
				if newValue[0] > oldValue[0] {
					LOCAL p IS list().
					list parts in p.
					set partCount to p:length.
					set runmode to 1.1.
				}
			}
		} else {
			if landing["boostback"] {
				set newValue[0] to 0.
			} else {
				set newValue[0] to landingOffset:mag. // Tracking changes in distance to target position
			}
		}
	}
	else if runmode = 1.1 // Send separation request to launch script
	{			
		if sendMessage("command", list(list("engineShutdown", "Merlin1D-0"), list("setThrottle", 1, 0.36), list("setUpfgTime"))) {
			set runmode to 1.2.
		}
	}
	else if runmode = 1.2 // Take control of booster after separation
	{
		LOCAL p IS list().
		list parts in p.
		if p:length <> partCount {
			wait 0.
			SET CONFIG:IPU TO 2000.
			lock throttle to max(0, min(1, tval)).
			set eventTime to mT + 3.
			set clearRequired to true.
			rcs on.
			if landing["boostback"] {
				set runmode to 2. // Go to boostback
			} else {
				set runmode to 3. // Skip boostback and go straight to reentry
				set flipDir to 180.
			}
		}
	}
	else if runmode = 2 // Stabilizing and reorienting for boostback burn [optional]
	{
		if mT > eventTime {
			if stable = false {
				if stabilize(flipDir) = true {
					set stable to true.
				}
			} else {
				startFlip(24, flipDir).
			}
			if rotCur[0] > 75 {
				set runmode to 2.1.
			}
		} else {
			stabilize(flipDir).
		}
	}
	else if runmode = 2.1 // Reorienting and proceeding to boostback
	{
		if rotCur[0] < 75 {
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
				if stabilize(flipDir) = true {
					set stable to true.
				}
			} else {
				startFlip(24).
			}
		}
	}
	else if runmode = 2.2 // Boostback burn
	{
		// The below values need reviewing
		set steeringmanager:maxstoppingtime to 1.
		set steeringmanager:rolltorquefactor to 2.

		set newValue[0] to landingOffset:mag. // Tracking changes in distance to target position
		set newValue[1] to oldValue[0].

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
				set engStartup to false.
				set eventTime to mT + 2.
			}
		}

		if ullageReq { // If ullage IS required, switch RCS on and thrust forward until fuel IS settled
			rcs on.
			set ship:control:fore to 1.
			set engStartup to true. // Keep trying to start the engines
		} else {
			rcs off.
			set ship:control:fore to 0.
			set engStartup to false.
		}

		if landingOffset:mag > lzOffsetDist * 3 { // If far from target position point in its direction
			set steer to lookdirup(landingOffset, body:position).
		} else {
			if (newValue[0] + newValue[1])/2 > (oldValue[0] + oldValue[1])/2 { // If went past the target position
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
		stabilize(flipDir - 180).
		set eventTime to mT + 5.
		set runmode to 3.1.
		set clearRequired to true.
	}
	else if runmode = 3.1
	{
		if mT > eventTime {
			if stable = false {
				if stabilize(flipDir - 180) = true {
					set stable to true.
				}
			} else {
				startFlip(1.5, flipDir - 180).
			}
			if rotCur[0] > 80 {
				ag5 on.
				set runmode to 3.2.
			}
		} else {
			stabilize(flipDir - 180).
		}
	}
	else if runmode = 3.2
	{
		print "rotCur:    " + round(rotCur[0], 2) + "        " at(3, 40).
		print "vang:      " + round(90-vang(ship:up:vector, -ship:velocity:surface), 2) + "        " at(3, 41).
		if rotCur[0] < 90-vang(ship:up:vector, -ship:velocity:surface) {
			set ship:control:neutralize to true.
			set stable to false.
			set steeringmanager:rollts to 15.
			set steeringmanager:pitchts to 10.
			set steeringmanager:yawts to 15.
			set steeringmanager:maxstoppingtime to 0.2. // Steer very gently to save RCS fuel
			lock steering to steer.
			set steer to lookdirup(-ship:velocity:surface, ship:facing:topvector).
			set engStartup to true.
			set eventTime to mT + 600.
			if landing["boostback"] {
				set lzOffsetDist to 500.
			} else {
				set lzOffsetDist to 1000.
			}
			getReentryAngle("new").
			when DragForce() > 0.9 then {
				set nd:eta to 25.
			}
			set runmode to 3.3.
		} else {
			if stable = false {
				if stabilize(flipDir - 180) = true {
					set stable to true.
				}
			} else {
				startFlip(1.5, flipDir - 180).
			}
		}
	}
	else if runmode = 3.3 // Reentry burn
	{
		if reentryBurnDeltaV = 0 {
			set reentryBurnDeltaV to boosterDeltaV - landingBurnDeltaV.
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
				set engStartup to false.
			}
		}

		if ullageReq { // If ullage IS required, switch RCS on and thrust forward until fuel IS settled
			rcs on.
			set ship:control:fore to 1.
			set engStartup to true. // Keep trying to start the engines
		} else {
			rcs off.
			set ship:control:fore to 0.
			set engStartup to false.
		}
		
		if reentryAngle["fou"] {
			set steer to lookdirup(nd:deltav, ship:facing:topvector).
			set eventTime to mT + nd:eta + 2.
			if nd:eta < 0 { // If time for reentry, start the engines
				set steeringmanager:maxstoppingtime to 2.
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
						set runmode to 8. // Will need to change this number
					}
				}
			}
		} else {
			set steer to lookdirup(-ship:velocity:surface, ship:facing:topvector).
			if vang(-ship:velocity:surface, ship:facing:forevector) < 1.5 { rcs off.} else { rcs on. }
			if DragForce() > 1 { getReentryAngle(). } // Once drag has at least 1kN of force, create a meneuver node with eta of 25 secods
		}
		
		if shipCurrentTWR() > 0.5 {
			rcs off.
		} else if nd:eta < 5 {
			rcs on.
		}
	}
	else if runmode = 8
	{
		set steer to lookdirup(-ship:velocity:surface, ship:facing:topvector).
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
			set steer to lookdirup(rodrigues(-ship:velocity:surface, getNormal(lzImpactOffset, ship:position), steerAngle), ship:facing:topvector).
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
	
	if runmode >= 8 {
		
		set vec1 to vecdraw(ship:position, impPosFut:position, rgb(1,0,0), "Imp", 1, true).
		set vec2 to vecdraw(ship:position, posCur:position, rgb(0,1,0), "Pos", 1, true).
		set vec3 to vecdraw(ship:position, lzPos:position + landingOffset, rgb(1,1,1), "LO2", 1, true).
	}

	//Title bar
	print "------------------- Flight Display 1.0 --------------------"						at (1, 1).
	print "Launch Time:             T" + round(mT - lT) + "               "					at (3, 2).

	print "Runmode:                   " + runmode + "     "									at (3, 4).
	print "DeltaV remaining:          " + round(boosterDeltaV) + "     "					at (3, 5).

	print "Drag Force:                " + round(DragForce(),3) + "     "					at (3, 7).
	print "Terminal Velocity:         " + round(TermVel(ship:altitude),2) + "     "			at (3, 8).
	
	print "Impact Time:               " + round(impT, 2) + "     "							at (3, 10).
	print "Impact Distance:           " + round(lzDistImp:mag, 2) + "          " 			at (3, 11).
	
	print "Landing offset:            " + round(landingOffset:mag, 2) + "           " 		at (3, 13).
	print "LZ offset distance:        " + round(lzOffsetDist, 2) + "           " 			at (3, 14).
	print "Distance to LZ:            " + round(lzDistCur:mag, 2) + "           " 			at (3, 15).
	
	print "Steering Angle:            " + round(steerAngle, 1) + "     "					at (3, 17).
	
	print "Impact Velocity            " + round(velImp:mag, 1) + "         "				at (3, 19).

	print "Landing DeltaV:            " + round(landingBurnDeltaV, 1) + "        "			at (3, 21).
	
	if runmode = 3.3 {
	print "Reentry DeltaV:            " + round(reentryBurnDeltaV, 1) + "     "				at (3, 22).

	print "ID:	       " + reentryAngle["id"] + "          " 	at (3, 24).
	print "Dist:	   " + round(reentryAngle["dist"],1) + "          "	at (3, 25).
	print "Best Dist:  " + round(reentryAngle["bestD"],1) + "          " at (3, 26).
	print "Angle:	   " + reentryAngle["ang"] + "           " 	at (3, 27).
	print "Increment:  " + reentryAngle["inc"] + "           " 	at (3, 28).
	print "Found?:	   " + reentryAngle["fou"] + "           " 	at (3, 29).

	print "Node Prograde: " + round(nd:prograde,1) + "                   " 	at (3, 31).
	print "Node Normal:   " + round(nd:normal,1) + "                   " 	at (3, 32).
	print "Node Radial:   " + round(nd:radialout,1) + "                   " 	at (3, 33).
	}

	if runmode = 9 {
	print "Time:                    " + round(landBurnT, 5) + "     "					at (3, 30).
		
	print "Height:                   " + round(landBurnH, 5) + "     "					at (3, 32).
		
	print "landBurnS:                " + round(landBurnS, 2) + "     "					at (3, 34).
	print "landBurnS2:               " + round(landBurnS2, 2) + "     "					at (3, 35).
	}
	
	// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
	
	set pT to mT.
	set impPosPrev to impPosFut.
	set oldValue[0] to newValue[0].
	set oldValue[1] to newValue[1].
	set oldValue[2] to newValue[2].
	set oldValue[3] to newValue[3].

	// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
	
	wait 0.
}
set vec1:show to false.
set vec2:show to false.
set vec3:show to false.

unlock all.