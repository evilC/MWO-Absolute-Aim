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
SetKeyDelay, 0, 50	; MWO does not recognize keys held for <50ms
#include <CvJoyInterface>
#include <CGdipSnapshot>

ADHD := new ADHDLib()

GUI_WIDTH := 200
SNAPSHOT_WIDTH := 100
SNAPSHOT_HEIGHT := 100

mwo_class := "CryENGINE"
starting_up := 1

default_low_thresh := 2460
default_high_thresh := 12314
;default_low_thresh := 0
;default_high_thresh := 0

Gui, 1:New
Gui, 1:Default
Gui, 1:Add, Text, xm ym Section, Low Threshold
Gui, 1:Add, Edit, vLowThresh gThreshChanged w50 ys-3, % default_low_thresh
Gui, 1:Add, Text, xm Section, High Threshold
Gui, 1:Add, Edit, vHighThresh gThreshChanged w50 ys-3, % default_high_thresh
;Gui, 1:Add, Text, xm Section, Small Step Size
;Gui, 1:Add, Edit, vSmallStep gStepSizeChanged w50 ys-3, 1
;Gui, 1:Add, Text, xm Section, High Threshold
;Gui, 1:Add, Edit, vBigStep gStepSizeChanged w50 ys-3, 100
;Gui, 1:Add, CheckBox, xm vCalibrationMode gCalibrationModeChanged, Calibration Mode
Gui, 1:Add, Text, xm Section, Joystick ID
Gui, 1:Add, DDL, vStickID gStickChanged w50 ys-3, 1|2||3|4|5|6|7|8|9|10|11|12|13|14|15|16
Gui, 1:Add, Text, xm Section, Joystick X Axis
Gui, 1:Add, DDL, vStickXAxis gStickChanged w50 ys-3, 1||2|3|4|5|6|7|8
;Gui, 1:Add, Text, xm Section, Hotkeys:`nF5: Calibration Mode On/Off`nF6: Set Low Threshhold`nF7: Set High Threshold`nF8: Center`nF9/F10: Small Step Low/High`nF11/F12: Large Step Low/High
/*
Gui, 1:Add, Text, xm Section, Hotkeys:`nF11: Auto-Calibrate Deadzone`nF12: Auto-Calibrate twist limits
Gui, 1:Add, GroupBox, xm Section w%GUI_WIDTH% h200, Auto-Calibrate
Gui, 1:Add, Button, xs+10 ys+20 gAutoDeadzone, Auto Deadzone
*/
Gui, 1:Show, % "w" GUI_WIDTH + 20

Gui, 2:New
Gui, 2:Add, Text, 0xE xm Section w%SNAPSHOT_WIDTH% h%SNAPSHOT_HEIGHT% hwndSnapshotPreview
Gui, 2:Add, Edit, xm Section w%SNAPSHOT_WIDTH% center disabled vAngle
Gui, 2:Add, Text, xm Section w%SNAPSHOT_WIDTH% center R3 vSnapshotDebug


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

MainLoop()

; End Startup Sequence
Return

MainLoop(){
	; Helper Objects
	Global myStick
	; Var to stop loop doing anything
	Global joy_on
	
	; Nasty globals - remove
	Global ax
	Global joy_x_str
	
	; Excusable globals
	Global conv_ratio
	
	; GuiControls
	Global LowThresh
	
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
			;tooltip % "Joy: " joy_x_str "`nsgn: " sgn "`nratio: " conv_ratio "`nin: " ax "`nout: " out
			myStick.SetAxisByIndex(out, 1)
		}
		Sleep 20
	}
}

