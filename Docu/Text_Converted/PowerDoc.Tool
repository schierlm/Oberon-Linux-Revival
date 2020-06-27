Script.Open PowerDoc.Tool
Edit.Open PowerDoc.Mod
Edit.Open PowerDoc.Text
Desktops.OpenDoc Libraries.Panel

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Grey rectangle/JG, 25.3.98")
  (FRAME
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME (POS 2 @ 2) (OBJ Panels.NewPanel) (SIZE 400 @ 300))
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "GUI panel/JG, 25.3.98")
  (FRAME
   (GRID 2:* @ 2:*)
   (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
   (FRAME
      (OBJ Panels.NewPanel)
      (POS 2 @ 2)
      (SIZE 400 @ 300)
      (GRID 3:33.34% @ 5:20%)
      (FRAME (POS 1:2 @ 1:3) (OBJ Panels.NewPanel))
      (FRAME (POS 1 @ 4:2) (OBJ TextFields.NewTextField))
      (FRAME (POS 2 @ 4) (OBJ BasicGadgets.NewButton
        (Cmd "System.Time")))
      (FRAME (POS 2 @ 5) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 3 @ 1:5) (OBJ BasicGadgets.NewButton))
    )
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (FRAME
    (META "Panel on clown/JG, 25.3.98")
    (BG Clown.Pict)
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME GUI (POS 2 @ 2) (OBJ PowerDoc.SimP1))
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (FRAME
    (META "Panel on clown/JG, 25.3.98")
    (BG Clown.Pict)
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 100 @ 100))
    (FRAME (POS 2 @ 2) (OBJ PowerDoc.SimP3))
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Panel on Arabia/JG, 25.3.98")
  (FRAME GUI
    (BG "IbnTulun.Pict")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME (POS 2 @ 2)
      (SIZE 400 @ 300)
      (OBJ Panels.NewPanel)
      (GRID 4:25% @ 1:25% 1:50% 1:25%) (PAD 2)
      (FRAME (POS 1 @ 1) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 1 @ 2) (OBJ TextFields.NewTextField))
      (FRAME (POS 1 @ 3) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 2 @ 1) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 2 @ 2) (OBJ TextFields.NewTextField))
      (FRAME P1 (POS 2 @ 3))
      (FRAME P2 (POS 3:2 @ 1) (OBJ Clown.Pict))
      (FRAME (POS 3 @ 2:2)
        (GRID 3:33.34% @ 5:20%)
        (FRAME (POS 1:2 @ 1:3) (OBJ Pop1.Pict))
        (FRAME (POS 1 @ 4:2) (OBJ TextFields.NewTextField))
        (FRAME (POS 2 @ 4) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 2 @ 5) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 3 @ 1:5) (OBJ BasicGadgets.NewButton))
      )  
      (FRAME (POS 4 @ 2:2) (OBJ BasicGadgets.NewSlider))
    )
  )
)

Edit.Open PowerDoc.Text
System.CloseTrack
PowerDoc.Open

(DOC
  (META "Two-page text Egypt/JG, 4.4.98")
  (FRAME F1 (BG Egypt.Pict)
    (GRID 1:100% @ 2:50%)
    (PAD 32) (SEP 0 @ 1)
    (FRAME P1 (POS 1 @ 1) (STI PowerDoc2.Text (DSP)))
    (FRAME P2 (POS 1 @ 2) (STI PowerDoc2.Text (DSP)))
    (STI PowerDoc2.Text (DST P1 P2))
  )
  (FRAME F2 (BG Egypt.Pict)
    (GRID 3:33.4% @ 1:40% 1:60%)
    (PAD 55 @ 45) (SEP 0 @ 1)
    (FRAME P1 (POS 2:2 @ 1) (STI PowerDoc2.Text (DSP)))
    (FRAME P2 (POS 2:2 @ 2) (STI PowerDoc2.Text (DSP)))
    (FRAME P3 (POS 1 @ 1) (STD Index.Text (DSP 4 @ 4)))
    (FRAME P4 (POS 1 @ 2))
    (STI PowerDoc2.Text (DST P1 P2))
  )
  (STD PowerDoc2.Text (DST F1 F2))
)

Edit.Open PowerDoc.Text
System.CloseTrack
PowerDoc.Open

