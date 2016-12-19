// Ship telemetry calculations

FUNCTION currentBody {
	RETURN BODY:NAME.
}

FUNCTION staticGravity {
	RETURN BODY:MU / BODY:RADIUS^2.
}

function gravity {
	parameter alti.
	return body:mu / (body:radius + alti)^2.
}

FUNCTION shipMass {
	RETURN SHIP:MASS.
}

FUNCTION shipWetMass {
	RETURN SHIP:WETMASS.
}

FUNCTION shipDryMass {
	RETURN SHIP:DRYMASS.
}

FUNCTION shipAcc {
	IF engineFlameout() = FALSE {
		RETURN SHIP:MAXTHRUST / SHIP:MASS.
	}
	RETURN 0.1.
}

function shipCurrentTWR {
	return shipActiveThrust() / ship:mass / gravity(ship:altitude).
}

function shipTWR {
	return ship:maxthrust / ship:mass / gravity(ship:altitude).
}

FUNCTION shipSeaLevelTWR {
	RETURN SHIP:MAXTHRUST / SHIP:MASS / staticGravity().
}

FUNCTION atmHeight {	
	IF BODY:ATM:EXISTS {
		RETURN BODY:ATM:HEIGHT.
	} ELSE {
		RETURN "No atmosphere".
	}
}

FUNCTION shipActiveThrust {
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

FUNCTION engineFlameout {
	LOCAL allEngines IS 0.
	LIST ENGINES IN allEngines.
	FOR engine IN allEngines {
		IF engine:IGNITION AND engine:FLAMEOUT {
			RETURN TRUE.
		}
	}
	
	RETURN FALSE.
}

function deltaV {
	local dryMass is ship:mass - ((ship:liquidfuel + ship:oxidizer) * 0.005).
	list engines in shipEngines.
	return shipEngines[0]:isp * 9.80665 * ln(ship:mass / dryMass).
}

function timeToAltitude
{
	parameter desiredAltitude.
	parameter currentAltitude.
	
	if currentAltitude-desiredAltitude <= 0 {
		return 0.
	}
	return (-verticalspeed - sqrt( verticalspeed^2-(2 * (-gravity(currentAltitude)) * (currentAltitude - desiredAltitude))) ) /  ((-gravity(currentAltitude))).
}