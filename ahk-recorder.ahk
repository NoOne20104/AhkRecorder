;ahkv2 macro recorder 

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()
CoordMode("Mouse", "Screen")

;state
recording := false
playing   := false
stopPlay  := false
events := []
lastTime := 0
ih := 0

;mouse movment recording
lastMX := 0
lastMY := 0
moveThreshold := 5    
moveInterval  := 25   


humanize := false

delayJitterMs := 30      ;the ms added to each delay
mouseJitterPx := 3       ;px mousejitter
pauseChance   := 8       ;chance to insert a micro pause
pauseMinMs    := 50
pauseMaxMs    := 150

curveMouse := true 
curveMinSteps := 2
curveMaxSteps := 6
curveStepMinMs := 5
curveStepMaxMs := 18

fatigueMode := false    
fatigue := 0.0          
fatigueStep := 0.003    
fatigueMax  := 1.0       


;gui controlss
statusText := ""
countText  := ""

cbHuman := ""
cbCurve := ""
cbFatigue := ""

slDelay := ""
slMouse := ""
slPauseChance := ""
slPauseMin := ""
slPauseMax := ""


UpdateStatus(text) {
    global statusText
    if IsObject(statusText)
        statusText.Text := "Status: " text
}

UpdateCount() {
    global countText, events
    if IsObject(countText)
        countText.Text := "Events: " events.Length
}

Clamp(val, lo, hi) {
    if val < lo
        return lo
    if val > hi
        return hi
    return val
}



GetFatigueMultiplier() {
    global fatigueMode, fatigue
    return fatigueMode ? (1.0 + fatigue) : 1.0
}

HumanDelay(ms) {
    global humanize, delayJitterMs
    if !humanize
        return ms

    mult := GetFatigueMultiplier()
    jitter := Round(delayJitterMs * mult)
    if jitter <= 0
        return ms

    return Max(0, ms + Random(-jitter, jitter))
}

HumanTarget(x, y) {
    global humanize, mouseJitterPx
    if !humanize || mouseJitterPx <= 0
        return [x, y]

    mult := GetFatigueMultiplier()
    j := Round(mouseJitterPx * mult)

    return [ x + Random(-j, j), y + Random(-j, j) ]
}

MaybePause() {
    global humanize, pauseChance, pauseMinMs, pauseMaxMs
    if !humanize
        return

    mult := GetFatigueMultiplier()
    chance := Clamp(Round(pauseChance * mult), 0, 100)

    if Random(1, 100) <= chance {
        lo := Max(0, pauseMinMs)
        hi := Max(lo, pauseMaxMs)
        Sleep(Random(lo, hi))
    }
}

HumanMouseMove(x, y) {
    global humanize, curveMouse, curveMinSteps, curveMaxSteps, curveStepMinMs, curveStepMaxMs

    if !humanize || !curveMouse {
        MouseMove(x, y, 0)
        return
    }

    MouseGetPos(&sx, &sy)

    steps := Random(curveMinSteps, curveMaxSteps)
    if steps < 1
        steps := 1

    dx := x - sx
    dy := y - sy

    ;jst some sideways drift
    drift := Random(-10, 10)
    drift2 := Random(-10, 10)

    Loop steps {
        t := A_Index / steps


        ix := Round(sx + dx * t + drift * (t * (1 - t)))
        iy := Round(sy + dy * t + drift2 * (t * (1 - t)))

        MouseMove(ix, iy, 0)
        Sleep(Random(curveStepMinMs, curveStepMaxMs))
    }

    MouseMove(x, y, 0)
}

AdvanceFatigue() {
    global fatigueMode, fatigue, fatigueStep, fatigueMax
    if !fatigueMode
        return
    fatigue := Clamp(fatigue + fatigueStep, 0.0, fatigueMax)
}

;EMERGENCY STOP
EmergencyStop() {
    global recording, playing, stopPlay, ih

    stopPlay := true

    if recording {
        recording := false
        if ih
            ih.Stop()
        SetTimer(RecordMouseMove, 0)
    }

    playing := false
    UpdateStatus("Stopped")
    UpdateCount()
}

Esc::EmergencyStop()


