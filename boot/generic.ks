//	Boot file decides what programs to load based on CPU name
@LAZYGLOBAL OFF.
CLEARSCREEN.

//	Lists of programs and their requirements
LOCAL programs IS LEXICON(
	"recovery", LEXICON(
		"location", "0:/recovery/",
		"configLocation", "0:/config/",
		"uploadRequired", TRUE,
		"loadConfigs", FALSE,
		"boot", TRUE,
		"mainFileName", "recovery",
		"programFiles", LIST("recovery", "recovery_utils", "aero_functions", "lib_navball"),
		"configFiles", LIST("landing")
	),
	"recovery_test", LEXICON(
		"location", "0:/recovery/",
		"configLocation", "0:/config/",
		"uploadRequired", TRUE,
		"loadConfigs", FALSE,
		"boot", TRUE,
		"mainFileName", "recovery_test",
		"programFiles", LIST("recovery_test", "recovery_utils", "aero_functions", "lib_navball"),
		"configFiles", LIST("landing")
	),
	"pegas", LEXICON(
		"location", "0:/pegas/",
		"configLocation", "0:/config/",
		"uploadRequired", FALSE,
		"loadConfigs", TRUE,
		"boot", FALSE,
		"mainFileName", "pegas",
		"programFiles", LIST("pegas", "pegas_comm", "pegas_cser", "pegas_misc", "pegas_upfg", "pegas_util"),
		"configFiles", LIST("Falcon9", "mission")
	)
).

FUNCTION checkDiskSpace {
	PARAMETER programName.

	FUNCTION checkRequiredFiles {
		LOCAL size IS 0.
		IF NOT programName = FALSE {
			IF programs[programName]:HASKEY("configFiles") {
				FOR f IN programs[programName]["configFiles"] {
					SET size TO size + OPEN(programs[programName]["configLocation"] + f + ".ks"):SIZE.
				}
			}
			FOR f IN programs[programName]["programFiles"] {
				SET size TO size + OPEN(programs[programName]["location"] + f + ".ks"):SIZE.
			}
		}
		RETURN size.
	}

	LOCAL space IS VOLUME(1):FREESPACE.
	LOCAL spaceNeeded IS checkRequiredFiles().
	LOCAL enoughSpace IS FALSE.
	IF space > spaceNeeded { SET enoughSpace TO TRUE. }
	RETURN LIST(enoughSpace, space, spaceNeeded).
}
//	Make sure volume is named correctly
SET VOLUME(1):NAME TO CORE:TAG.
LOCAL programName IS FALSE.
IF VOLUME(1):NAME = "Falcon9S1" { SET programName TO "recovery". }
ELSE IF VOLUME(1):NAME = "Falcon9S1_Test" { SET programName TO "recovery_test". }
ELSE IF VOLUME(1):NAME = "Falcon9S2" { SET programName TO "pegas". }
IF programName:ISTYPE("Boolean") {
	PRINT "ERROR: No program found for current vessel.".
} ELSE {
	LOCAL diskSpace IS LIST(TRUE, 0, 0).
	IF programs[programName]["uploadRequired"] { SET diskSpace TO checkDiskSpace(programName). }
	IF diskSpace[0] {
		PRINT "Clear to proceed, waiting for instruction.".
		PRINT "Please hit '0' (action group) when you are ready.".
		WAIT UNTIL AG10.
		IF programs[programName]:HASKEY("configFiles") {
			FOR f IN programs[programName]["configFiles"] {
				COPYPATH(programs[programName]["configLocation"] + f + ".ks", "1:/config/" + f + ".ks").
				IF programs[programName]["loadConfigs"] { RUNPATH("1:/config/" + f + ".ks"). }
			}
		}
		IF programs[programName]["uploadRequired"] { FOR f IN programs[programName]["programFiles"] { COPYPATH(programs[programName]["location"] + f + ".ks", "1:"). } }
		IF programs[programName]["boot"] { SET CORE:BOOTFILENAME TO programs[programName]["mainFileName"] + ".ks". REBOOT. }
		ELSE { CD(programs[programName]["location"]). RUNPATH(programs[programName]["location"] + programs[programName]["mainFileName"] + ".ks"). }
	} ELSE {
		PRINT "ERROR: Not enough space on " + VOLUME(1):NAME.
		PRINT "Available space: " + diskSpace[1].
		PRINT "Required space:  " + diskSpace[2].
	}
}