/*
MWO Absolute stick aiming fix

Proof-of-concept

Requirements
============
EXE version or .ahk (source) version of script:
   vJoy virtual joystick driver from http://vjoystick.sourceforge.net

.ahk (source) - ie not the EXE version:
   AHK from http://ahkscript.org. !!! NOT autohotkey.com !!!
   AHK-CvJoyInterface.ahk from here: https://github.com/evilC/AHK-CvJoyInterface

MWO Setup:
	One Time
	========
	1) Set cl_joystick_absolute_inputs=1 is required in ?user.cfg? - i need mine in system.cfg
	2) In the CONTROLLER menu, the following sliders MUST be at thier DEFAULT values!
		X-AXIS SENSITIVITY, Y-AXIS SENSITIVITY and DEADZONE
		DO NOT attempt to set deadzone to 0! It goes mental!
	3) Bind vJoy axis 1 to TORSO TWIST in MWO:
		Start the script, enable calib mode, tab into MWO settings menu.
		Double click TORSO TWIST in the JOYSTICK column
		Spam F11 or F12 until it binds.
		F11 / F12 moves the virtual stick without you having to move the physical stick...
		... so we can be sure MWO binds to the virtual stick.
	
	Per-Run ( These settings will become persistent if I move past proof-of-concept stage)
	=======
	1) Configure inputs
		In the script, select the ID and axis number of the stick you wish to use as input.
	2) Set Low and High Threshold numbers.
		You need two numbers for the low and high threshold.
		If you have calibrated before and have good numbers, you can just plug them right in and go.
		If not, here is how to calibrate:
		A) Before you start, it seems to not matter if in windowed mode or fullscreen (same values)
			So ALT+ENTER to go windowed to be able to see script GUI if you like.
		B) Enter calibration mode in script (F5 or tick UI checkbox)
		C) Use F11/F12 to find roughly where view starts moving. Once you find it, Switch to F9/F10 to precisely locate.
			Once you have exact edge (first F10 push where screen moves), Hit F6 to set low threshold.
		D) Use same process - F11/F12 then F9/F10 to find rough high edge where view stops moving.
			Once you find high edge, hit F7
		E) Hit F5 to exit calibration mode and test.
		
*/
#SingleInstance, force
#include <CvJoyInterface>

starting_up := 1

default_low_thresh := 2460
default_high_thresh := 12314
;default_low_thresh := 0
;default_high_thresh := 0

Gui, Add, Text, xm ym Section, Low Threshold
Gui, Add, Edit, vLowThresh gThreshChanged w50 ys-3, % default_low_thresh
Gui, Add, Text, xm Section, High Threshold
Gui, Add, Edit, vHighThresh gThreshChanged w50 ys-3, % default_high_thresh
Gui, Add, Text, xm Section, Small Step Size
Gui, Add, Edit, vSmallStep gStepSizeChanged w50 ys-3, 1
Gui, Add, Text, xm Section, High Threshold
Gui, Add, Edit, vBigStep gStepSizeChanged w50 ys-3, 100
Gui, Add, CheckBox, xm vCalibrationMode gCalibrationModeChanged, Calibration Mode
Gui, Add, Text, xm Section, Joystick ID
Gui, Add, DDL, vStickID gStickChanged w50 ys-3, 1|2||3|4|5|6|7|8|9|10|11|12|13|14|15|16
Gui, Add, Text, xm Section, Joystick X Axis
Gui, Add, DDL, vStickXAxis gStickChanged w50 ys-3, 1||2|3|4|5|6|7|8
Gui, Add, Text, xm Section, Hotkeys:`nF5: Calibration Mode On/Off`nF6: Set Low Threshhold`nF7: Set High Threshold`nF8: Center`nF9/F10: Small Step Low/High`nF11/F12: Large Step Low/High
Gui, Show


axis_list_ahk := Array("X","Y","Z","R","U","V")

ax := 0

; Create an object from vJoy Interface Class.
vJoyInterface := new CvJoyInterface()

; Was vJoy installed and the DLL Loaded?
if (!vJoyInterface.vJoyEnabled()){
	; Show log of what happened
	Msgbox % vJoyInterface.LoadLibraryLog
	ExitApp
}

myStick := vJoyInterface.Devices[1]

Gosub StepSizeChanged
Gosub StickChanged
Gosub ThreshChanged
Gosub CalibrationModeChanged

starting_up := 0


Loop {
	if (joy_on){
		ax := GetKeyState(joy_x_str, "P")
		; ax is 0-100
		ax *= 327.68
		ax -= 16384
		if (ax > 0){
			sgn := 1
		} else if (ax < 0){
			sgn := -1
		} else {
			sgn := 0
		}
		out := ((abs(ax) * conv_ratio) + LowThresh) * sgn
		
		; move off-center
		out += 16384
		
		;tooltip % "sgn: " sgn "`nratio: " conv_ratio "`nin: " ax "`nout: " out
		myStick.SetAxisByIndex(out, 1)
		
	}
	sleep 10
}

; End Startup Sequence
Return

ThreshChanged:
	;soundbeep
	Gui, Submit, NoHide
	conv_ratio := ( HighThresh - LowThresh) / 16384
	return

CalibrationModeChanged:
	if (!starting_up){
		if (joy_on){
			soundbeep, 1000, 500
		} else {
			soundbeep 500, 500
		}
	}
	Gui, Submit, NoHide
	joy_on := !CalibrationMode
	if (!joy_on){
		GoSub, CenterStick
	}
	return

StickChanged:
	;soundbeep
	Gui, Submit, NoHide
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]
	return
	
StepSizeChanged:
	Gui, Submit, NoHide
	return

set_ratio(){
	global ax, myStick, low_thresh, high_thresh
	global conv_ratio
	
	conv_ratio := ( high_thresh - low_thresh) / 16384
	;msgbox % conv_ratio
}

inc_ang(amt){
	global ax
	global myStick
	ax += amt
	if (ax > 16384){
		ax := 16384
	}
	out := ax + 16384
	myStick.SetAxisByIndex(out, 1)
	show_ang()
}

dec_ang(amt){
	global ax
	global myStick
	ax -= amt
	if (ax < -16384){
		ax := -16384
	}
	out := ax + 16384
	myStick.SetAxisByIndex(out, 1)
	show_ang()
}

show_ang(){
	global ax
	tooltip % ax
}


;F5: Calibrate
f5::
	GuiControl, , CalibrationMode, % !CalibrationMode
	Gosub, CalibrationModeChanged
	return

f5 up::
	return



; F6: Set Low Threshold
F6::
	if (CalibrationMode){
		SoundBeep
		GuiControl,, LowThresh, % abs(ax)
	}
	return


F6 up::
	return


; F7: Set High Threshold
F7::
	if (CalibrationMode){
		SoundBeep
		GuiControl,, HighThresh, % abs(ax)
	}
	return

F7 up::
	return

; F8: Center
F8::
CenterStick:
	if (CalibrationMode){
		ax := 0
		myStick.SetAxisByIndex(16384, 1)
	}
	return

F8 up::
	return

; F9: Small Step Down
F9::
	if (CalibrationMode){
		dec_ang(SmallStep)
	}
	return

F9 up::
	return

; F19: Small Step Up
F10::
	if (CalibrationMode){
		inc_ang(SmallStep)
	}
	Return

F10 up::
	Return

; F11: Big Step Down
F11::
	if (CalibrationMode){
		dec_ang(BigStep)
	}
	return

f11 up::
	return

; F12: Big Step Up
F12::
	if (CalibrationMode){
		inc_ang(BigStep)
	}
	return

GuiClose:
	ExitApp