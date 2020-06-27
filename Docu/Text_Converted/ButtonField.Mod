(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE ButtonField;
(**looks like a Button but valued like a TextField*)
(**damien.guichard@wanadoo.fr*)

(**the design of this gadget has been inspired by expectings from Andr Fischer*)

IMPORT
	Files, Texts, Display, Display3, Printer, Printer3, Fonts, Strings, Attributes, Objects, Gadgets, Oberon;

CONST
	minVersion = 1; maxVersion = 1;

TYPE
	Frame = POINTER TO FrameDesc;
	FrameDesc = RECORD (Gadgets.FrameDesc)
		val: ARRAY 32 OF CHAR;
		col: INTEGER;
		flat, rain: BOOLEAN;
		look: Objects.Object;
		inM, outM: Display3.Mask
	END;

VAR W: Texts.Writer;
	
PROCEDURE Log;
BEGIN Texts.Append(Oberon.Log, W.buf) END Log;

PROCEDURE KillMasks(F: Objects.Object);
VAR O: Display3.OverlapMsg;
BEGIN
	O.F := NIL; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
END KillMasks;

PROCEDURE ButtonSetLook(F: Frame; f: Gadgets.Frame): BOOLEAN; (* ps - 8.5.96 *)
VAR CM: Display.ControlMsg; B: Objects.BindMsg;
BEGIN
	IF Gadgets.Recursive(F, f) THEN
		Texts.WriteString(W,"Not allowed, will cause recursive structures"); Log;
		RETURN FALSE
	ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
		Texts.WriteString(W,"Across library movement not allowed"); Log;
		RETURN FALSE
	ELSE
		CM.id := Display.remove; CM.F := f; Display.Broadcast(CM); (* <<< remove *)
		IF F.lib # NIL THEN B.lib:= F.lib; f.handle(f, B); END;
		F.look := f; KillMasks(F);
		RETURN TRUE
	END;
END ButtonSetLook;
	
PROCEDURE HandleAttr (F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; M.s := "ButtonField.New"; M.res := 0
		ELSIF M.name = "LineupHY" THEN (*only right for single line caption in default font*) 
			M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "Value" THEN M.class := Objects.String; COPY(F.val, M.s); M.res := 0 
		ELSIF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0 
		ELSIF M.name = "Flat" THEN M.class := Objects.Bool; M.b := F.flat; M.res := 0 
		ELSIF M.name = "Rainbow" THEN M.class := Objects.Bool; M.b := F.rain; M.res := 0 
		ELSIF M.name = "Font" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN M.class := Objects.String; COPY(Fonts.Default.name, M.s); M.res := 0 END
		ELSIF (M.name = "Field") OR (M.name = "Cmd") OR (M.name = "ConsumeCmd") THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Value" THEN IF M.class = Objects.String THEN COPY(M.s, F.val); M.res := 0 END
		ELSIF M.name = "Color" THEN IF M.class = Objects.Int THEN F.col := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "Flat" THEN IF M.class = Objects.Bool THEN F.flat := M.b ; M.res := 0 END 
		ELSIF M.name = "Rainbow" THEN IF M.class = Objects.Bool THEN F.rain := M.b ; M.res := 0 END 
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Value");  M.Enum("Field"); M.Enum("Color"); M.Enum("Flat"); M.Enum("Rainbow");
		M.Enum("Font"); M.Enum("Cmd"); M.Enum("ConsumeCmd");
		Gadgets.framehandle(F, M)
	END
END HandleAttr;

PROCEDURE Restore (F: Frame; R: Display3.Mask; x, y, w, h, u, v, w1, h1: INTEGER; dlink: Objects.Object);
	VAR fnt: Fonts.Font; A: Objects.AttrMsg; col: INTEGER; ch: CHAR;
			D: Display.DisplayMsg; L: Gadgets.Frame; O: Display3.OverlapMsg; ll, lr, lb, lt: INTEGER;
BEGIN
	(*frame*)
	IF F.flat THEN
		Display3.ReplConst(R, F.col, x, y, w, h, Display3.replace)
	ELSE
		Display3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display3.replace);
		Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, x+1, y+1, w-2, h-2, 1, Display3.replace);
	END;
	(*caption*)
	IF F.val # "" THEN
		col := Display3.textC;		(*text color*)
		IF F.rain THEN
			ch := F.val[Strings.Length(F.val)-1];
			CASE ch OF
			  "0" : col := Display3.white;
			| "1" : col := Display3.black;
			| "2".."9" : col := ORD(ch) - ORD("1");
			ELSE 
			END
		END;
		fnt := Fonts.Default;			(*text font*)
		A.id := Objects.get; A.name := "Font"; A.res := -1; Gadgets.framehandle(F, A);
		IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN
			fnt := Fonts.This(A.s); IF fnt = NIL THEN fnt := Fonts.Default END
		END;
		Display3.CenterString(R, col, x, y, w, h, fnt, F.val, Display3.textmode)
	ELSIF (F.look # NIL) THEN
		L := F.look(Gadgets.Frame);
		ll := x + w DIV 2 - L.W DIV 2; lr := ll + L.W - 1;
		lb := y + h DIV 2 - L.H DIV 2; lt := lb + L.H - 1;
		u := x + u; v := y + h - 1 + v;
		IF u < ll THEN DEC(w1, ll - u); u := ll END;
		IF v < lb THEN DEC(h1, lb - y); v := lb END;
		IF u + w1 - 1 > lr THEN w1 := lr + 1 - u END;
		IF v + h1 - 1 > lt THEN h1 := lt + 1 - v END;
		O.F := L; O.res := -1; O.M := F.outM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
		D.device := Display.screen; D.id := Display.area; D.F := L; D.dlink := dlink;
		D.x := ll - L.X; D.y := lb - L.Y;
		D.u := u - ll; D.v := v - lt; D.w := w1; D.h := h1;
		D.res := -1; L.handle(L, D)
	END;
	(*selection*)
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display3.paint)
	END
