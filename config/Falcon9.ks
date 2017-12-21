GLOBAL vehicle IS LIST(
					LEXICON(
						//	This stage will be ignited upon UPFG activation.
						"name", "FalconS2",
						"massTotal", 109990,
						"massFuel", 109983.794,
						"gLim", 3,
						"minThrottle", 0.39,
						"engines", LIST(LEXICON("isp", 348, "thrust", 934120)),
						"staging", LEXICON(
										"shutdownRequired", TRUE,
										"jettison", TRUE,
										"waitBeforeJettison", 2,
										"ignition", TRUE,
										"waitBeforeIgnition", 0.5,
										"ullage", "rcs",
										"ullageBurnDuration", 1,
										"postUllageBurn", 1
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -3, "type", "stage", "message", "Merlin 1D ignition"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", 180, "type", "stage", "message", "Fairing separation")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 6,
					"pitchOverAngle", 1,
					"upfgActivation", 152
).
SET STEERINGMANAGER:ROLLTS TO 10.
SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: Falcon 9!".