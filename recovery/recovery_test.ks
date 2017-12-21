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

//	Loading libraries and configs
FOR f IN OPEN("1:/config"):LIST:VALUES {
	RUNONCEPATH(f).
}

RUNPATH("1:/recovery_utils.ks").
RUNPATH("1:/aero_functions.ks").
RUNPATH("1:/lib_navball.ks").

//	Declare variables
LOCAL runmode IS 0.		//	Pre-launch
LOCAL subRunmode IS 0.
LOCAL currentPosition IS SHIP:GEOPOSITION.
LOCAL currentAltitude IS 0.
LOCAL impactPosition IS SHIP:GEOPOSITION.
LOCAL impactVelocity IS LIST(V(0,0,0), V(0,0,0), V(0,0,0), V(0,0,0), V(0,0,0)).	//	Velocity of impact point, not booster velocity at impact
LOCAL impactVelocityAvg IS V(0,0,0).
LOCAL lzImpactDistance IS V(0,0,0).
LOCAL lzCurrentDistance IS V(0,0,0).
LOCAL launchSiteDistance IS V(0,0,0).
LOCAL lzPosition IS V(0,0,0).
LOCAL lzAltitude IS 0.
LOCAL boosterDeltaV IS 0.
LOCAL TR IS ADDONS:TR.
//	Offsets
LOCAL lzOffsetDistance IS 3000.
LOCAL lzBoosterOffset IS V(0,0,0).
LOCAL lzImpactOffset IS V(0,0,0).
LOCAL landingOffset IS V(0,0,0).
//	Steering variables
LOCAL tval IS 0.
LOCAL throttleLimit IS 1.
LOCAL steer IS up.
LOCAL steerAngle IS 0.
LOCAL steerAngleMultiplier IS 1.
//	Engine variables
LOCAL engineReady IS FALSE.
LOCAL engineStartup IS FALSE.
LOCAL engineThrottle IS LIST(1,1,1).
LOCAL engineThrottleAvg IS 1.
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
LOCAL landingParam IS 0.
LOCAL landingSpeed IS 0.
//	Landing parameters
LOCAL reentryBurnDeltaV IS 0.
LOCAL flipDirection IS 0.
LOCAL flipSpeed IS 24.
LOCAL partCount IS 0. // Used to determine if upper stage has separated already
//	Messaging variables
LOCAL lastResponse IS LEXICON().
//	Vectors to be displayed
LOCAL vec1 IS 0.
LOCAL vec2 IS 0.
LOCAL vec3 IS 0.
LOCAL vec4 IS 0.
//	Other variables
LOCAL bodyRotation IS 360 / BODY:ROTATIONPERIOD.
//	Change-tracking variables
LOCAL previousPosition IS SHIP:GEOPOSITION.
LOCAL previousImpactPosition IS SHIP:GEOPOSITION.
LOCAL temporaryValues IS LEXICON().
//	Throttle control
LOCAL VelThr_PID IS PIDLOOP(2.1, 9, 0.15, vehicle["engines"]["minThrottle"], 1).
//	Aerodynamic steering loops
LOCAL AeroSteeringVel_PID IS PIDLOOP(0.2, 0, 0.1, -100, 100).
//	Powered steering loops
LOCAL PoweredSteeringVel_PID IS PIDLOOP(0.1, 0, 0.05, -5, 5).

//	Setting up UI
LOCAL UILex IS LEXICON("time", LIST(), "message", LIST()).
LOCAL UILexLength IS 0.
CreateUI().

//	Landing setup
IF landing["required"] {
	SET lzPosition TO landing["location"].
	TR:SETTARGET(lzPosition).	//	Setting target for Trajectories mod
	SET lzAltitude TO lzPosition:TERRAINHEIGHT.
	CalculateLandingBurn(50).	//	Calculate the landing burn details iteratively
	SET landingParam TO landingBurnData["speed"]:LENGTH-1.
}

//	A wrapper function that calls all other functions
FUNCTION Main {
	UpdateVars("start").
	IF 		runmode = 0 { Prelaunch().	}
	ELSE IF runmode = 1 { Launch().		}
	ELSE IF runmode = 2 { Recovery().	}
	RefreshUI().
	UpdateVars("end").
	IF runmode = 3 { RETURN TRUE. } ELSE { RETURN FALSE. }
}

