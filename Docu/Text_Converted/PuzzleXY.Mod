(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE PuzzleXY;	(* afi *)
(* In red: detail to improve the readability. *)
(* In blue: Program modification for exchanging Button and ButtonField gadgets. *)
(* The dimensions are implicit in the LayLa description. They are used by Scramble but not by Play.
	The algorithm is valid for boards of arbitrary width and height. No recompilation needed.*)
IMPORT Attributes, Gadgets, Links, Oberon, Objects, RandomNumbers, Strings, Out;
CONST Right = 0; Down = 1; Left = 2; Up = 3;

FieldName = "Value";	(* "Caption" when using Button OR "Value" when using ButtonField gadget. *)
(* Note that the module does not have to import a gadget module, e.g. ButtonField.Mod.
     The graphical interface defined in Layla makes the difference.
     If ButtonField used the same attribute name "Caption" as Button, no change would be needed. *)

PROCEDURE GetObj(x, y: LONGINT): Objects.Object;
VAR posname, abs: ARRAY 6 OF CHAR;
BEGIN
	Strings.IntToStr(y, posname);
	Strings.AppendCh(posname, ".");
	Strings.IntToStr(x, abs);
	Strings.Append(posname, abs);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

PROCEDURE GetCoord(name: ARRAY OF CHAR; VAR x, y: INTEGER);
VAR i: INTEGER;
BEGIN
	i := 0; x := 0; y := 0;
	WHILE name[i] # "." DO y := 10 * y + ORD(name[i])-ORD("0"); INC(i) END;
	INC(i);
	WHILE name[i] # 0X DO x := 10 * x + ORD(name[i])-ORD("0"); INC(i) END
END GetCoord;

(* Bring into the free cell at (row, col) the adjacent tile to move the specified direction. *)
PROCEDURE SlideTile(row, col: INTEGER; direction: INTEGER);
VAR obj, lnkobj: Objects.Object; cap: ARRAY 6 OF CHAR;
BEGIN
	CASE direction OF
	   Right: obj := GetObj(col - 1, row)
	| Down: obj := GetObj(col, row-1)
	| Left: obj := GetObj(col + 1, row)
	| Up: obj := GetObj(col, row+1)
	END;
	Attributes.GetString(obj, FieldName, cap);
	Links.GetLink(obj, "Look", lnkobj);
	IF cap # "" THEN
		obj := GetObj(col, row);
		Attributes.SetString(obj, FieldName, cap);
	END;
	Attributes.GetString(lnkobj, "Name", cap);
	obj := GetObj(col, row);
	Links.SetLink(obj, "Look", lnkobj);
	Attributes.SetInt(obj, "Color", 13);
	Gadgets.Update(obj)
END SlideTile;

PROCEDURE Scramble*;
VAR name, freepos, abs: ARRAY 6 OF CHAR; h, w, rowf, colf: INTEGER; Freeobj, obj: Objects.Object; count: LONGINT;
BEGIN
	(* Determine the width and the height of the board *)
	w := 0;
	REPEAT INC(w) UNTIL NIL = GetObj(w, 1);
	h := 0;
	REPEAT INC(h) UNTIL NIL = GetObj(1, h);
	DEC(w); DEC(h);
	FOR count := 1 TO (h + w) * h * w DO

		Freeobj := Gadgets.FindObj(Gadgets.context, "Free");
		Attributes.GetString(Freeobj, "Value", freepos);
		GetCoord(freepos, colf, rowf);

		CASE ENTIER(RandomNumbers.Uniform()*4) OF
			0: IF 1 < colf THEN SlideTile(rowf, colf, Right); DEC(colf) END
			| 1: IF colf < w THEN SlideTile(rowf, colf, Left); INC(colf) END
			| 2: IF 1 < rowf THEN SlideTile(rowf, colf, Down); DEC(rowf) END
			| 3: IF rowf < h THEN SlideTile(rowf, colf, Up); INC(rowf) END
		END;
		obj := GetObj(colf, rowf);
		Attributes.SetString(obj, FieldName, "");
		Attributes.SetInt(obj, "Color", 0);
		Links.SetLink(obj, "Look", NIL);
		Gadgets.Update(obj);
		Strings.IntToStr(rowf, name);
		Strings.AppendCh(name, ".");
		Strings.IntToStr(colf, abs);
		Strings.Append(name, abs);
		Attributes.SetString(Freeobj, "Value", name);
		Gadgets.Update(Freeobj)
	END
END Scramble;

PROCEDURE FlipTiles*;
VAR cap: ARRAY 6 OF CHAR; h, w, row, col: INTEGER; obj, lnkobj: Objects.Object;
BEGIN
	(* Determine the width and the height of the board *)
	w := 0;
	REPEAT INC(w) UNTIL NIL = GetObj(w, 1);
	h := 0;
	REPEAT INC(h) UNTIL NIL = GetObj(1, h);
	DEC(w); DEC(h);
	FOR row := 1 TO h DO
		FOR col := 1 TO w DO
			obj := GetObj(col, row);
			Attributes.GetString(obj, "Value", cap);
			IF cap = "" THEN
				Links.GetLink(obj, "Look", lnkobj);
				Attributes.GetString(lnkobj, "Name", cap);
				Attributes.SetString(obj, "Value", cap)
			ELSE
				Attributes.SetString(obj, "Value", "")
			END;
			Gadgets.Update(obj)
		END
	END
END FlipTiles;

PROCEDURE Play*;
VAR name, freepos: ARRAY 6 OF CHAR; row, col, rowf, colf: INTEGER; Freeobj, obj: Objects.Object;
BEGIN
	Attributes.GetString(Gadgets.executorObj, "Name", name);
	GetCoord(name, col, row);

	Freeobj := Gadgets.FindObj(Gadgets.context, "Free");
	Attributes.GetString(Freeobj, "Value", freepos);
	GetCoord(freepos, colf, rowf);

	IF (row = rowf) & (col # colf) THEN
		IF col < colf THEN
			WHILE col < colf DO SlideTile(row, colf, Right); DEC(colf) END
		ELSE
			WHILE col > colf DO SlideTile(row, colf, Left); INC(colf) END
		END;
		obj := GetObj(colf, row);
		Attributes.SetString(obj, FieldName, "");
		Attributes.SetInt(obj, "Color", 0);
		Links.SetLink(obj, "Look", NIL);
		Gadgets.Update(obj);
		Attributes.SetString(Freeobj, "Value", name);
		Gadgets.Update(Freeobj)
	ELSIF (row # rowf) & (col = colf) THEN
		IF row < rowf THEN
			WHILE row < rowf DO SlideTile(rowf, col, Down); DEC(rowf) END
		ELSE
			WHILE row > rowf DO SlideTile(rowf, col, Up); INC(rowf) END
		END;
		obj := GetObj(col, rowf);
		Attributes.SetString(obj, FieldName, "");
		Attributes.SetInt(obj, "Color", 0);
		Links.SetLink(obj, "Look", NIL);
		Gadgets.Update(obj);
		Attributes.SetString(Freeobj, "Value", name);
		Gadgets.Update(Freeobj)
	END
END Play;

BEGIN
	RandomNumbers.InitSeed(Oberon.Time())
END PuzzleXY.

System.Free PuzzleXY ~

Puzzle 15 info on the Web:
"http://www.org2.com/jaap/puzzles/fifteen.htm"

User instructions:
------
Compiler.Compile ButtonField.Mod PuzzleXY.Mod PuzzleLayLa.Mod ~
PuzzleLayLa.CreateBoard width height ~  Two integers which you choose
A text document viewer PuzzleXY.Desc is opened
		(This is not really necessary but is meant to visualize the LayLa description produced. )
Execute the first line: LayLa.OpenAsDoc
Scramble the board
Reorder the board with MM key

PuzzleXY.Mod works with any board dimensions. In fact PuzzleXY.Play works without that knowledge.
PuzzleLayLa.Mod constructs the board you fancy.

I am working o a version with pictures, of the same vein as Emil Zeller's Scramble.
------

To construct a game board of your size use the command PuzzleLayLa.CreateBoard width height ~

OR one of these fixed board size (4 x 4) desriptions appearing below:

LayLa.OpenAsDoc
{ This game board definition is parameterized. It uses the original Button gadget. }
(CONFIG
	(DEF Tile
		(CONFIG
			(DEF me "")
			(DEF cap "")
			(DEF mycolor 13)
			(NEW Button (w=60 h=60) (ATTR Name=me Caption=cap Led=FALSE Color=mycolor Cmd="PuzzleXY.Play"))
		)
	)

	(TABLE Panel (border=8 dist=0 cols=4) (ATTR Name="Panel" Locked=TRUE)
			(LINKS Model=(NEW String (ATTR Name="Free" Value="4.4")))
		(NEW Tile (PARAMS me = "1.1" cap="1"))
		(NEW Tile (PARAMS me="1.2" cap="2"))
		(NEW Tile (PARAMS me="1.3" cap="3"))
		(NEW Tile (PARAMS me="1.4" cap="4"))
		(NEW Tile (PARAMS me="2.1" cap="5"))
		(NEW Tile (PARAMS me="2.2" cap="6"))
		(NEW Tile (PARAMS me="2.3" cap="7"))
		(NEW Tile (PARAMS me="2.4" cap="8"))
		(NEW Tile (PARAMS me="3.1" cap="9"))
		(NEW Tile (PARAMS me="3.2" cap="10"))
		(NEW Tile (PARAMS me="3.3" cap="11"))
		(NEW Tile (PARAMS me="3.4" cap="12"))
		(NEW Tile (PARAMS me="4.1" cap="13"))
		(NEW Tile (PARAMS me="4.2" cap="14"))
		(NEW Tile (PARAMS me="4.3" cap="15"))
		(NEW Tile (PARAMS me="4.4" cap="" mycolor=0))
		(SPAN 1 4
		(NEW Button (w=[]) (ATTR Caption="Scramble" Cmd="PuzzleXY.Scramble"))
		)
	)
)
~

(* Successful attempt to use ButtonField.Mod from FiveToOne.Arc contribution. Useful for
	its large font digits. *)
LayLa.OpenAsDoc
(CONFIG
	(DEF Tile
		(CONFIG
			(DEF me "12")
			(DEF number "0")
			(DEF mycolor 13)
			(NEW ButtonField.New (w=60 h=60)
			(ATTR Name=me Value=number Font="Oberon14b.Scn.Fnt" Color=mycolor Cmd="PuzzleXY.Play"))
		)
	)

	(TABLE Panel (border=8 dist=0 cols=4) (ATTR Locked=TRUE)
			(LINKS Model=(NEW String (ATTR Name="Free" Value="4.4")))
		(NEW Tile (PARAMS me = "1.1" number="1"))
		(NEW Tile (PARAMS me="1.2" number="2"))
		(NEW Tile (PARAMS me="1.3" number="3"))
		(NEW Tile (PARAMS me="1.4" number="4"))
		(NEW Tile (PARAMS me="2.1" number="5"))
		(NEW Tile (PARAMS me="2.2" number="6"))
		(NEW Tile (PARAMS me="2.3" number="7"))
		(NEW Tile (PARAMS me="2.4" number="8"))
		(NEW Tile (PARAMS me="3.1" number="9"))
		(NEW Tile (PARAMS me="3.2" number="10"))
		(NEW Tile (PARAMS me="3.3" number="11"))
		(NEW Tile (PARAMS me="3.4" number="12"))
		(NEW Tile (PARAMS me="4.1" number="13"))
		(NEW Tile (PARAMS me="4.2" number="14"))
		(NEW Tile (PARAMS me="4.3" number="15"))
		(NEW Tile (PARAMS me="4.4" number="" mycolor=0))
		(SPAN 1 2
		(NEW Button (w=[]) (ATTR Caption="Scramble" Cmd="PuzzleXY.Scramble"))
		)
		(NEW Button (w=[]) (ATTR Caption="Set picture" Cmd="PuzzleXY.SetPicture"))
		(NEW Button (w=[]) (ATTR Caption="Set numbers" Cmd="PuzzleXY.SetNumbers"))
	)
)
~
