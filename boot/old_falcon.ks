@lazyglobal off.
clearscreen.
wait 0.

local storagePath is "Falcon9S1Storage:".
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
	
	// \/ Need renaming \/ //
	local posOffset is 10000.
	local landingOffset is 0.
	local landingOffset2 is 0.
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
		
	// ---== PREPARING PID LOOPS ==--- //
		// ----- Landing loops ----- //
		// Landing velocity control
		local AltVel_PID is pidloop(0.45, 0, 0.3, -600, 600).
		local VelThr_PID is pidloop(0.05, 0.01, 0.005, 0.01, 1).
		
		// ----- Controlled descent loops ----- //
		// Latitude control
		local DescLatitudeChange_PID is pidloop(3, 0.005, 0.3, -0.1, 0.1).
		local DescLatitude_PID is pidloop(300, 1, 30, -35, 35).
		// Longditude control
		local DescLongitudeChange_PID is pidloop(3, 0.005, 0.3, -0.1, 0.1).
		local DescLongitude_PID is pidloop(300, 1, 30, -35, 35).

		// ----- Final touch-down loops ----- //
		// Latitude control
		local LandLatitudeChange_PID is pidloop(1, 0.001, 0.2, -0.01, 0.01).
		local LandLatitude_PID is pidloop(200, 0, 40, -15, 15).
		// Longditude control
		local LandLongitudeChange_PID is pidloop(1, 0.001, 0.2, -0.01, 0.01).
		local LandLongitude_PID is pidloop(200, 0, 40, -15, 15).
		
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
	local landBurnT is 0. // Landing burn time
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
	
	local bodyRotation is 360 / body:rotationperiod.
	
// ---=== [**END**] [ DECLARING ALL NECESSARY VARIABLES ] [**END**] ===---

// ---=== [**START**] [ GETTING NECESSARY DATA ] [**START**] ===---

	wait until exists(storagePath + "/stage1status.ks").
	runpath(storagePath + "/stage1status.ks").

	if lzPos <> 0 {
		if lzPos = 1 {
			set lzPos to KSCLaunchPad.
		}
		
		set lzAlt to lzPos:terrainheight.
	}

	when (altCur - lzAlt) < 500 and runmode > 2 then { gear on. }

// final preparation - setting up for launch

	set sT to time:seconds.
	set pT to sT.
	set posPrev to ship:geoposition.
	set impPosPrev to ship:geoposition.
	set rotPrev to list(pitch_for(ship), compass_for(ship), roll_for(ship)).
	
	createLog().

// ---=== [**END**] [ GETTING NECESSARY DATA ] [**END**] ===---

wait 0. // waiting 1 physics tick so that everything updates

