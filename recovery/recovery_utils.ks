//	Recovery utilities

LOCAL ullageReq IS FALSE.

//	Variables for controling rcs system during flips
LOCAL rollAngSpeed IS 600/360.

LOCAL RollSpd_PID IS PIDLOOP(0.2, 0, 0.3, -2, 2).
LOCAL Roll_PID IS PIDLOOP(0.4, 0, 0.3, -1, 1).
LOCAL Pitch_PID IS PIDLOOP(0.2, 0, 0.2, -2, 2).	//	Changed limits from 0.8. Need to test.

//	landing burn variables
LOCAL landingBurnData IS LEXICON("speed", LIST(), "altitude", LIST(), "mass", LIST(), "dryMass", 0).

//	Function to get list of engines, start, shutdown or throttle
FUNCTION Engines {
	PARAMETER task, engineList IS LIST(), param IS FALSE.

	IF task:CONTAINS("Engines") {
		LOCAL engList IS LIST().
		FOR eng IN vehicle["current"]["engines"]["list"] {
			FOR e IN SHIP:PARTSTAGGED(eng) {
				IF engList:LENGTH < landing[task] {
					engList:ADD(e).
				}
			}
		}
		RETURN engList.
	}

	IF engineList:EMPTY {
		FOR eng IN vehicle["current"]["engines"]["list"] {
			FOR e IN SHIP:PARTSTAGGED(eng) {
				engineList:ADD(e).
			}
		}
	}

	FUNCTION start {
		LOCAL engineReady IS TRUE.
		FOR e IN engineList {
			IF NOT e:IGNITION {
				LOCAL eng IS e:GETMODULE("ModuleEnginesRF").
				IF eng:GETFIELD("propellant") <> "Very Stable" {
					SET engineReady TO FALSE.
					SET ullageReq TO TRUE.
				}
			}
		}
		IF engineReady {
			SET ullageReq TO FALSE.
			FOR e IN engineList {
				IF e:IGNITION = FALSE {
					e:ACTIVATE.
				}
			}
		}
	}

	FUNCTION stop {
		FOR e IN engineList {
			IF e:IGNITION {
				e:SHUTDOWN.
			}
		}
	}

	//	Expects param to be the throttle value
	FUNCTION throttle {
		LOCAL minThrottle IS vehicle["current"]["engines"]["minThrottle"].
		SET param TO MAX(minThrottle, MIN(1, param)).
		FOR e IN engineList {
			SET e:THRUSTLIMIT TO (param - minThrottle) / (1 - minThrottle).
		}
	}

	IF task = "start" { start(). }
	ELSE IF task = "stop" { stop(). }
	ELSE IF task = "throttle" { throttle(). }
}

//	Function for getting deltaV and calculating masses
FUNCTION Booster {
	PARAMETER task, param IS FALSE.

	LOCAL tank IS SHIP:PARTSTAGGED(vehicle["current"]["fuel"]["tankNametag"]).

	FUNCTION fuelMass {
		PARAMETER fuelType.
		IF NOT fuelType:ISTYPE("List") { SET fuelType TO LIST(fuelType). }

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
		LOCAL dryMass IS vehicle["current"]["mass"]["dry"].
		FOR f IN vehicle["current"]["fuel"]["rcsFuels"] { SET dryMass TO dryMass + fuelMass(f)[1]. }
		RETURN dryMass.
	}

	//	Maximum DeltaV available in the booster
	FUNCTION deltaV {
		PARAMETER param IS SHIP:SENSORS:PRES * CONSTANT:KPATOATM.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["current"]["engines"]["list"][0])[0].
		LOCAL dm IS trueDryMass().
		//	Not 100% sure if 9.80665 should be used
		RETURN e:ISPAT(press) * 9.80665 * LN((dm + fuelMass(vehicle["current"]["fuel"]["list"])[1] / dm).
	}

	//	Mass of fuel required for the certain DeltaV
	FUNCTION massOfDeltaV {
		PARAMETER param.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["current"]["engines"]["list"][0])[0].
		LOCAL dm IS trueDryMass().
		RETURN dm - (dm * (CONSTANT:E * (param / (e:SLISP * 9.80665)))).
	}

	IF task = "deltaV" { IF param = FALSE { RETURN deltaV(). } ELSE { RETURN deltaV(param). } }
	ELSE IF task = "dryMass" { RETURN trueDryMass(). }
	ELSE IF task = "massOfDeltaV" { IF param = FALSE { RETURN 0. } ELSE { RETURN massOfDeltaV(param). } }
}