(DOC
  (META "Two-page text Stories/JG, 25.3.98")
  (FRAME FR1 (BG "6")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 20 @ 20))
    (FRAME SFR1
      (POS 2 @ 2) (SIZE 600 @ 730) (BG "11")
      (GRID 4:25% @ 2:50%)
      (PAD 32) (SEP 0 @ 1)
      (FRAME P2 (POS 1:2 @ 1) (STI PowerDoc.Text (DSP)))
      (FRAME F1 (POS 3 @ 1) (BG "Clown.Pict"))
      (FRAME P1 (POS 4 @ 1) (STI PowerDoc.Text (DSP)))
      (FRAME P3 (POS 3:2 @ 2) (STI PowerDoc.Text (DSP)))
      (FRAME (POS 2 @ 2)
        (OBJ Panels.NewPanel)
        (GRID 4:25% @ 1:25% 1:50% 1:25%) (PAD 4) 
        (FRAME (POS 1 @ 1) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 1 @ 2) (OBJ TextFields.NewTextField))
        (FRAME (POS 1 @ 3) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 2 @ 1) (OBJ BasicGadgets.NewButton
          (Cmd "System.Time")))
        (FRAME (POS 2 @ 2) (OBJ TextFields.NewTextField))
        (FRAME (POS 2 @ 3) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 3:2 @ 1:2) (OBJ Molecules.Pict))
        (FRAME (POS 3:2 @ 3) (OBJ Cells.Pict))
      )Panel
      (FRAME P4 (POS 1 @ 2) (STI PowerDoc.Text (DSP)))
      (STI PowerDoc.Text (DST P1 P2 P3 P4))
    )SFR1
    (STI PowerDoc.Text (DST SFR1))
  )FR1
  (FRAME FR2
    (BG "6")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 20 @ 20))
    (FRAME SFR2
      (POS 2 @ 2) (SIZE 600 @ 730) (BG "11")
      (GRID 8:12.5% @ 2:50%)
      (PAD 32) (SEP 0 @ 1)
      (FRAME (POS 6:3 @ 1) (BG "Grapes.Pict"))
      (FRAME P1 (POS 3:3 @ 1) (STI PowerDoc.Text (DSP)))
      (FRAME (POS 1:2 @ 1) (BG "Fractal.Pict"))
      (FRAME P2 (POS 5:4 @ 2) (STI PowerDoc.Text (DSP)))
      (FRAME (POS 1:4 @ 2) (OBJ TextGadgets.New))
      (STI PowerDoc.Text (DST P1 P2))
    )SFR2
   (STI PowerDoc.Text (DST SFR2))
  )FR2
  (STD PowerDoc.Text (DST FR1 FR2))
)

Edit.Open PowerDoc2.Text
System.CloseTrack
PowerDoc.Open

(DOC
  (FRAME
    (META "Black Beauty/JG, 25.3.98")
    (BG "13")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 20 @ 20))
    (FRAME
      (POS 2 @ 2)
      (SIZE 600 @ 730)
      (BG "15")
      (GRID 4:25% @ 2:50%)
      (PAD 32) (SEP 0 @ 1)
      (FRAME P2 (POS 1:2 @ 1) (STI PowerDoc.Text (DSP 4 @ 4)))
      (FRAME F1 (POS 3 @ 1) (BG "Clown.Pict"))
      (FRAME P1 (POS 4 @ 1) (STI PowerDoc.Text (DSP 4 @ 4)))
      (FRAME P3 (POS 3:2 @ 2) (STI PowerDoc.Text (DSP 4 @ 4)))
      (FRAME (POS 2 @ 2)
        (OBJ Panels.NewPanel)
        (GRID 4:25% @ 1:25% 1:50% 1:25%) (PAD 4) 
        (FRAME (POS 1 @ 1) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 1 @ 2) (OBJ TextFields.NewTextField))
        (FRAME (POS 1 @ 3) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 2 @ 1) (OBJ BasicGadgets.NewButton
          (Cmd "System.Time")))
        (FRAME (POS 2 @ 2) (OBJ TextFields.NewTextField))
        (FRAME (POS 2 @ 3) (OBJ BasicGadgets.NewButton))
        (FRAME (POS 3:2 @ 1:2) (OBJ Molecules.Pict))
        (FRAME (POS 3:2 @ 3) (OBJ Cells.Pict))
      )
      (FRAME P4 (POS 1 @ 2) (STI PowerDoc.Text (DSP 4 @ 4)))
      (STD PowerDoc.Text (DST P1 P2 P3 P4))
    )
  )
)

