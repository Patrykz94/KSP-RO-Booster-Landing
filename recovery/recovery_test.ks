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
GLOBAL runmode IS 0.		//	Pre-launch
LOCAL subRunmode IS 0.
LOCAL currentPosition IS SHIP:GEOPOSITION.
GLOBAL currentAltitude IS 0.
LOCAL impactPosition IS SHIP:GEOPOSITION.
GLOBAL impactVelocity IS V(0,0,0).	//	Velocity of impact point, not booster velocity at impact
GLOBAL lzImpactDistance IS V(0,0,0).
GLOBAL lzCurrentDistance IS V(0,0,0).
GLOBAL launchSiteDistance IS V(0,0,0).
LOCAL lzPosition IS SHIP:GEOPOSITION.
GLOBAL lzAltitude IS 0.
GLOBAL boosterDeltaV IS 0.
LOCAL TR IS ADDONS:TR.
//	Offsets
LOCAL lzOffsetDistance IS 3000.
LOCAL lzBoosterOffset IS V(0,0,0).
LOCAL lzImpactOffset IS V(0,0,0).
GLOBAL landingOffset IS V(0,0,0).
//	Steering variables
LOCAL tval IS 0.
LOCAL throttleLimit IS 1.
LOCAL steer IS up.
LOCAL steerAngle IS 0.
LOCAL steerAngleMultiplier IS 1.
//	Engine variables
LOCAL engineStartup IS FALSE.
LOCAL engineThrottle IS 1.
LOCAL stable IS FALSE.
//	Time tracking variables
LOCAL dT IS 0.				//	Delta time
GLOBAL mT IS TIME:SECONDS.	//	Current time
GLOBAL lT IS 0.				//	Until/since launch
LOCAL pT IS 0.				//	Previous tick time
LOCAL eventTime IS 0.
LOCAL event IS FALSE.
//	Landing burn variables
GLOBAL impactTime IS 0.
LOCAL landingParam IS 0.
LOCAL landingSpeed IS 0.
//	Landing parameters
GLOBAL reentryBurnDeltaV IS 0.
LOCAL flipDirection IS 0.
LOCAL flipSpeed IS 24.
LOCAL partCount IS 0. // Used to determine if upper stage has separated already
//	Messaging variables
GLOBAL lastResponse IS LEXICON().
//	Vectors to be displayed
LOCAL vec1 IS 0.
LOCAL vec2 IS 0.
LOCAL vec3 IS 0.
LOCAL vec4 IS 0.
//	Other variables
LOCAL bodyRotation IS 360 / BODY:ROTATIONPERIOD.
LOCAL refreshCounter IS 0.
LOCAL refreshIntervals IS 10.	//	How many physics ticks between each refresh
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
GLOBAL UILex IS LEXICON("time", LIST(), "message", LIST()).
GLOBAL UILexLength IS 0.
CreateUI().

//	Landing setup
IF landing["required"] {
	SET lzPosition TO landing["location"].
	TR:SETTARGET(lzPosition).	//	Setting target for Trajectories mod
	SET lzAltitude TO lzPosition:TERRAINHEIGHT.
	CalculateLandingBurn(50).	//	Calculate the landing burn details iteratively
	SET landingParam TO landingBurnData["speed"]:LENGTH-1.
	FUNCTION printBurnData {
		LOG "0" TO "0:/logs/landingBurn.csv".
		DELETEPATH("0:/logs/landingBurn.csv").
		LOG "Time,Speed,Altitude,Mass,DryMass,DvSpent" TO "0:/logs/landingBurn.csv".
		LOCAL lParam IS landingParam.
		UNTIL lParam = 0 {
			LOG (lParam/20) + "," + landingBurnData["speed"][lParam] + "," + landingBurnData["altitude"][lParam] + "," + landingBurnData["mass"][lParam] + "," + landingBurnData["dryMass"] + "," + landingBurnData["dvSpent"] TO "0:/logs/landingBurn.csv".
			SET lParam TO lParam - 1.
		}
	}
	printBurnData().
}

//	A wrapper function that calls all other functions
FUNCTION Main {
	UpdateVars("start").
	IF 		runmode = 0 { Prelaunch().	}
	ELSE IF runmode = 1 { Launch().		}
	ELSE IF runmode = 2 { Recovery().	}
	IF refreshCounter = refreshIntervals {
		RefreshUI().
	}
	UpdateVars("end").
	IF runmode = 3 { RETURN TRUE. } ELSE { RETURN FALSE. }
}

