runpath("0:/libs/lib_navball.ks").
clearscreen.
steeringmanager:resetpids().
set steeringmanager:maxstoppingtime to 5.

set steeringmanager:pitchts to 25.
set steeringmanager:yawts to 15.
set steeringmanager:rollts to 25.

//set steeringmanager:pitchpid:kp to 6.
set steeringmanager:pitchpid:ki to 0.
set steeringmanager:pitchpid:kd to 1.5.

//set steeringmanager:yawpid:kp to 12.
set steeringmanager:yawpid:ki to 0.
set steeringmanager:yawpid:kd to 1.5.

//set steeringmanager:rollpid:kp to 2.
set steeringmanager:rollpid:ki to 0.
set steeringmanager:rollpid:kd to 1.5.

//set steeringmanager:rolltorquefactor to 5.

set targetDir to -ship:velocity:orbit.

//lock steering to heading(90, desPitch).

until false {
	print pitch_for(ship) + "        " at(3,5).
	print rotatefromto(ship:facing:forevector,-ship:velocity:orbit) + "        " at(3,7).

	if ag1 {
		set vec1 to vecdraw(ship:position, ship:facing:forevector*40, rgb(1,0,0), "Forevector", 1, true, 0.2).
		set vec2 to vecdraw(ship:position, ship:facing:topvector*20, rgb(0,1,0), "Topvector", 1, true, 0.2).
		set vec3 to vecdraw(ship:position, ship:facing:starvector*20, rgb(0,0,1), "Starvector", 1, true, 0.2).
	} else {
		set vec1 to vecdraw(ship:position, ship:facing:forevector*40, rgb(1,0,0), "Forevector", 1, false, 0.2).
		set vec2 to vecdraw(ship:position, ship:facing:topvector*20, rgb(0,1,0), "Topvector", 1, false, 0.2).
		set vec3 to vecdraw(ship:position, ship:facing:starvector*20, rgb(0,0,1), "Starvector", 1, false, 0.2).
	}
}