AutoDeadzone(){
	Global mwo_class
	Global joy_on
	Global SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT
	Global SnapshotPreview, Angle, SnapshotDebug, LowThresh
	
	WinGet, mwo_hwnd, ID, ahk_class %mwo_class%
	if (!mwo_hwnd){
		msgbox MWO is not running!
		return
	}

	joy_on := 0
	; Find resolution
	WinGetPos , X, Y, Width, Height, ahk_class %mwo_class%

	base_snap := ""
	diff_snap := ""
	; Define shapshot location - center of screen
	base_snap := new CGdipSnapshot((width / 2) - (SNAPSHOT_WIDTH / 2),(height / 2) - (SNAPSHOT_HEIGHT / 2),SNAPSHOT_WIDTH,SNAPSHOT_HEIGHT)
	diff_snap := new CGdipSnapshot((width / 2) - (SNAPSHOT_WIDTH / 2),(height / 2) - (SNAPSHOT_HEIGHT / 2),SNAPSHOT_WIDTH,SNAPSHOT_HEIGHT)

	x := (x + width) - (SNAPSHOT_WIDTH + 40)
	y := (y + height) - (SNAPSHOT_HEIGHT + 200)
	
	; Show preview window at bottom right of screen
	Gui, 2:+AlwaysOnTop
	Gui, 2:Show, x%x% y%y%
	WinActivate, ahk_class %mwo_class%
	
	; Do the calibration
	SoundBeep, 500, 250
	
	center_stick()
	Send {c}
	Sleep 2000
	SoundBeep, 1000, 250

	base_snap.TakeSnapshot()
	base_snap.TakeSnapshot()
	c1 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
	c1_rgb := diff_snap.ToRGB(c1)
	
	ax := 0
	Loop 16384 {
		ax := A_Index
		SetAxis(ax, 1)
		;inc_ang(1)
		;Sleep 10
		
		diff_snap.TakeSnapshot()
		diff_snap.ShowSnapshot(SnapshotPreview)
		
		c2 := diff_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
		c2_rgb := diff_snap.ToRGB(c2)
		
		res := diff_snap.Compare(diff_snap.ToRGB(c1), diff_snap.ToRGB(c2), 50)
		
		Gui, 2:Default
		GuiControl, , Angle, % ax
		GuiControl, , SnapshotDebug, % "r:" c1_rgb.r " g:" c1_rgb.g " b:" c1_rgb.b "`nr:" c2_rgb.r " g:" c2_rgb.g " b:" c2_rgb.b "`nSame? " res
		;GuiControl, +c%c2%, BaseCol
		;GuiControl, , BaseCol, #
		Gui, 1:Default
		
		;tooltip % ax " - " res

		if (!res){
			break
		}

		;Sleep 10
	}
	
	if (ax){
		GuiControl, , LowThresh, % ax
		Gosub, ThreshChanged
		Soundbeep
	}
	
	Gui, 2:Hide
	joy_on := 1
	return

}

SetAxis(val, axis){
	global myStick
	myStick.SetAxisByIndex(val + 16384, axis)
}

AutoDeadzone:
	AutoDeadzone()
	return

ThreshChanged:
	;soundbeep
	Gui, 1:Submit, NoHide
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
	Gui, 1:Submit, NoHide
	joy_on := !CalibrationMode
	if (!joy_on){
		GoSub, CenterStick
	}
	return

StickChanged:
	;soundbeep
	Gui, 1:Submit, NoHide
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]
	return
	
StepSizeChanged:
	Gui, 1:Submit, NoHide
	return

set_ratio(){
	global ax, myStick, low_thresh, high_thresh
	global conv_ratio
	
	conv_ratio := ( high_thresh - low_thresh) / 16384
	;msgbox % conv_ratio
}

center_stick(){
	global CalibrationMode, ax, myStick
	if (CalibrationMode){
		ax := 0
		myStick.SetAxisByIndex(16384, 1)
	}
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
	;tooltip % ax
}

;F5: Calibrate
~f5::
	AutoDeadzone()
	return

~f5 up::
	return


/*
;F5: Calibrate
~f5::
	GuiControl, , CalibrationMode, % !CalibrationMode
	Gosub, CalibrationModeChanged
	return

~f5 up::
	return



; F6: Set Low Threshold
~F6::
	if (CalibrationMode){
		SoundBeep
		GuiControl,, LowThresh, % abs(ax)
	}
	return


~F6 up::
	return


; F7: Set High Threshold
~F7::
	if (CalibrationMode){
		SoundBeep
		GuiControl,, HighThresh, % abs(ax)
	}
	return

~F7 up::
	return

; F8: Center
~F8::
*/
CenterStick:
	center_stick()
	return

~F8 up::
	return

/*
; F9: Small Step Down
~F9::
	if (CalibrationMode){
		dec_ang(SmallStep)
	}
	return

~F9 up::
	return

; F19: Small Step Up
~F10::
	if (CalibrationMode){
		inc_ang(SmallStep)
	}
	Return

~F10 up::
	Return

; F11: Big Step Down
~F11::
	if (CalibrationMode){
		dec_ang(BigStep)
	}
	return

~f11 up::
	return

; F12: Big Step Up
~F12::
	if (CalibrationMode){
		inc_ang(BigStep)
	}
	return
*/

#include <ADHDlib>