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
ADHD.config_size(GUI_WIDTH + 20, 300)
ADHD.config_event("option_changed", "option_changed_hook")
ADHD.config_hotkey_add({uiname: "Auto Deadzone", subroutine: "AutoDeadzone"})
ADHD.config_hotkey_add({uiname: "Auto Twist Limit", subroutine: "AutoTwistLimit"})

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
Gui, Add, Text, xm yp+40 Section, Auto Calibrate Start
ADHD.gui_add("Edit", "AutoCalibStart", "w50 h20 ys-3", 0, 0)

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
	Global joy_x_str, joy_y_str
	
	; Excusable globals
	Global conv_ratio_x, conv_ratio_y
	
	; GuiControls
	Global LowThreshX, LowThreshY, HighThreshX, HighThreshY
	
	Loop {
		if (joy_on){
			ax_x := GetKeyState(joy_x_str, "P")
			ax_y := GetKeyState(joy_y_str, "P")
			; ax is 0-100
			ax_x *= 327.68
			ax_y *= 327.68
			
			ax_x -= 16384
			ax_y -= 16384
			
			if (ax_x > 0){
				sgn_x := 1
			} else if (ax_x < 0){
				sgn_x := -1
			} else {
				sgn_x := 0
			}
			
			if (ax_y > 0){
				sgn_y := 1
			} else if (ax_y < 0){
				sgn_y := -1
			} else {
				sgn_y := 0
			}
			out_x := ((abs(ax_x) * conv_ratio_x) + LowThreshX) * sgn_x
			out_y := ((abs(ax_y) * conv_ratio_y) + LowThreshY) * sgn_y
			; move off-center
			out_x += 16384
			out_y += 16384
			;tooltip % "X: " joy_x_str "`nsgn: " sgn_x "`nratio: " conv_ratio_x "`nin: " ax_x "`nout: " out_x "`n`nY: " joy_y_str "`nsgn: " sgn_y "`nratio: " conv_ratio_y "`nin: " ax_y "`nout: " out_y
			myStick.SetAxisByIndex(out_x, 1)
			myStick.SetAxisByIndex(out_y, 2)
		}
		Sleep 20
	}
}

AutoCalibrate(hilo, axis){
	Global mwo_class
	Global joy_on
	Global SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT
	Global SnapshotPreview, Angle, SnapshotDebug, AutoCalibStart, SnapshotDebug
	;Global LowThreshX
	
	Gui, 2:Default

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
	
	max := 16384 - AutoCalibStart
	
	if (hilo){
		; High - twist limits
		if (axis = 1){
			ax := max
		} else {
			ax := max * -1
		}
		SetAxis(ax,axis)

		Sleep 2500
		SoundBeep, 1000, 250

	} else {
		; Low - deadzone
		ax := 0
		SetAxis(ax,axis)

		Send {c}
		Sleep 2500
		SoundBeep, 1000, 250
	}

	base_snap.TakeSnapshot()
	base_snap.TakeSnapshot()
	c1 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
	c1_rgb := diff_snap.ToRGB(c1)
	c2_rgb := {r: 205, g: 177, b: 102}
	tol := 50
	step_size := 1
	x := (width / 2) - (SNAPSHOT_WIDTH / 2)
	y := (height / 2) - (SNAPSHOT_HEIGHT / 2)

	if (hilo){
		if (axis){
			; x
			reticule := x
			reticule_max := SNAPSHOT_WIDTH
		} else {
			reticule := y
			reticule_max := SNAPSHOT_HEIGHT
		}
		if (diff_snap.Compare(c1_rgb, c2_rgb, tol)){
			res := diff_snap.Compare(c1_rgb, c2_rgb, tol)
			while (res && (reticule < reticule_max)){
				reticule += step_size
				;base_snap := new CGdipSnapshot(x,y,SNAPSHOT_WIDTH,SNAPSHOT_HEIGHT)
				;base_snap.Coords := {x: x, y: y, w: SNAPSHOT_WIDTH, h:SNAPSHOT_HEIGHT }
				if (axis == 1){
					base_snap.Coords.x := reticule
				} else {
					base_snap.Coords.y := reticule
				}
				base_snap.TakeSnapshot()
				base_snap.ShowSnapshot(SnapshotPreview)
				
				c1 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
				c1_rgb := base_snap.ToRGB(c1)
				
				res := base_snap.Compare(c1_rgb, c2_rgb, tol)
				GuiControl, , Angle, % round(x)
				GuiControl, , SnapshotDebug, % "r:" c1_rgb.r " g:" c1_rgb.g " b:" c1_rgb.b "`nr:" c2_rgb.r " g:" c2_rgb.g " b:" c2_rgb.b "`nSame? " res
				if (!res){
					reticule -= step_size
					if (axis == 1){
						x := reticule
					} else {
						y := reticule
					}
					diff_snap.Coords := {x: x, y: y, w: SNAPSHOT_WIDTH, h:SNAPSHOT_HEIGHT }
				}
			}
		}
	}

	found := 0


	Loop % max {
		if (!WinActive("ahk_class " mwo_class)){
			soundbeep, 500
			return
		}
		if (hilo){
			ax := max - A_Index
		} else {
			ax := AutoCalibStart + A_Index
		}
		SetAxis(ax, axis)
		
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
	}

	if (found){
		if (hilo){
			if (axis == 1){
				GuiControl, , HighThreshX, % ax
			} else {
				GuiControl, , HighThreshY, % ax
			}
		} else {
			if (axis == 1){
				GuiControl, , LowThreshX, % ax
			} else {
				GuiControl, , LowThreshY, % ax
			}
		}
		Soundbeep
	}
	
	Gui, 2:Hide
	joy_on := 1
	return

}

option_changed_hook(){
	Global conv_ratio_x, conv_ratio_y
	Global LowThreshX, HighThreshX 
	Global LowThreshY, HighThreshY
	Global StickID, StickXAxis, StickYAxis
	Global axis_list_ahk
	Global joy_x_str, joy_y_str
	
	conv_ratio_x := ( HighThreshX - LowThreshX) / 16384
	conv_ratio_y := ( HighThreshY - LowThreshY) / 16384
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]
	joy_y_str := StickID "Joy" axis_list_ahk[StickYAxis]

}

SetAxis(val, axis){
	global myStick
	myStick.SetAxisByIndex(val + 16384, axis)
}

AutoDeadzone:
	;AutoCalibrate(0,1)
	AutoCalibrate(0,2)
	return

AutoTwistLimit:
	;AutoCalibrate(1,1)
	AutoCalibrate(1,2)
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