;toggle record
ToggleRecord() {
    global recording, events, lastTime, ih, lastMX, lastMY, moveInterval

    if recording {
        recording := false
        if ih
            ih.Stop()
        SetTimer(RecordMouseMove, 0)
        UpdateStatus("Idle")
        UpdateCount()
        return
    }

    recording := true
    events := []
    lastTime := A_TickCount
    MouseGetPos(&lastMX, &lastMY)

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := KeyDown
    ih.OnKeyUp   := KeyUp
    ih.Start()

    SetTimer(RecordMouseMove, moveInterval)
    UpdateStatus("Recording")
    UpdateCount()
}

F9::ToggleRecord()


RecordMouseMove() {
    global recording, events, lastTime, lastMX, lastMY, moveThreshold
    if !recording
        return

    MouseGetPos(&x, &y)

    if Abs(x - lastMX) < moveThreshold && Abs(y - lastMY) < moveThreshold
        return

    now := A_TickCount
    events.Push({ type: "mouse_move", x: x, y: y, delay: now - lastTime })

    lastTime := now
    lastMX := x
    lastMY := y
}


;keyboard events
KeyDown(ih, vk, sc) {
    global recording, events, lastTime
    if !recording
        return
    now := A_TickCount
    events.Push({ type: "key_down", sc: sc, delay: now - lastTime })
    lastTime := now
}

KeyUp(ih, vk, sc) {
    global recording, events, lastTime
    if !recording
        return
    now := A_TickCount
    events.Push({ type: "key_up", sc: sc, delay: now - lastTime })
    lastTime := now
}


;mouse buttons
~LButton::
~LButton Up::
~RButton::
~RButton Up::
~MButton::
~MButton Up:: {
    global recording, events, lastTime
    if !recording
        return

    MouseGetPos(&x, &y)
    now := A_TickCount

    btn := InStr(A_ThisHotkey, "LButton") ? "L"
         : InStr(A_ThisHotkey, "RButton") ? "R"
         : "M"

    state := InStr(A_ThisHotkey, "Up") ? "up" : "down"

    events.Push({
        type: "mouse_btn",
        btn: btn,
        state: state,
        x: x,
        y: y,
        delay: now - lastTime
    })

    lastTime := now
}


;playback
PlayMacro() {
    global recording, playing, stopPlay, events
    global fatigue, fatigueMode

    if recording {
        MsgBox("Stop recording first.")
        return
    }
    if events.Length = 0 {
        MsgBox("No events loaded.")
        return
    }

    stopPlay := false
    playing := true
    UpdateStatus("Playing")

    ;reset fatigue
    fatigue := 0.0

    for , e in events {
        if stopPlay
            break

        Sleep(HumanDelay(e.delay))
        if stopPlay
            break

        MaybePause()

        switch e.type {
            case "key_down":
                Send("{sc" Format("{:03X}", e.sc) " down}")

            case "key_up":
                Send("{sc" Format("{:03X}", e.sc) " up}")

            case "mouse_move":
                pos := HumanTarget(e.x, e.y)
                HumanMouseMove(pos[1], pos[2])

            case "mouse_btn":
                pos := HumanTarget(e.x, e.y)
                HumanMouseMove(pos[1], pos[2])
                Click(e.btn, , , , e.state)
        }

        AdvanceFatigue()
    }

    playing := false
    UpdateStatus("Idle")
}

F10::PlayMacro()

;saves and loads .ini file
SaveMacro() {
    global events
    if events.Length = 0 {
        MsgBox("Nothing to save.")
        return
    }

    file := FileSelect("S16", , "Save Macro", "Macro (*.ini)")
    if !file
        return

    if FileExist(file)
        FileDelete(file)

    IniWrite(events.Length, file, "meta", "count")

    for i, e in events {
        sec := "event_" i
        IniWrite(e.type,  file, sec, "type")
        IniWrite(e.delay, file, sec, "delay")

        if e.type = "key_down" || e.type = "key_up" {
            IniWrite(e.sc, file, sec, "sc")
        } else {
            IniWrite(e.x, file, sec, "x")
            IniWrite(e.y, file, sec, "y")
            if e.type = "mouse_btn" {
                IniWrite(e.btn,   file, sec, "btn")
                IniWrite(e.state, file, sec, "state")
            }
        }
    }

    MsgBox("Saved " events.Length " events.")
}

