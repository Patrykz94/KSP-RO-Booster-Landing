//Print data to screen
@lazyglobal off.

set terminal:width to 60.
set terminal:height to 50.

function displayFlightData {

//Title bar
print "------------------- Flight Display 1.0 --------------------"																at (1,1).		
print "Launch Time:             T" + round(mT - lT) + "               "												at (3,2).
// Body info
print "Current Body:            " + currentBody() + "               "															at (3,3).
print "Atm Height:              " + atmHeight() + "               "																at (3,4).
print "SL Gravity:              " + round(staticGravity(), 2) + "               "												at (3,5).
print "                                                           "																at (1,6).
print "Current Gravity:         " + round(gravity(ship:altitude), 2) + "               "														at (3,7).
print "TWR:                     " + round(shipCurrentTWR(), 2) + " / " + round(shipTWR(), 2) + "               "				at (3,8).
print "                                                           "																at (1,9).
print "Heading:                 " + round(compass_for(ship), 2) + "               "												at (3,10).
print "Pitch:                   " + round(pitch_for(ship), 2) + "               "												at (3,11).
print "Roll:                    " + round(roll_for(ship), 2) + "               "												at (3,12).
print "                                                          "																at (1,13).
print "Sea Level Altitude:      " + round(ship:altitude / 1000 , 1) + "km               "										at (3,14).
print "                                                           "																at (1,15).
print "-----------------------------------------------------------"																at (1,16).
print "                                                           "																at (1,17).
}

function displayLaunchData {

print "Target Heading:          " + round(compass, 2) + "               "														at (3,18).
print "Target Pitch:            " + round(pitch, 2) + "               "															at (3,19).
print "Target Apoapsis:         " + round(orbAlt / 1000) + "km               "											at (3,20).
print "Current Apoapsis:        " + round(ship:apoapsis / 1000, 3) + "km               "										at (3,21).
print "                                                           "																at (1,22).
print "-----------------------------------------------------------"																at (1,23).
print "                                                           "																at (1,24).
}

function displayManeuverData {
parameter node.

//print "Target Apoapsis:         " + round(targetAltitude / 1000) + "km               "											at (3,18).
print "Maneuver ETA:            " + round(node:eta - (nodeBurnTime(node) / 2), 1) + "s               "							at (3,19).
//print "Orbital Velocity:        " + round(getOrbitalVelocity(ship:apoapsis), 1) + "m/s               "							at (3,20).
//print "Velocity at Apoapsis:    " + round(getVelocityAtApoapsis(), 1) + "m/s               "									at (3,21).
print "Node DeltaV Reqired:     " + round(node:deltav:mag, 1) + "m/s               "											at (3,22).
print "Estimated Burn Time:     " + round(nodeBurnTime(node), 1) + "s               "											at (3,23).
print "                                                           "																at (1,24).
print "-----------------------------------------------------------"																at (1,25).
print "                                                           "																at (1,26).
}