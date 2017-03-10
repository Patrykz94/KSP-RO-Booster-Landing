@lazyglobal off.

local rollAngSpeed is 600/360.

local RollSpd_PID is pidloop(0.2, 0, 0.3, -2, 2).
local Roll_PID is pidloop(0.4, 0, 0.3, -1, 1).

local Pitch_PID is pidloop(0.2, 0, 0.2, -0.8, 0.8).

set ship:control:neutralize to true.

function circCalc {
	parameter desC.
	parameter oldC.
	if oldC < 180 {
		if desC > oldC + 180 {
			return desC - 360.
		} else {
			return desC.
		}
	} else {
		if desC > oldC - 180 {
			return desC.
		} else {
			return desC + 360.
		}
	}
}

function rollConvert {
	parameter rol is roll_for(ship).
	if rol < 0 {
		return rol + 360.
	} else {
		return rol.
	}
}

function moveRoll {
	parameter setRoll.
	parameter force is 1.
	set Roll_PID:minoutput to -force.
	set Roll_PID:maxoutput to force.
	local curRoll is rollConvert(roll_for(ship)) * rollAngSpeed.
	set setRoll to circCalc(setRoll, rollConvert(roll_for(ship))) * rollAngSpeed.
	set RollSpd_PID:setpoint to setRoll.
	set Roll_PID:setpoint to RollSpd_PID:update(time:seconds, curRoll).
	set ship:control:roll to Roll_PID:update(time:seconds, -ship:angularmomentum:y/20).
}

function killRoll {
	parameter force is 1.
	set ship:control:roll to max(-force, min(force, ship:angularmomentum:y/10)).
}

function killYaw {
	parameter force is 1.
	set ship:control:yaw to max(-force, min(force, ship:angularmomentum:z/40)).
}

function killPit {
	parameter force is 1.
	set ship:control:pitch to max(-force, min(force, ship:angularmomentum:x/40)).
}

function stabilize {
	set ship:control:neutralize to true.
	if roll_for(ship) > 1 or roll_for(ship) < -1 {
		moveRoll(0).
	} else {
		killRoll(0.5).
		killYaw(0.5).
	}
	if abs(ship:angularmomentum:y) < 1 and abs(ship:angularmomentum:z) < 5 {
		return true.
	} else {
		return false.
	}
}

function startFlip {
	parameter flipSpeed is 12.
	set ship:control:neutralize to true.
	killRoll(0.1).
	killYaw(0.1).
	set Pitch_PID:setpoint to flipSpeed.
	if (-ship:angularmomentum:x/150) < flipSpeed * 0.85 or (-ship:angularmomentum:x/150) > flipSpeed * 1.15 {
		set ship:control:pitch to Pitch_PID:update(time:seconds, -ship:angularmomentum:x/150).
	} else {
		set ship:control:pitch to 0.
	}
}

function startFlip2 {
	parameter flipSpeed is 1.
	set ship:control:neutralize to true.
	moveRoll(0, 0.2).
	killYaw(0.1).
	set Pitch_PID:setpoint to flipSpeed.
	if (-ship:angularmomentum:x/150) < flipSpeed * 0.8 or (-ship:angularmomentum:x/150) > flipSpeed * 1.2 {
		set ship:control:pitch to Pitch_PID:update(time:seconds, -ship:angularmomentum:x/150).
	} else {
		set ship:control:pitch to 0.
	}
}