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
   ADHD from https://github.com/evilC/ADHD-AHK-Dynamic-Hotkeys-for-Dummies

MWO Setup:
	One Time
	========
	1) Set cl_joystick_absolute_inputs=1 is required in ?user.cfg? - i need mine in system.cfg
	2) In the CONTROLLER menu, the following sliders MUST be at thier DEFAULT values!
		X-AXIS SENSITIVITY, Y-AXIS SENSITIVITY and DEADZONE
		DO NOT attempt to set deadzone to 0! It goes mental!
	3) Bind vJoy axis 1 to TORSO TWIST in MWO:
		Start the script, go into the BINDINGS tab and bind a KEYBOARD KEY to "MWO Bind X" and "MWO Bind Y".
		Double click TORSO TWIST in the JOYSTICK column
		Hit the key you bound to "MWO Bind X"
		This moves the virtual stick without you having to move the physical stick...
		... so we can be sure MWO binds to the virtual stick.
		Now repeat for the PITCH setting.
	3) Configure inputs
		In the script, select the ID and axis number of the stick you wish to use as input.
		
	Per-Mech etc
	============
	Low Threshold (Deadzone) is probably the same for all mechs.
	However, the High Threshold may well vary from mech to mech.
	You can use the PROFIlES tab to add profiles if you need different setups for different situations.
	
	Calibration process:
	1) Make sure MWO is running in FULL WINDOW mode, and at the best resolution you possibly can (Lower resolutions = bad pixel detection)
	Make sure you bind a key on the BINDINGS tab to AUTO DEADZONE and AUTO TWIST LIMIT
	
	2) Make sure ARM LOCK is set to OFF! Even in a mech with no arm movement in any direction!
	AUTO DEADZONE will set the lower threshold, AUTO TWIST LIMIT will set the high threshold.
	
	3) hit the hotkey for AUTO DEADZONE or AUTO TWIST LIMIT and sit back.
		A window will appear at the bottom right of your screen with a snapshot view of what the macro is looking at - you can watch it work ;)
		DO NOT touch the mouse - this will abort.
	
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
ADHD.config_about({name: "MWO Absolute Aim", version: "1.0", author: "evilC", link: "<a href=""https://github.com/evilC/MWO-Absolute-Aim"">Homepage</a> / <a href=""http://mwomercs.com/forums/topic/186302"">Forum Thread</a>"})

ADHD.config_size(GUI_WIDTH + 20, 240)
ADHD.config_event("option_changed", "option_changed_hook")
ADHD.config_hotkey_add({uiname: "Auto Deadzone", subroutine: "AutoDeadzone"})
ADHD.config_hotkey_add({uiname: "Auto Twist Limit", subroutine: "AutoTwistLimit"})
ADHD.config_hotkey_add({uiname: "MWO Bind X", subroutine: "MWOBindX"})
ADHD.config_hotkey_add({uiname: "MWO Bind Y", subroutine: "MWOBindY"})

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

Gui, Add, Text, xm yp+40 Section, Joystick ID
ADHD.gui_add("DropDownList", "StickID", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16", "2")

Gui, Add, Text, ys Section, X Axis
ADHD.gui_add("DropDownList", "StickXAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "1")
Gui, Add, Text, ys Section, Y Axis
ADHD.gui_add("DropDownList", "StickYAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "2")
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
		
		diff_snap.TakeSnapshot()
		diff_snap.ShowSnapshot(SnapshotPreview)
		
		c2 := diff_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
		c2_rgb := diff_snap.ToRGB(c2)
		
		res := diff_snap.Compare(diff_snap.ToRGB(c1), diff_snap.ToRGB(c2), 50)
		
		Gui, 2:Default
		GuiControl, , Angle, % ax
		GuiControl, , SnapshotDebug, % "r:" c1_rgb.r " g:" c1_rgb.g " b:" c1_rgb.b "`nr:" c2_rgb.r " g:" c2_rgb.g " b:" c2_rgb.b "`nSame? " res
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

MWOBindX:
	SetAxis(16384,1)
	Sleep 250
	SetAxis(0,1)
	return

MWOBindY:
	SetAxis(16384,2)
	Sleep 250
	SetAxis(0,2)
	return

AutoDeadzone:
	;AutoCalibrate(0,1)
	AutoCalibrate(0,2)
	return

AutoTwistLimit:
	;AutoCalibrate(1,1)
	AutoCalibrate(1,2)
	return

#include <ADHDlib>