@lazyglobal off.

if volume(1):name = "Falcon9-S1" {

	mainEngineName = "merlin1D".
	
	local minThrottle is 36.

	local mainTanks is ship:partstagged("Falcon9-S1-Tank").
	
} else if volume(1):name = "Falcon9-S2" {

	mainEngineName = "merlin1D.vac".
	
	local minThrottle is 39.

	local mainTanks is ship:partstagged("Falcon9-S2-Tank").
	
}