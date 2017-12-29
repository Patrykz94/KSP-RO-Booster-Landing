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
	ELSE IF runmode = 2 { Boostback().	}
	ELSE IF runmode = 3 { Reentry().	}	//	To be improved...
	ELSE IF runmode = 4 { Recovery().	}
	RefreshUI().
	UpdateVars("end").
	IF runmode = 5 { RETURN TRUE. } ELSE { RETURN FALSE. }
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
	IF subRunmode = 0 {			//	Request a lift-off time from PEGAS
		IF SendMessage("request", "liftoffTime") { SET subRunmode TO 1. }
		ELSE { ForceCrash("Failed to send a message. Check message receiver and try again."). }
	} ELSE IF subRunmode = 1 {	//	Wait for response and update lift-off time
		IF lastResponse:LENGTH > 0 {
			IF NOT lastResponse["data"]:ISTYPE("String") { SET lT TO lastResponse["data"]["liftoffTime"]. }
			ELSE { ForceCrash(lastResponse["data"]). }
			IF landing["required"] { SendMessage("command", LIST(LIST("setUpfgTime", 252))). }
			SET subRunmode TO 2.
		}
	} ELSE IF subRunmode = 2 {	//	Move strongback at T-15s and go into launch mode
		IF mT > lT - 15 { AG9 ON. SET runmode TO 1. SET subRunmode TO 0. temporaryValues:ADD("separationPhase", 1). AddUIMessage("Strongback retracting"). WHEN mT > lT THEN { AddUIMessage("Liftoff!"). } }
	}
}

//	Handles things that happen during launch
FUNCTION Launch {
	//	Handle G limit during ascent
	IF landing["launchGLimit"] <> 0 AND ShipTWR() > 0 {
		SET throttleLimit TO MIN(1, MAX(vehicle["engines"]["minThrottle"], landing["launchGLimit"]/ShipTWR())).
		IF NOT event AND throttleLimit < 1 { SET event TO TRUE. AddUIMessage("Throttling down to maintain " + landing["launchGLimit"] + "Gs"). }
	}

	IF subRunmode = 0 {	//	Handle separation conditions and throttling down
		LOCAL shutdownCondition IS FALSE.
		LOCAL throttleCondition IS FALSE.
		LOCAL separationCondition IS FALSE.

		IF landing["boostback"] {
			//	RTLS/ASDS landings requiring boostback burn
			LOCAL deltaVatSep IS landingBurnData["dvSpent"] + (SHIP:VELOCITY:SURFACE:MAG/4) + (GROUNDSPEED * 1.4).

			SET shutdownCondition TO { RETURN deltaVatSep > boosterDeltaV - 30. }.
			SET throttleCondition TO { RETURN deltaVatSep > boosterDeltaV - 15. }.
			IF throttleCondition() { SET engineThrottle[0] TO MIN(1, MAX(0, (boosterDeltaV-deltaVatSep)/15)). }
			SET separationCondition TO { RETURN deltaVatSep > boosterDeltaV. }.

		} ELSE {
			//	ASDS landing following a ballistic trajectory. To be completed...
		}

		IF temporaryValues["separationPhase"] = 1 AND shutdownCondition() {
			//	Ask PEGAS to shut down 8 out of 9 engines for a precise separation time.
			SendMessage("command", LIST("engineShutdown",
				"Merlin1D-1", "Merlin1D-2", "Merlin1D-3", "Merlin1D-4", "Merlin1D-5", "Merlin1D-6", "Merlin1D-7", "Merlin1D-8"
			)).
			//	Dividing the gLimit by 9 so that engine won't throttle up suddenly.
			SET landing["launchGLimit"] TO landing["launchGLimit"]/9.
			SET CONFIG:IPU TO 2000.
			SET temporaryValues["separationPhase"] TO 2.
		}
		
		IF throttleCondition() {
			//	Progressively decrease throttle
			Engines("throttle", Engines("centerEngines"), MIN(throttleLimit, engineThrottle[0])).
			SET temporaryValues["separationPhase"] TO 3.
		} ELSE {
			Engines("throttle", Engines("allEngines"), throttleLimit).
		}
		
		IF temporaryValues["separationPhase"] = 3 AND separationCondition() {
			//	Ask PEGAS to shut down the last engine and separate
			LOCAL P IS LIST().
			LIST PARTS IN P.
			SET partCount TO P:LENGTH.	//	Saving part count before separation
			IF SendMessage("command", LIST(
				LIST("engineShutdown", "Merlin1D-0"),
				LIST("setUpfgTime")
			)) { SET subRunmode TO 1. temporaryValues:REMOVE("separationPhase"). SET event TO FALSE. AddUIMessage("MECO (Main Engine Cut-Off)"). }
		}
	} ELSE IF subRunmode = 1 {	// Wait until separated and set up for next phases
		LOCAL P IS LIST().
		LIST PARTS IN P.
		IF P:LENGTH <> partCount {	//	If number of parts does not equal number of parts before separation, then stage 2 has already separated
			CORE:PART:CONTROLFROM().
			SET CONFIG:IPU TO 2000.
			LOCK THROTTLE TO MAX(0, MIN(1, tval)).
			SET eventTime TO mT + 1.5.
			CreateUI().
			RCS ON.
			IF landing["boostback"] { SET runmode TO 2. }
			ELSE { SET runmode TO 3. SET flipDirection TO 180. }
			SET subRunmode TO 0.
			AddUIMessage("Stage separation").
		}
	}
}

