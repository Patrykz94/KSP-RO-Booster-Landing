//	Recovery utilities

LOCAL ullageRequired IS FALSE.

//	Variables for controling rcs system during flips
LOCAL rollAngSpeed IS 600/360.

LOCAL RollSpd_PID IS PIDLOOP(0.2, 0, 0.3, -2, 2).
LOCAL Roll_PID IS PIDLOOP(0.4, 0, 0.3, -1, 1).
LOCAL Pitch_PID IS PIDLOOP(0.2, 0, 0.2, -2, 2).	//	Changed limits from 0.8. Need to test.

//	landing burn variables
LOCAL g0 IS 9.80665.
LOCAL landingBurnData IS LEXICON("speed", LIST(0), "altitude", LIST(0), "mass", LIST(0), "dryMass", 0, "dvSpent", 0).

{	//	Start, shutdown, throttle or get list of engines
	FUNCTION start {
		PARAMETER engineList.
		LOCAL engineReady IS TRUE.
		FOR e IN engineList {
			IF NOT e:IGNITION {
				LOCAL eng IS e:GETMODULE("ModuleEnginesRF").
				IF eng:GETFIELD("propellant") <> "Very Stable" {
					SET engineReady TO FALSE.
					SET ullageRequired TO TRUE.
				}
			}
		}
		IF engineReady {
			SET ullageRequired TO FALSE.
			FOR e IN engineList {
				IF e:IGNITION = FALSE {
					e:ACTIVATE.
				}
			}
		}
	}

	FUNCTION stop {
		PARAMETER engineList.
		FOR e IN engineList {
			IF e:IGNITION {
				e:SHUTDOWN.
			}
		}
	}

	//	Expects param to be the throttle value
	FUNCTION throttle {
		PARAMETER engineList, param.
		LOCAL minThrottle IS vehicle["engines"]["minThrottle"].
		SET param TO MAX(minThrottle, MIN(1, param)).
		FOR e IN engineList {
			SET e:THRUSTLIMIT TO ((param - minThrottle) / (1 - minThrottle))*100.
		}
	}

	FUNCTION gimbal {
		PARAMETER engineList, param.
		IF param { SET param TO FALSE. } ELSE { SET param TO TRUE. }
		FOR e IN engineList {
			SET e:GIMBAL:LOCK TO param.
		}
	}

	GLOBAL Engines IS {
		PARAMETER task, engineList IS LIST(), param IS FALSE.

		IF task:CONTAINS("Engines") {
			LOCAL engList IS LIST().
			IF landing:HASKEY(task) {
				IF task = "sideEngines" {
					FOR eng IN vehicle["engines"]["list"] {
						IF engList:LENGTH < landing[task] + landing["centerEngines"] {
							engList:ADD(SHIP:PARTSTAGGED(eng)[0]).
						}
					}
					LOCAL centerList IS LIST().
					FOR eng IN vehicle["engines"]["list"] {
						IF centerList:LENGTH < landing["centerEngines"] {
							centerList:ADD(SHIP:PARTSTAGGED(eng)[0]).
						}
					}
					LOCAL finalList IS LIST().
					FOR e IN engList {
						LOCAL isInCenterList IS FALSE.
						FOR c IN centerList {
							IF c = e { SET isInCenterList TO TRUE. }
						}
						IF NOT isInCenterList { finalList:ADD(e). }
					}
					RETURN finalList.
				} ELSE {
					FOR eng IN vehicle["engines"]["list"] {
						IF engList:LENGTH < landing[task] {
							engList:ADD(SHIP:PARTSTAGGED(eng)[0]).
						}
					}
				}
			} ELSE {
				IF task = "outerEngines" {
					FROM { LOCAL i IS vehicle["engines"]["list"]:LENGTH-1. } UNTIL i = landing["centerEngines"]-1 STEP { SET i TO i-1. } DO {
						LOCAL e IS SHIP:PARTSTAGGED(vehicle["engines"]["list"][i])[0].
						engList:ADD(e).
					}
				} ELSE IF task = "allEngines" {
					FOR eng IN vehicle["engines"]["list"] {
						engList:ADD(SHIP:PARTSTAGGED(eng)[0]).
					}
				}
			}
			RETURN engList.
		} ELSE IF engineList:EMPTY {
			FOR eng IN vehicle["engines"]["list"] {
				engineList:ADD(SHIP:PARTSTAGGED(eng)[0]).
			}
		}

		IF task = "start" { start(engineList). }
		ELSE IF task = "stop" { stop(engineList). }
		ELSE IF task = "throttle" { throttle(engineList, param). }
		ELSE IF task = "gimbal" { gimbal(engineList, param). }
	}.
}