//	Controling attitude during flips
FUNCTION AttitudeControl {
	PARAMETER task, param1 IS FALSE, param2 IS FALSE.

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
		IF setRoll:ISTYPE("bool") { SET setRoll TO 0. }
		IF force:ISTYPE("bool") { SET force TO 0. }

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
		PARAMETER roll.
		IF roll:ISTYPE("bool") { SET roll TO 0. }

		SET roll TO rollConvert(roll).
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		IF roll_for(SHIP) > 1 OR roll_for(SHIP) < -1 {
			roll(roll).
		} ELSE {
			killRoll(0.5).
			killYaw(0.5).
		}
		IF ABS(SHIP:ANGULARMOMENTUM:Y) < 1 AND ABS(SHIP:ANGULARMOMENTUM:Z) < 5 {
			RETURN TRUE.
		} ELSE {
			RETURN FALSE.
		}
	}

	FUNCTION flip {
		PARAMETER flipSpeed, rollDir.
		IF flipSpeed:ISTYPE("bool") { SET flipSpeed TO 24. }
		IF rollDir:ISTYPE("bool") { SET rollDir TO 0. }

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

	IF task = "flip" { flip(param1, param2). }
	ELSE IF task = "roll" { roll(param1, param2). }
	ELSE IF task = "stabilize" { stabilize(param1). }
}

FUNCTION CalculateLandingBurn {
	PARAMETER param IS 50.

	FUNCTION setUp {
		SET landingBurnData["dryMass"] TO Booster("dryMass").
		landingBurnData["speed"]:CLEAR. landingBurnData["speed"]:ADD(0).
		landingBurnData["altitude"]:CLEAR. landingBurnData["altitude"]:ADD(lzAltitude).
		landingBurnData["mass"]:CLEAR. landingBurnData["mass"]:ADD(landingBurnData["dryMass"] + Booster("massOfDeltaV", param)).
	}

	FUNCTION iterate {
		LOCAL last IS landingBurnData["speed"]LENGTH-1.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["current"]["engines"]["list"][0])[0].
		LOCAL engThrottle IS e:MAXTHRUST * SHIP:PARTSTAGGED(vehicle["current"]["engines"]["list"][0])[0].
		landingBurnData["speed"]:ADD(landingBurnData["speed"][last]+)

		IF landingBurnData["speed"] > TermVel() { RETURN TRUE. }
		ELSE { RETURN FALSE. }
	}

	IF param:ISTYPE("Scalar") { setUp(). }
	ELSE IF param = "iterate" { RETURN iterate(). }
}

//	Rodrigues vector rotation formula
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

// nodeFromVector function was originally created by reddit user ElWanderer_KSP
FUNCTION NodeFromVector {
	PARAMETER vec, n_time IS TIME:SECONDS.

	LOCAL s_pro IS VELOCITYAT(SHIP,n_time):SURFACE.
	LOCAL s_pos IS POSITIONAT(SHIP,n_time) - BODY:POSITION.
	LOCAL s_nrm IS VCRS(s_pro,s_pos).
	LOCAL s_rad IS VCRS(s_nrm,s_pro).

	RETURN NODE(n_time, VDOT(vec,s_rad:NORMALIZED), VDOT(vec,s_nrm:NORMALIZED), VDOT(vec,s_pro:NORMALIZED)).
}

//	Function for sending messages and saving a response
FUNCTION SendMessage {
	PARAMETER type.
	PARAMETER data.
	PARAMETER cpuName IS vehicle["current"]["pegas_cpu"].

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
	PARAMETER desiredAltitude.
	PARAMETER currentAltitude.
	
	IF currentAltitude-desiredAltitude <= 0 {
		RETURN 0.
	}
	RETURN (-VERTICALSPEED - SQRT( verticalspeed^2-(2 * (-Gravity(currentAltitude)) * (currentAltitude - desiredAltitude))) ) /  ((-Gravity(currentAltitude))).
}

