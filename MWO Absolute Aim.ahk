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

GUI_WIDTH := 350
SNAPSHOT_WIDTH := 100
SNAPSHOT_HEIGHT := 100

mwo_class := "CryENGINE"
starting_up := 1

ADHD := new ADHDLib()
ADHD.config_size(GUI_WIDTH + 20, 200)
ADHD.config_event("option_changed", "option_changed_hook")
ADHD.config_hotkey_add({uiname: "Auto Deadzone", subroutine: "AutoDeadzone"})

axis_list_ahk := Array("X","Y","Z","R","U","V")

default_low_thresh := 2460
default_high_thresh := 12314
;default_low_thresh := 0
;default_high_thresh := 0

ADHD.init()
ADHD.create_gui()

;Gui, 1:New
;Gui, 1:Default
Gui, Tab, 1
Gui, Add, GroupBox, xm y40 w%GUI_WIDTH% R1, X Axis
Gui, Add, Text, xm+10 yp+15 Section, Low Threshold
ADHD.gui_add("Edit", "LowThreshX", "w50 h20 ys-3", 1, 1)
Gui, Add, Text, ys Section, High Threshold
ADHD.gui_add("Edit", "HighThreshX", "w50 h20 ys-3", 16384, 16384)

Gui, Add, GroupBox, xm yp+30 w%GUI_WIDTH% R1, Y Axis
Gui, Add, Text, xm+10 yp+15 Section, Low Threshold
ADHD.gui_add("Edit", "LowThreshY", "w50 h20 ys-3", 1, 1)
Gui, Add, Text, ys Section, High Threshold
ADHD.gui_add("Edit", "HighThreshY", "w50 h20 ys-3", 16384, 16384)

;Gui, 1:Add, Text, xm Section, Small Step Size
;Gui, 1:Add, Edit, vSmallStep gStepSizeChanged w50 ys-3, 1
;Gui, 1:Add, Text, xm Section, High Threshold
;Gui, 1:Add, Edit, vBigStep gStepSizeChanged w50 ys-3, 100
;Gui, 1:Add, CheckBox, xm vCalibrationMode gCalibrationModeChanged, Calibration Mode
Gui, Add, Text, xm yp+40 Section, Joystick ID
;Gui, Add, DDL, vStickID gStickChanged w50 ys-3, 1|2||3|4|5|6|7|8|9|10|11|12|13|14|15|16
ADHD.gui_add("DropDownList", "StickID", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16", "2")

Gui, Add, Text, ys Section, X Axis
;Gui, Add, DDL, vStickXAxis gStickChanged w50 ys-3, 1||2|3|4|5|6|7|8
ADHD.gui_add("DropDownList", "StickXAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "1")
Gui, Add, Text, ys Section, Y Axis
;Gui, Add, DDL, vStickYAxis gStickChanged w50 ys-3, 1|2||3|4|5|6|7|8
ADHD.gui_add("DropDownList", "StickYAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "2")
;Gui, 1:Add, Text, xm Section, Hotkeys:`nF5: Calibration Mode On/Off`nF6: Set Low Threshhold`nF7: Set High Threshold`nF8: Center`nF9/F10: Small Step Low/High`nF11/F12: Large Step Low/High
/*
Gui, 1:Add, Text, xm Section, Hotkeys:`nF11: Auto-Calibrate Deadzone`nF12: Auto-Calibrate twist limits
Gui, 1:Add, GroupBox, xm Section w%GUI_WIDTH% h200, Auto-Calibrate
Gui, 1:Add, Button, xs+10 ys+20 gAutoDeadzone, Auto Deadzone
*/
;Gui, 1:Show, % "w" GUI_WIDTH + 20

ADHD.finish_startup()

Gui, 2:New
Gui, 2:Add, Text, 0xE xm Section w%SNAPSHOT_WIDTH% h%SNAPSHOT_HEIGHT% hwndSnapshotPreview
Gui, 2:Add, Edit, xm Section w%SNAPSHOT_WIDTH% center disabled vAngle
Gui, 2:Add, Text, xm Section w%SNAPSHOT_WIDTH% center R3 vSnapshotDebug

ax := 0
joy_on := 1

; Create an object from vJoy Interface Class.
vJoyInterface := new CvJoyInterface()

; Was vJoy installed and the DLL Loaded?
if (!vJoyInterface.vJoyEnabled()){
	; Show log of what happened
	Msgbox % vJoyInterface.LoadLibraryLog
	ExitApp
}

myStick := vJoyInterface.Devices[1]

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
	Global LowThreshX
	
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
			out := ((abs(ax) * conv_ratio) + LowThreshX) * sgn
			
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
	Global SnapshotPreview, Angle, SnapshotDebug, LowThreshX
	
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
	
	ax := 0
	SetAxis(ax,1)

	Send {c}
	Sleep 2500
	SoundBeep, 1000, 250

	base_snap.TakeSnapshot()
	base_snap.TakeSnapshot()
	c1 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
	c1_rgb := diff_snap.ToRGB(c1)
	
	found := 0
	
	Loop 16384 {
		if (!WinActive("ahk_class " mwo_class)){
			soundbeep, 500
			return
		}
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
			found := 1
			break
		}

		;Sleep 10
	}
	
	if (found){
		GuiControl, , LowThreshX, % ax
		Soundbeep
	}
	
	Gui, 2:Hide
	joy_on := 1
	return

}

option_changed_hook(){
	Global conv_ratio
	Global LowThreshX, HighThreshX 
	Global LowThreshY, HighThreshXY
	Global StickID, StickXAxis, StickYAxis
	Global axis_list_ahk
	Global joy_x_str
	
	conv_ratio := ( HighThreshX - LowThreshX) / 16384
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]

}

SetAxis(val, axis){
	global myStick
	myStick.SetAxisByIndex(val + 16384, axis)
}

AutoDeadzone:
	AutoDeadzone()
	return

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

#include <ADHDlib>