{	//	Getting deltaV and calculating masses
	LOCAL tank IS SHIP:PARTSTAGGED(vehicle["fuel"]["tankNametag"]).

	FUNCTION fuelMass {
		PARAMETER fuelType.
		IF NOT fuelType:ISTYPE("list") { SET fuelType TO LIST(fuelType). }

		LOCAL amount IS 0.
		LOCAL mass IS 0.
		FOR t IN tank {
			FOR r IN t:RESOURCES {
				FOR fuel IN fuelType {
					IF r:NAME = fuel { SET amount TO amount + r:AMOUNT. SET mass TO mass + (r:AMOUNT * r:DENSITY). }
				}
			}
		}
		RETURN LIST(amount, mass).
	}

	FUNCTION trueDryMass {
		LOCAL dryMass IS vehicle["mass"]["dry"].
		FOR f IN vehicle["fuel"]["rcsFuels"] { SET dryMass TO dryMass + fuelMass(f)[1]. }
		RETURN dryMass.
	}

	//	Maximum DeltaV available in the booster
	FUNCTION deltaV {
		PARAMETER param IS SHIP:SENSORS:PRES * CONSTANT:KPATOATM.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["engines"]["list"][0])[0].
		LOCAL dm IS trueDryMass().
		//	Not 100% sure if 9.80665 should be used
		RETURN e:ISPAT(param) * g0 * LN((dm + fuelMass(vehicle["fuel"]["fuelNames"])[1]) / dm).
	}

	//	Mass of fuel required for the certain DeltaV
	FUNCTION massOfDeltaV {
		PARAMETER param.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["engines"]["list"][0])[0].
		LOCAL dm IS trueDryMass().
		RETURN (dm * (CONSTANT:E^(param / (e:SLISP * g0)))) - dm.
	}

	GLOBAL Booster IS {
		PARAMETER task, param IS FALSE.
		IF task = "deltaV" { IF param:ISTYPE("boolean") { RETURN deltaV(). } ELSE { RETURN deltaV(param). } }
		ELSE IF task = "dryMass" { RETURN trueDryMass(). }
		ELSE IF task = "massOfDeltaV" { IF param:ISTYPE("boolean") { RETURN 0. } ELSE { RETURN massOfDeltaV(param). } }
		ELSE IF task = "fuelMass" { IF param:ISTYPE("boolean") { RETURN 0. } ELSE { RETURN fuelMass(param). } }
	}.
}