//	Updating varibales before and after every iteration
FUNCTION UpdateVars {
	PARAMETER type.

	IF type = "start" {
		SET mT TO TIME:SECONDS.
		SET dT TO mT - pT.
		SET currentAltitude TO BODY:ALTITUDEOF(SHIP:PARTSTAGGED(vehicle["bottomPart"]["name"])[0]:position) - vehicle["bottomPart"]["heightOffset"].
		SET currentPosition to SHIP:GEOPOSITION.
		SET impactTime to timeToAltitude(lzAltitude, currentAltitude).
		IF TR:HASIMPACT { SET impactPosition TO TR:IMPACTPOS. }	//	Need to test if else condition is needed
		SET impactVelocity[4] TO impactVelocity[3]. SET impactVelocity[3] TO impactVelocity[2]. SET impactVelocity[2] TO impactVelocity[1]. SET impactVelocity[1] TO impactVelocity[0].
		SET impactVelocity[0] TO (impactPosition:ALTITUDEPOSITION(lzAltitude) - previousImpactPosition:ALTITUDEPOSITION(lzAltitude))/dT.	//	Not precise at all. Needs attention
		SET impactVelocityAvg TO (impactVelocity[0] + impactVelocity[0] + impactVelocity[0] + impactVelocity[0] + impactVelocity[0])/5.
		SET lzCurrentDistance TO lzPosition:POSITION - SHIP:GEOPOSITION:ALTITUDEPOSITION(lzAltitude).	//	Ship -> LZ
		SET lzImpactDistance TO lzPosition:POSITION - impactPosition:ALTITUDEPOSITION(lzAltitude).		//	Impact point -> LZ
		SET boosterDeltaV TO Booster("deltaV").
		SET lzBoosterOffset TO VXCL(lzCurrentDistance - BODY:POSITION, lzCurrentDistance):NORMALIZED * lzOffsetDistance.	//	Flattened and sized <lzCurrentDistance>
		SET lzImpactOffset TO VXCL(lzImpactDistance - BODY:POSITION, lzImpactDistance):NORMALIZED * lzOffsetDistance.		//	Flattened and sized <lzImpactDistance>
		SET landingOffset TO lzPosition:POSITION + lzBoosterOffset - impactPosition:ALTITUDEPOSITION(lzAltitude).			//	Pos behind the LZ to aim at during descent
		SET launchSiteDistance TO (landing["launchLocation"]:POSITION - SHIP:GEOPOSITION:ALTITUDEPOSITION(lzAltitude)):MAG.	//	Downrange distance
	} ELSE IF type = "end" {
		SET pT TO mT.
		SET previousImpactPosition TO impactPosition.
	}
}

//	Handles things that happen before launch
FUNCTION Prelaunch {
	IF subRunmode = 0 {	//	Wait for response and update lift-off time
			CORE:PART:CONTROLFROM().
			SET CONFIG:IPU TO 2000.
			SET lT TO mT + 5.
			SET subRunmode TO 1.
	} ELSE IF subRunmode = 1 {	//	Move strongback at T-15s and go into launch mode
		IF mT > lT - 10 { SET subRunmode TO 2. Engines("gimbal", Engines("outerEngines"), FALSE). }
	} ELSE IF subRunmode = 2 {
		IF mT > lT - 3 { SET subRunmode TO 3. STAGE. LOCK THROTTLE TO tval. LOCK STEERING TO UP. SET tval TO 1. }
	} ELSE IF subRunmode = 3 {
		IF mT > lT { SET runmode TO 1. SET subRunmode TO 0. STAGE. }
	}
}

//	Handles things that happen during launch
FUNCTION Launch {
	IF ShipTWR() > 0 {
		SET throttleLimit TO MIN(1, MAX(vehicle["engines"]["minThrottle"], 1.2/ShipTWR())).
		Engines("throttle", Engines("centerEngines"), throttleLimit).
	}

	IF subRunmode = 0 {
		LOCAL shutdownCondition IS FALSE.
		LOCAL deltaVatSep IS landingBurnData["dvSpent"].
		SET shutdownCondition TO { RETURN deltaVatSep > boosterDeltaV - 30. }.

		IF shutdownCondition() {
			Engines("stop", Engines("allEngines")).
			SET subRunmode TO 1.
			RCS ON.
			SET STEERINGMANAGER:MAXSTOPPINGTIME TO 0.5.
			SET STEERINGMANAGER:ROLLTS TO 40.
			SET STEERINGMANAGER:PITCHTS TO 100.
			SET STEERINGMANAGER:YAWTS TO 100.
			//SET STEERINGMANAGER:SHOWFACINGVECTORS TO TRUE.
			//SET STEERINGMANAGER:SHOWANGULARVECTORS TO TRUE.
		}
	} ELSE IF subRunmode = 1 {
		IF VERTICALSPEED < -120 { AG5 ON. SET subRunmode TO 2. }
	} ELSE IF subRunmode = 2 {
		LOCK THROTTLE TO MAX(0, MIN(1, tval)).
		SET runmode TO 2.
		SET subRunmode TO 0.
		LOCK STEERING TO steer.
		STEERINGMANAGER:RESETTODEFAULT().
	}
}

