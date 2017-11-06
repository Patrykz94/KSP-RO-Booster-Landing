@lazyglobal off.
function startScript {
	clearscreen.
	print "Waiting for instructions. Please update launch/landing parameters and when you are ready, hit '0' (action group).".
	wait until AG10.
}
wait 0.
set volume(1):name to core:tag.
if volume(1):name = "Falcon9S1" {
	startScript().
	if not exists("1:/recovery.ks") {
		copypath("0:/boot/recovery.ks","1:").
	}
	set core:bootfilename to recovery.ks.
	reboot.
} else if volume(1):name = "Falcon9S2" {
	startScript().
	copypath("0:/pegas.ks","1:").
	copypath("0:/pegas_cser.ks","1:").
	copypath("0:/pegas_misc.ks","1:").
	copypath("0:/pegas_upfg.ks","1:").
	copypath("0:/pegas_util.ks","1:").

	copypath("0:/config/Falcon9.ks","1:").
	copypath("0:/config/mission.ks","1:").

	runpath("1:/Falcon9.ks").
	runpath("1:/mission.ks").
	
	runpath("1:/pegas.ks").
}
else if volume(1):name = "Falcon9S1-Grasshopper" {
	startScript().
	copypath("0:/boot/recovery_test.ks","1:").
	runpath("1:/recovery_test.ks").
}