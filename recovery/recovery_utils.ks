//	Recovery utilities

LOCAL ullageReq IS FALSE.

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

FUNCTION Booster {
	PARAMETER task.
	PARAMETER param IS FALSE.

	LOCAL tank IS SHIP:PARTSTAGGED(vehicle["current"]["fuel"]["tankNametag"]).

	FUNCTION fuelMass {
		PARAMETER fuelType.
		IF NOT fuelType:ISTYPE("List") {
			SET fuelType TO LIST(fuelType).
		}
		LOCAL amount IS 0.
		LOCAL mass IS 0.
		FOR t IN tank {
			FOR r IN t:RESOURCES {
				FOR fuel IN fuelType {
					IF r:NAME = fuel {
						SET amount TO amount + r:AMOUNT.
						SET mass TO mass + (r:AMOUNT * r:DENSITY).
					}
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

	FUNCTION deltaV {
		PARAMETER param IS SHIP:SENSORS:PRES * CONSTANT:KPATOATM.
		LOCAL e IS SHIP:PARTSTAGGED(vehicle["current"]["engine"]["list"][0])[0].
		LOCAL dm IS trueDryMass().
		//	Not 100% sure if 9.80665 should be used
		RETURN e:ISPAT(press) * 9.80665 * LN((dm + fuelMass(vehicle["current"]["fuel"]["list"])[1] / dm).
	}

	IF task = "deltaV" { IF param = FALSE { RETURN deltaV(). } ELSE { RETURN deltaV(param). } }
}


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

// nodeFromVector function was originally created by reddit user ElWanderer_KSP
function nodeFromVector // create a maneuver node from burn vector
{
	parameter vec, n_time is time:seconds.
	local s_pro is velocityat(ship,n_time):surface.
	local s_pos is positionat(ship,n_time) - body:position.
	local s_nrm is vcrs(s_pro,s_pos).
	local s_rad is vcrs(s_nrm,s_pro).

	set nd:prograde to vdot(vec,s_pro:normalized).
	set nd:normal to vdot(vec,s_nrm:normalized).
	set nd:radialout to vdot(vec,s_rad:normalized).
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

function sendMessage {
	parameter type.
	parameter data.

	if processor("Falcon9S2"):connection:sendmessage(LEXICON("type", type, "data", data, "sender", CORE:TAG)) {
		when not core:messages:empty then { set lastResponse to core:messages:pop:content. }
		return true.
	}
	return false.
}

function getNormal {
	parameter prog is ship:velocity:surface.
	parameter pos is ship:position - body:position.
	return vcrs(prog,pos).
}

//	Rodrigues vector rotation formula
function rodrigues {
	declare parameter inVector.	//	Expects a vector
	declare parameter axis.		//	Expects a vector
	declare parameter angle.	//	Expects a scalar
	
	set axis to axis:normalized.
	
	local outVector is inVector*cos(angle).
	set outVector to outVector + vcrs(axis, inVector)*sin(angle).
	set outVector to outVector + axis*vdot(axis, inVector)*(1-cos(angle)).
	
	return outVector.
}