GLOBAL vehicle IS LIST(
					LEXICON(
						//	This stage will be ignited upon UPFG activation.
						"name", "FalconS2",
						"massTotal", 109990,
						"massFuel", 109983.794,
						"gLim", 3,
						"engines", LIST(LEXICON("isp", 348, "thrust", 934120)),
						"staging", LEXICON(
										"jettison", TRUE,
										"waitBeforeJettison", 3,
										"ignition", TRUE,
										"waitBeforeIgnition", 1,
										"ullage", "rcs",
										"ullageBurnDuration", 5,
										"postUllageBurn", 3
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -3, "type", "stage", "message", "Merlin 1D ignition"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", 20, "type", "roll", "angle", 0, "message", "Performing roll maneuver"),
					LEXICON("time", 190, "type", "stage", "message", "Fairing separation")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 5,
					"pitchOverAngle", 1,
					"upfgActivation", 152
).
SET STEERINGMANAGER:ROLLTS TO 10.
SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: Falcon 9!".