//	Flips the booster around and executes the boostback burn
FUNCTION Boostback {
	IF subRunmode = 0 {	//	Wait for a few seconds to make sure booster is stable and then start the fast flip
		IF mT > eventTime {
			IF stable { AttitudeControl("flip", flipSpeed, flipDirection). }
			ELSE { SET stable TO AttitudeControl("stabilize", flipDirection). }
			IF pitch_for(SHIP) > 75 { SET subRunmode TO 1. }
		} ELSE {
			AttitudeControl("stabilize", flipDirection).
		}
	} ELSE IF subRunmode = 1 {	//	If pitch went over 75 degrees and then back under 75, we have done most of the flip. At this point switch engines on.
		IF pitch_for(SHIP) < 75 {
			SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
			SET steer TO lzImpactOffset.
			LOCK STEERING TO steer.
			SET engineStartup TO TRUE.
			SET eventTime TO mT + 2.
			Engines("throttle", Engines("bostbackEngines"), 1).
			temporaryValues:ADD("landingOffset", landingOffset:MAG).
			SET stable TO FALSE.
			SET subRunmode TO 2.
		} ELSE {
			IF stable { AttitudeControl("flip", flipSpeed, flipDirection). }
			ELSE { SET stable TO AttitudeControl("stabilize", flipDirection). }
		}
	} ELSE IF subRunmode = 2 {	//	Maintain correct orientation until boostback burn is completed. Boostback is completed when impact position is just behind the LZ position from boosters POV.
		SET STEERINGMANAGER:MAXSTOPPINGTIME TO 1.

		SET tval TO 1.
		
		IF engineStartup OR mT > eventTime { // Start the engines (center first then two side engines)
			IF mT > eventTime {
				Engines("start", Engines("boostbackEngines")).
				SET engineStartup TO FALSE.
				SET eventTime TO mT + 600.
			} ELSE {
				Engines("start", Engines("centerEngines")).
				SET engineStartup TO FALSE.
				SET eventTime TO mT + 2.
			}
		}

		IF ullageRequired { // If ullage is required, switch RCS on and thrust forward until fuel is settled
			RCS ON.
			SET SHIP:CONTROL:FORE TO 1.
			SET engineStartup TO TRUE. // Keep trying to start the engines
		} ELSE {
			RCS OFF.
			SET SHIP:CONTROL:FORE TO 0.
			SET engineStartup TO FALSE.
		}

		IF landingOffset:MAG > lzOffsetDistance * 3 { // If far from target position point in its direction
			SET steer TO LOOKDIRUP(landingOffset, BODY:POSITION).
		} ELSE {
			IF landingOffset:MAG > temporaryValues["landingOffset"] { // If went past the target position
				Engines("stop", Engines("boostbackEngines")).
				SET tval TO 0.
				UNLOCK STEERING.
				SET runmode TO 3.
				SET subRunmode TO 0.
			} ELSE { // If close to the target position stop 2 engines and adjust throttle of center engine
				Engines("stop", Engines("sideEngines")).
				Engines("gimbal", Engines("outerEngines"), FALSE).
				Engines("throttle", Engines("centerEngines"), MAX(vehicle["engines"]["minThrottle"], MIN(1, landingOffset:mag/(lzOffsetDistance*3)))).
			}
		}
		SET temporaryValues["landingOffset"] TO landingOffset:MAG. // Tracking changes in distance to target position
	}
}