// ----------------================ \/ Magic. Do not touch! \/ ================----------------
if lzPos <> 0 {
	until runmode = 0 {
		
	// ---=== [**START**] [ UPDATING VARIABLES BEFORE EVERY ITERATION ] [**START**] ===--- //
		
		set mT to time:seconds.
		set dT to mT - pT.
		set posCur to ship:geoposition.
		set rotCur to list(pitch_for(ship), compass_for(ship), rollConvert()).
		set rotSpd to list((mod(90 + rotCur[0] - rotPrev[0], 180) -90)/dT, mod(rotCur[1] - rotPrev[1], 360)/dT,(mod(180 + rotCur[2] - rotPrev[2], 360) -180)/dT).
		set altCur to body:altitudeof(Merlin1D_0:position) - 3.9981.
		set velLatCur to (mod(180 + posPrev:lat - posCur:lat, 360) - 180)/dT.
		set velLngCur to (mod(180 + posPrev:lng - posCur:lng, 360) - 180)/dT.
		
		set impT to timeToAltitude(lzAlt, altCur).
		set landBurnT to mnv_time(ship:velocity:surface:mag).
		set lzPosFut to latlng(lzPos:lat, mod(lzPos:lng + 180 + (impT * bodyRotation), 360) - 180).
		set impPosCur to body:geopositionof(positionat(ship, time:seconds + impT)).
		
		set impPosFut to latlng(body:geopositionof(positionat(ship, time:seconds + impT)):lat, body:geopositionof(positionat(ship, time:seconds + impT)):lng - (impT * bodyRotation)).
		
		set velLatImp to (mod(180 + impPosPrev:lat - impPosCur:lat, 360) - 180)/dT.
		set velLngImp to (mod(180 + impPosPrev:lng - impPosCur:lng, 360) - 180)/dT.
		
		set landingOffset to vxcl(lzPos:position - body:position, lzPos:position):normalized * posOffset.
		set landingOffset2 to vxcl((lzPosFut:position) - impPosCur:position - body:position, (lzPosFut:position) - impPosCur:position):normalized.
		
		set lzDistCur to lzPos:position - ship:geoposition:altitudeposition(lzAlt).
		set lzDistImp to lzPosFut:position - impPosCur:position.
		
		if runmode >= 2 {
			
			// final landing loop
			set velDir to ship:velocity:surface:normalized * 25.
			set velDirFlat to vxcl(ship:velocity:surface - body:position, ship:velocity:surface):normalized * 25.
			if runmode < 4 {
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
		
	
		
		// The main code
		if runmode = 1 {
			if exists(storagePath + "/separated.ks") {
				wait 0.
				lock throttle to max(0, min(1, tval)).
				lock steering to steer.
				set steeringmanager:maxstoppingtime to 1.
				set steeringmanager:rollts to 9.
				set steeringmanager:pitchts to 5.
				set steeringmanager:yawts to 5.
				set steeringmanager:pitchpid:kd to 12.
				set steeringmanager:yawpid:kd to 12.
				set runmode to 2.
			}
		}
		else if runmode = 2
		{
			set tval to 0.
			rcs on.
			set reorienting to true.
			set steer to ship:velocity:surface.
			set eventTime to mT.
			set runmode to 2.1.
		}
		else if runmode = 2.1
		{
			if mT > eventTime + 4 {
				set clearRequired to true.
				set runmode to 2.2.
				set steer to -body:position.
			}
		}
		else if runmode = 2.2
		{
			// turning booster around
			if 	rotCur[0] > 70 {
				set runmode to 2.4.
			}
		}
		else if runmode = 2.3
		{
			if rotCur[0] < 70 {
				set runmode to 2.4.
			}
		}
		else if runmode = 2.4
		{
			set steer to heading(lzPosFut:heading, 0).
			set runmode to 3.
		}
		else if runmode = 3
		{
			if 	rotCur[0] < 20 // making sure we point in the right direction before boostback burn
				and rotCur[0] > -20
			{
				
				if lzDistImp:mag > 500 and lzDistImp:mag < posOffset and impPosCur:position:mag > lzPosFut:position:mag {
					set tval to 0.05.
				} else {
					set tval to 1.
				}
				Engine["Start"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				if ullageReq {
					rcs on.
					set ship:control:fore to 1.
				} else {
					rcs off.
					set reorienting to false.
					set ship:control:fore to 0.
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
				set runmode to 3.1.
			}
		}
		else if runmode = 3.1
		{
			set tval to 0.
			rcs on.
			set reorienting to true.
			set steer to heading(compass_for(ship), pitch_for(ship)).
			set eventTime to mT.
			set runmode to 3.2.
		}
		else if runmode = 3.2
		{
			if mT > eventTime + 5 {
				set clearRequired to true.
				set runmode to 3.5.
				set steer to -body:position.
				//rcs on.
				//sas on.
			}
		}
		else if runmode = 3.5
		{			
			if 	rotCur[0] > 65 {
				set runmode to 3.7.
			}
		}
		else if runmode = 3.6
		{
			if rotCur[0] < 65 {
				set runmode to 3.7.
			}
		}
		else if runmode = 3.7
		{
			set steer to -ship:velocity:surface.
			ag5 on.
			set runmode to 4.
		}
		else if runmode = 4
		{
			if altCur <= reentryBurnAlt {
				set ship:control:fore to 0.
				set posOffset to 1500.
				
				set reorienting to false.
				
				Engine["Start"](list(
					Merlin1D_0,
					Merlin1D_1,
					Merlin1D_2
				)).
				rcs off.
				
				if lzDistImp:mag > (posOffset * 1.5) {
					set tval to 1.
				} else {
					set tval to 0.1.
				}
				
				if (lzDistImp:mag <= posOffset) {
					Engine["Stop"](list(
						Merlin1D_0,
						Merlin1D_1,
						Merlin1D_2
					)).
					set tval to 0.
					set runmode to 6.
				}
				
				set steer to desiredDir.
			} else {
				
				if not reorienting {
					set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lat. // steering
					set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosCur:lat).
					set steerPitch to DescLatitude_PID:update(mT, velLatImp).
					
					set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lng.
					set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosCur:lng).
					set steerYaw to DescLongitude_PID:update(mT, velLngImp).
					
					set steer to (-ship:velocity:surface):direction + r(steerPitch, steerYaw, 0).
				} else {
					set steer to -ship:velocity:surface.
				}
				
				if altCur < reentryBurnAlt + 5000 {
					set ship:control:fore to 1.
				}
			}
		}
		else if runmode = 5
		{
			set steer to -ship:velocity:surface.
			if altCur < 15000 {
				set runmode to 7.
			}
		}
		else if runmode = 6
		{
			
			set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lat.
			set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosCur:lat).
			set steerPitch to DescLatitude_PID:update(mT, velLatImp).
			
			set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lng.
			set DescLongitude_PID:setpoint to DescLongitudeChange_PID:update(mT, impPosCur:lng).
			set steerYaw to DescLongitude_PID:update(mT, velLngImp).
			
			set steer to (-ship:velocity:surface):direction + r(steerPitch, steerYaw, 0).
			if altCur < 45000
			{
				//Engine["Start"](list(
				//	Merlin1D_0
				//)).
				set runmode to 7.
			}
		}
		else if runmode = 7
		{
			set AltVel_PID:maxoutput to pidLimit.
			set AltVel_PID:minoutput to -pidLimit.
			set AltVel_PID:setpoint to lzAlt.
			set VelThr_PID:setpoint to AltVel_PID:update(mT, altCur).
			set tval to VelThr_PID:update(mT, verticalspeed).
			
			if altCur - lzAlt > 2000 {
				
				if lzDistCur:mag < 200 {
					set posOffset to 10.
				} else {
					set posOffset to min(1000, lzDistCur:mag/2).
				}
			
				set DescLatitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lat. // steering
				set DescLatitude_PID:setpoint to DescLatitudeChange_PID:update(mT, impPosCur:lat).
				set steerPitch to -DescLatitude_PID:update(mT, velLatImp).
				
				set DescLongitudeChange_PID:setpoint to body:geopositionof(lzPosFut:position + landingOffset):lng.
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
			
			if tval < 0.5 and (altCur - lzAlt) > 300 {
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
				//Engine["Stop"](list(
				//	Merlin1D_0
				//)).
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
		// if (runmode >= 2 and runmode <= 2.1 and reorienting) or (runmode >= 3.1 and runmode <= 3.2 and reorienting) {
			
			// set Pitch_PID:setpoint to 0.
			// set Yaw_PID:setpoint to 0.
			// set Roll_PID:setpoint to 0.
			
			// set Pitch_val to Pitch_PID:update(mT, rotSpd[0]).
			// set Yaw_val to Yaw_PID:update(mT, rotSpd[1]).
			
			// set Pitch_set to (Pitch_val * pitchYawRatio()[0]) + (Yaw_val * pitchYawRatio()[1]).
			// set Yaw_set to (Yaw_val * pitchYawRatio()[0]) + (Pitch_val * pitchYawRatio()[1]).
			
			// set ship:control:roll to Roll_PID:update(mT, rotSpd[2]).
			// if abs(rotSpd[2]) < 1 {
				// set ship:control:pitch to Pitch_set.
				// set ship:control:yaw to Yaw_set.
			// } else {
				// set ship:control:pitch to 0.
				// set ship:control:yaw to 0.
			// }
			
		// } else if (runmode >= 2.2 and runmode <= 2.4) or (runmode >= 3.5 and runmode <= 3.7) {
		
			// set PitchSpd_PID:setpoint to steer[0].
			// set YawSpd_PID:setpoint to compassCalc(steer[1], rotCur[1]).
			// set RollSpd_PID:setpoint to compassCalc(steer[2], rotCur[2]).
		
			// set Pitch_PID:setpoint to PitchSpd_PID:update(mT, rotSpd[0]).
			// set Yaw_PID:setpoint to YawSpd_PID:update(mT, rotSpd[1]).
			// set Roll_PID:setpoint to RollSpd_PID:update(mT, rotSpd[2]).

			// set Pitch_val to Pitch_PID:update(mT, rotSpd[0]).
			// set Yaw_val to Yaw_PID:update(mT, rotSpd[1]).
			
			// set Pitch_set to (Pitch_val * pitchYawRatio()[0]) + (Yaw_val * pitchYawRatio()[1]).
			// set Yaw_set to (Yaw_val * pitchYawRatio()[0]) + (Pitch_val * pitchYawRatio()[1]).
			
			// if (abs(rotCur[0]) - abs(steer[0]) < 1 and abs(rotCur[1]) - abs(steer[1]) < 1 and abs(rotSpd[0]) < 0.1 and abs(rotSpd[1]) < 0.1) or (abs(rotSpd[2]) > 1)  {
				// set ship:control:pitch to 0.
				// set ship:control:yaw to 0.
				// set ship:control:roll to Roll_PID:update(mT, rotSpd[2]).
			// } else {
				// set ship:control:pitch to Pitch_set.
				// set ship:control:yaw to Yaw_set.
				// set ship:control:roll to 0.
			// }
			
		// }
		if reorienting and (runmode > 3.1 and runmode < 5) {
		
			set steeringmanager:maxstoppingtime to 0.5.
			//set steeringmanager:rollts to 9.
			//set steeringmanager:pitchts to 5.
			//set steeringmanager:yawts to 5.
			//set steeringmanager:pitchpid:kd to 10.
			//set steeringmanager:yawpid:kd to 10.
			
		} else if reorienting and steeringmanager:maxstoppingtime <> 2 {
		
			set steeringmanager:maxstoppingtime to 2.
			//set steeringmanager:rollts to 9.
			//set steeringmanager:pitchts to 5.
			//set steeringmanager:yawts to 5.
			//set steeringmanager:pitchpid:kd to 10.
			//set steeringmanager:yawpid:kd to 10.
			
		} else if not reorienting and steeringmanager:maxstoppingtime <> 1 {
		
			set steeringmanager:maxstoppingtime to 1.
			//set steeringmanager:rollts to 2.
			//set steeringmanager:pitchts to 2.
			//set steeringmanager:yawts to 2.
			//set steeringmanager:pitchpid:kd to 0.
			//set steeringmanager:yawpid:kd to 0.
		
		}
		
		if runmode >= 6 {
		
			set vec1 to vecdraw(ship:position, impPosFut:position, rgb(1,0,0), "", 1, true).
			set vec2 to vecdraw(ship:position, posCur:position, rgb(0,1,0), "", 1, true).
			set vec3 to vecdraw(ship:position, lzPos:position + landingOffset, rgb(0,0,1), "T", 1, true).
			//set vec4 to vecdraw(ship:position, lzPos:position, rgb(1,0.3,0), "", 1, true).
			
		}
		
		if runmode >= 3 {
			print "Current Position:          " + round(longitude, 3) + ", " + round(latitude, 3) + "             " at (3,20).
			print "Impact Position:           " + round(impPosCur:lng, 3) + ", " + round(impPosCur:lat, 3) + "             " at (3,21).
			
			print "Impact Time:               " + round(impT, 2) + "     " at (3, 23).
			print "Suicide Burn Time:         " + round(landBurnT, 2) + "     " at (3, 24).
			print "Impact Distance:           " + round(lzDistImp:mag, 2) + "          " at (3, 25).
			
			print "Position offset:           " + round(posOffset, 2) + "           " at (3, 27).
			print "Distance to LZ:            " + round(lzDistCur:mag, 2) + "           " at (3, 28).
			
			print "Steer Pitch:               " + round(steerPitch, 2) + "     " at (3, 30).
			print "Steer Yaw:                 " + round(steerYaw, 2) + "     " at (3, 31).
			
		}
		
		print "Runmode:                       " + runmode + "     " at (3, 33).
		print "DeltaV remaining:              " + round(Fuel["Stage 1 DeltaV"]()) + "     " at (3, 35).
		//if runmode >= 3.5 {
		//	print "Estimated Drag Force:      " + round((1.9 * (ship:sensors:pres * constant:kpatoatm) * (airspeed^2/2) * (7.28))*0.00144,3) + "     " at (3, 36).
		//}
		print "Runmode:                       " + runmode + "     " at (3,40).
		// ---=== [**START**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**START**] ===--- //
		
		// Logging flight data to file
		
		
		
		if runmode >= 2.4 { // log data
			logData().
		}
		
		set pT to mT.
		set posPrev to posCur.
		set impPosPrev to impPosCur.
		set rotPrev to rotCur.

		// ---=== [**END**] [ UPDATING VARIABLES AFTER EVERY ITERATION ] [**END**] ===--- //
		
		wait 0.
	}
}
unlock all. // we are done!
sas on.