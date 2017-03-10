@lazyglobal off.

// ---=== [**START**] [ DECLARING VARIABLES ] [**START**] ===--- //

	local KSCLaunchPad is latlng(28.6083859739973, -80.5997467227517).
	local Waypoint is latlng(28.6183859739973, -80.5997467227517).
	
	if volume(1):name = "Falcon9-S2" {
		local Merlin1D_Vac is ship:partstagged("Merlin1D-Vac")[0].
	}
		local Merlin1D_0 is ship:partstagged("Merlin1D-0")[0].
		local Merlin1D_1 is ship:partstagged("Merlin1D-1")[0].
		local Merlin1D_2 is ship:partstagged("Merlin1D-2")[0].
		local Merlin1D_3 is ship:partstagged("Merlin1D-3")[0].
		local Merlin1D_4 is ship:partstagged("Merlin1D-4")[0].
		local Merlin1D_5 is ship:partstagged("Merlin1D-5")[0].
		local Merlin1D_6 is ship:partstagged("Merlin1D-6")[0].
		local Merlin1D_7 is ship:partstagged("Merlin1D-7")[0].
		local Merlin1D_8 is ship:partstagged("Merlin1D-8")[0].
		
	local ullageReq is false.
	
	local merlinData is list( false ).
	
// ---=== [**START**] [ DECLARING VARIABLES ] [**START**] ===--- //

{ // Falcon Engine Management Functions (FEMF..)
	
	function startEngine {
		parameter engineList.
		local engineReady is true.
		
		for engine in engineList {
			local eng is engine:getModule("ModuleEnginesRF").
			if eng:getField("propellant") <> "Very Stable" {
				set engineReady to false.
				set ullageReq to true.
			}
		}
		
		if engineReady {
			set ullageReq to false.
			for engine in engineList {
				if engine:ignition = false {
					engine:activate.
				}
			}
		}
	}
	
	function stopEngine {
		parameter engineList.
		
		for engine in engineList {
			if engine:ignition {
				engine:shutdown.
			}
		}
	}
	
	function setThrottle {
		parameter engineList.
		for engine in engineList {
			local minThrottle is 0.
			if engine[0]:name = "KK.SPX.Merlin1D+" { set minThrottle to 36. } else { set minThrottle to 39. }
			set engine[1] to min(100, max(minThrottle, engine[1])).
			local multiplier is 1 / (1 - (minThrottle * 0.01)).
			
			set engine[0]:thrustlimit to (engine[1] * multiplier) - (minThrottle * multiplier).
		}
	}
	
	global Engine is lexicon(
		"Start", startEngine@,
		"Stop", stopEngine@,
		"Throttle", setThrottle@
	).
	
	//--== Starting an engine example: ==--
	//	Engine["Start"](list(
	//		mainEngines[0],
	//		mainEngines[3],
	//		mainEngines[4]
	//	)).
	
	//--== Stopping an engine example: ==--
	//	Engine["Stop"](list(
	//		mainEngines[0],
	//		mainEngines[3],
	//		mainEngines[4]
	//	)).
	
	//--== Setting throttle level example: ==--
	//	Engine["Throttle"](
	//		list(
	//			list(mainEngines[0], 36),
	//			list(mainEngines[3], 36),
	//			list(mainEngines[4], 36)
	//	)).
	
}

// Falcon Fuel Control Functions (FFCF..)

{
	local f9DryMass is 22.9364756622314.
	local f9tank is ship:partstagged("Falcon9-S1-Tank")[0].
	
	function getF9DeltaV {
		parameter press is ship:sensors:pres * constant:kpatoatm.
		local totalFuelMass is 0.
		local f9Dry is f9DryMass.
		local resources is f9tank:resources.
		for resource in resources {
			if resource:name = "Kerosene" or resource:name = "LqdOxygen" {
				set totalFuelMass to totalFuelMass + (resource:density * resource:amount).
			} else if resource:name = "Nitrogen" {
				set f9Dry to f9Dry + (resource:density * resource:amount).
			}
		}
		return Merlin1D_0:ispat(press) * 9.80665 * ln((f9Dry + totalFuelMass) / f9Dry).
	}
	
	global Fuel is lexicon(
		"Stage 1 DeltaV", getF9DeltaV@
	).
}

function landingDeltaV { // Calculating the deltaV required at separation
	parameter landing is 1.
	local delv is 0.
	
	if landing <> 0 {
		if landing <= 10 {
			set delv to (groundspeed * 1.4) + 800 + 400.
		} else if landing <= 20 {
			set delv to (groundspeed * 0.75) + 800 + 400.
		} else {
			set delv to (groundspeed * 0.4) + 300.
		}
	}
	
	return delv.
}

function landingBurnTime {
	parameter dv.
	parameter ensNo is 1.
	parameter thrustL is 1.
	//local dv2 is 50.
	//local dv1 is max(0, dv - dv2).
	local ens is list().
	if ensNo = 1 {
		set ens to list(Merlin1D_0).
	} else if ensNo = 3 {
		set ens to list(Merlin1D_0, Merlin1D_1, Merlin1D_2).
	}
	local ens_thrust is 0.
	local ens_isp is 0.

	for en in ens {
		if en:isp = 0 or en:maxthrust = 0 {
			if merlinData[0] = true {
				set ens_thrust to ens_thrust + merlinData[1].
				set ens_isp to ens_isp + merlinData[3].
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
		local f1 is ens_thrust * thrustL * 1000.  // engine thrust (kg * m/s²)
		//local f2 is ens_thrust/ens:length * 0.4 * 1000.  // engine thrust (kg * m/s²)
		local m is ship:mass * 1000.        // starting mass (kg)
		local e is constant():e.            // base of natural log
		local p is ens_isp/ens:length.               // engine isp (s) support to average different isp values
		local g is ship:orbit:body:mu/ship:obt:body:radius^2.    // gravitational acceleration constant (m/s²)
		
		//local t2 is g * m * p * (1 - e^(-dv2/(g*p))) / f2.
		//if dv1 = 0 {
		//	return list(max(0.001, t2), 0.001, max(0.001, t2)).
		//} else {
		//	local t1 is g * m * p * (1 - e^(-dv1/(g*p))) / f1.
		//	return list(max(0.001, t1+t2), max(0.001, t1), max(0.001, t2)).
		//}
		return list(g * m * p * (1 - e^(-dv/(g*p))) / f1).
	}
}

function landBurnHeight {
	if verticalspeed < 0 {
		local height1 is 0.
		//local height2 is min(50, ship:velocity:surface:mag)^2 / (2*(min(50, ship:velocity:surface:mag)/landBurnT[2] - gravity())).
		//if ship:velocity:surface:mag > 50 {
		set height1 to ship:velocity:surface:mag^2 / (2*(ship:velocity:surface:mag/landBurnT[0] - gravity())).
		return list(height1).
		//} else {
		//	set height1 to 0.
		//}
		//return list(max(0.001, height1+height2), max(0.001, height1), max(0.001, height2)).
	} else {
		return list(0.001,0.001,0.001).
	}
}

function landBurnSpeed {
	//if ship:velocity:surface:mag > 50 {
	//	return -sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT[1] - gravity()))). //Speed 1
	//} else {
		return -sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT[0] - gravity()))). //Speed 2
	//}
	
	//set landBurnS to -sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT - gravity()))).
}