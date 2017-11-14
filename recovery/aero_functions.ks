//	returns approximated desnity of air at a given altitude as kg/m^3
FUNCTION ATMDens {
	PARAMETER a IS SHIP:ALTITUDE.
	
	LOCAL SLDens IS 1.22.
	LOCAL scaleHeight IS 8500.
	RETURN SLDens * CONSTANT:E^(-a/scaleHeight).
}

//	Returns drag coefficient. Expects surface velocity as parameter
FUNCTION DragCoeff {
	PARAMETER v IS 250.
	LOCAL m IS ABS(v)/340.29.	//	Mach number
	LOCAL Cd IS 0.
	IF ROUND(m,2) < 0.6 {
		SET Cd TO vehicle["current"]["aerodynamics"]["CdMin"].
	} ELSE IF ROUND(m,2) >= 0.6 and ROUND(m,2) <= 1.19 {
		SET Cd TO vehicle["current"]["aerodynamics"]["CdRound2"][m].
	} ELSE IF ROUND(m,1) >= 1.2 and ROUND(m,1) <= 2.4 {
		SET Cd TO vehicle["current"]["aerodynamics"]["CdRound1"][m].
	} ELSE {
		SET Cd TO vehicle["current"]["aerodynamics"]["CdMax"](m).
	}
	RETURN Cd.
}

FUNCTION DragForce {
	LOCAL d IS ATMDens(SHIP:ALTITUDE).
	LOCAL s IS SHIP:VELOCITY:SURFACE:MAG.
	LOCAL ar IS vehicle["current"]["aerodynamics"]["surfaceArea"].
	LOCAL Cd IS DragCoeff(s).
	RETURN (0.5 * d * s^2 * Cd * ar)/1000.
}

FUNCTION TerminalVelocity {
	PARAMETER a IS SHIP:ALTITUDE.
	LOCAL d IS ATMDens(a).
	LOCAL g IS Gravity(a).
	LOCAL ar IS vehicle["current"]["aerodynamics"]["surfaceArea"].
	LOCAL Cd IS DragCoeff().
	RETURN SQRT((2*(SHIP:MASS*1000)*g)/(d*ar*Cd)).
}

FUNCTION landingBurnData {
	PARAMETER vel IS SHIP:VELOCITY:SURFACE.
	PARAMETER tVel IS termVel().
	
	LOCAL t IS 0.
	LOCAL acc IS 0.
	LOCAL dryMass IS Fuel["Mass"][0].
	LOCAL fuelMass IS Fuel["Mass"][1].
}