//	Handles the landing procedure
FUNCTION Recovery {
	SET lzOffsetDistance TO MIN(500, lzCurrentDistance:MAG/3).
	SET steerAngleMultiplier TO MAX(0.5, MIN(20, ((currentAltitude-lzAltitude)/-VERTICALSPEED)/2)).
	//	Change the way of steering depending on wheter engines are running or not
	IF ShipCurrentTWR() < 2 AND SHIP:VELOCITY:SURFACE:MAG > 120 {
		SET AeroSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO MAX(-10, MIN(10, AeroSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
		PRINT "Aero V:    " + AeroSteeringVel_PID + "                              " AT (3, 31).
		PRINT "Aero:      " + steerAngleMultiplier + "                              " AT (3, 34).
	} ELSE {
		SET PoweredSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO MAX(-5, MIN(5, PoweredSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
		PRINT "Powered V: " + PoweredSteeringVel_PID + "                              " AT (3, 31).
		PRINT "Powered:   " + steerAngleMultiplier + "                              " AT (3, 34).
	}
	IF currentAltitude < lzAltitude + 20 OR VERTICALSPEED > 0 {
		SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
	} ELSE {
		IF ShipCurrentTWR() > 2 AND SHIP:VELOCITY:SURFACE:MAG < 120 { SET steerAngle TO -steerAngle. }
		SET steer TO LOOKDIRUP(RODRIGUES(-SHIP:VELOCITY:SURFACE, GetNormalVec(landingOffset, impactPosition:POSITION + landingOffset), steerAngle), SHIP:FACING:TOPVECTOR).
		
		//	Debug line
		PRINT "Steering angle:  " + ROUND(steerAngle, 3) + "        " AT (3, 22).
	}

	IF currentAltitude < landingBurnData["altitude"][landingParam] {
		UNTIL currentAltitude >= landingBurnData["altitude"][landingParam] {
			IF landingParam	> 1 {
				SET landingParam TO landingParam -1.
			} ELSE { BREAK. }
		}
		SET landingParam TO landingParam -1.
	}
	PRINT "Landing param:   " + landingParam + "     " AT (3,25).
	//IF landingParam < landingBurnData["altitude"]:LENGTH-1 {
	//	//	May not even need the code below, need to test and see if any significant precision is gained
	//	LOCAL speedMultiplier IS (currentAltitude - landingBurnData["altitude"][landingParam])/(landingBurnData["altitude"][landingParam+1] - landingBurnData["altitude"][landingParam]).
	//	SET landingSpeed TO landingBurnData["speed"][landingParam] + (landingBurnData["speed"][landingParam+1] - landingBurnData["speed"][landingParam]) * speedMultiplier.
	//	PRINT 1 AT (1,26).
	//} ELSE {
	SET landingSpeed TO landingBurnData["speed"][landingParam]. PRINT 2 AT (1,26).
	//}
	PRINT "Landing speed:   " + landingSpeed + "     " AT (3,26).

	IF subRunmode = 0 {	//	Control when engines are being started and shut down
		IF TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 1 {
			SET tval TO 1.
			Engines("start", Engines("centerEngines")).
			Engines("throttle", Engines("landingEngines"), landing["landingThrottle"]).
			WHEN TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 1.5 THEN {
				Engines("start", Engines("landingEngines")).
				WHEN landingParam < 50 THEN {
					Engines("stop", Engines("sideEngines")).
					GEAR ON.
				}
			}
			SET subRunmode TO 1.
		}
	} ELSE IF subRunmode = 1 {	//	Control the throttle of center engine and shut it down once landed
		SET VelThr_PID:SETPOINT TO -landingSpeed.
		SET engineThrottle[2] TO engineThrottle[1]. SET engineThrottle[1] TO engineThrottle[0].
		SET engineThrottle[0] TO VelThr_PID:UPDATE(mT, -SHIP:VELOCITY:SURFACE:MAG)/COS(VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR)).
		SET engineThrottleAvg TO (engineThrottle[0] + engineThrottle[1] + engineThrottle[2])/3.
		//	Debug line below...
		PRINT "Engine throttle: " + round(engineThrottleAvg, 3) + "          " AT (3,24).
		Engines("throttle", Engines("centerEngines"), engineThrottleAvg).

		IF landingParam = 0 OR VERTICALSPEED >= 0 {
			Engines("stop", Engines("landingEngines")).
			SET tval TO 0.
			SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
			SET runmode TO 3.
			SET subRunmode TO 0.
		}
	}

	//	Displaying some useful vectors
	SET vec1 TO VECDRAW(SHIP:POSITION, impactPosition:POSITION, RGB(1,0,0), "Impact", 1, TRUE).
	SET vec2 TO VECDRAW(SHIP:POSITION, currentPosition:POSITION, RGB(0,1,0), "Position", 1, TRUE).
	SET vec3 TO VECDRAW(SHIP:POSITION, lzPosition:POSITION + landingOffset, RGB(1,1,1), "Targetting", 1, TRUE).
	SET vec4 TO VECDRAW(SHIP:POSITION, steer:FOREVECTOR * 75, RGB(1,0.55,0), "Steering", 1, TRUE).
}

//	Waiting 1 physics tick so that everything updates
WAIT 0.

LOCAL finished IS FALSE.

//	Program loop
UNTIL finished {
	SET finished TO Main().
	WAIT 0.
}

//	Hide all vectors at the end
SET vec1:SHOW TO FALSE.
SET vec2:SHOW TO FALSE.
SET vec3:SHOW TO FALSE.
SET vec4:SHOW TO FALSE.

//	Once done, release control of everything
UNLOCK ALL.