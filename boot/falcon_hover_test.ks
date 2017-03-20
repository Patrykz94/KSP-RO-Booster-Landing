@lazyglobal off.
clearscreen.
set ship:control:pilotmainthrottle to 0.
wait 0.

local storagePath is "1:".
if not exists(storagePath + "/libs") {
	createdir(storagePath + "/libs").
}

function libDl {
	parameter libs is list().
	
	for lib in libs {
		copypath("0:/libs/" + lib + ".ks", storagePath + "/libs/").
	}
	for lib in libs {
		runpath(storagePath + "/libs/" + lib + ".ks").
	}
}

libDl(list("lib_navball", "telemetry", "flight_display", "maneuvers", "functions", "falcon_functions", "falcon_rcs")).

// ---=== [**START**] [ DECLARING ALL NECESSARY VARIABLES ] [**START**] ===---

	rcs off.
	sas off.
	
	wait until ag10.

	// default launch parameters can be changed while starting the program.
	// You can do it by typing "run boot_testflight(250,90,1)."

	parameter orbAlt is 200. // Default target altitude
	parameter orbDir is 90.  // Default launch direction (landing only works on launching to 90 degrees)
	parameter landing is 1.  // Landing site
	set orbAlt to orbAlt * 1000.

	// NAVIGATION AND ROCKET SYSTEMS VAIRABLES

	local compass is 0.
	local pitch is 90.
	
	local runmode is 1.
	local cpuName is core:tag.
	local reorienting is false.

	// SHIP POSITIONING AND VELOCITY TRACKING VARIABLES

	local posCur is 0.
	local posPrev is 0.
	local altCur is 0.
	
	local impPosCur is 0.
	local impPosPrev is 0.
	local impPosFut is 0. // may be redundant
	local impDist is 0.
	local lzDistCur is 0.
	local lzDistImp is 0.
	
	local velLatCur is 0.
	local velLngCur is 0.
	local velLatImp is 0.
	local velLngImp is 0.
	local velDir is 0. // surface prograde
	local velDirFlat is 0. // horizontal direction
	
	local sepDeltaV is 0.
	
	// \/ Need renaming \/ //
	local posOffset is 4500.
	local landingOffset is 0.
	local landingOffset2 is 0.
	local dirRet is 0.
	local dirVecOffset is 0.
	local desiredDir is 0.

	// STEERING VARIABLES

	local tval is 0.
	local stable is false.
	
	local steer is up.
	local steerPitch is 0.
	local steerYaw is 0.
	
	local pidLimit is 900.
	
	local rotCur is 0.
	local rotPrev is 0.
	local rotSpd is 0.
	
	local Pitch_val is 0.
	local Yaw_val is 0.
	local Pitch_set is 0.
	local Yaw_set is 0.
	
	local engReady is true.
	local engStartup is false.
	local engThrust is 0.
		
	// ---== PREPARING PID LOOPS ==--- //
		// ----- Landing loops ----- //		
		// Landing velocity control
		local AltVel_PID is pidloop(1, 0, 0.3, -100, 100).
		local VelThr_PID is pidloop(2.1, 9, 0.15, 0.36, 1).
		
		// ----- Controlled descent loops ----- //
		// Latitude control
		local DescLatitudeChange_PID is pidloop(20, 0, 5, -0.1, 0.1).
		local DescLatitude_PID is pidloop(300, 1, 150, -10, 10).
		// Longditude control
		local DescLongitudeChange_PID is pidloop(20, 0, 5, -0.1, 0.1).
		local DescLongitude_PID is pidloop(300, 1, 150, -10, 10).

		// ----- Final touch-down loops ----- //
		// Latitude control
		local LandLatitudeChange_PID is pidloop(60, 0, 10, -0.05, 0.05).
		local LandLatitude_PID is pidloop(500, 0, 150, -5, 5).
		// Longditude control
		local LandLongitudeChange_PID is pidloop(60, 0, 10, -0.05, 0.05).
		local LandLongitude_PID is pidloop(500, 0, 150, -5, 5).

	// ---== END PID LOOPS ==--- //
	
	// TIME TRACKING VARIABLES

	local dT is 0. // delta
	local mT is 0. // mission/current
	local lT is 0. // until/since launch
	local sT is 0. // start of program
	local pT is 0. // previous tick
	local impT is 0.
	local landBurnT is list(0.001). // Landing burn time
	local landBurnH is list(0.001). // Landing burn height
	local landBurnD is 0. // Landing burn distance
	local landBurnS is 0. // Landing burn speed target
	local landBurnEngs is 1.
	local eventTime is 0.
	local event is false.
	
	// MISSION PARAMETERS
	
	local lzPos is 0.
	local lzPosFut is 0.
	local lzAlt is 0.
	local reentryBurnAlt is 55000.

	// OTHER VARIABLES

	local clearRequired is false.
	
	local vec1 is 0.
	local vec2 is 0.
	local vec3 is 0.
	local vec4 is 0.
	local vec5 is 0.
	
	local bodyRotation is 360 / body:rotationperiod.
	local tr is addons:tr.
	
