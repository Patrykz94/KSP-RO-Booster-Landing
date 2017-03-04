runpath("0:/libs/lib_navball.ks").
runpath("0:/libs/falcon_rcs.ks").
clearscreen.
sas off.
rcs on.

set newRoll to 0.
local stable is false.

until false {
	//print roll_for(ship) + "        " at(3,5).
	print rollConvert() + "        " at(3,4).
	print circCalc(newRoll, rollConvert()) + "        " at(3,5).
	print circCalc(newRoll, rollConvert()) - rollConvert() + "        " at(3,7).
	//print rotatefromto(ship:facing:forevector,-ship:velocity:orbit) + "        " at(3,7).
	//print ship:angularmomentum:mag + "        " at(3,8).
	print ship:angularmomentum:x + "        " at(3,9). //Vertical
	print ship:angularmomentum:y + "        " at(3,10). //Roll
	print ship:angularmomentum:z + "        " at(3,11). //Horizontal
	
	if stable = false {
		if stabilize() = true {
			set stable to true.
		}
	} else {
		startFlip(15).
	}
	wait 0.	
}