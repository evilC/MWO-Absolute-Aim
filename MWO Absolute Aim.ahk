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
	1) 	Make sure on the BINDINGS tab you bind something to CALIBRATION MODE, AXIS SELECT, TOGGLE LOW / HIGH and AXIS SET.
		Make sure CALIBRATION MODE is not something you would normally use in-game, but when not calibrating, the others do nothing.
	2)	In-Game, at any point, you can hit CALIBRATION MODE to calibrate.
		You will hear a voice telling you that you entered calibration mode, and what current setting you are setting.
		eg "Calibrate: X, Low"
		This means you are calibrating the Low Threshold of X.
	3)	You can hit AXIS SELECT or TOGGLE LOW / HIGH to switch between settings (eg X / Y and Low / High)
	4)	The stick controls the edge of the threshold - move it left to decrease X, up to increase Y etc.
		You can only move X when editing X, and Y when editing Y, to avoid unintentional changing of an axis you dont want to.
	5)	When you find the edge of motion, hit AXIS SET to set that setting (eg X Low)
	6)	Unless you use AXIS SET for a given setting, no changes are saved when change setting or exit Calibration Mode.
	7)	If you know roughly where a threshold is, you can use the CALIB START LOW, CALIB START HIGH edit boxes to set values to start at.
		This can GREATLY speed up fine-tuning

	Good luck and REMEMBER you have PROFILES!
	You can duplicate the current profile, so you can save known good settings and experiment in other profiles.
*/

#SingleInstance, force
SetKeyDelay, 0, 50	; MWO does not recognize keys held for <50ms
#include <CvJoyInterface> 

global GUI_MARGIN := 15
global DOUBLE_GUI_MARGIN := 30
global GUI_WIDTH := 350
global SNAPSHOT_WIDTH := 100
global SNAPSHOT_HEIGHT := 100
global SNAPSHOT_GUI_WIDTH := 200
global SNAPSHOT_GUI_HEIGHT := 200
global MAX_DEFLECTION := 16384

mwo_class := "CryENGINE"
starting_up := 1
calib_current_axis := "x"
calib_current_speed := "fast"
calib_current_x := 0
calib_current_y := 0
calib_current_lohi := "low"

ADHD := new ADHDLib()
ADHD.config_about({name: "MWO Absolute Aim", version: "2.0", author: "evilC", link: "<a href=""https://github.com/evilC/MWO-Absolute-Aim"">Homepage</a> / <a href=""http://mwomercs.com/forums/topic/186302"">Forum Thread</a>"})

ADHD.config_size(GUI_WIDTH + 20, 320)
ADHD.config_event("option_changed", "option_changed_hook")
;ADHD.config_hotkey_add({uiname: "Auto Deadzone", subroutine: "AutoDeadzone"})
;ADHD.config_hotkey_add({uiname: "Auto Twist Limit", subroutine: "AutoTwistLimit"})
ADHD.config_hotkey_add({uiname: "MWO Bind X", subroutine: "MWOBindX"})
ADHD.config_hotkey_add({uiname: "MWO Bind Y", subroutine: "MWOBindY"})

ADHD.config_hotkey_add({uiname: "Calibration Mode", subroutine: "CalibModeToggle"})
ADHD.config_hotkey_add({uiname: "Axis Select", subroutine: "CalibAxisSelect"})
ADHD.config_hotkey_add({uiname: "Toggle Low / High", subroutine: "CalibAxisLoHi"})
ADHD.config_hotkey_add({uiname: "Axis Set", subroutine: "CalibAxisSet"})

axis_list_ahk := Array("X","Y","Z","R","U","V")
axis_to_index := {x: 1, y: 2}
index_to_axis := ["x","y"]

ADHD.init()
ADHD.create_gui()

;Gui, 1:New
;Gui, 1:Default
Gui, Tab, 1
Gui, Add, GroupBox, xm y40 w%GUI_WIDTH% R1, X Axis
Gui, Add, Text, xm+10 yp+15 Section, Low Threshold
ADHD.gui_add("Edit", "LowThreshX", "w50 h20 ys-3", 1, 1)
Gui, Add, Text, ys Section, High Threshold
ADHD.gui_add("Edit", "HighThreshX", "w50 h20 ys-3", MAX_DEFLECTION, MAX_DEFLECTION)

Gui, Add, GroupBox, xm yp+30 w%GUI_WIDTH% R1, Y Axis
Gui, Add, Text, xm+10 yp+15 Section, Low Threshold
ADHD.gui_add("Edit", "LowThreshY", "w50 h20 ys-3", 1, 1)
Gui, Add, Text, ys Section, High Threshold
ADHD.gui_add("Edit", "HighThreshY", "w50 h20 ys-3", MAX_DEFLECTION, MAX_DEFLECTION)

