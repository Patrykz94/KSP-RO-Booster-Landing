function hohman_dv {
	parameter desiredAltitude.
	
	local u is ship:obt:body:mu.
	local r1 is ship:obt:semimajoraxis.
	local r2 is desiredAltitude + ship:obt:body:radius.
	// v1
	local v1 is sqrt(u / r1) * (sqrt((2 * r2) / (r1 + r2)) - 1).
	// v2
	local v2 is sqrt(u / r2) * (1 - sqrt((2 * r1) / (r1 + r2))).
	
	return list(v1, v2).
}

function mnv_time {
	parameter dv.
	parameter manualEns is list().
	set ens to list().
	ens:clear.
	set ens_thrust to 0.
	set ens_isp to 0.
	if manualEns:length = 0 {
		list engines in myengines.

		for en in myengines {
			if en:ignition = true and en:flameout = false {
				ens:add(en).
			}
		}
	} else {
		set ens to manualEns.
	}

	for en in ens {
		set ens_thrust to ens_thrust + en:maxthrust.
		if en:isp = 0 or en:maxthrust = 0 {
			set ens_isp to ens_isp + en:slisp.
		} else {
			set ens_isp to ens_isp + en:isp.
		}
	}

	if ens_thrust = 0 or ens_isp = 0 {
		//notify("No engines available!").
		return 0.
	} else {
		local f is ens_thrust * 1000.  // engine thrust (kg * m/s²)
		local m is ship:mass * 1000.        // starting mass (kg)
		local e is constant():e.            // base of natural log
		local p is ens_isp/ens:length.               // engine isp (s) support to average different isp values
		local g is ship:orbit:body:mu/ship:obt:body:radius^2.    // gravitational acceleration constant (m/s²)
		return g * m * p * (1 - e^(-dv/(g*p))) / f.
	}
}

function execNodeOld {
	parameter node.
	parameter dispData.
	local nodeDV is 0.
	local mnvPhase is 0.
	set mnvInProgress to true.
	sas off.
	
	until mnvPhase = 1 {
		set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
		until abs(nodeDir:pitch - facing:pitch) < 0.1 and abs(nodeDir:yaw - facing:yaw) < 0.1 {
			mainLoop().
			wait 0.001.
		}
		SET WARPMODE TO "RAILS".
		warpto(time:seconds + (node:eta - (nodeBurnTime(node) / 2)) - 15).
		until abs(nodeDir:pitch - facing:pitch) < 0.1 and abs(nodeDir:yaw - facing:yaw) < 0.1 {
			mainLoop().
			wait 0.001.
		}
		mainLoop().
		set mnvPhase to 1.
	}
	
	until mnvPhase = 2 {
		set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
		set mnv_complete to false.
		set nodeDV to node:deltav.
		if node:eta <= (nodeBurnTime(node) / 2) {
			until mnv_complete {
				set tval to min(node:deltav:mag / shipAcc(), 1).
				set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
				if vdot(nodeDV, node:deltav) < 0 {
					lock throttle to 0.
					break.
				}
				if node:deltav:mag < 0.4 {
					until vdot(nodeDV, node:deltav) < 0.5 {
						displayGUI().
						wait 0.001.
					}
					lock throttle to 0.
					set tval to 0.
					set mnv_complete to true.
					unlock steering.
					unlock throttle.
					set mnvPhase to 2.
				}
				displayGUI().
			}
		}
		displayGUI().
	}
	set mnvInProgress to false.
	set mNodeDisp to false.
	set tval to 0.
	remove node.
	return true.
}

function execNode {
	parameter node.
	parameter dispData.
	local nodeDV is 0.
	local mnvPhase is 0.
	set mnvInProgress to true.
	sas off.
	
	until mnvPhase = 1 {
		set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
		until abs(nodeDir:pitch - facing:pitch) < 0.1 and abs(nodeDir:yaw - facing:yaw) < 0.1 {
			mainLoop().
			wait 0.001.
		}
		SET WARPMODE TO "RAILS".
		warpto(time:seconds + (node:eta - (nodeBurnTime(node) / 2)) - 15).
		until abs(nodeDir:pitch - facing:pitch) < 0.1 and abs(nodeDir:yaw - facing:yaw) < 0.1 {
			mainLoop().
			wait 0.001.
		}
		mainLoop().
		set mnvPhase to 1.
	}
	
	until mnvPhase = 2 {
		set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
		set mnv_complete to false.
		set nodeDV to node:deltav.
		if node:eta <= (nodeBurnTime(node) / 2) {
			until mnv_complete {
				set tval to min(node:deltav:mag / shipAcc(), 1).
				set nodeDir to lookdirup(node:deltav, ship:facing:topvector).
				if vdot(nodeDV, node:deltav) < 0 {
					lock throttle to 0.
					break.
				}
				if node:deltav:mag < 0.4 {
					until vdot(nodeDV, node:deltav) < 0.5 {
						displayGUI().
						wait 0.001.
					}
					lock throttle to 0.
					set tval to 0.
					set mnv_complete to true.
					unlock steering.
					unlock throttle.
					set mnvPhase to 2.
				}
				displayGUI().
			}
		}
		displayGUI().
	}
	set mnvInProgress to false.
	set mNodeDisp to false.
	set tval to 0.
	remove node.
	return true.
}