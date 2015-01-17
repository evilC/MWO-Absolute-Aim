/*
MWO Absolute stick aiming fix

Proof-of-concept

Requirements
============
Quick Start:
   Install vJoy virtual joystick driver from http://vjoystick.sourceforge.net
   Use the EXE file in the zip

For coders:
	Also Download:
	AHK from http://ahkscript.org. !!! NOT autohotkey.com !!!
	AHK-CvJoyInterface.ahk from here: https://github.com/evilC/AHK-CvJoyInterface
	ADHD from https://github.com/evilC/ADHD-AHK-Dynamic-Hotkeys-for-Dummies
	Then use the AHK version from the zip

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

global GUI_MARGIN := 15
global DOUBLE_GUI_MARGIN := 30
global GUI_WIDTH := 350
global SNAPSHOT_WIDTH := 100
global SNAPSHOT_HEIGHT := 100
global SNAPSHOT_GUI_WIDTH := 200
global SNAPSHOT_GUI_HEIGHT := 200

mwo_class := "CryENGINE"
starting_up := 1

ADHD := new ADHDLib()
ADHD.config_about({name: "MWO Absolute Aim", version: "1.0", author: "evilC", link: "<a href=""https://github.com/evilC/MWO-Absolute-Aim"">Homepage</a> / <a href=""http://mwomercs.com/forums/topic/186302"">Forum Thread</a>"})

ADHD.config_size(GUI_WIDTH + 20, 300)
ADHD.config_event("option_changed", "option_changed_hook")
ADHD.config_hotkey_add({uiname: "Auto Deadzone", subroutine: "AutoDeadzone"})
ADHD.config_hotkey_add({uiname: "Auto Twist Limit", subroutine: "AutoTwistLimit"})
ADHD.config_hotkey_add({uiname: "MWO Bind X", subroutine: "MWOBindX"})
ADHD.config_hotkey_add({uiname: "MWO Bind Y", subroutine: "MWOBindY"})

axis_list_ahk := Array("X","Y","Z","R","U","V")
axis_to_index := {x: 1, y: 2}
index_to_axis := ["x","y"]

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
Gui, Add, Text, xm yp+40 Section, Auto Calib Start Low
ADHD.gui_add("Edit", "AutoCalibStartDZ", "w40 h20 ys-3", 0, 0)
Gui, Add, Text, xm yp+40 Section, Auto Calib Start High (X)
ADHD.gui_add("Edit", "AutoCalibStartTLX", "w40 h20 ys-3", 0, 16384)
Gui, Add, Text, ys Section, Auto Calib Start High (Y)
ADHD.gui_add("Edit", "AutoCalibStartTLY", "w40 h20 ys-3", 0, 16384)

ADHD.finish_startup()

Gui, 2:New
Gui, 2:Add, Text, xm Section w%SNAPSHOT_GUI_WIDTH% center, Snapshot
tmpx := GUI_MARGIN + ((SNAPSHOT_Gui_WIDTH - SNAPSHOT_WIDTH) / 2)
Gui, 2:Add, Text, 0xE x%tmpx% Section w%SNAPSHOT_WIDTH% h%SNAPSHOT_HEIGHT% hwndSnapshotPreview
Gui, 2:Add, Edit, xm Section w%SNAPSHOT_GUI_WIDTH% center disabled vAngle
Gui, 2:Add, Text, xm Section w%SNAPSHOT_GUI_WIDTH% R5 vSnapshotDebug

Gui, 2:Show, % "w" SNAPSHOT_GUI_WIDTH + DOUBLE_GUI_MARGIN " h" SNAPSHOT_GUI_HEIGHT + DOUBLE_GUI_MARGIN
Gui, 2:Hide
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

ActivateCalibMode(){
	Global mwo_class
	Global joy_on
	
	WinGet, mwo_hwnd, ID, ahk_class %mwo_class%
	if (!mwo_hwnd){
		msgbox MWO is not running!
		return 0
	}

	joy_on := 0

	WinActivate, ahk_class %mwo_class%
	Sleep 1000

	; Find resolution
	WinGetPos , X, Y, Width, Height, ahk_class %mwo_class%
	x := (x + width) - (SNAPSHOT_GUI_WIDTH + DOUBLE_GUI_MARGIN + 10)
	y := (y + height) - (SNAPSHOT_GUI_HEIGHT + DOUBLE_GUI_MARGIN + 80)

	
	; Show preview window at bottom right of screen
	Gui, 2:+AlwaysOnTop
	Gui, 2:Show, x%x% y%y%

	WinActivate, ahk_class %mwo_class%
	return 1
}

DeActivateCalibMode(){
	Global joy_on
	Gui, 2:Hide
	;joy_on := 1
	
}

AutoCalibrate(hilo, axis){
	Global mwo_class
	Global joy_on
	Global SnapshotPreview, Angle, SnapshotDebug, AutoCalibStartDZ, AutoCalibStartTLX, AutoCalibStartTLY, SnapshotDebug
	Global axis_to_index, index_to_axis
	Global auto_calib_start
	
	static hud_dim_rgb := {r: 173, g: 149, b: 87}
	static hud_bright_rgb := {r: 242, g: 178, b: 67}
	static big_move_sleep := 3000
	static small_move_sleep := 10
	static wait_center := 3000
	static wait_timeout := 5000
	
	static main_tol := 100

	if (!WinActive("ahk_class " mwo_class)){
		soundbeep, 500
		return
	}
	
	Gui, 2:Default
	; Dirty hack - sometimes calib window disappears
	;Gui, 2:Show
	;WinActivate, ahk_class %mwo_class%
	;Sleep, 1000
	
	; Get screen size etc
	WinGetPos , game_x, game_y, game_width, game_height, ahk_class %mwo_class%
		
	; Terminology:
	; O : The Arm crosshair (The one shaped like a O)
	; + : The Torso crosshair (The one shaped like a +)
	; Min def: Minimum deflection. Towards the center.
	; Max def: Maximum deflection. Towards the right if X, Towards up if Y. (MUST be UP! Map covers arm reticule line if you use bottom!)
	
	; Procedure:
	
	; Find Low Threshold (Deadzone)
	; 1) Set stick to min def.
	; 2) Look for the pip / line at the center of the + / o
	; 3) 

	; Find High Threshold (Twist Limit)
	; This is way more complicated, as we have to detect arm motion also, and support lateral / vertical only arm motion mechs.
	; Procedure is:
	; 1) Move the stick to max def
	;    if we have arm motion in that direction, we need to find the HUD coloured pixel at the center of the O
	;    If we do not have arm motion in that direction, we need to find the HUD coloured pixel on the max def edge of the +
	; 2) Once we have that pixel, move the stick back towards min def until we see the pixel go from HUD colour to something else. 

	if (hilo == "l"){
		; Find Low Threshold (Deadzone)
		; 1) Set stick to min def.
		; 2) find the HUD coloured pixel on the max def edge of the +
		; 3) 
		
		GuiControl, , Angle, % "Setting up..."
		Soundbeep, 500
		
		SetAxisByName(0,"x")
		SetAxisByName(0,"y")
		;Sleep % big_move_sleep
		
		base_snap := new CGdipSnapshot((game_width / 2) - (SNAPSHOT_WIDTH / 2), (game_height / 2) - (SNAPSHOT_HEIGHT / 2), SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT)
		base_snap.TakeSnapshot()
		base_snap.ShowSnapshot(SnapshotPreview)
		base_snap.SaveSnapshot("base.png")
		
		; Wait for pip to appear at center
		
		center_rgb := GetCenterRGB(base_snap)
		pixels_match := base_snap.Compare(hud_dim_rgb, center_rgb, main_tol)
		wait_start := A_TickCount
		max_wait := wait_center + wait_timeout
		GuiControl, , Angle, % "Waiting for view to settle"
		while (!pixels_match){
			if (!WinActive("ahk_class " mwo_class)){
				soundbeep, 500
				return 0
			}
			Sleep 100
			if (A_TickCount - wait_start > wait_center){
				GuiControl, , Angle, % "Waiting for center PIP"
				base_snap.TakeSnapshot()
				base_snap.ShowSnapshot(SnapshotPreview)
				center_rgb := GetCenterRGB(base_snap)
				pixels_match := base_snap.Compare(hud_dim_rgb, center_rgb, main_tol)
				GuiControl, , SnapshotDebug, % "HUD = r:" hud_dim_rgb.r " g:" hud_dim_rgb.g " b:" hud_dim_rgb.b "`nCurrent = r:" center_rgb.r " g:" center_rgb.g " b:" center_rgb.b "`nSame? " pixels_match
			}
			
			if (A_TickCount - wait_start > max_wait){
				msgbox Waited too long, exiting...
				return
			}
		}
		
		SoundBeep, 1000

		; Pip appeared, start to move stick.
		stick_val := AutoCalibStartDZ
		
		Loop % 16384 - AutoCalibStartDZ {
			if (!WinActive("ahk_class " mwo_class)){
				soundbeep, 500
				return 0
			}

			SetAxisByName(stick_val,axis)
			;Sleep % small_move_sleep
			base_snap.TakeSnapshot()
			base_snap.ShowSnapshot(SnapshotPreview)
			center_rgb := GetCenterRGB(base_snap)
			pixels_match := base_snap.Compare(hud_dim_rgb, center_rgb, main_tol)
			GuiControl, , Angle, % "Moving Stick: " round(stick_val)
			GuiControl, , SnapshotDebug, % "HUD = r:" hud_dim_rgb.r " g:" hud_dim_rgb.g " b:" hud_dim_rgb.b "`nCurrent = r:" center_rgb.r " g:" center_rgb.g " b:" center_rgb.b "`nSame? " pixels_match
			if (!pixels_match){
				;msgbox % "Thresh Found: " stick_val
				break
			}
			stick_val++
			; Safety
			if (stick_val > 16384){
				msgbox Stick went above 16384 error
				break
			}
		}
		
	
	} else {
		; Find High Threshold (Twist Limit)
		; This is way more complicated, as we have to detect arm motion also, and support lateral / vertical only arm motion mechs.
		; Procedure is:
		; 1) Move the stick to max def
		;    if we have arm motion in that direction, we need to find the HUD coloured pixel at the center of the O
		;    If we do not have arm motion in that direction, we need to find the HUD coloured pixel on the max def edge of the +
		; 2) Once we have that pixel, move the stick back towards min def until we see the pixel go from HUD colour to something else. 
	}
	
	return 1
	
}

GetCenterRGB(var){
	return var.ToRGB(var.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2))
}

/*
AutoCalibrate(hilo, axis){
	Global mwo_class
	Global joy_on
	Global SNAPSHOT_WIDTH, SNAPSHOT_HEIGHT
	Global SnapshotPreview, Angle, SnapshotDebug, AutoCalibStartDZ, AutoCalibStartTLX, AutoCalibStartTLY, SnapshotDebug
	;Global LowThreshX

	main_tol := 10
	reticule_tol := 50
	reticule_rewind_tol := 20
	
	hud_dim_col := {r: 197, g: 167, b: 91}
	hud_bright_col := {r: 242, g: 178, b: 67}

	if (!WinActive("ahk_class " mwo_class)){
		soundbeep, 500
		return
	}

	
	move_sleep := 3000
	Gui, 2:Default

	; Find resolution
	WinGetPos , X, Y, Width, Height, ahk_class %mwo_class%
	base_snap := ""
	diff_snap := ""
	; Define shapshot location - center of screen
	base_snap := new CGdipSnapshot((width / 2) - (SNAPSHOT_WIDTH / 2),(height / 2) - (SNAPSHOT_HEIGHT / 2),SNAPSHOT_WIDTH,SNAPSHOT_HEIGHT)
	diff_snap := new CGdipSnapshot((width / 2) - (SNAPSHOT_WIDTH / 2),(height / 2) - (SNAPSHOT_HEIGHT / 2),SNAPSHOT_WIDTH,SNAPSHOT_HEIGHT)

	;x := (x + width) - (SNAPSHOT_WIDTH + 40)
	;y := (y + height) - (SNAPSHOT_HEIGHT + 200)
	
	; Do the calibration
	SoundBeep, 500, 250
	
	if (hilo){
		if (axis = 1){
			max := AutoCalibStartTLX
		} else {
			max := AutoCalibStartTLY
		}
	} else {
		max := 16384 - AutoCalibStartDZ
	}
	
	; Set initial view
	if (hilo){
		; High - twist limits
		if (axis = 1){
			ax := max
			SetAxis(0,2)
		} else {
			ax := max * -1
			SetAxis(0,1)
		}
		SetAxis(ax,axis)

		Sleep % move_sleep
		SoundBeep, 1000, 250

	} else {
		; Low - deadzone
		ax := 0
		if (axis = 1){
			SetAxis(0,2)
		} else {
			SetAxis(0,1)
		}
		SetAxis(ax,axis)
		
		Send {c}
		Sleep % move_sleep
		SoundBeep, 1000, 250
	}

	;base_snap.TakeSnapshot()
	base_snap.TakeSnapshot()
	base_snap.SaveSnapshot("base.png")
	c1 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
	c1_rgb := diff_snap.ToRGB(c1)
	
	;msgbox % "r: " c1_rgb.r "/ g: " c1_rgb.g " / b: " c1_rgb.b
		
	;c2_rgb := {r: 205, g: 177, b: 102}
	c2_rgb := {r: 197, g: 167, b: 91}
	
	;c1_rgb := c2_rgb
	x := (width / 2) - (SNAPSHOT_WIDTH / 2)
	y := (height / 2) - (SNAPSHOT_HEIGHT / 2)

	if (hilo && (axis = 2)){
			step_size := -1
	} else {
		step_size := 1
	}

	; When finding the high threshold, we have to find the end of the arm reticule (the 'O' not the '+') ...
	if (hilo){
		; c2 is the colour of the current pixel being examined
		c2 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
		c2_rgb := base_snap.ToRGB(c2)

		if (axis = 1){
			; x
			reticule := base_snap.Coords.x
			reticule_max := width
		} else {
			; y
			reticule := base_snap.Coords.y
			reticule_max := height
			;msgbox % reticule
		}
		res := ( diff_snap.Compare(hud_dim_col, c2_rgb, reticule_tol) || diff_snap.Compare(hud_bright_col, c2_rgb, reticule_tol))
		while (res && (reticule < reticule_max)){
			if (!WinActive("ahk_class " mwo_class)){
				soundbeep, 500
				return
			}
			reticule += step_size
			if (axis == 1){
				base_snap.Coords.x := reticule
			} else {
				;msgbox % "S: " base_snap.Coords.x
				base_snap.Coords.y := reticule
			}
			base_snap.TakeSnapshot()
			base_snap.ShowSnapshot(SnapshotPreview)
			
			; c2 is the colour of the current pixel being examined
			c2 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
			c2_rgb := base_snap.ToRGB(c2)
			
			; make sure res is calculated the same way here as in the start of the while()

			res := ( diff_snap.Compare(hud_dim_col, c2_rgb, reticule_tol) || diff_snap.Compare(hud_bright_col, c2_rgb, reticule_tol))
			GuiControl, , Angle, % "Find reticule: " round(reticule)
			GuiControl, , SnapshotDebug, % "HUD: " hud_dim_col.r "/" hud_dim_col.g "/" hud_dim_col.b "`nCurr: " c2_rgb.r "/" c2_rgb.g "/" c2_rgb.b "`nSame? " res
			if (!res){
				; Rewind the snapshot position to the end of the last hud_dim_col - timer in testing grounds may cover reticule if at top of screen
				; Hmm - only need if in testing grounds for a long time?
				
				base_snap.TakeSnapshot()
				base_snap.ShowSnapshot(SnapshotPreview)
				base_snap.SaveSnapshot("ReticuleEndBefore.png")

				while (!diff_snap.Compare(hud_dim_col, c2_rgb, reticule_rewind_tol)){
					;msgbox % "reticule: " reticule ", one less: " reticule - step_size
					reticule -= step_size
					
					if (axis = 1){
						base_snap.Coords.x := reticule
					} else {
						base_snap.Coords.y := reticule
					}
					base_snap.TakeSnapshot()
					base_snap.ShowSnapshot(SnapshotPreview)
					c2 := base_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
					c2_rgb := base_snap.ToRGB(c2)
				}

				base_snap.SaveSnapshot("ReticuleEndAfter.png")

				if (axis == 1){
					x := reticule
					base_snap.Coords.x := reticule
				} else {
					y := reticule
					base_snap.Coords.y := reticule
				}
			}
			; Set position of snapshot so next part can work
			diff_snap.Coords := base_snap.Coords
			c1_rgb := c2_rgb
		}
	}

	; c1_rgb should now hold rgb values for the center of the reticule - let's see if we can make it change...
	found := 0
	Loop % max {
		if (!WinActive("ahk_class " mwo_class)){
			soundbeep, 500
			return
		}
		if (hilo){
			if (axis = 1){
				ax := AutoCalibStartTLX - A_Index
				SetAxis(ax, axis)
			} else {
				ax := AutoCalibStartTLY - A_Index
				SetAxis(ax * -1, axis)
			}
			; in Y mode, we want to use up to calibrate, as if we use down, the map covers the reticule
		} else {
			ax := AutoCalibStartDZ + A_Index
			SetAxis(ax, axis)
		}
		
		diff_snap.TakeSnapshot()
		diff_snap.ShowSnapshot(SnapshotPreview)
		
		c2 := diff_snap.SnapshotGetColor(SNAPSHOT_WIDTH/2, SNAPSHOT_HEIGHT/2)
		c2_rgb := diff_snap.ToRGB(c2)
		
		res := diff_snap.Compare(c1_rgb,c2_rgb, main_tol)
		
		Gui, 2:Default
		GuiControl, , Angle, % ax
		GuiControl, , SnapshotDebug, % "Base: " c1_rgb.r "/" c1_rgb.g "/" c1_rgb.b "`nCurr: " c2_rgb.r "/" c2_rgb.g "/" c2_rgb.b "`nSame? " res
		Gui, 1:Default
		
		;tooltip % ax " - " res

		if (!res){
			found := 1
			break
		}
	}

	if (found){
		msgbox, 4,, % "A new value was found of " ax ", Do you want to use it?"
		ifmsgbox yes
		{
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
		}
	} else {
		msgbox Value not found
	}
	
	return

}
*/
option_changed_hook(){
	Global conv_ratio_x, conv_ratio_y
	Global LowThreshX, HighThreshX 
	Global LowThreshY, HighThreshY
	Global StickID, StickXAxis, StickYAxis
	Global axis_list_ahk
	Global joy_x_str, joy_y_str
	Global AutoCalibStartTLX, AutoCalibStartTLY
	Global auto_calib_start
	
	conv_ratio_x := ( HighThreshX - LowThreshX) / 16384
	conv_ratio_y := ( HighThreshY - LowThreshY) / 16384
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]
	joy_y_str := StickID "Joy" axis_list_ahk[StickYAxis]
	auto_calib_start := {x: AutoCalibStartTLX, y: AutoCalibStartTLY}
}

SetAxis(val, axis){
	global myStick
	myStick.SetAxisByIndex(val + 16384, axis)
}

SetAxisByName(val, axis){
	Global axis_to_index
	SetAxis(val, axis_to_index[axis])
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
	if (ActivateCalibMode()){
		; X Axis
		;AutoCalibrate(0,1)
		if (AutoCalibrate("l","x")){
			if (AutoCalibrate("l","y")){
				msgbox Calibrated.
			}
		}
		; Y Axis
		;AutoCalibrate(0,2)
		;AutoCalibrate("l","y")
		DeActivateCalibMode()
		;msgbox Done.
	}
	return

AutoTwistLimit:
	if (ActivateCalibMode()){
		; X Axis
		;AutoCalibrate(1,1)
		if (AutoCalibrate("h","x")){
			if (AutoCalibrate("h","y")){
				msgbox Calibrated.
			}
		}
		; Y Axis
		;AutoCalibrate(1,2)
		;AutoCalibrate("h","y")
		DeActivateCalibMode()
		;msgbox Done.
	}
	return

#include <ADHDlib>