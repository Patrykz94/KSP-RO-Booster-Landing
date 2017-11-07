//	Boot file decides what programs to load based on CPU name
@LAZYGLOBAL OFF.
CLEARSCREEN.

//	Lists of files required for each script
LOCAL programs IS LEXICON(
	"recovery", LIST(LIST("recovery", "recovery_functions", "aero_functions", "falcon_rcs", "lib_navball", "telemetry"), LIST("landing")),
	"pegas", LIST(LIST("pegas", "pegas_comm", "pegas_cser", "pegas_misc", "pegas_upfg", "pegas_util"), LIST("Falcon9", "mission"))
).

FUNCTION checkDiskSpace {
	PARAMETER programName.

	FUNCTION checkRequiredFiles {
		PARAMETER programName.
		LOCAL size IS 0.
		IF NOT programName = FALSE {
			IF programs[programName]:LENGTH > 1 {
				FOR f IN programs[programName][1] {
					SET size TO size + OPEN("0:/config/" + f + ".ks"):SIZE.
				}
			}
			FOR f IN programs[programName][0] {
				SET size TO size + OPEN("0:/" + programName + "/" + f + ".ks"):SIZE.
			}
		}
		RETURN size.
	}

	LOCAL space IS VOLUME(1):FREESPACE.
	LOCAL spaceNeeded IS checkRequiredFiles(programName).
	LOCAL enoughSpace IS FALSE.
	IF space > spaceNeeded { SET enoughSpace TO TRUE. }
	RETURN LIST(enoughSpace, space, spaceNeeded).
}
//	Make sure volume is named correctly
SET VOLUME(1):NAME TO CORE:TAG.
LOCAL programName IS FALSE.
IF VOLUME(1):NAME = "Falcon9S1" { SET programName TO "recovery". }
ELSE IF VOLUME(1):NAME = "Falcon9S2" { SET programName. }
LOCAL diskSpace IS checkDiskSpace(programName)[0].
IF diskSpace[0] {
	PRINT "Clear to proceed, waiting for instruction.".
	PRINT "Please hit '0' (action group) when you are ready.".
	WAIT UNTIL AG10.
	IF programs[programName]:LENGTH > 1 {
		FOR f IN programs[programName][1] { COPYPATH("0:/config/" + f + ".ks", "1:"). }
	}
	FOR f IN programs[programName][0] { COPYPATH("0:/" + programName + "/" + f + ".ks", "1:"). }
	IF programName = "recovery" { SET CORE:BOOTFILENAME TO "1:/" + programName + "/" + programName + ".ks". REBOOT. }
	ELSE IF programName = "pegas" { RUNPATH("1:/pegas.ks"). }
} ELSE {
	PRINT "ERROR: Not enough space on " + VOLUME(1):NAME.
	PRINT "Available space: " + diskSpace[1].
	PRINT "Required space:  " + diskSpace[2].
}