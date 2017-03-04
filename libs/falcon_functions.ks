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
	local f9DryMass is 23.0644756622314.
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
			set delv to (groundspeed * 1.5) + 700 + 500.
		} else if landing <= 20 {
			set delv to (groundspeed * 0.75) + 700 + 400.
		} else {
			set delv to (groundspeed * 0.4) + 300.
		}
	}
	
	return delv.
}