END Restore;

PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
	VAR R: Display3.Mask; fnt: Fonts.Font; A: Objects.AttrMsg; col: INTEGER; ch: CHAR;
		   D: Display.DisplayMsg; x, y, w, h: INTEGER; L: Gadgets.Frame; O: Display3.OverlapMsg;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	(*frame*)
	IF F.flat THEN
		Printer3.ReplConst(R, F.col, x, y, w, h, Display3.replace)
	ELSE
		Printer3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, P(1), Display3.replace);
		Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, x+P(1), y+P(1), w-P(2), h-P(2), P(1), Display3.replace);
	END;
	(*caption*)
	IF F.val # "" THEN
		col := Display3.textC;		(*text color*)
		IF F.rain THEN
			ch := F.val[Strings.Length(F.val)-1];
			CASE ch OF
			  "0" : col := Display3.white;
			| "1" : col := Display3.black;
			| "2".."9" : col := ORD(ch) - ORD("1");
			ELSE 
			END
		END;
		fnt := Fonts.Default;			(*text font*)
		A.id := Objects.get; A.name := "Font"; A.res := -1; Gadgets.framehandle(F, A);
		IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN
			fnt := Fonts.This(A.s); IF fnt = NIL THEN fnt := Fonts.Default END
		END;
		Printer3.CenterString(R, col, x, y, w, h, fnt, F.val, Display3.textmode)
	ELSIF (F.look # NIL) THEN
		L := F.look(Gadgets.Frame);
		O.res := -1; O.M := F.outM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
		D.device := Display.printer; D.id := Display.full; D.F := NIL; D.dlink := M.dlink;
		D.x := x + w DIV 2 - P(L.W DIV 2); D.y := y + h DIV 2 - P(L.H DIV 2);
		D.res := -1;
		L.handle(L, D)
	END;
END Print;

PROCEDURE Copy (VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	to.val := from.val; to.col := from.col; to.flat := from.flat; to.rain := from.rain;
	to.look := Gadgets.CopyPtr(M, from.look); Gadgets.CopyFrame(M, from, to)
END Copy;

PROCEDURE Handler (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR x, y, w, h: INTEGER; f: Gadgets.Frame; F1: Frame; R: Display3.Mask; A: Objects.AttrMsg; version: LONGINT;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Restore(F, R, x, y, w, h, 0, 1 - h, w, h, M.dlink)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R); 
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									Restore(F, R, x, y, w, h, M.u, M.v, M.w, M.h, M.dlink)
								END
							ELSIF M.device = Display.printer THEN Print(F, M)
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO (* ps - 8.5.96 *)
							IF (M.id = Display.drop) & (M.F = F) & (F.val = "") & (M.obj IS Gadgets.Frame) & (F.look = NIL) THEN
								IF ButtonSetLook(F, M.obj(Gadgets.Frame)) THEN
									M.res:= 0; Gadgets.Update(F);
								END
							ELSE
								Gadgets.framehandle(F, M);
							END
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO
							Gadgets.framehandle(F, M);
							IF F.look # NIL THEN
								f := F.look(Gadgets.Frame);
								IF F.mask = NIL THEN
									KillMasks(F.look); F.inM := NIL; F.outM := NIL;
								ELSE
									Display3.Copy(M.M, F.outM);
									Display3.Intersect(F.outM, 2, -h + 3, w - 4, h - 4);
									Display3.Intersect(F.outM, w DIV 2 - f.W DIV 2, (-h+1) DIV 2 - f.H DIV 2, f.W, f.H);
									F.outM.x := -(w DIV 2 - f.W DIV 2); F.outM.y := -((-h+1) DIV 2 - f.H DIV 2 + f.H) + 1;
									Display3.Shift(F.outM);
									
									Display3.Copy(M.M, F.inM);
									Display3.Intersect(F.inM, 2, -h + 3, w - 4, h - 4);
									Display3.Intersect(F.inM, w DIV 2 - f.W DIV 2 + 1, (-h+1) DIV 2 - f.H DIV 2 - 1, f.W, f.H);
									F.inM.x := -(w DIV 2 - f.W DIV 2 + 1); F.inM.y := -((-h+1) DIV 2 - f.H DIV 2 + f.H - 1) + 1;
									Display3.Shift(F.inM)
								END
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = F.obj THEN (* model has changed *)
								A.id := Objects.get; A.name := "Field"; A.res := -1; Gadgets.framehandle(F, A);
								IF (A.res < 0) OR (A.class # Objects.String) OR (A.s = "") THEN A.s := "Value" END;
								Attributes.GetString(F.obj, A.s, F.val);
								IF (F.look = NIL) OR (F.val # "") THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Oberon.RemoveMarks(x, y, w, h);  (*needed with MemoryUsed-like volatile models*)
									Restore(F, R, x, y, w, h, 0, 1 - h, w, h, M.dlink)
								END
							ELSE Gadgets.framehandle(F, M) (* may be for this frame too *)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END			
		ELSIF M IS Objects.AttrMsg THEN HandleAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, maxVersion);
					Files.WriteString(M.R, F.val); Files.WriteInt(M.R, F.col);
					Files.WriteBool(M.R, F.flat); Files.WriteBool(M.R, F.rain);
					Gadgets.WriteRef(M.R, F.lib, F.look);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, version);
					IF version IN {minVersion..maxVersion} THEN
						Files.ReadString(M.R, F.val); Files.ReadInt(M.R, F.col);
						Files.ReadBool(M.R, F.flat); Files.ReadBool(M.R, F.rain);
						Gadgets.ReadRef(M.R, F.lib, F.look);
						Gadgets.framehandle(F, M)
					ELSE	(*can not read this version*)
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, maxVersion, 0);
						Texts.WriteString(W, " of ButtonField cannot read version ");
						Texts.WriteInt(W, version, 0); Texts.WriteLn(W); Log; HALT(42)
					END;
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
				ELSE (*first arrival*)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					Copy(M, F, F1); M.obj := F1
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.look # NIL THEN F.look.handle(F.look, M) END;
		ELSIF M IS Objects.LinkMsg THEN (* ps - 8.5.96 *)
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Look" THEN M.obj:= F.look; M.res:= 0
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Look" THEN
						IF M.obj = NIL THEN F.look:= NIL; M.res:= 0
						ELSIF M.obj = F.look THEN M.res:= 0
						ELSIF M.obj IS Gadgets.Frame THEN
							IF ButtonSetLook(F, M.obj(Gadgets.Frame)) THEN M.res:= 0 END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Look"); Gadgets.framehandle(F, M)
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END Handler;

PROCEDURE Init (F: Frame);
BEGIN
	F.val := "Button Field"; F.col := Display3.upC; F.flat := FALSE; F.rain := FALSE;
	F.W := 40; F.H := 30; F.handle := Handler
END Init;

PROCEDURE New*;
	VAR F: Frame;
BEGIN
	NEW(F); Init(F); Objects.NewObj := F
END New;

BEGIN Texts.OpenWriter(W)
END ButtonField.

System.Free ButtonField ~
Gadgets.Insert ButtonField.New ~
