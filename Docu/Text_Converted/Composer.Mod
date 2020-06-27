(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Composer; (*JG 10.1.2000*)

(*graphic = { declaration | scene }.
  declaration = name "=" scene.
  scene = name | "{" { attribute }  { scene | command } "}".
  attribute = coord [ rot T ] [ scale s ] | linew w | linecol c | fillcol c.
  command = go d | goto pos | turn a | turnto A | line d | lineto pos | curveto pos pos pos | circle r | close | fill.
  pos = X Y | polar a d.
  T, s, w, c, r, X, Y, a, A, d = number.*)

  IMPORT In, Out, Oberon, Math, Turtle;

  CONST arc = Math.pi/180.0; min = 0.01;
    inval* = 0; op* = 1; id* = 2; int* = 3; real*=4; (*Scanner symbols*)
    scene = 0; circle = 1; filledcircle = 2; path = 3; closedpath = 4; filledpath = 5; (*object type*)
    line = 0; curve = 1; (*segment type*)
    group = 0; system = 1; (*scene type*)

  TYPE
    Scene = POINTER TO SceneDesc;

    Segment = POINTER TO SegDesc;
    SegDesc = RECORD
      next: Segment;
      type: INTEGER;
      X0, Y0, X1, Y1, X, Y: REAL
    END;

    Object = POINTER TO ObjDesc;
    ObjDesc = RECORD
      next: Object;
      type: INTEGER;
      X, Y, r: REAL;
      rot: REAL; scn: Scene;
      segs, lastSeg: Segment
    END;

    SceneDesc = RECORD
      type: INTEGER;
      objs, lastObj: Object; (*list of objects in scene*)
      segs, lastSeg: Segment; (*current path*)
      linew: REAL; linecol, fillcol: LONGINT; (*attributes*)
      rot, scale: REAL (*coords*)
    END;

    Declaration = POINTER TO DeclDesc;
    DeclDesc = RECORD
      next: Declaration;
      scn: Scene;
      name: ARRAY 32 OF CHAR
    END;

  VAR first: Declaration; pos: LONGINT; ch: CHAR;
    Done: BOOLEAN; sym: INTEGER; ival: LONGINT; rval: REAL; str: ARRAY 16 OF CHAR;

  (*Scanner*)

  PROCEDURE Scan;
    VAR i: INTEGER; neg: BOOLEAN; w: REAL;
  BEGIN
    WHILE In.Done & (ch <= " ") DO In.Char(ch); INC(pos) END;
    IF In.Done THEN
      IF ("a" <= ch) & (ch <= "z") OR ("A" <= ch) & (ch <= "Z") THEN
        str[0] := ch; i := 1; In.Char(ch); INC(pos);
        WHILE In.Done & ("a" <= ch) & (ch <= "z") OR ("A" <= ch) & (ch <= "Z") OR ("0" <= ch) & (ch <= "9") DO
          str[i] := ch; INC(i); In.Char(ch); INC(pos)
        END;
        str[i] := 0X;
        sym := id
      ELSE
        IF ch = "-" THEN In.Char(ch); INC(pos); neg := TRUE END;
        IF ("0" <= ch) & (ch <= "9") THEN
          sym := int; ival := ORD(ch) - ORD("0"); In.Char(ch); INC(pos);
          WHILE In.Done & ("0" <= ch) & (ch <= "9") DO
            ival := ival*10 + ORD(ch) - ORD("0"); In.Char(ch); INC(pos);
          END;
          rval := ival;
          IF ch = "." THEN
            sym := real; w := 1/10.0; In.Char(ch); INC(pos);
            WHILE In.Done & ("0" <= ch) & (ch <= "9") DO
              rval := rval + (ORD(ch) - ORD("0"))*w; w := w/10.0; In.Char(ch); INC(pos)
            END
          END;
          IF neg THEN ival := -ival; rval := -rval END
        ELSIF neg THEN str[0] := "-"; sym := op
        ELSE str[0] := ch; In.Char(ch); INC(pos); sym := op
        END
      END
    ELSE sym := inval
    END
  END Scan;

  PROCEDURE Err (msg: ARRAY OF CHAR);
  BEGIN Out.Int(pos, 1); Out.Char(" "); Out.String(msg); Out.Ln; Done := FALSE; Scan
  END Err;

  PROCEDURE OpenScanner;
  BEGIN In.Open; pos := Oberon.Par.pos; In.Char(ch); INC(pos); Done := TRUE; Scan
  END OpenScanner;

  (*Interpreter*)

  PROCEDURE Find (VAR name: ARRAY OF CHAR; VAR dcl: Declaration);
  BEGIN dcl := first;
    WHILE (dcl # NIL) & (dcl.name # name) DO dcl := dcl.next END
  END Find;

  PROCEDURE ReadInt (VAR i: LONGINT);
  BEGIN IF sym = int THEN i := ival; Scan ELSE Err("integer expected") END
  END ReadInt;

  PROCEDURE ReadNum (VAR x: REAL);
  BEGIN IF (sym = int) OR (sym = real) THEN x := rval; Scan ELSE Err("number expected") END
  END ReadNum;

  PROCEDURE NewObj (scn: Scene; type: INTEGER; VAR obj: Object);
  BEGIN NEW(obj); obj.type := type; scn.lastObj.next := obj; scn.lastObj := obj
  END NewObj;

  PROCEDURE Go (dir: REAL; VAR X, Y: REAL);
    VAR d: REAL;
  BEGIN ReadNum(d);
    X := X + Math.cos(dir)*d; Y := Y + Math.sin(dir)*d
  END Go;

  PROCEDURE Goto (VAR X, Y: REAL);
    VAR d, a: REAL;
  BEGIN
    IF (sym = id) & (str = "polar") THEN
      ReadNum(d); ReadNum(a); X := Math.cos(arc*a)*d; Y := Math.sin(arc*a)*d
    ELSE ReadNum(X); ReadNum(Y)
    END
  END Goto;

  PROCEDURE NewSeg (scn: Scene; type: INTEGER; VAR seg: Segment);
  BEGIN NEW(seg); seg.type := type; scn.lastSeg.next := seg; scn.lastSeg := seg
  END NewSeg;

  PROCEDURE Line (scn: Scene; dir: REAL; VAR X, Y: REAL);
    VAR d: REAL; seg: Segment;
  BEGIN
    IF scn.segs.next = NIL THEN scn.segs.X := X; scn.segs.Y := Y END;
    NewSeg(scn, line, seg);
    ReadNum(d); seg.X := X + Math.cos(dir)*d; seg.Y := Y + Math.sin(dir)*d;
    X := seg.X; Y := seg.Y
  END Line;

  PROCEDURE Lineto (scn: Scene; VAR X, Y: REAL);
    VAR d, a: REAL; seg: Segment;
  BEGIN
    IF scn.segs.next = NIL THEN scn.segs.X := X; scn.segs.Y := Y END;
    NewSeg(scn, line, seg); Goto(seg.X, seg.Y);
    X := seg.X; Y := seg.Y
  END Lineto;

  PROCEDURE Curveto (scn: Scene; VAR X, Y: REAL);
    VAR d, a: REAL; seg: Segment;
  BEGIN
    IF scn.segs.next = NIL THEN scn.segs.X := X; scn.segs.Y := Y END;
    NewSeg(scn, curve, seg); Goto(seg.X0, seg.Y0); Goto(seg.X1, seg.Y1); Goto(seg.X, seg.Y);
    X := seg.X; Y := seg.Y
  END Curveto;

  PROCEDURE EndPath (scn: Scene);
    VAR obj: Object;
  BEGIN
    IF scn.segs.next # NIL THEN
      NewObj(scn, path, obj); obj.X := scn.segs.X; obj.Y := scn.segs.Y;
      obj.segs := scn.segs.next; scn.segs.next := NIL
    END
  END EndPath;

  PROCEDURE Circle (scn: Scene; VAR X, Y: REAL);
    VAR obj: Object;
  BEGIN NewObj(scn, circle, obj); obj.X := X; obj.Y := Y; ReadNum(obj.r)
  END Circle;

  PROCEDURE CloseFig (scn: Scene; VAR X, Y: REAL);
  BEGIN
    IF scn.lastObj.type = path THEN scn.lastObj.type := closedpath
      ELSE Err("wrong use of close")
    END
  END CloseFig;

  PROCEDURE FillFig (scn: Scene; VAR X, Y: REAL);
  BEGIN
    IF (scn.lastObj.type = path) OR (scn.lastObj.type = closedpath) THEN scn.lastObj.type := filledpath
      ELSIF scn.lastObj.type = circle THEN scn.lastObj.type := filledcircle
      ELSE Err("wrong use of close")
    END
  END FillFig;

  PROCEDURE ReadScene (X, Y, dir: REAL; VAR scn: Scene);
    VAR a: REAL; dcl: Declaration; obj: Object;
  BEGIN NEW(scn);
    IF (sym = id) & (str = "coord") THEN Scan;
      scn.type := system; scn.rot := 0; scn.scale := 1;
      IF (sym = id) & (str = "rot") THEN Scan;
        IF (sym = int) OR (sym = real) THEN scn.rot := arc*rval; Scan
          ELSE Err("angle expected")
        END
      ELSIF (sym = id) & (str = "dir") THEN scn.rot := dir; Scan
      END;
      IF (sym = id) & (str = "scale") THEN Scan; ReadNum(a); scn.scale := a END;
      X := 0; Y := 0; dir := dir - scn.rot
    ELSE scn.type := group
    END;
    scn.linew := -1; scn.linecol := -1; scn.fillcol := -1;
    LOOP
      IF sym = id THEN
        IF str = "linew" THEN Scan; ReadNum(scn.linew)
        ELSIF str = "linecol" THEN Scan; ReadInt(scn.linecol)
        ELSIF str = "fillcol" THEN Scan; ReadInt(scn.fillcol)
        ELSE EXIT
        END
      ELSE EXIT
      END
    END;
    NEW(scn.objs); scn.lastObj := scn.objs; NEW(scn.segs); scn.lastSeg := scn.segs;
    LOOP
      IF sym = id THEN
        IF str = "go" THEN Scan; EndPath(scn); Go(dir, X, Y)
        ELSIF str = "goto" THEN Scan; EndPath(scn); Goto(X, Y)
        ELSIF str = "turn" THEN Scan; ReadNum(a); dir := dir + arc*a
        ELSIF str = "turnto" THEN Scan; ReadNum(a); dir := arc*a
        ELSIF str = "line" THEN Scan; Line(scn, dir, X, Y)
        ELSIF str = "lineto" THEN Scan; Lineto(scn, X, Y)
        ELSIF str = "curveto" THEN Scan; Curveto(scn, X, Y)
        ELSIF str = "circle" THEN Scan; EndPath(scn); Circle(scn, X, Y)
        ELSIF str = "close" THEN EndPath(scn); CloseFig(scn, X, Y); Scan
        ELSIF str = "fill" THEN EndPath(scn); FillFig(scn, X, Y); Scan
        ELSE Find(str, dcl);
          IF dcl # NIL THEN
            NewObj(scn, scene, obj); obj.X := X; obj.Y := Y; obj.rot := dir; obj.scn := dcl.scn; Scan
          ELSE Err("command expected"); EXIT
          END
        END
      ELSIF (sym = op) & (str[0] = "{") THEN
        NewObj(scn, scene, obj); obj.X := X; obj.Y := Y; obj.rot := 0; Scan; ReadScene(X, Y, dir, obj.scn)
      ELSE EXIT
      END
    END;
    EndPath(scn);
    IF (sym = op) & (str[0] = "}") THEN Scan ELSE Err('"}" expected') END
  END ReadScene;

  PROCEDURE ToUniverse (X, Y, rot, scale, x, y: REAL; VAR xU, yU: REAL);
  BEGIN
    xU := (Math.cos(rot)*x - Math.sin(rot)*y)*scale + X;
    yU := (Math.sin(rot)*x + Math.cos(rot)*y)*scale + Y
  END ToUniverse;

  PROCEDURE DisplayScene (X, Y, rot, scale: REAL; linew: REAL; linecol, fillcol: LONGINT; scn: Scene);
    VAR obj: Object; seg: Segment; x0U, y0U, x1U, y1U, xU, yU: REAL;
  BEGIN
    IF scale >= min THEN
      IF scn.linew >= 0 THEN linew := scn.linew END;
      IF scn.linecol >= 0 THEN linecol := scn.linecol END;
      IF scn.fillcol >= 0 THEN fillcol := scn.fillcol END;
      Turtle.SetWidth(linew); Turtle.SetLineCol(linecol); Turtle.SetFillCol(fillcol);
      obj := scn.objs.next;
      WHILE obj # NIL DO
        ToUniverse(X, Y, rot, scale, obj.X, obj.Y, xU, yU);
        IF (path <= obj.type) & (obj.type <= filledpath) THEN
          Turtle.BeginPath(xU, yU, obj.type - path); seg := obj.segs;
          WHILE seg # NIL DO ToUniverse(X, Y, rot, scale, seg.X, seg.Y, xU, yU);
            IF seg.type = line THEN Turtle.LineTo(xU, yU)
            ELSE
              ToUniverse(X, Y, rot, scale, seg.X0, seg.Y0, x0U, y0U);
              ToUniverse(X, Y, rot, scale, seg.X1, seg.Y1, x1U, y1U);
              (*Turtle.CurveTo(x0U, y0U, x1U, y1U, xU, yU)*)
            END;
            seg := seg.next
          END;
          Turtle.EndPath
        ELSIF (circle <= obj.type) & (obj.type <= filledcircle) THEN
          Turtle.Circle(xU, yU, obj.r, obj.type - circle + 1)
        ELSIF obj.type = scene THEN
          IF obj.scn.type = system THEN
            DisplayScene(xU, yU, rot + obj.rot + scn.rot, scale*scn.scale, linew, linecol, fillcol, obj.scn)
          ELSE (*obj.scn.type = group*) DisplayScene(X, Y, rot, scale, linew, linecol, fillcol, obj.scn)
          END;
          Turtle.SetWidth(linew); Turtle.SetLineCol(linecol); Turtle.SetFillCol(fillcol)
        END;
        obj := obj.next
      END
    END
  END DisplayScene;

  PROCEDURE Display*;
    VAR dcl, dcl0: Declaration; scn: Scene; X, Y, rot, scale, dir: REAL;
  BEGIN OpenScanner;
    WHILE (sym = id) OR (sym = op) & (str[0] = "{") DO
      IF sym = id THEN
        NEW(dcl); dcl.next := first; first := dcl; COPY(str, dcl.name); Scan; Scan;
        IF sym = id THEN Find(str, dcl0);
          IF dcl0 # NIL THEN dcl.scn:= dcl0.scn ELSE Err("declaration not found") END
        ELSIF (sym = op) & (str[0] = "{") THEN X := 0; Y := 0; dir := 0; Scan; ReadScene(X, Y, dir, dcl.scn)
        ELSE Err("declaration or scope expected")
        END
      ELSE (*str[0] = "{"*) X := 0; Y := 0; dir := 0; Scan; ReadScene(X, Y, dir, scn);
        IF Done THEN
          X := 0; Y := 0; rot := 0; scale := 1; Turtle.Open; DisplayScene(X, Y, rot, scale, 1, 15, 15, scn)
        END
      END
    END
  END Display;
  
END Composer.

System.Free Composer ~

Composer.Display

  quad = {coord linew 6 linecol 10 fillcol 1 lineto 100 0 lineto 100 -100 lineto 0 -100 lineto 0 0 fill}
  {coord linew 8 linecol 1 fillcol 5 goto 360 370 circle 100 fill {linew 10 linecol 2 fillcol 15 goto 440 440 circle 45 fill}}
  {coord linew 5 linecol 4 fillcol 3 goto 200 200 line 200 turn 120 quad line 200 turn 120 quad line 200 turn 120 quad fill} ~

Composer.Display

  star = {coord scale 0.3
    line 300 turn 144 star line 300 turn 144 star line 300 turn 144 star line 300 turn 144 star line 300 turn 144 star}

  { coord linew 2 linecol 1 goto 50 200 star }
  { coord linew 2 linecol 6 goto 250 150 star }
  { coord linew 2 linecol 3 goto 250 450 star }
  { coord linew 2 linecol 5 goto 50 500 star } ~

Composer.Display

  {coord linew 8 linecol 1 fillcol 5 goto 360 370 lineto 200 200 curveto 100 150 300 320 250 190 lineto 50 50} ~
  
  