// ---=== [**END**] [ DECLARING ALL NECESSARY VARIABLES ] [**END**] ===---

// ---=== [**START**] [ GETTING NECESSARY DATA ] [**START**] ===---

// final preparation - setting up for launch

	set sT to time:seconds.
	set pT to sT.
	set lT to sT + 10.
	set posPrev to ship:geoposition.
	set impPosPrev to ship:geoposition.
	set impPosFut to ship:geoposition.
	set rotPrev to list(pitch_for(ship), compass_for(ship), roll_for(ship)).
	set steeringmanager:rollts to 15.
	
	if landing <> 0 {
		if landing = 1 {
			set lzPos to KSCLaunchPad.
			tr:settarget(KSCLaunchPad).
		}
		
		set lzAlt to lzPos:terrainheight.
		when (altCur - lzAlt) < 200 and runmode > 2 then { gear on. }
	} else {
		set lzAlt to 0.
	}
	
	lock throttle to max(0, min(1, tval)).
	lock steering to steer.
	
	//createLog().

// ---=== [**END**] [ GETTING NECESSARY DATA ] [**END**] ===---

wait 0. // waiting 1 physics tick so that everything updates


until runmode = 0 {
	
// ---=== [**START**] [ UPDATING VARIABLES BEFORE EVERY ITERATION ] [**START**] ===--- //
	
	set mT to time:seconds.
	set dT to mT - pT.
	set altCur to body:altitudeof(Merlin1D_0:position) - 3.9981.
	if landing <> 0 {
		if merlinData[0] = false {
			if tval = 1 and Merlin1D_0:ignition = true and Merlin1D_0:flameout = false {
				set merlinData to list( true, Merlin1D_0:maxthrustat(1), Merlin1D_0:maxthrustat(0), Merlin1D_0:slisp, Merlin1D_0:visp).
			}
		}
		set posCur to ship:geoposition.
		set rotCur to list(pitch_for(ship), compass_for(ship), rollConvert()).
		set rotSpd to list((mod(90 + rotCur[0] - rotPrev[0], 180) -90)/dT, mod(rotCur[1] - rotPrev[1], 360)/dT,(mod(180 + rotCur[2] - rotPrev[2], 360) -180)/dT).
		set velLatCur to (mod(180 + posPrev:lat - posCur:lat, 360) - 180)/dT.
		set velLngCur to (mod(180 + posPrev:lng - posCur:lng, 360) - 180)/dT.
		
		set impT to timeToAltitude(lzAlt, altCur).
		set lzPosFut to latlng(lzPos:lat, mod(lzPos:lng + 180 + (impT * bodyRotation), 360) - 180).
		
		set impPosCur to latlng(body:geopositionof(positionat(ship, mT + impT)):lat, body:geopositionof(positionat(ship, mT + impT)):lng - 0.0000801).
		if tr:hasimpact {
			set impPosFut to tr:impactpos.
		}// else {
		//	set impPosFut to latlng(body:geopositionof(positionat(ship, mT + impT)):lat, body:geopositionof(positionat(ship, mT + impT)):lng - (impT * bodyRotation) - 0.0000801).
		//}
		set velLatImp to (mod(180 + impPosPrev:lat - impPosFut:lat, 360) - 180)/dT.
		set velLngImp to (mod(180 + impPosPrev:lng - impPosFut:lng, 360) - 180)/dT.
		
		set lzDistCur to lzPos:position - ship:geoposition:altitudeposition(lzAlt).
		set lzDistImp to lzPos:position - impPosFut:position.
		set sepDeltaV to Fuel["Stage 1 DeltaV"]().
		
		set landingOffset to vxcl(lzDistImp - body:position, lzDistImp):normalized * posOffset.
		set landingOffset2 to (vxcl(lzPos:position - body:position, lzPos:position):normalized * (lzDistCur:mag/10)) + landingOffset.
		
		if runmode >= 4 {
			set velDir to ship:velocity:surface:normalized * 25.
			set velDirFlat to vxcl(ship:velocity:surface - body:position, ship:velocity:surface):normalized * 25.
			if runmode < 7 {
				set desiredDir to (vxcl((velDir - (velDir - (landingOffset:normalized * 25))*2) - body:position, (velDir - (velDir - (landingOffset:normalized * 25))*2)):normalized * 25) - (body:position:normalized * 1).
			} else {
				set dirRet to (velDirFlat - (landingOffset:normalized * 25)*2):normalized * 25.
				set dirVecOffset to dirRet - velDirFlat.
				set desiredDir to (-dirVecOffset - velDir):normalized * 25.
			}
		}
		
		if runmode = 9 {
			set landBurnT to landingBurnTime(ship:velocity:surface:mag, 1, 0.8).//max(0.1,mnv_time(ship:velocity:surface:mag, list(Merlin1D_0))) * 1.2.
			set landBurnH to landBurnHeight().//verticalspeed^2 / (2*(ship:velocity:surface:mag/landBurnT - gravity())).
			set landBurnD to altCur - lzAlt - landBurnH[0].//altCur - lzAlt - landBurnH.
			set landBurnS to landBurnSpeed().//-sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT - gravity()))).
		}
	}
	
	// Main logic
	
	if runmode = 1 {
		set steer to up.
		set tval to 0.
		stage.
		Engine["Stop"](list(
			Merlin1D_1,
			Merlin1D_2,
			Merlin1D_3,
			Merlin1D_4,
			Merlin1D_5,
			Merlin1D_6,
			Merlin1D_7,
			Merlin1D_8
		)).
		set tval to 1.
		wait 3.
		stage.
		set steerPitch to 0.
		set steerYaw to 0.
		set eventTime to mT.
		set runmode to 2.
		set AltVel_PID:setpoint to 15000.
	} else if runmode = 2 {
		set VelThr_PID:setpoint to AltVel_PID:update(mt, altCur).
		
		Engine["Throttle"](
		list(
			list(Merlin1D_0, (VelThr_PID:update(mT, verticalspeed)*100)/cos(vang(up:vector, ship:facing:forevector)))
		)).
		set steer to up.// + r(steerPitch, steerYaw, 90).
		if sepDeltaV < 600 {
			set AltVel_PID:setpoint to lzAlt.
			set tval to 0.
			Engine["Stop"](list(
				Merlin1D_0
			)).
			if verticalspeed < -50 {
				when timeToAltitude(landBurnH[0] + lzAlt, altCur) < 3 and altCur - lzAlt < 6000 then {
					set tval to 1.
					if landBurnEngs = 1 {
						Engine["Start"](list(
							Merlin1D_0
						)).
					} else {
						Engine["Start"](list(
							Merlin1D_0,
							Merlin1D_1,
							Merlin1D_2
						)).
					}
				}
				ag5 on.
				set runmode to 9.
			}
		}
	}
	else if runmode = 9
	{
		set VelThr_PID:setpoint to landBurnS.
		//if landBurnH[1] = 0 {
			Engine["Stop"](list(
				Merlin1D_1,
				Merlin1D_2
			)).
		//}
		set engThrust to (VelThr_PID:update(mT, verticalspeed)*100)/cos(vang(up:vector, ship:facing:forevector)).
		Engine["Throttle"](
		list(
			list(Merlin1D_0, engThrust),
			list(Merlin1D_1, engThrust),
			list(Merlin1D_2, engThrust)
		)).
		
		set DescLatitudeChange_PID:kp to max(5, min(60, 60-((altCur/1000)*4))).
		set DescLongitudeChange_PID:kp to max(5, min(60, 60-((altCur/1000)*4))).
		
		if tval = 0 {
			
			set posOffset to max(-500, min(500, lzDistImp:mag)).
			
			set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lat. // steering
			set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosFut:lat).
			set steerPitch to -DescLatitude_PID:update(mT, velLatImp).
			
			set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lng.
			set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosFut:lng).
			set steerYaw to -DescLongitude_PID:update(mT, velLngImp).
			
		} else {
			
			set posOffset to max(-200, min(200, lzDistImp:mag/2)).
			
			set LandLatitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lat.
			set LandLatitude_PID:setpoint to LandLatitudeChange_PID:update(mT, impPosFut:lat).
			set steerPitch to -LandLatitude_PID:update(mT, velLatImp).
			
			set LandLongitudeChange_PID:setpoint to body:geopositionof(lzPos:position + landingOffset2):lng.
			set LandLongitude_PID:setpoint to LandLongitudeChange_PID:update(mT, impPosFut:lng).
			set steerYaw to -LandLongitude_PID:update(mT, velLngImp).
			
		}
		
		if (VelThr_PID:output < 0.5 or tval = 0) and ship:velocity:surface:mag > 100 {
			set steerPitch to -steerPitch.
			set steerYaw to -steerYaw.
		}
		
		if altCur < lzAlt + 200 or verticalspeed > 0 {
			set steer to up + r(steerPitch, steerYaw, 90).
		} else {
			set steer to (-ship:velocity:surface):direction + r(steerPitch, steerYaw, 90).
		}
		if ship:status = "Landed" {
			set runmode to 0.
			Engine["Stop"](list(
				Merlin1D_0,
				Merlin1D_1,
				Merlin1D_2
			)).
			set tval to 0.
			set steer to up.
		}
	}
	
	// stuff that needs to update after every iteration
	if clearRequired {
		clearscreen.
		set clearRequired to false.
	}
	
	
	displayFlightData().
	if runmode < 4 {
		displayLaunchData().
	}
	//displayF9Data().
	
	if runmode >= 8 {
		
		set vec1 to vecdraw(ship:position, impPosFut:position, rgb(1,0,0), "Imp", 1, true).
		set vec2 to vecdraw(ship:position, posCur:position, rgb(0,1,0), "Pos", 1, true).
		//set vec3 to vecdraw(ship:position, tr:plannedvec:normalized * 50, rgb(0,0,1), "PlaV", 1, true).
		//set vec4 to vecdraw(ship:position, tr:correctedvec:normalized * 50, rgb(1,0.3,0), "CorV", 1, true).
		set vec5 to vecdraw(ship:position, lzPos:position + landingOffset2, rgb(1,1,1), "LO4", 1, true).
		
	}
	
	if runmode >= 4 {
		//print "Current Position:          " + round(longitude, 3) + ", " + round(latitude, 3) + "             " at (3,20).
		//print "Impact Position:           " + round(impPosFut:lng, 3) + ", " + round(impPosFut:lat, 3) + "             " at (3,21).
		
		print "Impact Time:               " + round(impT, 2) + "     " at (3, 23).
		//print "Suicide Burn Time:         " + round(landBurnT, 2) + "     " at (3, 24).
		print "Impact Distance:           " + round(lzDistImp:mag, 2) + "          " at (3, 25).
		
		print "Position offset:           " + round(posOffset, 2) + "           " at (3, 27).
		print "Distance to LZ:            " + round(lzDistCur:mag, 2) + "           " at (3, 28).
		
		print "Steer Latitude:            " + round(steerPitch, 2) + "     " at (3, 30).
		print "Steer Longitude:           " + round(steerYaw, 2) + "     " at (3, 31).
		
		print "Latitude Velocity          " + round(velLatImp, 4) + "         " at (3, 33).
		print "Longitude Velocity         " + round(velLngImp, 4) + "         " at (3, 34).
	}
	print "Runmode:                   " + runmode + "     " at (3, 36).
	print "DeltaV remaining:          " + round(sepDeltaV) + "     " at (3, 37).
	print "PID loop KP:               " + round(DescLatitudeChange_PID:kp, 2) + "     " at (3, 38).
	
	if runmode = 9 {
		//print "T1:                        " + round(landBurnT[1], 5) + "     " at (3, 40).
		//print "T2:                        " + round(landBurnT[2], 5) + "     " at (3, 41).
		print "T1 + T2:                   " + round(landBurnT[0], 5) + "     " at (3, 42).
		
		//print "Height 1:                  " + round(landBurnH[1], 5) + "     " at (3, 44).
		//print "Height 2:                  " + round(landBurnH[2], 5) + "     " at (3, 45).
		print "Height 1 + Height 2:       " + round(landBurnH[0], 5) + "     " at (3, 46).
		
		print "landBurnS                  " + round(landBurnS, 2) + "     " at (3, 48).
	}
	
	// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
	
	set pT to mT.
	set posPrev to posCur.
	set impPosPrev to impPosFut.
	set rotPrev to rotCur.

	// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
	
	wait 0.
}

unlock all.