{	//	Controling attitude during flips
	FUNCTION circCalc {
		PARAMETER desC.
		PARAMETER oldC.
		IF oldC < 180 { IF desC > oldC + 180 { RETURN desC - 360. } ELSE { RETURN desC. } }
		ELSE { IF desC > oldC - 180 { RETURN desC. } ELSE { RETURN desC + 360. } }
	}

	FUNCTION rollConvert {
		PARAMETER rol IS roll_for(SHIP).
		IF rol < 0 { RETURN rol + 360. }
		ELSE { RETURN rol. }
	}

	FUNCTION roll {
		PARAMETER setRoll, force.
		IF setRoll:ISTYPE("boolean") { SET setRoll TO 0. }
		IF force:ISTYPE("boolean") { SET force TO 0. }

		SET Roll_PID:MINOUTPUT TO -force.
		SET Roll_PID:MAXOUTPUT TO force.
		LOCAL curRoll IS rollConvert(roll_for(SHIP)) * rollAngSpeed.
		SET setRoll TO circCalc(setRoll, rollConvert(roll_for(SHIP))) * rollAngSpeed.
		SET RollSpd_PID:SETPOINT TO setRoll.
		SET Roll_PID:SETPOINT TO RollSpd_PID:UPDATE(TIME:SECONDS, curRoll).
		SET SHIP:CONTROL:ROLL TO Roll_PID:UPDATE(TIME:SECONDS, -SHIP:ANGULARMOMENTUM:Y/20).
	}

	FUNCTION killRoll {
		PARAMETER force IS 1.
		SET SHIP:CONTROL:ROLL TO MAX(-force, MIN(force, SHIP:ANGULARMOMENTUM:Y/10)).
	}

	FUNCTION killYaw {
		PARAMETER force IS 1.
		SET SHIP:CONTROL:YAW TO MAX(-force, MIN(force, SHIP:ANGULARMOMENTUM:Z/40)).
	}

	FUNCTION killPit {
		PARAMETER force IS 1.
		SET SHIP:CONTROL:PITCH TO MAX(-force, MIN(force, SHIP:ANGULARMOMENTUM:X/40)).
	}

	FUNCTION stabilize {
		PARAMETER rol.
		IF rol:ISTYPE("boolean") { SET rol TO 0. }

		SET rol TO rollConvert(rol).
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		IF roll_for(SHIP) > 1 OR roll_for(SHIP) < -1 {
			roll(rol, 1).
		} ELSE {
			killRoll(0.5).
			killYaw(0.5).
		}
		IF ABS(SHIP:ANGULARMOMENTUM:Y) < 1 AND ABS(SHIP:ANGULARMOMENTUM:Z) < 5 {
			SAS OFF.
			RETURN TRUE.
		} ELSE {
			IF ABS(SHIP:ANGULARMOMENTUM:Y) < 2 AND ABS(SHIP:ANGULARMOMENTUM:Z) < 20 {
				SAS ON.
			}
			RETURN FALSE.
		}
	}

	FUNCTION flip {
		PARAMETER flipSpeed, rollDir.
		IF flipSpeed:ISTYPE("boolean") { SET flipSpeed TO 24. }
		IF rollDir:ISTYPE("boolean") { SET rollDir TO 0. }

		SET rollDir TO rollConvert(rollDir).
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		IF rollDir = 180 {
			SET flipSpeed TO -flipSpeed.
		}
		IF VANG(UP:VECTOR, SHIP:FACING:TOPVECTOR) < VANG(UP:VECTOR, -SHIP:FACING:TOPVECTOR) {
			SET rollDir TO 0.
		} ELSE {
			SET rollDir TO 180.
		}
		IF vang(UP:VECTOR, SHIP:FACING:FOREVECTOR) < 20 {
			killRoll(0.2).
		} ELSE {
			roll(rollDir, 0.2).
		}
		killYaw(0.1).
		SET Pitch_PID:SETPOINT TO flipSpeed.
		IF (-SHIP:ANGULARMOMENTUM:X/150) < flipSpeed * 0.8 OR (-SHIP:ANGULARMOMENTUM:X/150) > flipSpeed * 1.2 {
			SET SHIP:CONTROL:PITCH TO Pitch_PID:UPDATE(TIME:SECONDS, -SHIP:ANGULARMOMENTUM:X/150).
		} ELSE {
			SET SHIP:CONTROL:PITCH TO 0.
		}
	}

	GLOBAL AttitudeControl IS {
		PARAMETER task, param1 IS FALSE, param2 IS FALSE.
		IF task = "flip" { flip(param1, param2). }
		ELSE IF task = "roll" { roll(param1, param2). }
		ELSE IF task = "stabilize" { RETURN stabilize(param1). }
	}.
}

