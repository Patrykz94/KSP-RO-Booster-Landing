
function matchTWR {
	parameter expTWR.

	if (shipTWR() > 0) AND (expTWR > 0) {
		return MAX(0, MIN(1, expTWR / shipTWR())).
	} else {
		return 0.
	}
}

function getGravAccConst {
	return 9.80665.
}

function getOrbitalVelocity {
	parameter alt.
	
	return body:radius * sqrt(staticGravity() / (body:radius + alt)).
}

function getObtPeriodAtAlt {
	parameter alt.
	local semimajoraxis is body:radius+alt.
	
	return (constant():PI*2) * sqrt(semimajoraxis^3 / (body:mu)).
}

function getVelocityAtApoapsis {
	return sqrt(((1-obt:eccentricity) * body:mu) / ((1+obt:eccentricity) * obt:semimajoraxis)).
}

function getVelocityAtPeriapsis {
	return sqrt(((1+obt:eccentricity) * body:mu) / ((1-obt:eccentricity) * obt:semimajoraxis)).
}

function getCircularizationDeltaV {
	parameter apo.
	
	return getOrbitalVelocity(apo) - getVelocityAtApoapsis().
}

function nodeBurnTime {
	parameter node.
	return node:deltav:mag / shipAcc().
}

function convAngle {
	parameter angle.
	if angle < 0 {
		set angle to angle + 360.
	}
	return angle.
}