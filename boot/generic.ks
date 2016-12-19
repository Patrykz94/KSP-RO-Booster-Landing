wait 0.
set volume(1):name to core:tag.
if volume(1):name = "Falcon9-S1" {
	if not exists("Falcon9S1Storage:/falcon.ks") {
		copypath("0:/boot/falcon.ks","Falcon9S1Storage:").
	}
	runpath("Falcon9S1Storage:/falcon.ks").
} else if volume(1):name = "Falcon9-S1-Grasshopper" {
	if not exists("Falcon9S1Storage:/falcon_hover_test.ks") {
		copypath("0:/boot/falcon_hover_test.ks","Falcon9S1Storage:").
	}
	runpath("Falcon9S1Storage:/falcon_hover_test.ks").
} else if volume(1):name = "Falcon9-S2" {
	if not exists("Falcon9S2Storage:/falcons2.ks") {
		copypath("0:/boot/falcons2.ks","Falcon9S2Storage:").
	}
	runpath("Falcon9S2Storage:/falcons2.ks").
}