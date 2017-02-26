runpath("1:/libs/lib_navball.ks").
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

set desPitch to 0.

lock steering to heading(90, desPitch).

//log "Desired Pitch, Current Pitch, Difference" to pidlog.csv.

until false {
	print desPitch at(3,4).
	print pitch_for(ship) at(3,5).
	print pitch_for(ship) - desPitch at(3,6).
	
	//log desPitch + ", " + pitch_for(ship) +  ", " + (pitch_for(ship) - desPitch) to pidlog.csv.
}