{	//	Calculating the landing burn using a reverse-landing simulation
	LOCAL IPS IS 10.	//	Iterations per second
	LOCAL last IS 0.
	LOCAL press IS 0.
	LOCAL engs IS vehicle["engines"].
	LOCAL e IS SHIP:PARTSTAGGED(engs["list"][0])[0].
	LOCAL touchDownTime IS IPS*3.	//	How many iterations should the touchdown take
	
	FUNCTION setUp {
		PARAMETER dryDeltaV.
		SET landingBurnData["dryMass"] TO Booster("dryMass").
		landingBurnData["speed"]:CLEAR. landingBurnData["speed"]:ADD(0).
		landingBurnData["altitude"]:CLEAR. landingBurnData["altitude"]:ADD(lzAltitude).
		landingBurnData["mass"]:CLEAR. landingBurnData["mass"]:ADD(landingBurnData["dryMass"] + Booster("massOfDeltaV", dryDeltaV)).
		SET landingBurnData["dvSpent"] TO 0.
	}

	FUNCTION getMaxThrust {
		PARAMETER p IS press.
		RETURN engs["maxThrust"]/e:VISP * e:ISPAT(p).
	}

	FUNCTION getFlow {
		PARAMETER tval.
		RETURN tval * getMaxThrust(0) / (e:VISP*g0).
	}

	FUNCTION getTimeToTermVel {
		IF last < 1 { RETURN 10. }
		LOCAL tvel IS TerminalVelocity(landingBurnData["altitude"][last], landingBurnData["mass"][last]*1000, landingBurnData["speed"][last])*1.05.
		LOCAL acc IS (landingBurnData["speed"][last]-landingBurnData["speed"][last-1])*10.
		RETURN (tvel - landingBurnData["speed"][last])/acc.
	}

	FUNCTION iterate {
		SET last TO landingBurnData["speed"]:LENGTH-1.
		SET press TO BODY:ATM:ALTITUDEPRESSURE(landingBurnData["altitude"][last]).

		LOCAL tval IS min(engs["minThrottle"] + (last/(touchDownTime/(landing["landingThrottle"] - engs["minThrottle"]))), landing["landingThrottle"]).
		LOCAL numEngs IS 1.
		IF last > touchDownTime + IPS*0.5 AND getTimeToTermVel() > 2 {	//	Due to how I calculate terminal velocity, 2 outer engines should start 0.5 seconds after center one, not 2 secods
			SET numEngs TO landing["landingEngines"].
		}
		LOCAL eForce IS getMaxThrust() * tval * numEngs.
		LOCAL dForce IS DragForce(landingBurnData["altitude"][last], landingBurnData["speed"][last]).
		LOCAL acc IS (dForce+eForce)/landingBurnData["mass"][last] - Gravity(landingBurnData["altitude"][last]).
		LOCAL engAcc IS eForce/landingBurnData["mass"][last].

		landingBurnData["speed"]:ADD(landingBurnData["speed"][last] + (acc/IPS)).
		landingBurnData["altitude"]:ADD(landingBurnData["altitude"][last] + (landingBurnData["speed"][last+1]/IPS)).
		landingBurnData["mass"]:ADD(landingBurnData["mass"][last] + (getFlow(tval)*numEngs)/IPS).
		SET landingBurnData["dvSpent"] TO landingBurnData["dvSpent"] + (engAcc/IPS).

		IF landingBurnData["speed"][last+1] > TerminalVelocity(landingBurnData["altitude"][last+1], landingBurnData["mass"][last+1]*1000, landingBurnData["speed"][last+1])*1.05 { RETURN TRUE. }
		ELSE { RETURN FALSE. }
	}

	GLOBAL CalculateLandingBurn IS {
		PARAMETER dryDeltaV IS 50.

		setUp(dryDeltaV).
		LOCAL done IS FALSE.
		UNTIL done {
			SET done TO iterate().
		}
	}.
}

//	Rodrigues vector rotation formula - Borrowed from PEGAS
FUNCTION Rodrigues {
	PARAMETER inVector.	//	Expects a vector
	PARAMETER axis.		//	Expects a vector
	PARAMETER angle.	//	Expects a scalar
	
	SET axis TO axis:NORMALIZED.
	
	LOCAL outVector IS inVector*COS(angle).
	SET outVector TO outVector + VCRS(axis, inVector)*SIN(angle).
	SET outVector TO outVector + axis*VDOT(axis, inVector)*(1-COS(angle)).
	
	RETURN outVector.
}

//	Function that returns a normal vector
FUNCTION GetNormalVec {
	PARAMETER prog IS SHIP:VELOCITY:SURFACE, pos IS SHIP:POSITION - BODY:POSITION.
	RETURN VCRS(prog,pos).
}

