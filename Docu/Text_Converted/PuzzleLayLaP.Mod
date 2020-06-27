(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE PuzzleLayLaP;	(* afi *)
IMPORT Attributes, Display, Desktops, Documents, Gadgets, LayLa, Oberon, Objects,
		Panels, PanelDocs, Pictures, Rembrandt, Strings, Texts;
VAR W: Texts.Writer; Pict, ScaledPict: Pictures.Picture;
		boardwidth, boardheight, tilew, pictwidth, pictheight: LONGINT;
		TD: Texts.Text;

(** Construct the LayLa definition for a PuzzleXY game board.
		The game is driven by module PuzzleXY.Mod which applies to any board size. *)
(**** NOTE: Uses the ButtonField gadget. ****)

PROCEDURE Write(s: ARRAY OF CHAR; nl: BOOLEAN);
BEGIN
	Texts.WriteString(W, s);
	IF nl THEN Texts.WriteLn(W) END
END Write;

PROCEDURE BuildDesc(WithCmd: BOOLEAN);
VAR j, k, pos: INTEGER; objname, coord: ARRAY 4 OF CHAR; obj: Objects.Object;
		L: Objects.Library; B: Objects.BindMsg; picts: Pictures.Picture; sideshrt: INTEGER;
		scale: BOOLEAN;
BEGIN
	SetParams;
	sideshrt := SHORT(tilew);
	Strings.IntToStr(sideshrt, coord);

	Objects.FreeLibrary("Stickers.Lib");
	L := Objects.ThisLibrary("Stickers.Lib");
	B.lib := L;

	obj := Gadgets.FindObj(Gadgets.context, "scale");
	Attributes.GetBool(obj, "Value", scale);
	NEW(ScaledPict); Pictures.Create(ScaledPict, SHORT(pictwidth), SHORT(pictheight), 8);
	Pictures.Copy(Pict, ScaledPict, 0, 0, Pict.width, Pict.height, 0, 0, ScaledPict.width, ScaledPict.height, Display.replace);

	IF WithCmd THEN Write('LayLa.OpenAsDoc', TRUE) END;
	Write('(CONFIG', TRUE);
	Write('   (DEF Tile', TRUE);
	Write('      (CONFIG', TRUE);
	Write('      (DEF me "12")', TRUE);
	Write('      (DEF number "0")', TRUE);
	Write('      (DEF mycolor 13)', TRUE);
	Write('      (DEF LibObj )', TRUE);
	Write('      (NEW ButtonField.New (w=', FALSE);
	Write(coord, FALSE);
	Write(' h=', FALSE);
	Write(coord, FALSE);
	Write(')', TRUE);
	Write('      (ATTR Name=me Value=number Font="Oberon14b.Scn.Fnt" Color=mycolor Cmd="PuzzleXY.Play")', TRUE);
	Write('      (LINKS Look=LibObj))', TRUE);
	Write('   )   )', TRUE);
	Write('   (TABLE Panel (border=8 dist=0 cols=', FALSE);
	Strings.IntToStr(boardwidth, coord);
	Write(coord, FALSE);
	Write(') (ATTR Locked=TRUE)', TRUE);
	Write('      (LINKS Model=(NEW String (ATTR Name="Free" Value="', FALSE);
	Strings.IntToStr(boardheight, coord);
	Write(coord, FALSE);
	Write(".", FALSE);
	Strings.IntToStr(boardwidth, coord);
	Write(coord, FALSE);
	Write('")))', TRUE);
	pos := 1;
	FOR j := 0 TO SHORT(boardheight) - 1 DO
		FOR k := 0 TO SHORT(boardwidth) - 1 DO
			obj := Gadgets.CreateObject("Rembrandt.New");
			WITH obj: Rembrandt.Frame DO
				NEW(picts); Pictures.Create(picts, sideshrt, sideshrt, 8);
				IF scale THEN
					Pictures.CopyBlock(ScaledPict, picts, sideshrt*k, ScaledPict.height - sideshrt*(j+1), sideshrt, sideshrt, 0, 0, Display.replace)
				ELSE
					Pictures.CopyBlock(Pict, picts, sideshrt*k, Pict.height - sideshrt*(j+1), sideshrt, sideshrt, 0, 0, Display.replace)
				END;
				obj.pict := picts;
				obj.W := picts.width;
				obj.H := picts.height;
				obj.handle(obj, B);
				Strings.IntToStr( j * boardwidth + k + 1 , objname);
				Objects.PutName(L.dict, obj.ref, objname)
			END;
			Write('      (NEW Tile (PARAMS me="', FALSE);
			Strings.IntToStr(j + 1, coord);
			Write(coord, FALSE);
			Write(".", FALSE);
			Strings.IntToStr(k + 1, coord);
			Write(coord, FALSE);
			Write('" number="', FALSE);
			IF (j = boardheight - 1) & (k = boardwidth - 1) THEN	(* Last tile description *)
				Write('" mycolor=0))', TRUE)
			ELSE	(* Normal tile description *)
				Strings.IntToStr(pos, objname);
				Write(objname, FALSE);
				Write('" LibObj=Stickers.', FALSE);
				Write(objname, FALSE);
				Write('))', TRUE)
			END;
			INC(pos)
		END
	END;
	Write('      (SPAN 1 ', FALSE);
	Strings.IntToStr(boardwidth-1, coord);
	Write(coord, TRUE);
	Write('      (NEW Button (w=[]) (ATTR Caption="Scramble" Cmd="PuzzleXY.Scramble")))', TRUE);
	Write('      (NEW Button (w=[]) (ATTR Caption="Flip Tiles" Cmd="PuzzleXY.FlipTiles"))', TRUE);
	Write('   )', TRUE);
	Write('))', TRUE);
	NEW(TD); Texts.Open(TD, "");
	Texts.Append(TD, W.buf)
END BuildDesc;

PROCEDURE BoardDesc*;
BEGIN
	BuildDesc(TRUE);
	Oberon.OpenText("PuzzleXY.Desc", TD, Display.Width DIV 2, 300)
END BoardDesc;

PROCEDURE OpenPanelDoc(obj: Objects.Object; Name: ARRAY OF CHAR);
VAR D: Documents.Document;
BEGIN
	IF obj IS Panels.Panel THEN
		WITH obj: Gadgets.Frame DO
			NEW(D);
			D.Load := PanelDocs.LoadPanel; D.Store := PanelDocs.StorePanel; D.handle := PanelDocs.DocHandle;
			COPY(Name, D.name); D.W := obj.W; D.H := obj.H;
			Documents.Init(D, obj)
		END
	END;
	IF D # NIL THEN Desktops.ShowDoc(D) END
END OpenPanelDoc;

PROCEDURE CreateBoard*;
VAR obj: Objects.Object;
BEGIN
	BuildDesc(FALSE);
	obj := LayLa.ParseText(TD, 0);
	OpenPanelDoc(obj, "PuzzleXY.Panel")
END CreateBoard;

PROCEDURE SetParams*;
VAR obj: Objects.Object;
BEGIN
	obj := Gadgets.FindObj(Gadgets.context, "side");
	Attributes.GetInt(obj, "Value", tilew);
	obj := Gadgets.FindObj(Gadgets.context, "sw");
	Attributes.SetInt(obj, "Value", tilew);
	Gadgets.Update(obj);
	obj := Gadgets.FindObj(Gadgets.context, "bw");
	Attributes.GetInt(obj, "Value", boardwidth);

	pictwidth := tilew * boardwidth;
	obj := Gadgets.FindObj(Gadgets.context, "pw");
	Attributes.SetInt(obj, "Value", pictwidth);
	Gadgets.Update(obj);
	obj := Gadgets.FindObj(Gadgets.context, "bh");
	Attributes.GetInt(obj, "Value", boardheight);

	pictheight := tilew * boardheight;
	obj := Gadgets.FindObj(Gadgets.context, "ph");
	Attributes.SetInt(obj, "Value", pictheight);
	Gadgets.Update(obj)
END SetParams;

PROCEDURE LoadPict*;
VAR obj: Objects.Object; name: ARRAY  32 OF CHAR;
BEGIN
	obj := Gadgets.FindObj(Gadgets.context, "PictName");
	Attributes.GetString(obj, "Value", name);
	NEW(Pict); Pictures.Create(Pict, 0, 0, 8);
	
	Pictures.Open(Pict, name, TRUE);
	obj := Gadgets.FindObj(Gadgets.context, "ow");
	Attributes.SetInt(obj, "Value", Pict.width);
	Gadgets.Update(obj);
	obj := Gadgets.FindObj(Gadgets.context, "oh");
	Attributes.SetInt(obj, "Value", Pict.height);
	Gadgets.Update(obj);
	SetParams
END LoadPict;

PROCEDURE GUI*;
VAR TL: Texts.Text; obj: Objects.Object;
BEGIN
	NEW(TL);
	Texts.Open(TL, "PuzzleLayLaP.Desc");
	obj := LayLa.ParseText(TL, 0);
	OpenPanelDoc(obj, "PuzzleXY.Constr.Panel");
	Gadgets.context := obj;
	LoadPict
END GUI;

BEGIN Texts.OpenWriter(W)
END PuzzleLayLaP.

System.Free PuzzleLayLaP ~
PuzzleLayLaP.GUI

PuzzleLayLaP.Desc


Example of how to cut a picture, placing the pieces into a public library:

PROCEDURE CutPict;
VAR L: Objects.Library; B: Objects.BindMsg; obj: Objects.Object; picts: Pictures.Picture; sideshrt: INTEGER;
		j, k: INTEGER; name, abscissa: ARRAY 4 OF CHAR; Pict: Pictures.Picture;
BEGIN
	NEW(Pict); Pictures.Create(Pict, 0, 0, 8);
	Pictures.Open(Pict, name, TRUE);

	Objects.FreeLibrary("Stickers.Lib");
	L := Objects.ThisLibrary("Stickers.Lib");
	B.lib := L;
	sideshrt := SHORT(side);
	FOR j := 0 TO SHORT(height) - 1 DO
		FOR k := 0 TO SHORT(width) - 1 DO
		obj := Gadgets.CreateObject("Rembrandt.New");
			WITH obj: Rembrandt.Frame DO
				NEW(picts); Pictures.Create(picts, sideshrt, sideshrt, 8);
				Pictures.CopyBlock(Pict, picts, sideshrt*k, Pict.height - sideshrt*(j+1), sideshrt, sideshrt, 0, 0, Display.replace);
				obj.pict := picts;
				obj.W := picts.width;
				obj.H := picts.height;
				obj.handle(obj, B);
				Strings.IntToStr( j * width + k + 1, name);
				Objects.PutName(L.dict, obj.ref, name)
			END
		END
	END
END CutPict;