//	----------Below functions haven't been rewritten yet

//	Need to replace this function
function landingBurnTime {
	parameter dv.
	parameter ensNo is 1.
	parameter thrustL is 1.
	local ens is list().
	if ensNo = 1 {
		set ens to list(Merlin1D_0).
	} else if ensNo = 3 {
		set ens to list(Merlin1D_0, Merlin1D_1, Merlin1D_2).
	}
	local ens_thrust is 0.
	local ens_isp is 0.
	local press is ship:sensors:pres * constant:kpatoatm.

	for en in ens {
		local cIsp is en:ispat(press).
		if en:isp = 0 or en:maxthrust = 0 {
			if merlinData[0] = true {
				set ens_thrust to ens_thrust + (merlinData[2] / merlinData[4]* cIsp).
				set ens_isp to ens_isp + cIsp.
			}
		} else {
			set ens_thrust to ens_thrust + en:maxthrust.
			set ens_isp to ens_isp + en:isp.
		}
	}

	if ens_thrust = 0 or ens_isp = 0 {
		//notify("No engines available!").
		return 0.
	} else {
		local f is ens_thrust * thrustL * 1000. // engine thrust (kg * m/s²)
		local m is ship:mass * 1000. // starting mass (kg)
		local e is constant():e. // base of natural log
		local p is ens_isp/ens:length. // engine isp (s) support to average different isp values
		local g is ship:orbit:body:mu/ship:obt:body:radius^2. // gravitational acceleration constant (m/s²)
		
		return g * m * p * (1 - e^(-dv/(g*p))) / f.
	}
}

function landBurnHeight {
	return (ship:velocity:surface:mag^2 / (2*(ship:velocity:surface:mag/landBurnT - gravity()))).
}

function landBurnSpeed {
	return -sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT - gravity()))).
}

function getReentryAngle { // Generate a burn vector for reentry burn experimentaly by checking landing distance and adjusting multiple times
	parameter lastRun is "old".

	if lastRun = "new" { // Generate a maneuver node and a lexicon for tracking changes every iteration
		global reentryAngle is lexicon(
			"id", 0,
			"dist", 1000000,
			"ang", 0,
			"inc", 0.5,
			"best", -velocityat(ship,100):surface,
			"bestD", 1000000,
			"fou", false
			).
		global nd is node(mT + 100, 0, 0, -100).
		global bV is -velocityat(ship,100):surface.
		add nd.
	} else {
		if hasnode {
			if nd:eta < 5 { // At the moment, the script assumes reentry burn only needs to change prograde and radial values and not normal. This will need to be changed
				set bV to reentryAngle["best"]:normalized * (reentryBurnDeltaV + 100).
				nodeFromVector(bV, mT + nd:eta). // For steering reasons, the final meneuver node will have 100m/s more velocity than needed
				set reentryAngle["fou"] to true.
			} else {
				set reentryAngle["id"] to reentryAngle["id"] + 1.
				if landingOffset:mag > reentryAngle["dist"] {
					if reentryAngle["dist"] < 500 {
						if reentryAngle["inc"] > 0 { set reentryAngle["inc"] to 0.1. } else { set reentryAngle["inc"] to -0.1. }
						
					}
					set reentryAngle["inc"] to -reentryAngle["inc"].
				}
				set reentryAngle["dist"] to landingOffset:mag.
				set reentryAngle["ang"] to reentryAngle["ang"] + reentryAngle["inc"].
				if reentryAngle["dist"] < reentryAngle["bestD"] {
					set reentryAngle["bestD"] to reentryAngle["dist"].
					set reentryAngle["best"] to bV.
				}

				set bV to rodrigues(-velocityat(ship,nd:eta-1):surface, getNormal(velocityat(ship,nd:eta-1):surface, positionat(ship,nd:eta-1) - body:position), reentryAngle["ang"]):normalized * reentryBurnDeltaV.
				nodeFromVector(bV, mT + nd:eta).
			}
		} else {
			add nd.
		}
	}
}