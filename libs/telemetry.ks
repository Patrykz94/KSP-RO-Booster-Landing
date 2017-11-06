// Ship telemetry calculations

function gravity {
	parameter alti is ship:altitude.
	return body:mu / (body:radius + alti)^2.
}

function shipCurrentTWR {
	return shipActiveThrust() / ship:mass / gravity(ship:altitude).
}

function shipTWR {
	return ship:maxthrust / ship:mass / gravity(ship:altitude).
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

function timeToAltitude
{
	parameter desiredAltitude.
	parameter currentAltitude.
	
	if currentAltitude-desiredAltitude <= 0 {
		return 0.
	}
	return (-verticalspeed - sqrt( verticalspeed^2-(2 * (-gravity(currentAltitude)) * (currentAltitude - desiredAltitude))) ) /  ((-gravity(currentAltitude))).
}