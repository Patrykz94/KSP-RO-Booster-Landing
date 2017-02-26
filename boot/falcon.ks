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

libDl(list("lib_navball", "telemetry", "flight_display", "maneuvers", "functions", "falcon_functions")).

// ---=== [**START**] [ DECLARING ALL NECESSARY VARIABLES ] [**START**] ===---

	rcs off.
	sas off.
	
	wait until ag10.

	// default launch parameters can be changed while starting the program.
	// You can do it by typing "run boot_testflight(250,90,1)."

	parameter orbAlt is 200. // Default target altitude
	parameter orbDir is 0.  // Default launch direction (landing only works on launching to 90 degrees)
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
	local landingOffset3 is 0.
	local landingOffset4 is 0.
	local dirRet is 0.
	local dirVecOffset is 0.
	local desiredDir is 0.

	// STEERING VARIABLES

	local tval is 0.
	
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
		
	// ---== PREPARING PID LOOPS ==--- //
		// ----- Landing loops ----- //		
		// Landing velocity control
		local AltVel_PID is pidloop(0.45, 0, 0.3, -600, 0.1).
		local VelThr_PID is pidloop(2.1, 9, 0.15, 0.36, 1).
		
		// ----- Controlled descent loops ----- //
		// Latitude control
		local DescLatitudeChange_PID is pidloop(5, 0.02, 0.3, -0.1, 0.1).
		local DescLatitude_PID is pidloop(300, 1, 150, -35, 35).
		// Longditude control
		local DescLongitudeChange_PID is pidloop(5, 0.02, 0.3, -0.1, 0.1).
		local DescLongitude_PID is pidloop(300, 1, 150, -35, 35).

		// ----- Final touch-down loops ----- //
		// Latitude control
		local LandLatitudeChange_PID is pidloop(7.5, 0, 12, -0.01, 0.01).
		local LandLatitude_PID is pidloop(500, 0, 0, -5, 5).
		// Longditude control
		local LandLongitudeChange_PID is pidloop(7.5, 0, 12, -0.01, 0.01).
		local LandLongitude_PID is pidloop(500, 0, 0, -5, 5).
		
		// ----- Attitude control loops ----- //
		// Pitch control
		local PitchSpd_PID is pidloop(0.2, 0, 0.5, -5, 5).
		local Pitch_PID is pidloop(0.8, 0, 0.3, -1, 1).
		// Yaw control
		local YawSpd_PID is pidloop(0.2, 0, 0.5, -5, 5).
		local Yaw_PID is pidloop(0.8, 0, 0.3, -1, 1).
		// Roll control
		local RollSpd_PID is pidloop(0.4, 0, 0.3, -20, 20).
		local Roll_PID is pidloop(0.2, 0, 0.1, -1, 1).

	// ---== END PID LOOPS ==--- //
	
	// TIME TRACKING VARIABLES

	local dT is 0. // delta
	local mT is 0. // mission/current
	local lT is 0. // until/since launch
	local sT is 0. // start of program
	local pT is 0. // previous tick
	local impT is 0.
	local landBurnT is 1. // Landing burn time
	local landBurnH is 0. // Landing burn height
	local landBurnD is 0. // Landing burn distance
	local landBurnS is 0. // Landing burn speed target
	local eventTime is 0.
	
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
	
// ---=== [**END**] [ DECLARING ALL NECESSARY VARIABLES ] [**END**] ===---

// ---=== [**START**] [ GETTING NECESSARY DATA ] [**START**] ===---