LoadMacro() {
    global events

    file := FileSelect("1", , "Load Macro", "Macro (*.ini)")
    if !file
        return

    if !FileExist(file) {
        MsgBox("File not found.")
        return
    }

    events := []
    count := IniRead(file, "meta", "count", 0)

    Loop count {
        sec := "event_" A_Index
        e := {}
        e.type  := IniRead(file, sec, "type")
        e.delay := IniRead(file, sec, "delay", 0) + 0

        if e.type = "key_down" || e.type = "key_up" {
            e.sc := IniRead(file, sec, "sc", 0) + 0
        } else {
            e.x := IniRead(file, sec, "x", 0) + 0
            e.y := IniRead(file, sec, "y", 0) + 0
            if e.type = "mouse_btn" {
                e.btn   := IniRead(file, sec, "btn")
                e.state := IniRead(file, sec, "state")
            }
        }

        events.Push(e)
    }

    UpdateStatus("Idle")
    UpdateCount()
    MsgBox("Loaded " events.Length " events.")
}

F7::SaveMacro()
F8::LoadMacro()

;gui settings
SyncFromGui(*) {
    global humanize, curveMouse, fatigueMode
    global delayJitterMs, mouseJitterPx, pauseChance, pauseMinMs, pauseMaxMs
    global cbHuman, cbCurve, cbFatigue
    global slDelay, slMouse, slPauseChance, slPauseMin, slPauseMax

    humanize := cbHuman.Value
    curveMouse := cbCurve.Value
    fatigueMode := cbFatigue.Value

    delayJitterMs := slDelay.Value
    mouseJitterPx := slMouse.Value
    pauseChance   := slPauseChance.Value
    pauseMinMs    := slPauseMin.Value
    pauseMaxMs    := slPauseMax.Value
}

mainGui := Gui("+AlwaysOnTop", "Macro Recorder")
mainGui.SetFont("s10")

mainGui.AddText("xm", "Controls")
mainGui.AddButton("w160", "Record / Stop").OnEvent("Click", (*) => ToggleRecord())
mainGui.AddButton("w160", "Play").OnEvent("Click", (*) => PlayMacro())
mainGui.AddButton("w160", "Save").OnEvent("Click", (*) => SaveMacro())
mainGui.AddButton("w160", "Load").OnEvent("Click", (*) => LoadMacro())
mainGui.AddButton("w160 cRed", "EMERGENCY STOP").OnEvent("Click", (*) => EmergencyStop())

mainGui.AddText("xm y+10", "Humanization")
cbHuman := mainGui.AddCheckbox("xm", "Humanize (more human-like)")
cbHuman.Value := humanize
cbHuman.OnEvent("Click", SyncFromGui)

cbCurve := mainGui.AddCheckbox("xm", "Curved mouse movement")
cbCurve.Value := curveMouse
cbCurve.OnEvent("Click", SyncFromGui)

cbFatigue := mainGui.AddCheckbox("xm", "Fatigue mode (increases over time)")
cbFatigue.Value := fatigueMode
cbFatigue.OnEvent("Click", SyncFromGui)

mainGui.AddText("xm y+10", "Delay jitter (ms)")
slDelay := mainGui.AddSlider("xm w240 Range0-200 ToolTip", delayJitterMs)
slDelay.OnEvent("Change", SyncFromGui)

mainGui.AddText("xm y+5", "Mouse jitter (px)")
slMouse := mainGui.AddSlider("xm w240 Range0-30 ToolTip", mouseJitterPx)
slMouse.OnEvent("Change", SyncFromGui)

mainGui.AddText("xm y+5", "Micro-pause chance (%)")
slPauseChance := mainGui.AddSlider("xm w240 Range0-50 ToolTip", pauseChance)
slPauseChance.OnEvent("Change", SyncFromGui)

mainGui.AddText("xm y+5", "Micro-pause min (ms)")
slPauseMin := mainGui.AddSlider("xm w240 Range0-1000 ToolTip", pauseMinMs)
slPauseMin.OnEvent("Change", SyncFromGui)

mainGui.AddText("xm y+5", "Micro-pause max (ms)")
slPauseMax := mainGui.AddSlider("xm w240 Range0-2000 ToolTip", pauseMaxMs)
slPauseMax.OnEvent("Change", SyncFromGui)

statusText := mainGui.AddText("xm y+12 w260", "Status: Idle")
countText  := mainGui.AddText("xm w260", "Events: 0")

mainGui.Show()
UpdateStatus("Idle")
UpdateCount()
SyncFromGui()