Edit.Open PowerDoc.Text
System.CloseTrack
PowerDoc.Open

(DOC
  (META "Shallow/JG, 25.3.98")
  (FRAME FR1
    (BG "6")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME SFR1
      (BG "10")
      (POS 2 @ 2)
      (SIZE 500 @ 700)
      (GRID 1:100% @ 2:50%)
      (PAD 32) (SEP 1)
      (FRAME P1 (POS 1 @ 1) (STI PowerDoc1.Text (DSP)))
      (FRAME P2 (POS 1 @ 2) (STI PowerDoc1.Text (DSP)))
      (STI PowerDoc1.Text (DST P1 P2))
    )SFR1
   (STD PowerDoc1.Text (DST SFR1))
  )FR1
)DOC

Edit.Open PowerDoc.Text
System.CloseTrack
PowerDoc.Open

(DOC
  (META "Shallow/JG, 25.3.98")
  (FRAME FR1
    (BG "6")
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 50 @ 50))
    (FRAME SFR1
      (BG "10")
      (POS 2 @ 2)
      (SIZE 500 @ 700)
      (GRID 4:25% @ 2:50%)
      (PAD 32) (SEP 1)
      (FRAME F1 (POS 4 @ 1:2) (BG "3")
        (STD PowerDoc2.Text (DSP 4 @ 4)))
      (FRAME P1 (POS 1:3 @ 1) (STI PowerDoc1.Text (DSP)))
      (FRAME P2 (POS 1:3 @ 2) (STI PowerDoc1.Text (DSP)))
      (STI PowerDoc1.Text (DST P1 P2))
    )SFR1
   (STD PowerDoc1.Text (DST SFR1))
  )FR1
)DOC

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Text on transparent background/JG, 25.3.98")
  (FRAME
    (PAD 50)
    (GRID 2:* @ 2:*)
    (FRAME
      (POS 2 @ 2)
      (SIZE 500 @ 700)
      (GRID 1:100% @ 2:50%)
      (PAD 32) (SEP 1)
      (FRAME P1 (POS 1 @ 1) (STI PowerDoc1.Text (DSP)))
      (FRAME P2 (POS 1 @ 2) (STI PowerDoc1.Text (DSP)))
      (STD PowerDoc1.Text (DST P1 P2))
    )
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Two pictures/JG, 25.3.98")
  (FRAME
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 350 @ 220) (OBJ Grapes.Pict))
    (FRAME (POS 2 @ 2) (SIZE 290 @ 200) (OBJ Clown.Pict))
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Concrete art/JG, 25.3.98")
  (FRAME
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (BG "1") (SIZE 320 @ 384))
    (FRAME (POS 2 @ 2) (BG "2") (SIZE 320 @ 384))
    (FRAME (POS 1 @ 2) (BG "3") (SIZE 320 @ 384))
    (FRAME (POS 2 @ 1) (BG "4") (SIZE 320 @ 384))
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Artwork pictured/JG, 25.3.98")
  (FRAME
    (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 100 @ 100))
    (FRAME
      (POS 2 @ 2)
      (GRID 4:* @ 4:*)
      (FRAME (POS 1 @ 1) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 3 @ 1) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 3 @ 2) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 4 @ 2) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 1 @ 3) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 4 @ 3) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 2 @ 4) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 3 @ 4) (SIZE 100 @ 50) (BG Clown.Pict))
      (FRAME (POS 2 @ 1) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 4 @ 1) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 1 @ 2) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 2 @ 2) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 2 @ 3) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 3 @ 3) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 1 @ 4) (SIZE 100 @ 50) (BG Clouds.Pict))
      (FRAME (POS 4 @ 4) (SIZE 100 @ 50) (BG Clouds.Pict))
     )
    )
  )
)

System.CloseTrack
PowerDoc.Open

