//	Landing configuration file
GLOBAL landing IS LEXICON(
	"required", TRUE,
	"landingEngines", 1,
	"landingThrottle", 0.6,
	"location", landing["listOfLocations"]["KSCLaunchPad"],	//	Not sure if this will work?
	"boostback", TRUE,
	"boostbackEngines", 3,
	"boostbackThrottle", 1,
	"reentry", TRUE,
	"reentryEngines", 3,
	"reentryThrottle", 0.75,
	"listOfLocations", LEXICON(
		"KSCLaunchPad", LATLNG(28.6083859739973, -80.5997467227517),
		"ASDS_GTO_1", LATLNG(28.1322262, -73.4441595)
	)
).

GLOBAL vehicle IS LEXICON(
	"current", vehicle["listOfVessels"]["Falcon 9 FT"],		//	Not sure if this will work?
	"listOfVessels", LEXICON(
		"Falcon 9 FT", LEXICON(
			"pegas_cpu", "Falcon9S2",
			"aerodynamics", LEXICON(
				"CdMin", 0.0386,
				"CdRound2", LEXICON(
				//	Mach	Cd
					0.6, 0.0386, 0.61, 0.0386, 0.62, 0.0386, 0.63, 0.0388, 0.64, 0.0426, 0.65, 0.0488, 0.66, 0.0637, 0.67, 0.0762, 0.68, 0.0969, 0.69, 0.1255,
					0.7, 0.1355, 0.71, 0.1847, 0.72, 0.2119, 0.73, 0.249, 0.74, 0.2922, 0.75, 0.3283, 0.76, 0.3736, 0.77, 0.4159, 0.78, 0.4629, 0.79, 0.5087,
					0.8, 0.5585, 0.81, 0.6027, 0.82, 0.6506, 0.83, 0.699, 0.84, 0.7493, 0.85, 0.7901, 0.86, 0.832, 0.87, 0.8776, 0.88, 0.9209, 0.89, 0.9597,
					0.9, 0.9976, 0.91, 1.0329, 0.92, 1.0666, 0.93, 1.0977, 0.94, 1.1249, 0.95, 1.1477, 0.96, 1.1661, 0.97, 1.1814, 0.98, 1.1929, 0.99, 1.1994,
					1, 1.202, 1.01, 1.2022, 1.02, 1.2023, 1.03, 1.2024, 1.04, 1.2025, 1.05, 1.2026, 1.06, 1.2026, 1.07, 1.2025, 1.08, 1.2026, 1.09, 1.2031,
					1.1, 1.203, 1.11, 1.2028, 1.12, 1.2024, 1.13, 1.2023, 1.14, 1.2018, 1.15, 1.2012, 1.16, 1.2006, 1.17, 1.1999, 1.18, 1.1992, 1.19, 1.1985
				),
				"CdRound1", LEXICON(
				//	Mach	Cd
					1.2, 1.1977, 1.3, 1.1884, 1.4, 1.1761, 1.5, 1.1632, 1.6, 1.1488, 1.7, 1.1342, 1.8, 1.1197,
					1.9, 1.1051, 2, 1.0937, 2.1, 1.0773, 2.2, 1.0658, 2.3, 1.0579, 2.4, 1.0491
				),
				"CdMax", {	//	Anonymous function
					PARAMETER m.
					RETURN 1.1237*(0.9622907946^m).
				},
				"surfaceArea", 17.1766,
			),
			"mass", LEXICON(
				"dry", 22.936
			),
			"fuel", LEXICON(
				"tankNametag", "Falcon9-S1-Tank",
				"rcsFuels", LIST("Nitrogen"),
				"fuelNames", LIST("Kerosense", "LqdOxygen")
			),
			"engines", LEXICON(
				"list", LIST("Merlin1D-0", "Merlin1D-1", "Merlin1D-2", "Merlin1D-3", "Merlin1D-4", "Merlin1D-5", "Merlin1D-6", "Merlin1D-7", "Merlin1D-8"),
				"mixtureRatio", 0.35,
				"spoolUpTime", 3,
				"minThrottle", 0.36
			)
		)
	)
).