Gui, Add, Text, xm yp+40 Section, Joystick ID
ADHD.gui_add("DropDownList", "StickID", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16", "2")

Gui, Add, Text, ys Section, X Axis
ADHD.gui_add("DropDownList", "StickXAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "1")
Gui, Add, Text, ys Section, Y Axis
ADHD.gui_add("DropDownList", "StickYAxis", "w50 ys-3 h20 R9", "1|2|3|4|5|6|7|8", "2")
Gui, Add, Text, xm yp+40 Section, Calib Start Low ( 0 - %MAX_DEFLECTION%)
ADHD.gui_add("Edit", "AutoCalibStartDZ", "w40 h20 ys-3", 0, 0)
Gui, Add, Text, xm yp+30 Section, Calib Start High X ( 0 - %MAX_DEFLECTION%)
ADHD.gui_add("Edit", "AutoCalibStartTLX", "w40 h20 ys-3", 0, %MAX_DEFLECTION%)
Gui, Add, Text, xm yp+30 Section, Calib Start High Y ( 0 - %MAX_DEFLECTION%)
ADHD.gui_add("Edit", "AutoCalibStartTLY", "w40 h20 ys-3", 0, %MAX_DEFLECTION%)

ADHD.finish_startup()

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
	
	Global calib_current_x, calib_current_y, calib_current_axis
	
	Loop {
		if (joy_on){
			ax_x := GetKeyState(joy_x_str, "P")
			ax_y := GetKeyState(joy_y_str, "P")
			; ax is 0-100
			ax_x *= 327.68
			ax_y *= 327.68
			
			ax_x -= MAX_DEFLECTION
			ax_y -= MAX_DEFLECTION
			
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
			out_x += MAX_DEFLECTION
			out_y += MAX_DEFLECTION
			;tooltip % "X: " joy_x_str "`nsgn: " sgn_x "`nratio: " conv_ratio_x "`nin: " ax_x "`nout: " out_x "`n`nY: " joy_y_str "`nsgn: " sgn_y "`nratio: " conv_ratio_y "`nin: " ax_y "`nout: " out_y
			myStick.SetAxisByIndex(out_x, 1)
			myStick.SetAxisByIndex(out_y, 2)
		} else {
			; calibration mode
			SetAxisByName(calib_current_x,"x")
			SetAxisByName(calib_current_y * -1,"y")
			
			; Convert 0 -> 100 scale to -1 -> +1 scale
			xin := round((((GetKeyState(joy_x_str) / 100) * 2) - 1), 2)
			yin := round((((GetKeyState(joy_y_str) / 100) * 2) - 1), 2)
			;invert y
			yin *= -1
			
			if (calib_current_axis = "x" && abs(xin)){
				calib_current_x += (xin * 5)
				calib_current_x := round(calib_current_x,0)
			}

			if (calib_current_axis = "y" && abs(yin)){
				calib_current_y += (yin * 5)
				calib_current_y := round(calib_current_y,0)
			}

			;Tooltip % xin ", " yin
			Tooltip % calib_current_x ", " calib_current_y
		}
		Sleep 20
	}
}

option_changed_hook(){
	Global conv_ratio_x, conv_ratio_y
	Global LowThreshX, HighThreshX 
	Global LowThreshY, HighThreshY
	Global StickID, StickXAxis, StickYAxis
	Global axis_list_ahk
	Global joy_x_str, joy_y_str
	Global AutoCalibStartTLX, AutoCalibStartTLY
	Global auto_calib_start
	
	conv_ratio_x := ( HighThreshX - LowThreshX) / MAX_DEFLECTION
	conv_ratio_y := ( HighThreshY - LowThreshY) / MAX_DEFLECTION
	joy_x_str := StickID "Joy" axis_list_ahk[StickXAxis]
	joy_y_str := StickID "Joy" axis_list_ahk[StickYAxis]
	auto_calib_start := {x: AutoCalibStartTLX, y: AutoCalibStartTLY}
}

SetAxis(val, axis){
	global myStick
	myStick.SetAxisByIndex(val + MAX_DEFLECTION, axis)
}

SetAxisByName(val, axis){
	Global axis_to_index
	SetAxis(val, axis_to_index[axis])
}

MWOBindX:
	SetAxis(MAX_DEFLECTION,1)
	Sleep 250
	SetAxis(0,1)
	return

MWOBindY:
	SetAxis(MAX_DEFLECTION,2)
	Sleep 250
	SetAxis(0,2)
	return

CalibAxisSelect:
	if (!joy_on){
		if (calib_current_axis = "x"){
			calib_current_axis := "y"
		} else {
			calib_current_axis := "x"
		}
		Gosub, CalibModeChanged
		;TTS(calib_current_axis)
	}
	return

CalibAxisLoHi:
	if (!joy_on){
		if (calib_current_lohi = "low"){
			calib_current_lohi := "high"
		} else {
			calib_current_lohi := "low"
		}
		Gosub, CalibModeChanged
		;TTS(calib_current_lohi)
	}
	return
	
CalibAxisSet:
	if (!joy_on){
		if (calib_current_axis = "x"){
			if (calib_current_lohi = "low"){
				GuiControl, , LowThreshX, % calib_current_x
			} else {
				GuiControl, , HighThreshX, % calib_current_x
			}
		} else {
			if (calib_current_lohi = "low"){
				GuiControl, , LowThreshY, % calib_current_y
			} else {
				GuiControl, , HighThreshY, % calib_current_y
			}
		}
		TTS("Set: " calib_current_axis ": " calib_current_lohi) 
	}
	return
	
CalibModeToggle:
	joy_on := !joy_on
	TTS(joy_on ? "Run" : "Calibrate")
	Gosub, CalibModeChanged
	return

CalibModeChanged:
	; remove tooltips
	Tooltip
	if (calib_current_lohi = "high"){
		if (calib_current_axis = "x"){
			calib_current_x := AutoCalibStartTLX
			calib_current_y := 0
		} else {
			calib_current_x := 0
			calib_current_y := AutoCalibStartTLY
		}
	} else {
		if (calib_current_axis = "x"){
			calib_current_x := AutoCalibStartDZ
			calib_current_y := 0
		} else {
			calib_current_x := 0
			calib_current_y := AutoCalibStartDZ
		}
	}
	if (!joy_on){
		TTS(calib_current_axis ": " calib_current_lohi)
	}
	return

TTS(str){
	ComObjCreate("SAPI.SpVoice").Speak(str)
}

#include <ADHDlib>