//	Handles the reentry burn
FUNCTION Reentry {
	//	Temporary solution...
	IF subRunmode > 0 AND subRunmode < 3 {
		//	Keep updating varibales during a certain time period
		SET temporaryValues["reentryTime"] TO mT + TimeToAltitude(50000).
		SET temporaryValues["reentryVelocity"] TO VELOCITYAT(SHIP, temporaryValues["reentryTime"]):SURFACE.
		SET temporaryValues["angleToReentry"] TO VANG(SHIP:FACING:FOREVECTOR, -temporaryValues["reentryVelocity"]).
		SET flipSpeed TO (temporaryValues["angleToReentry"]/(temporaryValues["reentryTime"]-mT-30))*1.1.
	}

	IF subRunmode = 0 {	//	Set up and stabilize for a slower flip ahead of reentry
		AttitudeControl("stabilize", flipDirection - 180).
		SET eventTime TO mT + 2.
		RCS ON.
		//	Create some temporary varibales
		temporaryValues:ADD("reentryTime", mT + TimeToAltitude(50000)).
		temporaryValues:ADD("reentryVelocity", VELOCITYAT(SHIP, temporaryValues["reentryTime"]):SURFACE).
		temporaryValues:ADD("angleToReentry", VANG(SHIP:FACING:FOREVECTOR, -temporaryValues["reentryVelocity"])).
		SET flipSpeed TO (temporaryValues["angleToReentry"]/(temporaryValues["reentryTime"]-mT-30))*1.1.
		SET subRunmode TO 1.
	} ELSE IF subRunmode = 1 {	//	Start slowly flipping the booster around
		IF mT > eventTime {
			IF stable { AttitudeControl("flip", flipSpeed, flipDirection - 180). }
			ELSE { SET stable TO AttitudeControl("stabilize", flipDirection - 180). }
			IF pitch_for(SHIP) > 85 { AG5 ON. SET subRunmode TO 2. }
		} ELSE {
			AttitudeControl("stabilize", flipDirection - 180).
		}
	} ELSE IF subRunmode = 2 {	//	Continue the flip until pointing in the right direction
		//	When facing the desired direction, stop the flip and proceed to reentry
		IF pitch_for(SHIP) < 90-VANG(SHIP:UP:VECTOR, -temporaryValues["reentryVelocity"]) {
			SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
			//	Set up steering manager
			SET STEERINGMANAGER:MAXSTOPPINGTIME TO 2.
			SET STEERINGMANAGER:ROLLTS TO 40.
			SET STEERINGMANAGER:PITCHTS TO 40.
			SET STEERINGMANAGER:YAWTS TO 40.
			LOCK STEERING TO steer.
			SET engineStartup TO TRUE.
			SET eventTime TO mT + 600.	//	Just moving it far away...
			IF landing["boostback"] { SET lzOffsetDistance TO 200. } ELSE { SET lzOffsetDistance TO 1000. }
			SET reentryBurnDeltaV TO boosterDeltaV - landingBurnData["dvSpent"].
			//	Setting the initial maneuver node
			LOCAL nodeData IS NodeFromVector(-temporaryValues["reentryVelocity"]:NORMALIZED * reentryBurnDeltaV, temporaryValues["reentryTime"]).
			GLOBAL reentryNode IS NODE(temporaryValues["reentryTime"], 0, 0, reentryBurnDeltaV).
			SET reentryNode:RADIALOUT TO nodeData[0]. SET reentryNode:NORMAL TO nodeData[1]. SET reentryNode:PROGRADE TO nodeData[2].
			ADD(reentryNode).
			SET eventTime TO mT + reentryNode:ETA.
			SET subRunmode TO 3.
		} ELSE {
			IF stable { AttitudeControl("flip", flipSpeed, flipDirection - 180). }
			ELSE { SET stable TO AttitudeControl("stabilize", flipDirection - 180). }
		}
	} ELSE IF subRunmode = 3 {
		IF reentryNode:ETA < 5 {	//	When approaching the reentry burn, point in the right direction
			IF NOT temporaryValues:HASKEY("ReentryFound") {
				GetReentry(TRUE).
				temporaryValues:ADD("ReentryFound", TRUE).
			}
			SET steer TO LOOKDIRUP(reentryNode:DELTAV, SHIP:FACING:TOPVECTOR).
			IF reentryNode:ETA < 2 {	//	Start the center engine first and 2 seconds later the side engines
				IF engineStartup OR mT > eventTime {
					IF mT > eventTime { Engines("start", Engines("reentryEngines")). SET engineStartup TO FALSE. SET eventTime TO mT + 100. }
					ELSE { Engines("start", Engines("centerEngines")). SET engineStartup TO FALSE. }
				}
				SET tval TO 1.
				IF (reentryNode:DELTAV:MAG - 500) > 64 { Engines("throttle", Engines("reentryEngines"), landing["reentryThrottle"]). }
				ELSE {
					IF NOT temporaryValues:HASKEY("EnginesStopped") {	//	Stop the side engines first for a more precise shutdown
						Engines("stop", Engines("sideEngines")).
						temporaryValues:ADD("EnginesStopped", TRUE).
					}
					Engines("throttle", Engines("centerEngines"), MAX(vehicle["engines"]["minThrottle"], MIN(landing["reentryThrottle"], (reentryNode:DELTAV:MAG-64)/500))).
					IF (reentryNode:DELTAV:MAG - 500) < 0 {
						Engines("stop", Engines("reentryEngines")).
						SET tval TO 0.
						//	Remove temporary variables
						temporaryValues:REMOVE("EnginesStopped").
						temporaryValues:REMOVE("reentryTime").
						temporaryValues:REMOVE("reentryVelocity").
						temporaryValues:REMOVE("angleToReentry").
						temporaryValues:REMOVE("ReentryFound").
						REMOVE(reentryNode).
						CreateUI().
						SET runmode TO 4.
						SET subRunmode TO 0.
						STEERINGMANAGER:RESETTODEFAULT().
					}
				}
			}
		} ELSE {
			IF reentryNode:ETA < 15 { GetReentry(). }
			SET steer TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:FACING:TOPVECTOR).
			IF VANG(-SHIP:VELOCITY:SURFACE, SHIP:FACING:FOREVECTOR) < 1 { RCS OFF. } ELSE { RCS ON. }
		}

		//	When engines are runnign, swithc RCS off to save fuel
		IF ShipCurrentTWR() > 0.5 { RCS OFF. }
		ELSE IF reentryNode:ETA < 5 { RCS ON. }
	}
}

