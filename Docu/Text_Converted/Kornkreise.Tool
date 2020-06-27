SaveTiles.Install
System.CloseTrack
PowerDoc.Open

(DOC
  (META "Kornkreise/JG, 21.10.99")
  (FRAME FR1
    (BG "6")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME SFR1
      (BG "10")
      (POS 2 @ 2)
      (SIZE 500 @ 700)
      (GRID 10:10% @ 1:40% 1:60%)
      (PAD 20) (SEP 1)
      (FRAME F1 (POS 10 @ 1:2) (BG "3") (STI Kornkreise.Title (DSP)))
      (FRAME P4 (POS 4:1 @ 1) 
        (OBJ Panels.NewPanel)
        (GRID 1 @ 3:33.3%) (PAD 4) 
        (FRAME (POS 1 @ 1) (OBJ BasicGadgets.NewButton
          (Color 4) (Caption "Pause") (Cmd "SaveScreen.Run")))
        (FRAME (POS 1 @ 2) (OBJ TextFields.NewTextField))
        (FRAME (POS 1 @ 3) (OBJ BasicGadgets.NewButton
          (Color 11) (Caption "Time") (Cmd "System.Time"))))
      (FRAME P5 (POS 5:3 @ 1) (OBJ Kornkreise.Bild3))
      (FRAME P6 (POS 8:2 @ 1) (STI Kornkreise.Text (DSP)))
      (FRAME P3 (POS 1:3 @ 1:2) (OBJ Kornkreise.Bild1))
      (FRAME P2 (POS 4:2 @ 2) (STI Kornkreise.Text (DSP)))
      (FRAME F1 (POS 6:4 @ 2) (OBJ Kornkreise.Bild2))
      (STI Kornkreise.Text (DST P6 P2))
      (STD Kornkreise.Title (DST F1))
    )SFR1
   (STD Kornkreise.Text (DST SFR1))
  )FR1
)DOC
