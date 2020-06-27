(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Turtle;	(* eos 14.12.1999 *)

	IMPORT
		Objects, Display, Viewers, MenuViewers, TextFrames, Oberon, Math, Gfx, GfxDisplay;
		
	
	CONST
		stroke* = 0; close* = 1; fill* = 2;	(** polygon and circle modes **)
		
		closed = 0; displayed = 2;	(* viewer state *)
		bg = 14; fg = 12;	(* background and grid color *)
		grid = 20;	(* grid distance *)
		
	
	TYPE
		Frame = Display.Frame;
		
	
	VAR
		V: MenuViewers.Viewer;
		DC: GfxDisplay.Context;
		AutoClose: BOOLEAN;
		
	
	PROCEDURE Restore (x, y, w, h, x0, y0: INTEGER);
	BEGIN
		Display.ReplConst(bg, x, y, w, h, Display.replace);
		INC(w, x); INC(h, y);
		x0 := (x - x0 + (grid-1)) DIV grid * grid; y := (y - y0 + (grid-1)) DIV grid * grid;
		WHILE y < h DO
			x := x0;
			WHILE x < w DO
				Display.Dot(fg, x, y, Display.replace);
				INC(x, grid)
			END;
			INC(y, grid)
		END
	END Restore;
	
	PROCEDURE Handle (f: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR copy: Frame;
	BEGIN
		WITH f: Frame DO
			IF msg IS Oberon.InputMsg THEN
				WITH msg: Oberon.InputMsg DO
					IF msg.id = Oberon.track THEN
						Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, msg.X, msg.Y); msg.res := 0
					END
				END
			ELSIF msg IS Display.ModifyMsg THEN
				WITH msg: Display.ModifyMsg DO
					IF msg.F = f THEN
						Oberon.RemoveMarks(f.X, f.Y, f.W, f.H);
						IF msg.id = Display.extend THEN
							IF msg.dY > 0 THEN
								Display.CopyBlock(f.X, f.Y, f.W, f.H, f.X, f.Y + msg.dY, Display.replace);
								f.Y := f.Y + msg.dY
							END;
							Restore(f.X, msg.Y, f.W, f.Y - msg.Y, f.X, f.Y + f.H);
							f.H := f.H + f.Y - msg.Y; f.Y := msg.Y
						ELSIF msg.id = Display.reduce THEN
							f.H := f.Y + f.H - (msg.Y + msg.dY); f.Y := msg.Y + msg.dY;
							IF msg.dY > 0 THEN
								Display.CopyBlock(f.X, f.Y, f.W, f.H, f.X, msg.Y, Display.replace);
								f.Y := msg.Y
							END
						END;
						GfxDisplay.Init(DC, f.X, f.Y, f.X + f.W, f.Y + f.H);
						Gfx.SetCapStyle(DC, Gfx.RoundCap); Gfx.SetJoinStyle(DC, Gfx.RoundJoin)
					END
				END
			ELSIF msg IS Display.LocateMsg THEN
				WITH msg: Display.LocateMsg DO
					IF (f.X <= msg.X) & (msg.X < f.X + f.W) & (f.Y <= msg.Y) & (msg.Y < f.Y + f.H) THEN
						msg.loc := f; msg.res := 0
					END
				END
			ELSIF msg IS Objects.CopyMsg THEN
				NEW(copy); copy.handle := f.handle; msg(Objects.CopyMsg).obj := copy
			END
		END
	END Handle;
	
	PROCEDURE Reset*;
	BEGIN
		Gfx.SetStrokeColor(DC, Gfx.Black); Gfx.SetFillColor(DC, Gfx.White); Gfx.SetLineWidth(DC, 1)
	END Reset;
	
	PROCEDURE Open*;
		VAR f: Frame; cm: Display.ControlMsg;
	BEGIN
		IF V = NIL THEN
			NEW(V); V.handle := MenuViewers.Handle; V.state := closed; V.menuH := TextFrames.menuH;
			V.dsc := TextFrames.NewMenu("Turtle Output", "System.Close");
			NEW(f); f.handle := Handle; f.W := V.W; V.dsc.next := f
		END;
		IF V.state # displayed THEN
			V.W := Oberon.SystemTrack(0);
			Oberon.OpenTrack(0, V.W);
			Viewers.Open(V, 0, Oberon.DisplayHeight(0));
			cm.F := NIL; cm.id := Display.restore; V.handle(V, cm);
			Reset
		END
	END Open;
	
	PROCEDURE Erase*;
		VAR f: Frame;
	BEGIN
		IF V.state = displayed THEN
			f := V.dsc.next;
			Oberon.RemoveMarks(f.X, f.Y, f.W, f.H);
			Restore(f.X, f.Y, f.W, f.H, f.X, f.Y + f.H);
			Reset
		END
	END Erase;
	
	PROCEDURE SetWidth* (w: REAL);
	BEGIN
		IF ~(Gfx.InPath IN DC.mode) THEN
			Gfx.SetLineWidth(DC, w)
		END
	END SetWidth;
	
	PROCEDURE SetLineCol* (col: Display.Color);
		VAR gc: Gfx.Color;
	BEGIN
		IF ~(Gfx.InPath IN DC.mode) THEN
			Display.GetColor(col, gc.r, gc.g, gc.b);
			Gfx.SetStrokeColor(DC, gc)
		END
	END SetLineCol;
	
	PROCEDURE SetFillCol* (col: Display.Color);
		VAR gc: Gfx.Color;
	BEGIN
		IF ~(Gfx.InPath IN DC.mode) THEN
			Display.GetColor(col, gc.r, gc.g, gc.b);
			Gfx.SetFillColor(DC, gc)
		END
	END SetFillCol;
	
	PROCEDURE BeginPath* (x, y: REAL; mode: INTEGER);
		VAR m: SET;
	BEGIN
		IF V.state = displayed THEN
			AutoClose := mode IN {close, fill};
			m := {};
			IF DC.lineWidth # 0 THEN INCL(m, Gfx.Stroke) END;
			IF mode = fill THEN INCL(m, Gfx.Fill) END;
			IF m # {} THEN
				Gfx.Begin(DC, m);
				Gfx.MoveTo(DC, x, y)
			END
		END
	END BeginPath;
	
	PROCEDURE LineTo* (x, y: REAL);
	BEGIN
		IF (V.state = displayed) & (Gfx.InPath IN DC.mode) THEN
			Gfx.LineTo(DC, x, y)
		END
	END LineTo;

    PROCEDURE CurveTo* (alpha, x, y, beta: REAL);
      CONST tension = 2.5;
      VAR d, x0, y0, x1, y1: REAL;
    BEGIN
      IF (V.state = displayed) & (Gfx.InPath IN DC.mode) THEN
        d := (ABS(x - DC.cpx) + ABS(y - DC.cpy))/tension;
        x0 := DC.cpx + d*Math.cos(alpha); y0 := DC.cpy + d*Math.sin(alpha);
        x1 := x - d*Math.cos(beta); y1 := y - d*Math.sin(beta);
        Gfx.BezierTo(DC, x, y, x0, y0, x1, y1)
      END
    END CurveTo;
	
	PROCEDURE EndPath*;
	BEGIN
		IF (V.state = displayed) & (Gfx.InPath IN DC.mode) THEN
			IF AutoClose THEN Gfx.Close(DC) END;
			Gfx.End(DC)
		END
	END EndPath;
	
	PROCEDURE Circle* (x, y, r: REAL; mode: INTEGER);
		VAR m: SET;
	BEGIN
		IF (V.state = displayed) & ~(Gfx.InPath IN DC.mode) THEN
			m := {};
			IF DC.lineWidth # 0 THEN INCL(m, Gfx.Stroke) END;
			IF mode = fill THEN INCL(m, Gfx.Fill) END;
			IF m # {} THEN
				Gfx.DrawCircle(DC, x, y, r, m)
			END
		END
	END Circle;
	
	
BEGIN
	NEW(DC)
END Turtle.

Turtle.Open	Turtle.Erase