(DOC
  (META "Text boxes/JG, 25.3.98")
  (FRAME (BG "6") (GRID 2:* @ 2:*)
    (FRAME (POS 1 @ 1) (SIZE 100 @ 100))
    (FRAME (POS 2 @ 2) (GRID 2:* @ 2:*) (BND 1) (PAD 8)
      (FRAME P1 (POS 1 @ 1) (SIZE 200 @ 200) (OBJ Panels.NewPanel (Color 12)) (STI PowerDoc2.Text (DSP 8 @ 8)))
      (FRAME P2 (POS 2 @ 2) (SIZE 200 @ 200) (OBJ Panels.NewPanel (Color 13)) (STI PowerDoc2.Text (DSP 8 @ 8)))
      (FRAME P3 (POS 2 @ 1) (SIZE 200 @ 200) (OBJ Panels.NewPanel (Color 14)) (STI PowerDoc2.Text (DSP 8 @ 8)))
      (FRAME P4 (POS 1 @ 2) (SIZE 200 @ 200) (OBJ Panels.NewPanel (Color 15)) (STI PowerDoc2.Text (DSP 8 @ 8)))
      (STD PowerDoc2.Text (DST P1 P2 P3 P4))
  )
)))

System.FreeLibraries PowerDoc.Lib ~
System.DeleteFiles PowerDoc.Lib ~

PowerDoc.Compile

(LIB PowerDoc.Lib
   (FRAME SimP1
      (OBJ Panels.NewPanel)
      (SIZE 400 @ 300)
      (GRID 3:33.34% @ 5:20%)
      (FRAME (POS 1:2 @ 1:3) (OBJ Panels.NewPanel))
      (FRAME (POS 1 @ 4:2) (OBJ TextFields.NewTextField))
      (FRAME (POS 2 @ 4) (OBJ BasicGadgets.NewButton
        (Cmd "System.Time")))
      (FRAME (POS 2 @ 5) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 3 @ 1:5) (OBJ BasicGadgets.NewButton))
    )
   (FRAME SimP2
      (OBJ Panels.NewPanel)
      (SIZE 400 @ 300)
      (GRID 3:33.34% @ 5:20%)
      (FRAME (POS 1:2 @ 1:3) (OBJ Panels.NewPanel))
      (FRAME (POS 1 @ 4:2) (OBJ BasicGadgets.NewButton))
      (FRAME (POS 2 @ 4) (OBJ BasicGadgets.NewButton
        (Cmd "System.Time")))
      (FRAME (POS 2 @ 5) (OBJ TextFields.NewTextField))
      (FRAME (POS 3 @ 1:5) (OBJ BasicGadgets.NewButton))
   )
   (FRAME SimP3 (OBJ Clown.Pict))
)

Backup.WriteFiles

Clouds.Pict
Bricks.Pict
Bows.Pict
Coins.Pict
Clown.Pict
Molecules.Pict
Cells.Pict
Flock.Pict
Grapes.Pict
Fractal.Pict ~

Backup.WriteFiles

PowerDoc.Tool
PowerDoc.Mod
PowerDoc.Text
PowerDoc1.Text
PowerDoc2.Text
Index.Text

Pop0.Pict
Pop1.Pict
Pop2.Pict
Pop3.Pict
Pop4.Pict
Pop5.Pict
Pop6.Pict

Egypt2.Pict
Egypt3.Pict
Egypt5.Pict
Egypt6.Pict
Egypt7.Pict
Egypt9.Pict
Egypt10.Pict
Egypt11.Pict
Egypt12.Pict
Egypt13.Pict
Egypt14.Pict
Egypt15.Pict
Egypt16.Pict

Egypt.Pict
IbnTulun.Pict ~

FTPTool.Open gutknech@lillian ~	Log in to the selected ftp server.
FTPTool.PutFiles
  Clouds.Pict
  Bricks.Pict
  Bows.Pict
  Coins.Pict
  Clown.Pict
  Molecules.Pict
  Cells.Pict
  Flock.Pict
  Grapes.Pict
  Fractal.Pict ~

FTPTool.PutFiles
PowerDoc.Tool
PowerDoc.Mod
PowerDoc.Text
PowerDoc1.Text
PowerDoc2.Text
Index.Text

Pop0.Pict
Pop1.Pict
Pop2.Pict
Pop3.Pict
Pop4.Pict
Pop5.Pict
Pop6.Pict

Egypt2.Pict
Egypt3.Pict
Egypt5.Pict
Egypt6.Pict
Egypt7.Pict
Egypt9.Pict
Egypt10.Pict
Egypt11.Pict
Egypt12.Pict
Egypt13.Pict
Egypt14.Pict
Egypt15.Pict
Egypt16.Pict

Egypt.Pict
IbnTulun.Pict ~

FTPTool.Close
