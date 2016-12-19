local h is 0.
local m is 0.
local s is 0.
local obtp is 0.

until false {

set obtp to ship:obt:period.
set h to floor(obtp/3600).
set m to floor((obtp - (h*3600))/60).
set s to round(obtp - (h*3600) - (m*60), 4).

clearscreen.

print (ship:obt:period) + "s".
print (h) + "h " + (m) + "m " + (s) + "s".

}