// nodeFromVector - originally created by reddit user ElWanderer_KSP
FUNCTION NodeFromVector {
	PARAMETER vec, n_time IS TIME:SECONDS.

	LOCAL s_pro IS VELOCITYAT(SHIP,n_time):ORBIT.
	LOCAL s_pos IS POSITIONAT(SHIP,n_time) - BODY:POSITION.
	LOCAL s_nrm IS VCRS(s_pro,s_pos).
	LOCAL s_rad IS VCRS(s_nrm,s_pro).

	RETURN LIST(VDOT(vec,s_rad:NORMALIZED), VDOT(vec,s_nrm:NORMALIZED), VDOT(vec,s_pro:NORMALIZED)).
}

//	Determines the best burn vector for reentry
FUNCTION GetReentry {
	PARAMETER final IS FALSE.
	//	RBS is short for Reentry Burn Stats
	IF NOT (DEFINED RBS) {
		GLOBAL RBS IS LEXICON(
			"anglePro", 0,
			"progradeInc", 0.5,
			"angleNor", 0,
			"normalInc", 0.5,
			"counter", 0,
			"counterLength", 20,
			"distance", landingOffset:MAG
		).
	}
	IF landingOffset:MAG < 500 {
		//	If landing distance just came below 500m, increase precission by making increments smaller
		IF ABS(RBS["progradeInc"]) = 0.5 {
			SET RBS["progradeInc"] TO RBS["progradeInc"]/5.
			SET RBS["normalInc"] TO RBS["normalInc"]/5.
		}
		SET RBS["counterLength"] TO 10.
	} ELSE {
		//	If landing distance just increased beyond 500m, decrease precission by making increments larger but not as large as at the start
		IF ABS(RBS["progradeInc"]) = 0.1 {
			SET RBS["progradeInc"] TO RBS["progradeInc"]*5.
			SET RBS["normalInc"] TO RBS["normalInc"]*5.
		}
		SET RBS["counterLength"] TO 20.
	}
	//	Increment the angles depending distance
	IF RBS["counter"] < RBS["counterLength"]/2 {
		IF landingOffset:MAG > RBS["distance"] {
			SET RBS["progradeInc"] TO -RBS["progradeInc"].
		}
		SET RBS["anglePro"] TO MIN(15, MAX(-15, RBS["anglePro"] + RBS["progradeInc"])).
	} ELSE {
		IF landingOffset:MAG > RBS["distance"] {
			SET RBS["normalInc"] TO -RBS["normalInc"].
		}
		SET RBS["angleNor"] TO MIN(15, MAX(-15, RBS["angleNor"] + RBS["normalInc"])).
	}

	//	Increment or reset the counter
	IF RBS["counter"] >= RBS["counterLength"] - 1 { SET RBS["counter"] TO 0. } ELSE { SET RBS["counter"] TO RBS["counter"] + 1. }

	//	Set up some vectors
	LOCAL pro IS VELOCITYAT(SHIP, mT + reentryNode:ETA-0.1):SURFACE.
	LOCAL pos IS POSITIONAT(SHIP, mT + reentryNode:ETA-0.1).
	//	Calculate the burn vector, up/down movement first and sideways after that
	LOCAL burnVector IS Rodrigues(-pro, GetNormalVec(pro, pos - BODY:POSITION), RBS["anglePro"]).
	LOCAL extraDv IS 0.
	IF final { SET extraDv TO 500. }
	SET burnVector TO Rodrigues(burnVector, pos - BODY:POSITION, RBS["angleNor"]):NORMALIZED *  (reentryBurnDeltaV + extraDv).
	//	Create a node out of new burn vector
	LOCAL nodeData IS NodeFromVector(burnVector, mT + reentryNode:ETA-0.1).
	SET reentryNode:RADIALOUT TO nodeData[0].
	SET reentryNode:NORMAL TO nodeData[1].
	SET reentryNode:PROGRADE TO nodeData[2].
}

//	Function for sending messages and saving a response
FUNCTION SendMessage {
	PARAMETER type.
	PARAMETER data.
	PARAMETER cpuName IS vehicle["pegas_cpu"].

	IF PROCESSOR(cpuName):CONNECTION:SENDMESSAGE(LEXICON("type", type, "data", data, "sender", CORE:TAG)) {
		WHEN NOT CORE:MESSAGES:EMPTY THEN { SET lastResponse TO CORE:MESSAGES:POP:CONTENT. }
		RETURN TRUE.
	}
	RETURN FALSE.
}