// final preparation - setting up for launch

	set sT to time:seconds.
	set pT to sT.
	set lT to sT + 10.
	set posPrev to ship:geoposition.
	set impPosPrev to ship:geoposition.
	set rotPrev to list(pitch_for(ship), compass_for(ship), roll_for(ship)).
	set steeringmanager:rollts to 15.
	
	if landing <> 0 {
		if landing = 1 {
			set lzPos to KSCLaunchPad.
		}
		
		set lzAlt to lzPos:terrainheight.
		when (altCur - lzAlt) < 500 and runmode > 2 then { gear on. }
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
		set posCur to ship:geoposition.
		set rotCur to list(pitch_for(ship), compass_for(ship), rollConvert()).
		set rotSpd to list((mod(90 + rotCur[0] - rotPrev[0], 180) -90)/dT, mod(rotCur[1] - rotPrev[1], 360)/dT,(mod(180 + rotCur[2] - rotPrev[2], 360) -180)/dT).
		set velLatCur to (mod(180 + posPrev:lat - posCur:lat, 360) - 180)/dT.
		set velLngCur to (mod(180 + posPrev:lng - posCur:lng, 360) - 180)/dT.
		
		set impT to timeToAltitude(lzAlt, altCur).
		set lzPosFut to latlng(lzPos:lat, mod(lzPos:lng + 180 + (impT * bodyRotation), 360) - 180).
		
		set impPosCur to latlng(body:geopositionof(positionat(ship, mT + impT)):lat, body:geopositionof(positionat(ship, mT + impT)):lng - 0.0000801).
		set impPosFut to latlng(body:geopositionof(positionat(ship, mT + impT)):lat, body:geopositionof(positionat(ship, mT + impT)):lng - (impT * bodyRotation) - 0.0000801).
		
		set velLatImp to (mod(180 + impPosPrev:lat - impPosCur:lat, 360) - 180)/dT.
		set velLngImp to (mod(180 + impPosPrev:lng - impPosCur:lng, 360) - 180)/dT.
		
		set lzDistCur to lzPos:position - ship:geoposition:altitudeposition(lzAlt).
		set lzDistImp to lzPosFut:position - impPosCur:position.
		set sepDeltaV to Fuel["Stage 1 DeltaV"]().
		
		set landingOffset to vxcl(lzPos:position - impPosFut:position - body:position, lzPos:position - impPosFut:position):normalized * posOffset.
		set landingOffset2 to vxcl(lzPosFut:position - impPosCur:position - body:position, lzPosFut:position - impPosCur:position):normalized.
		//set landingOffset3 to vxcl(lzPos:position -posCur:position - impPosFut:position - body:position, lzPos:position -posCur:position - impPosFut:position):normalized * posOffset.
		set landingOffset4 to (vxcl(lzPos:position - body:position, lzPos:position):normalized * (lzDistCur:mag/10)) + landingOffset.
		
		if runmode >= 4 {
			
			// final landing loop
			set velDir to ship:velocity:surface:normalized * 25.
			set velDirFlat to vxcl(ship:velocity:surface - body:position, ship:velocity:surface):normalized * 25.
			if runmode < 7 {
				//if lzDistCur:mag > lzDistImp:mag {
				//	set desiredDir to (vxcl((velDir - (velDir - (landingOffset:normalized * 25))*2) - body:position, (velDir - (velDir - (landingOffset:normalized * 25))*2)):normalized * 25) - (body:position:normalized * 2).
				//} else {
					set desiredDir to (vxcl((velDir - (velDir - (landingOffset2:normalized * 25))*2) - body:position, (velDir - (velDir - (landingOffset2:normalized * 25))*2)):normalized * 25) - (body:position:normalized * 1).
				//}
			} else {
				set dirRet to (velDirFlat - (landingOffset2:normalized * 25)*2):normalized * 25.
				set dirVecOffset to dirRet - velDirFlat.
				set desiredDir to (-dirVecOffset - velDir):normalized * 25.
			}
		}
		
		if runmode = 9 {
			set landBurnT to max(0.1,mnv_time(ship:velocity:surface:mag, list(Merlin1D_0))) * 1.2.
			//set landBurnD to altCur - lzAlt - verticalspeed * landBurnT + 0.5 * (ship:velocity:surface:mag/landBurnT) * landBurnT^2.
			set landBurnH to verticalspeed^2 / (2*(ship:velocity:surface:mag/landBurnT - gravity())).
			set landBurnD to altCur - lzAlt - landBurnH.
			set landBurnS to -sqrt((altCur - lzAlt)*(2*(ship:velocity:surface:mag/landBurnT - gravity()))).
		}
	}
	
	// Main logic
	
	if runmode = 1 // Engine ignition and liftoff
	{
		if altCur > 200 {
			set runmode to 2.
		} else if mT >= lt-3 {
			set tval to 1.
			stage.
			set runmode to 1.1.
		}
	}
	else if runmode = 1.1
	{
		if mT >= lt {
			stage.
			set runmode to 2.
		}
	}
	else if runmode = 2 // Pitchover
	{
		if airspeed >= 200 {
			set steer to ship:velocity:surface.
			set runmode to 3.
		} else {
			if airspeed >= 20 {
				set compass to orbDir.
			}
			if airspeed >= 60 {
				set pitch to max(0, 90 * (1 - ((airspeed - 60) / 120) / 7.5)).
			}
			set steer to heading(compass, pitch).
		}
	}
	else if runmode = 3 // Gravity turn and stage separation
	{
		set steer to ship:velocity:surface.
		
		if shipCurrentTWR() > 3 {
			if Merlin1D_3:ignition or Merlin1D_4:ignition {
				Engine["Stop"](list(
					Merlin1D_3,
					Merlin1D_4
				)).
			}
		}
		
		if landing <> 0 {
			if sepDeltaV < landingDeltaV(landing) {
				Engine["Stop"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2,
					Merlin1D_3,
					Merlin1D_4,
					Merlin1D_5,
					Merlin1D_6,
					Merlin1D_7,
					Merlin1D_8
				)).
				set tval to 0.
				rcs on.
				set eventTime to mT + 2.
				set runmode to 3.1.
			}
		} else {
			if Merlin1D_0:ignition and Merlin1D_0:flameout {
				set tval to 0.
				rcs on.
				wait 1.
				log " " to "Falcon9S2:/separated.ks".
				stage.
				set clearRequired to true.
				set runmode to 0.
			}
		}
	}
	else if runmode = 3.1 // Booster reorienting.
	{
		if mT > eventTime {
			log " " to "Falcon9S2:/separated.ks".
			stage.
			set eventTime to mT + 2.
			set clearRequired to true.
			set runmode to 4.
		}
	}
	else if runmode = 4 // Booster reorienting.
	{
		if mT > eventTime {
			steeringConfig("reorientingFast").
			set steer to -body:position.
			set runmode to 4.1.
		}
	}
	else if runmode = 4.1
	{
		if rotCur[0] > 75 {
			rcs off.
			set runmode to 4.2.
		}
	}
	else if runmode = 4.2
	{
		if rotCur[0] < 75 {
			set steer to heading(lzPosFut:heading, 0).
			rcs on.
			set engStartup to true.
			set runmode to 5.
		}
	}
	else if runmode = 5 // boostback burn
	{
	
		if 	rotCur[0] < 25 // making sure we point in the right direction before boostback burn
			and rotCur[0] > -20
		{
			set steeringmanager:rolltorquefactor to 5.
			
			//if lzDistImp:mag > 500 and lzDistImp:mag < posOffset and impPosCur:position:mag > lzPosFut:position:mag {
			if lzDistImp:mag < posOffset {
				Engine["Stop"](list(
					Merlin1D_1,
					Merlin1D_2
				)).
				Engine["Throttle"](
				list(
					list(Merlin1D_0, 36)
				)).
			} else {
				Engine["Throttle"](
				list(
					list(Merlin1D_0, 100),
					list(Merlin1D_1, 100),
					list(Merlin1D_2, 100)
				)).
			}
			
			set tval to 1.
			
			if engStartup {
				Engine["Start"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				set engStartup to false.
			}
			if ullageReq {
				rcs on.
				set ship:control:fore to 1.
				set engStartup to true.
			} else {
				rcs off.
				set reorienting to false.
				set ship:control:fore to 0.
				set engStartup to false.
			}
		}
		
		if lzDistImp:mag > posOffset {
			set steer to desiredDir. // steering towards the target
		}
		
		if (lzDistImp:mag >= posOffset) and (lzDistImp:mag < (posOffset * 2)) and (impPosCur:position:mag > lzPosFut:position:mag) {
			Engine["Stop"](list(
				Merlin1D_0,
				Merlin1D_1,
				Merlin1D_2
			)).
			set tval to 0.
			//set latOffset to 0.
			set runmode to 6.
		}
	}
	else if runmode = 6 // Reorienting for reentry
	{
		rcs on.
		set reorienting to true.
		set steer to heading(rotCur[1], rotCur[0]).
		set eventTime to mT + 3.
		set runmode to 6.1.
	}
	else if runmode = 6.1
	{
		if mT > eventTime {
			steeringConfig("reorientingSlow").
			set clearRequired to true.
			set steer to -body:position.
			set runmode to 6.2.
		}
	}
	else if runmode = 6.2
	{			
		if 	rotCur[0] > 75 {
			rcs off.
			set runmode to 6.3.
		}
	}
	else if runmode = 6.3
	{
		if rotCur[0] < 75 {
			set steer to -ship:velocity:surface.
			rcs on.
			ag5 on.
			set engStartup to true.
			set runmode to 7.
		}
	}
	else if runmode = 7 // Reentry burn
	{
		if altCur <= reentryBurnAlt {
			set ship:control:fore to 0.
			set posOffset to 1500.
			
			set reorienting to false.
			set tval to 1.
			
			if lzDistImp:mag > (posOffset * 1.5) {
				Engine["Throttle"](list(
					list(Merlin1D_0, 75),
					list(Merlin1D_1, 75),
					list(Merlin1D_2, 75)
				)).
			} else {
				Engine["Throttle"](list(
					list(Merlin1D_0, 36),
					list(Merlin1D_1, 36),
					list(Merlin1D_2, 36)
				)).
			}
			
			if engStartup {
				Engine["Start"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				set engStartup to false.
			}
			
			if (lzDistImp:mag <= posOffset) {
				Engine["Stop"](list(
					Merlin1D_1,
					Merlin1D_2
				)).
				set tval to 0.
				set runmode to 8.
				rcs off.
			}
			
			set steer to desiredDir.
		} else {
			
			set steer to -ship:velocity:surface.
			
			if altCur < reentryBurnAlt + 5000 {
				rcs on.
				set ship:control:fore to 1.
			}
		}
	}
	else if runmode = 8
	{
		
		set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset4):lat.
		set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosCur:lat).
		set steerPitch to DescLatitude_PID:update(mT, velLatImp).
		
		set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset4):lng.
		set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosCur:lng).
		set steerYaw to DescLongitude_PID:update(mT, velLngImp).
		
		set steer to (-ship:velocity:surface):direction + r(steerPitch, steerYaw, 0).
		if altCur < 45000
		{
			set runmode to 9.
			when timeToAltitude(landBurnH + lzAlt, altCur) < 3 and altCur - lzAlt < 10000 then {
				set tval to 1.
			}
		}
	}
	else if runmode = 9
	{
		set AltVel_PID:setpoint to lzAlt.
		if landBurnS < -50 {
			set VelThr_PID:setpoint to landBurnS.
		} else {
			set VelThr_PID:setpoint to AltVel_PID:update(mT, altCur).
		}
		Engine["Throttle"](
		list(
			list(Merlin1D_0, VelThr_PID:update(mT, verticalspeed)*100)
		)).
		set DescLatitudeChange_PID:kp to min(25, max(5, 25 - altCur/1000)).
		set DescLongitudeChange_PID:kp to min(25, max(5, 25 - altCur/1000)).
		
		if altCur - lzAlt > 1000 {
			
			set posOffset to min(1500, lzDistImp:mag/2).
			
			set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset4):lat. // steering
			set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosCur:lat).
			set steerPitch to -DescLatitude_PID:update(mT, velLatImp).
			
			set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset4):lng.
			set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosCur:lng).
			set steerYaw to -DescLongitude_PID:update(mT, velLngImp).
			
		} else {
			
			set posOffset to 0.01.
			
			set LandLatitudeChange_PID:setpoint to lzPosFut:lat.
			set LandLatitude_PID:setpoint to LandLatitudeChange_PID:update(mT, impPosCur:lat).
			set steerPitch to -LandLatitude_PID:update(mT, velLatCur).
			
			set LandLongitudeChange_PID:setpoint to lzPosFut:lng.
			set LandLongitude_PID:setpoint to LandLongitudeChange_PID:update(mT, impPosCur:lng).
			set steerYaw to -LandLongitude_PID:update(mT, velLngCur).
			
		}
		
		if VelThr_PID:output < 0.37 {
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
				Merlin1D_0
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
		//set vec3 to vecdraw(ship:position, lzPos:position + landingOffset, rgb(0,0,1), "LO", 1, true).
		//set vec4 to vecdraw(ship:position, lzPos:position + landingOffset3, rgb(1,0.3,0), "LO3", 1, true).
		set vec5 to vecdraw(ship:position, lzPos:position + landingOffset4, rgb(1,1,1), "LO4", 1, true).
		
	}
	
	if runmode >= 4 {
		print "Current Position:          " + round(longitude, 3) + ", " + round(latitude, 3) + "             " at (3,20).
		print "Impact Position:           " + round(impPosFut:lng, 3) + ", " + round(impPosFut:lat, 3) + "             " at (3,21).
		
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
	print "Landing Burn Time:         " + round(landBurnT,1) + "     " at (3, 40).
	print "Landing Burn Distance:     " + round(landBurnH) + "     " at (3, 41).
	print "Dist until Landing Burn:   " + round(landBurnD) + "     " at (3, 42).
	print "Landing Burn Speed:        " + round(landBurnS) + "     " at (3, 43).
	print "Current Speed:             " + round(verticalspeed) + "     " at (3, 44).
	}
	
	// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
	
	set pT to mT.
	set posPrev to posCur.
	set impPosPrev to impPosCur.
	set rotPrev to rotCur.

	// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
	
	wait 0.
}

unlock all.