//	Handles the landing procedure
FUNCTION Recovery {
	SET lzOffsetDistance TO MIN(500, lzCurrentDistance:MAG/5).
	SET steerAngleMultiplier TO MAX(0.5, MIN(20, ((currentAltitude-lzAltitude)/-VERTICALSPEED)/2)).
	//	Change the way of steering depending on wheter engines are running or not
	IF ShipCurrentTWR() < 2 AND SHIP:VELOCITY:SURFACE:MAG > 120 {
		SET AeroSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO MAX(-10, MIN(10, AeroSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
	} ELSE {
		SET PoweredSteeringVel_PID:SETPOINT TO 0.
		SET steerAngle TO MAX(-5, MIN(5, PoweredSteeringVel_PID:UPDATE(mT, (landingOffset + lzImpactDistance):MAG)/steerAngleMultiplier)).
	}
	IF currentAltitude < lzAltitude + 20 OR VERTICALSPEED > 0 {
		SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
	} ELSE {
		IF ShipCurrentTWR() > 2 AND SHIP:VELOCITY:SURFACE:MAG < 120 { SET steerAngle TO -steerAngle. }
		SET steer TO LOOKDIRUP(RODRIGUES(-SHIP:VELOCITY:SURFACE, GetNormalVec(landingOffset, impactPosition:POSITION + landingOffset), steerAngle), SHIP:FACING:TOPVECTOR).
	}

	IF currentAltitude < landingBurnData["altitude"][landingParam] {
		UNTIL currentAltitude >= landingBurnData["altitude"][landingParam] {
			IF landingParam	> 1 {
				SET landingParam TO landingParam -1.
			} ELSE { BREAK. }
		}
		SET landingParam TO landingParam -1.
	}
	//IF landingParam < landingBurnData["altitude"]:LENGTH-1 {
	//	//	May not even need the code below, need to test and see if any significant precision is gained
	//	LOCAL speedMultiplier IS (currentAltitude - landingBurnData["altitude"][landingParam])/(landingBurnData["altitude"][landingParam+1] - landingBurnData["altitude"][landingParam]).
	//	SET landingSpeed TO landingBurnData["speed"][landingParam] + (landingBurnData["speed"][landingParam+1] - landingBurnData["speed"][landingParam]) * speedMultiplier.
	//} ELSE {
	SET landingSpeed TO landingBurnData["speed"][landingParam].
	//}

	IF subRunmode = 0 {	//	Control when engines are being started and shut down
		IF TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 2 {
			SET tval TO 1.
			Engines("start", Engines("centerEngines")).
			Engines("throttle", Engines("landingEngines"), landing["landingThrottle"]).
			WHEN TimeToAltitude(landingBurnData["altitude"][landingParam], currentAltitude) < vehicle["engines"]["spoolUpTime"] - 2.5 THEN {
				Engines("start", Engines("landingEngines")).
				WHEN landingParam < 35 THEN {
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
		Engines("throttle", Engines("centerEngines"), engineThrottleAvg).

		IF landingParam = 0 OR VERTICALSPEED >= 0 {
			Engines("stop", Engines("landingEngines")).
			SET tval TO 0.
			SET steer TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR).
			SET runmode TO 5.
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