FUNCTION Gravity {
	PARAMETER a IS SHIP:ALTITUDE.
	RETURN BODY:MU / (BODY:RADIUS + a)^2.
}

FUNCTION ShipCurrentTWR {
	RETURN ShipActiveThrust() / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

FUNCTION ShipTWR {
	RETURN SHIP:MAXTHRUST / SHIP:MASS / Gravity(SHIP:ALTITUDE).
}

FUNCTION ShipActiveThrust {
	LOCAL activeThrust IS 0.
	LOCAL allEngines IS 0.
	LIST ENGINES IN allEngines.
	FOR engine IN allEngines {
		IF engine:IGNITION {
			SET activeThrust TO activeThrust + engine:THRUST.
		}
	}
	RETURN activeThrust.
}

FUNCTION TimeToAltitude {
	PARAMETER desiredAlt.
	PARAMETER currentAlt IS currentAltitude.
	
	IF currentAlt-desiredAlt <= 0 {
		RETURN 0.
	}
	RETURN (-VERTICALSPEED - SQRT( (verticalspeed*verticalspeed)-(2 * (-Gravity(currentAlt)) * (currentAlt - desiredAlt))) ) /  ((-Gravity(currentAlt))).
}

FUNCTION CreateUI {
	CLEARSCREEN.
	SET TERMINAL:WIDTH TO 53.
	SET TERMINAL:HEIGHT TO 20+20.
	
	PRINT ".---------------------------------------------------.".
	PRINT "| Recovery -                                   v1.1 |".
	PRINT "|---------------------------------------------------|".
	PRINT "| Phase                    | Time                 s |".
	PRINT "|---------------------------------------------------|".
	PRINT "| TWR              /       | Mass               kg  |".
	PRINT "| Altitude              km | Velocity           m/s |".
	PRINT "| Apoapsis              km | Vertical           m/s |".
	PRINT "| Downrange             km | Horizontal         m/s |".
	PRINT "| Impact Dist.          km | DeltaV             m/s |".
	PRINT "| Impact Time           s  | Impact Vel.        m/s |".
	PRINT "| LZ Distance           km | Drag Force         kN  |".
	PRINT "|---------------------------------------------------|".
	PRINT "|         |                                         |".
	PRINT "|         |                                         |".
	PRINT "|         |                                         |".
	PRINT "|         |                                         |".
	PRINT "|         |                                         |".
	PRINT "|         |                                         |".
	PRINT "'---------------------------------------------------'".
	
	PrintValue(SHIP:NAME, 1, 13, 44, "L").
}

//	Print text at the given place on the screen. Pad and trim when needed. - Borrowed from PEGAS
FUNCTION PrintValue {
	PARAMETER val.			//	Message to write (string/scalar)
	PARAMETER line.			//	Line to write to (scalar)
	PARAMETER start.		//	First column to write to, inclusive (scalar)
	PARAMETER end.			//	Last column to write to, exclusive (scalar)
	PARAMETER align IS "l".	//	Align: "l"eft or "r"ight
	PARAMETER prec IS 0.	//	Decimal places (scalar)
	PARAMETER addSpaces IS TRUE.	//	Add spaces between every 3 digits

	LOCAL str IS "".
	IF val:ISTYPE("scalar") {
		SET str TO "" + ROUND(val, prec).
		//	Make sure the number has all the decimal places it needs to have
		IF prec > 0 {
			LOCAL hasZeros IS 0.
			IF str:CONTAINS(".") { SET hasZeros TO str:LENGTH - str:FIND(".") - 1. }
			ELSE { SET str TO str + ".". }
			FROM { LOCAL i IS hasZeros. } UNTIL i = prec STEP { SET i TO i + 1. } DO {
				SET str TO str + "0".
			}
		}
		//	Add a space between each 3 digits
		IF addSpaces {
			IF prec > 0 { SET prec TO prec+1. }
			IF str:LENGTH-prec > 3 {
				LOCAL addedSpaces IS FLOOR((str:LENGTH-prec-1)/3).
				LOCAL firstSpaceIndex IS (str:LENGTH-prec) - (addedSpaces*3).
				LOCAL desiredLength IS str:LENGTH - prec + addedSpaces.
				FROM { LOCAL i IS firstSpaceIndex. } UNTIL i + 4 >= desiredLength STEP { SET i TO i + 4. } DO {
					SET str TO str:INSERT(i, " ").
				}
			}
		}
	} ELSE { SET str TO val. }
	
	SET align TO align:TOLOWER().
	LOCAL flen IS end - start.
	//	If message is too long to fit in the field - trim, depending on type.
	IF str:LENGTH>flen {
		IF align="r" { SET str TO str:SUBSTRING(str:LENGTH-flen, flen). }
		ELSE IF align="l" { SET str TO str:SUBSTRING(0, flen). }
	}
	ELSE {
		IF align="r" { SET str TO str:PADLEFT(flen). }
		ELSE IF align="l" { SET str TO str:PADRIGHT(flen). }
	}
	PRINT str AT(start, line).
}

FUNCTION RefreshUI {
	IF runmode = 0 { PrintValue("Pre-launch", 3, 8, 26, "R"). }
	ELSE IF runmode = 1 { IF mT - lT > 0 { PrintValue("Ascent (PEGAS)", 3, 8, 26, "R"). } }
	ELSE IF runmode = 2 { PrintValue("Boostback", 3, 8, 26, "R"). }
	ELSE IF runmode = 3 { PrintValue("Re-entry", 3, 8, 26, "R"). }
	ELSE IF runmode = 4 { PrintValue("Landing", 3, 8, 26, "R"). }
	ELSE IF runmode = 5 { PrintValue("Landed", 3, 8, 26, "R"). }
	IF mT-lT < 0 { PrintValue("T" + ROUND(mT-lT), 3, 34, 50, "R"). } ELSE { PrintValue("T+" + ROUND(mT-lT), 3, 34, 50, "R"). }
	PrintValue(ShipCurrentTWR(), 5, 13, 18, "R", 2). PrintValue(ShipTWR(), 5, 21, 26, "R", 2).
	PrintValue(currentAltitude/1000, 6, 11, 24, "R", 3).
	PrintValue(SHIP:OBT:APOAPSIS/1000, 7, 11, 24, "R", 3).
	PrintValue(launchSiteDistance/1000, 8, 12, 24, "R", 3).
	PrintValue(lzImpactDistance:MAG/1000, 9, 15, 24, "R", 3).
	PrintValue(impactTime, 10, 14, 24, "R").
	PrintValue(lzCurrentDistance:MAG/1000, 11, 14, 24, "R", 3).
	PrintValue(SHIP:MASS*1000, 5, 34, 48, "R").
	PrintValue(SHIP:VELOCITY:SURFACE:MAG, 6, 38, 48, "R").
	PrintValue(VERTICALSPEED, 7, 38, 48, "R").
	PrintValue(GROUNDSPEED, 8, 40, 48, "R").
	PrintValue(boosterDeltaV, 9, 36, 48, "R").
	PrintValue(impactVelocity:MAG, 10, 41, 48, "R").
	PrintValue(DragForce(), 11, 40, 48, "R", 1).

	IF UILex["message"]:LENGTH <> UILexLength {
		UNTIL UILex["message"]:LENGTH <= 6 { UILex["message"]:REMOVE(0). UILex["time"]:REMOVE(0). }
		SET UILexLength TO UILex["message"]:LENGTH.

		FROM { LOCAL i IS UILexLength-1. LOCAL l IS 0. } UNTIL i = -1 STEP { SET i TO i - 1. SET l TO l + 1. } DO {
			IF UILex["time"][i] >= lT {
				PrintValue("T+" + ROUND(UILex["time"][i] - lT) + "s", 13 + l, 2, 8, "L", 0).
			} ELSE {
				PrintValue("T" + ROUND(UILex["time"][i] - lT) + "s", 13 + l, 2, 8, "L", 0).
			}
			PrintValue(UILex["message"][i], 13 + l, 12, 50, "L").
		}
	}
}

FUNCTION AddUIMessage {
	PARAMETER message IS FALSE.
	IF message:ISTYPE("String") {
		UILex["time"]:ADD(TIME:SECONDS).
		UILex["message"]:ADD(message).
	}
}