//	Updating varibales before and after every iteration
FUNCTION UpdateVars {
	PARAMETER type.

	IF type = "start" {
		SET refreshCounter TO refreshCounter + 1.
		SET mT TO TIME:SECONDS.
		SET dT TO mT - pT.
		SET currentAltitude TO BODY:ALTITUDEOF(SHIP:PARTSTAGGED(vehicle["bottomPart"]["name"])[0]:position) - vehicle["bottomPart"]["heightOffset"].
		SET currentPosition to SHIP:GEOPOSITION.
		SET impactTime to timeToAltitude(lzAltitude, currentAltitude).
		IF TR:HASIMPACT { SET impactPosition TO TR:IMPACTPOS. }
		IF runmode = 1 OR refreshCounter = refreshIntervals -1 {
			SET boosterDeltaV TO Booster("deltaV").
		}
		IF runmode = 2 OR refreshCounter = refreshIntervals -1 {
			SET lzCurrentDistance TO lzPosition:POSITION - SHIP:GEOPOSITION:ALTITUDEPOSITION(lzAltitude).						//	Ship -> LZ
			SET lzImpactDistance TO lzPosition:POSITION - impactPosition:ALTITUDEPOSITION(lzAltitude).							//	Impact point -> LZ
			SET lzBoosterOffset TO VXCL(lzCurrentDistance - BODY:POSITION, lzCurrentDistance):NORMALIZED * lzOffsetDistance.	//	Flattened and sized <lzCurrentDistance>
			SET landingOffset TO lzPosition:POSITION + lzBoosterOffset - impactPosition:ALTITUDEPOSITION(lzAltitude).			//	Pos behind the LZ to aim at during descent
		}
		IF runmode = 2 OR refreshCounter = refreshIntervals -1 {
			SET lzImpactOffset TO VXCL(lzImpactDistance - BODY:POSITION, lzImpactDistance):NORMALIZED * lzOffsetDistance.		//	Flattened and sized <lzImpactDistance>
		}
		IF refreshCounter = refreshIntervals -1 {
			SET impactVelocity TO (impactPosition:ALTITUDEPOSITION(lzAltitude) - previousImpactPosition:ALTITUDEPOSITION(lzAltitude))/dT.	//	Not precise at all. Needs attention
			SET launchSiteDistance TO (landing["launchLocation"]:POSITION - SHIP:GEOPOSITION:ALTITUDEPOSITION(lzAltitude)):MAG.	//	Downrange distance
		}
	} ELSE IF type = "end" {
		IF refreshCounter >= refreshIntervals { SET refreshCounter TO 0. }
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
		IF mT > lT { SET runmode TO 1. SET subRunmode TO 0. STAGE. AddUIMessage("Liftoff."). }
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
		LOCAL deltaVatSep IS landingBurnData["dvSpent"] + 50.
		SET shutdownCondition TO { RETURN deltaVatSep > boosterDeltaV. }.

		IF shutdownCondition() {
			Engines("stop", Engines("allEngines")).
			AddUIMessage("Engine Shutdown.").
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
		IF VERTICALSPEED < -120 { AG5 ON. SET subRunmode TO 2. AddUIMessage("Using aerodynamics to aim for Landing Zone 1."). }
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
	IF (ShipCurrentTWR() > 6 AND SHIP:VELOCITY:SURFACE:MAG < 300) OR
	(ShipCurrentTWR() > 4 AND SHIP:VELOCITY:SURFACE:MAG < 200) OR
	(ShipCurrentTWR() > 2 AND SHIP:VELOCITY:SURFACE:MAG < 150) OR
	(ShipCurrentTWR() > 1.5 AND SHIP:VELOCITY:SURFACE:MAG < 100) OR
	(ShipCurrentTWR() > 1.2 AND SHIP:VELOCITY:SURFACE:MAG < 50) {
		SET PoweredSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO -MAX(-7, MIN(7, PoweredSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
	} ELSE {
		SET AeroSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO MAX(-12, MIN(12, AeroSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
	}
	IF currentAltitude < lzAltitude + 30 OR VERTICALSPEED > 0 {
		SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
	} ELSE {
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
	}
	PRINT "Landing param:   " + landingParam + "     " AT (3,25).
	IF landingParam < landingBurnData["altitude"]:LENGTH-1 {
		//	May not even need the code below, need to test and see if any significant precision is gained
		LOCAL speedMultiplier IS (currentAltitude - landingBurnData["altitude"][landingParam])/(landingBurnData["altitude"][landingParam+1] - landingBurnData["altitude"][landingParam]).
		SET landingSpeed TO -(landingBurnData["speed"][landingParam] + (landingBurnData["speed"][landingParam+1] - landingBurnData["speed"][landingParam]) * speedMultiplier).
		PRINT 1 AT (1,26).
	} ELSE {
		SET landingSpeed TO -landingBurnData["speed"][landingParam]. PRINT 2 AT (1,26).
	}
	PRINT "Landing speed:   " + landingSpeed + "     " AT (3,26).

	IF subRunmode = 0 {	//	Control when engines are being started and shut down
		IF TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 1 {
			SET tval TO 1.
			AddUIMessage("Landing burn startup.").
			Engines("start", Engines("centerEngines")).
			Engines("throttle", Engines("landingEngines"), landing["landingThrottle"]).
			WHEN TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 1 THEN {
				Engines("start", Engines("landingEngines")).
				WHEN landingParam < 100 THEN {
					IF landing["landingEngines"] > 1 { AddUIMessage("Shutting down side engines.").	}
					Engines("stop", Engines("sideEngines")).
					GEAR ON.
				}
			}
			SET subRunmode TO 1.
		}
	} ELSE IF subRunmode = 1 {	//	Control the throttle of center engine and shut it down once landed
		PRINT "Alt Diff: " + ROUND(currentAltitude - lzAltitude, 2) + "       " AT (3,27).
		PRINT "Velocity: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 2) + "       " AT (3,28).
		PRINT "Time:     " + ROUND(landingParam/20, 2) + "       " AT (3,29).
		PRINT "Gravity:  " + ROUND(Gravity(), 2) + "       " AT (3,30).

		SET VelThr_PID:SETPOINT TO landingSpeed.
		SET engineThrottle TO VelThr_PID:UPDATE(mT, -SHIP:VELOCITY:SURFACE:MAG)/COS(VANG(UP:VECTOR, SHIP:FACING:FOREVECTOR)).
		//	Debug line below...
		PRINT "Engine throttle: " + round(engineThrottle, 3) + "          " AT (3,24).
		Engines("throttle", Engines("centerEngines"), engineThrottle).

		IF landingParam = 0 OR VERTICALSPEED >= 0 {
			Engines("stop", Engines("landingEngines")).
			SET tval TO 0.
			SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
			SET runmode TO 3.
			SET subRunmode TO 0.
			AddUIMessage("Touchdown.").
			RefreshUI().
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