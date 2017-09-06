@lazyglobal off.
run "0:/libs/telemetry.ks". // Remove this line later

function ATMDens { // returns the desnity of air at a given altitude as kg/m^3
	parameter alti is ship:altitude.
	
	local SLDens is 1.22.
	local scaleHeight is 8500.
	return SLDens * constant:e^(-alti/scaleHeight).
}

function DragCoeff {
	parameter vel is 250.
	local mach is abs(vel)/340.29.
	local Cd is 0.
	if round(mach,2) < 0.63 {
		set Cd to 0.0386.
	} else if round(mach,2) >= 0.63 and round(mach,2) <= 1.19 {
		set Cd to CdDataX2[round(mach,2)*200-125].
	} else if round(mach,1) >= 1.2 and round(mach,1) <= 2.4 {
		set Cd to CdDataX1[round(mach,1)*20-23].
	} else {
		set Cd to 1.1237*(0.9622907946^mach).
	}
	return Cd.
}

function DragForce {
	local d is ATMDens(ship:altitude).
	local s is ship:velocity:surface:mag.
	local a is 17.1766.
	local Cd is DragCoeff(s).
	return (0.5 * d * s^2 * Cd * a)/1000.
}

function TermVel {
	parameter alti is ship:altitude.
	local d is ATMDens(ship:altitude).
	local g is gravity(ship:altitude).
	local a is 17.1766.
	local Cd is DragCoeff().
	return sqrt((2*(ship:mass*1000)*g)/(d*a*Cd)).
}

function landingBurnData {
	parameter vel is ship:velocity:surface.
	parameter tVel is termVel().
	
	local t is 0.
	local acc is 0.
	local dryMass is Fuel["Mass"][0].
	local fuelMass is Fuel["Mass"][1].
}

function betterTimeToImpact {
	parameter alt0.
	
	local d is 0.
	local g is 0.
	local a is 17.1766.
	local Cd is 1.
}

// Falcon 9 Cd values gathered from FAR
local CdDataX2 is list(
//	Mach	Cd
	0.63,	0.0388,
	0.64,	0.0426,
	0.65,	0.0488,
	0.66,	0.0637,
	0.67,	0.0762,
	0.68,	0.0969,
	0.69,	0.1255,
	0.7,	0.1355,
	0.71,	0.1847,
	0.72,	0.2119,
	0.73,	0.249,
	0.74,	0.2922,
	0.75,	0.3283,
	0.76,	0.3736,
	0.77,	0.4159,
	0.78,	0.4629,
	0.79,	0.5087,
	0.8,	0.5585,
	0.81,	0.6027,
	0.82,	0.6506,
	0.83,	0.699,
	0.84,	0.7493,
	0.85,	0.7901,
	0.86,	0.832,
	0.87,	0.8776,
	0.88,	0.9209,
	0.89,	0.9597,
	0.9,	0.9976,
	0.91,	1.0329,
	0.92,	1.0666,
	0.93,	1.0977,
	0.94,	1.1249,
	0.95,	1.1477,
	0.96,	1.1661,
	0.97,	1.1814,
	0.98,	1.1929,
	0.99,	1.1994,
	1,		1.202,
	1.01,	1.2022,
	1.02,	1.2023,
	1.03,	1.2024,
	1.04,	1.2025,
	1.05,	1.2026,
	1.06,	1.2026,
	1.07,	1.2025,
	1.08,	1.2026,
	1.09,	1.2031,
	1.1,	1.203,
	1.11,	1.2028,
	1.12,	1.2024,
	1.13,	1.2023,
	1.14,	1.2018,
	1.15,	1.2012,
	1.16,	1.2006,
	1.17,	1.1999,
	1.18,	1.1992,
	1.19,	1.1985
).

local CdDataX1 is list(
//	Mach	Cd
	1.2,	1.1977,
	1.3,	1.1884,
	1.4,	1.1761,
	1.5,	1.1632,
	1.6,	1.1488,
	1.7,	1.1342,
	1.8,	1.1197,
	1.9,	1.1051,
	2,		1.0937,
	2.1,	1.0773,
	2.2,	1.0658,
	2.3,	1.0579,
	2.4,	1.0491
).

//Temporary test code

//clearscreen.

//until false {

//print "Gravity:                   " + round(gravity(ship:altitude),3) + "     " at (3, 5).
//print "ATM Desnity:               " + round(ATMDens(ship:altitude),3) + "     " at (3, 6).
//print "Terminal Velocity:         " + round(TermVel(ship:altitude),2) + "     " at (3, 7).
//print "Coefficient of Drag:       " + round(DragCoeff(ship:velocity:surface:mag),4) + "     " at (3, 9).
//print "Drag Force:                " + round(DragForce(),3) + "     " at (3, 10).

}