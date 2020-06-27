(* OBERON System 3

Copyright 1996 Team of the Institute of Computer Systems of ETH Zurich, ETH Center, CH-8092 Zurich,
e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon System 3 license contract.
The full text can be downloaded from ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/License.Text
or requested from the above-mentioned address.

Under the license terms dated it is in particular (a) prohibited to modify the interface of this module
in any way that disagrees with style or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Input;	(* pjm *)

(*
	Linux Native Oberon Input, p.matthias 1998

		2015-03-03	p.m.	first version for OLR on X11 and Framebuffer, derived from Display.Mod
		2015-03-10				fixed German characters in PollTTY
		2015-03-19	cleaned up, fixed PollX to make X11 working on MIPS & ARM again
		2015-03-26	prepared for copy&paste, added idle time when mouse button pressed
		2015-04-12	merged IdleFB and IdleX11, fixed Time for possible MIPS compiler bug 
		2015-04-28	reduced idle time to 10ms
		2015-04-29	removed wait in PollX
		2015-05-15	turning of scrollwheel in X11 mouse does not send button press events any more
		2015-05-25	changed PollMouseFB
		2015-05-29	changed X11 character mapping
		2015-06-05	input event support	( PollMouseFB, InitMouseFB ); use OMEVENT=/dev/input/eventX if correct device is not found
		2015-07-26	reading 32 bytes for events in PollX
		2015-12-01	PollX: Changed time arg. of Avail to 0 (otherwise pointer lags on MIPS)
		2016-08-24	Added HiDPI mode
		2017-04-16	using enumerate in InitMouseFB

see www.kernel.org/doc/Documentation/input/imput.txt and /usr/include/linux/input.h for information how to use input events (for mouse)

*)

(**
Module Input is responsible for event timing, mouse and keyboard input.
*)

IMPORT	Linux0, Kernel, FileDir, Display, SYSTEM;

CONST

	STDERR=2;
	KDSETMODE=4B3AH;

	TimeUnit* = Kernel.TimeUnit;	(** timer ticks per second ( fixed at 1000 for OLR).  *)

	SHIFT* = 0;  CTRL* = 1;  ALT* = 2;	(** for GetShiftState *)

(* X11 keystate *)
	Shift = 0; Lock = 1; Control = 2; NumLock=4; Win=6; Alt=7;
	CR = 0DX; LF = 0AX;

TYPE
(*
	PollMouse* = PROCEDURE (VAR keys: SET; VAR dx, dy, dz: INTEGER): BOOLEAN;	(** non-portable *)
	PollKeyboard* = PROCEDURE (VAR ch: CHAR; VAR keys: SET): BOOLEAN;	(** non-portable *)
*)
	TermIOs= RECORD
		ciflags, coflags, ccflags, clflags: SET;
		d: CHAR;
		ccc: ARRAY 23 OF CHAR;
	END;

	InputEvent=RECORD
				sec, usec: LONGINT;
				type, code: INTEGER;
				value: LONGINT;
	END;

	Event= RECORD
				code, detail: CHAR;
				sequence: INTEGER;
				time, a, b, c, d: LONGINT;
				ex, ey: INTEGER;
				f: LONGINT;
	END;
(* Events:

	KeyPress=2, KeyRelease=3, ButtonPress=4, ButtonRelease=5, MotionNotify=6, EnterNotify=7, LeaveNotify=8:
	a=root, b=event, c=child, d=rootx+100H*rooty, ex=eventx, xy=eventy, f=state+10000H*samescreen+1000000H*unused

	Expose=12:
	time=window, a=x+10000H*y, b=width+10000H*height

	PropertyNotify = 28
	time=window, a= Atom, b= timestamp, c=state
	
	SelectionClear=29:
	a=window, b=selection

	SelectionRequest=30:
	a=owner, b=requestor, c=selection, d=target, e=property, f=unused1

	SelectionNotify=31:
	a=requestor, b=selection, c=target, d=property, e= unused1, f=unused2

		KeyPress= RECORD
				code, detail: CHAR;
				sequence: INTEGER;
				time, root, event, child: LONGINT;
				rootx, rooty, eventx, eventy, state: INTEGER;
				samescreen, unused: CHAR;
		END;
		
		SelectionNotify= RECORD
				code, detail: CHAR;
				sequence: INTEGER;
				time, requestor, selection, target, property: LONGINT;
				unused1, unused2: LONGINT;
		END;
*)		
CONST
	CURRENTTIME=0;
	XAPRIMARY = 1;
	XASTRING = 31;
	None= 0;
	
VAR
	clip*: POINTER TO ARRAY OF CHAR;	(* clipboard *)
	dfd: LONGINT;	(* Display Filedescriptor (X11 socket or /dev/fb0 *)
	mouseX, mouseY: INTEGER;
	keyss, keyState: SET;
	err: LONGINT;
	cb1, cb2: LONGINT;
	buf: ARRAY 32 OF CHAR; (* input char buffer *)
	keywarn: BOOLEAN;

	fdset: SET;
	trace: BOOLEAN;

(* FB *)
	switching, onoberon: BOOLEAN;
	kbdfd: LONGINT;	(* keyboard fd *)
	mfd: LONGINT;	(* mouse fd *)
	oldtermios: TermIOs;

(* X11 *)
	CopyClip*, PasteClip*: PROCEDURE;	(* initialized in System *)
	x11, mmbe, iemouse: BOOLEAN;
	myProperty: LONGINT;

PROCEDURE WriteSH( str: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Kernel.WriteString( str); Kernel.WriteHex( i, 8); Kernel.WriteLn;
END WriteSH;

PROCEDURE WriteString( str: ARRAY OF CHAR);
BEGIN
	Kernel.WriteString( str); Kernel.WriteLn;
END WriteString;

PROCEDURE WriteErr( str: ARRAY OF CHAR);
VAR res, len: LONGINT;
BEGIN
	Kernel.WriteString( str); Kernel.WriteLn;
	len:=0;
	WHILE (str[len]#0X) & (len < LEN(str)-1) DO INC( len) END;
	str[len]:=0AX;
	res:=Linux0.Write0(STDERR, SYSTEM.ADR(str), len+1);
END WriteErr;

PROCEDURE Avail( fd: SET; usec: LONGINT): BOOLEAN;
TYPE	TimeVal= RECORD tvsec, tvusec: LONGINT END;
VAR num: LONGINT; timeout: TimeVal;
BEGIN
	timeout.tvsec:=0; timeout.tvusec:= usec;		(* don't block at all *)
	num:= Linux0.Select0( 16, SYSTEM.ADR( fd), 0, 0, SYSTEM.ADR( timeout));
	RETURN num>0;
END Avail;

PROCEDURE Idle( code: LONGINT);		(* code ignored *)
VAR x: BOOLEAN;
BEGIN
	x:=Avail( fdset, 10*1000)
END Idle;

PROCEDURE PollMouseFB;
VAR e: InputEvent;  res: LONGINT; b: ARRAY 4 OF CHAR;
BEGIN
	WHILE Avail( {mfd}, 0) DO
		IF iemouse THEN
			res:= Linux0.Read0( mfd, SYSTEM.ADR( e), SIZE(InputEvent));
			IF e.type=1H THEN		(* EV_KEY *)
				IF e.value= 1 THEN	(* button press *)
					IF e.code=110H THEN INCL( keyss, 2);		(* left *)
					ELSIF e.code= 112H THEN INCL( keyss, 1); (* middle *)
					ELSIF e.code= 111H THEN INCL( keyss, 0);	(* right *)
					END;
				ELSIF e.value= 0 THEN	(* button release *)
					IF e.code= 110H THEN	EXCL( keyss, 2);	(* left *)
					ELSIF e.code= 112H THEN EXCL( keyss, 1); (* middle *)
					ELSIF e.code= 111H THEN EXCL( keyss, 0);	(* right *)
					END;
				END;
			ELSIF e.type=2H THEN	(* EV_REL *)
				IF e.code=0H THEN	(* relx *)
					INC(mouseX, SHORT(e.value));
				ELSIF e.code= 1H THEN 	(* rely *)
					INC(mouseY, SHORT(e.value));
				END;
			END;
		ELSE	(* PS/2 mouse interface *)
			res:= Linux0.Read0( mfd, SYSTEM.ADR( b), 3);
		keyss:=SYSTEM.VAL( SET, LONG( ORD( b[0]) DIV 2 MOD 4 + ORD( b[0])  MOD 2*4));
			INC(mouseX,ORD(b[1])-ORD(b[0]) DIV 16 MOD 2 *256);
			DEC(mouseY, ORD(b[2])-ORD(b[0]) DIV 32 MOD 2 *256);
		END;
	END;
END PollMouseFB;

PROCEDURE ReadChar( VAR ch: CHAR);
BEGIN
	IF Linux0.Read0( kbdfd, SYSTEM.ADR(ch), 1)#1 THEN ch:=0X END;
	IF trace THEN Kernel.WriteHex( ORD( ch), 3) END;
END ReadChar;

PROCEDURE PollTTY;
VAR ch, ch2: CHAR;
BEGIN
IF Avail( {kbdfd}, 0) THEN  ReadChar( ch);
	IF ( ch= 1BX) & Avail( {kbdfd}, 0) THEN
		ReadChar( ch);
		IF ( ch= "[") & Avail( {kbdfd}, 0) THEN 
			ReadChar( ch);
			IF ( ch>="A") & (ch<="D") THEN ch:= CHR( ORD(ch)+80H);
			ELSIF Avail( {kbdfd}, 0) THEN
				ReadChar(ch2);
				IF ch= "[" THEN 		(*F1..F5 *)
					CASE ORD( ch2) OF
						65: ch:=0A4X;
					| 66: ch:=0A5X;
					| 67: ch:= 0A6X;
					| 68: ch:= 0A7X;
					| 69: ch:= 0F5X;
					END
				ELSIF ch=CHR(49) THEN	(* F6..F8 *)
					ch:=CHR( 0F6H-55+ORD( ch2));
					ReadChar( ch2);	(* dummy *)
				ELSIF ch=CHR(50) THEN	(* F9, F10, F11, F12 *)
					ch:=CHR( 0F9H-48+ORD( ch2)-ORD( ch2) DIV 50);
					IF ch2=0F9X THEN (* SetColors *) END; (* hack to reset colormap too *)
					ReadChar( ch2);	(* dummy *)
				ELSE
					IF (ch="1")THEN ch:= 0A8X;		(* pos1*)
					ELSIF (ch="2")THEN ch:= 0A0X;	(* insert*)
					ELSIF (ch="3")THEN ch:= 0A1X;	(* del*)
					ELSIF (ch="4")THEN ch:= 0A9X;	(* end*)
					ELSIF (ch="5")THEN ch:= 0A2X;	(* p. up *)
					ELSIF (ch="6")THEN ch:= 0A3X;	(* p. down *)
					END;
				END;
			END;
		END;
	ELSIF (ch=0C3X) & Avail( {kbdfd}, 0) THEN
		ReadChar( ch);
		IF ch=0A4X THEN ch:="";		(* german keyboard *)
		ELSIF ch=0B6X THEN ch:="";
		ELSIF ch=0BCX THEN ch:="";
		ELSIF ch=084X THEN ch:= ""; (* CAP("");*)
		ELSIF ch=096X THEN ch:= ""; (* CAP("");*)
		ELSIF ch=09CX THEN ch:= ""; (* CAP("");*)
		ELSIF ch=09FX THEN ch:= ""; (* sz *)
		END;
	ELSIF ch=0AX THEN ch:= 0DX;
	END;
	IF ch#0X THEN
		buf[ cb2 MOD 32]:=ch;
		INC( cb2);
		IF trace THEN WriteSH("->", ORD(ch)) END;
	END;
END;
END PollTTY;

PROCEDURE InternAtom(): LONGINT;
VAR b: ARRAY 8 OF LONGINT; res: LONGINT;
BEGIN
	b[0]:=16+ 6*10000H;
	b[1]:= 14;
	SYSTEM.MOVE( SYSTEM.ADR( "OberonProperty"), SYSTEM.ADR(b[ 2]), 14);
	res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  24);
	res:=Linux0.Read0(dfd, SYSTEM.ADR(b),  32);
	IF trace THEN WriteSH("OberonProperty = ", b[2]) END;
	RETURN b[2];
END InternAtom;

PROCEDURE GetProperty( VAR event: Event);
VAR res: LONGINT; b: ARRAY 8 OF LONGINT;
BEGIN
	IF trace THEN
		Kernel.WriteString("GetProperty seq, win, atom, time, state"); 
		Kernel.WriteHex( event.sequence, 9	);
		Kernel.WriteHex( event.time, 9	);
		Kernel.WriteHex( event.a, 9	);
		Kernel.WriteHex( event.b, 9	);
		Kernel.WriteHex( event.c, 9	); Kernel.WriteLn;
	END;
	b[0]:=20+6*10000H;		(* GetProperty *)
	b[1]:= Display.wid;
	b[2]:= myProperty;		(* property *)
	b[3]:= 0;	(* any type *)
	b[4]:= 0;	(* offset; *)
	b[5]:= 8192;	(*length;*)
	res:=Linux0.Write0( dfd, SYSTEM.ADR(b), 24);
	res:=Linux0.Read0( dfd, SYSTEM.ADR(b), 32);
	IF b[1]>0 THEN
		NEW( clip, b[4]);
		res:=Linux0.Read0( dfd, SYSTEM.ADR( clip^), b[4]);
		IF res=b[4] THEN WriteString( clip^)
		ELSE WriteString( "selection failed")
		END;
	END;
END GetProperty;

PROCEDURE Copy*;
VAR b: ARRAY 4 OF LONGINT; res: LONGINT;
BEGIN
	IF x11 THEN
		b[0]:=22+4*10000H;	(* SetSelectionOwner *)
		b[1]:=Display.wid;
		b[2]:=XAPRIMARY;
		b[3]:=CURRENTTIME;
		res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  16);
	END;
END Copy;

PROCEDURE GetSelectionOwner(): LONGINT;
VAR b: ARRAY 8 OF LONGINT; res: LONGINT;
BEGIN
	b[0]:=23+2*10000H;
	b[1]:=XAPRIMARY;
	res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  8);
	res:=Linux0.Read0(dfd, SYSTEM.ADR(b),  32);
	RETURN b[2];
END GetSelectionOwner;

PROCEDURE Paste*;
VAR b: ARRAY 6 OF LONGINT; res: LONGINT;
BEGIN
	IF x11 THEN
		b[0]:=24+6*10000H;	(* ConvertSelection *)
		b[1]:=Display.wid;
		b[2]:=XAPRIMARY;
		b[3]:=XASTRING;
		b[4]:= myProperty;
		b[5]:=CURRENTTIME;
		res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  24);
	END;
END Paste;

PROCEDURE SendSelection(VAR event: Event); 
VAR res: LONGINT;
		e: ARRAY 11 OF LONGINT;
		p: ARRAY 6 OF LONGINT;
BEGIN
	e[0]:=	25+11*10000H;	(* SendEvent *)
	e[1]:=	event.b; (*Display.scn.root;*)
	e[2]:=	0;
	e[0+3]:= 31; (* SelectionNotify *)
	e[1+3]:= CURRENTTIME;
	e[2+3]:= event.b;	(*requestor *)
	e[3+3]:= XAPRIMARY;
	e[4+3]:= event.d;	(* target *)
	IF (event.c = XAPRIMARY)  & (event.d = XASTRING) THEN
		e[5+3] := event.ex + 10000H*event.ey;	(*property *)

		p[0]:=18+0*100H+(6+(LEN(clip^)+3) DIV 4)*10000H;	(* ChangeProperty *)
		p[1]:= event.b;	(*requestor*)
		p[2]:= event.ex + 10000H*event.ey;	(*property*)
		p[3]:= event.d; (* target*)
		p[4]:= 8;	(* format (bits) *)
		p[5]:= LEN(clip^);
		res:=Linux0.Write0(dfd, SYSTEM.ADR(p),  6*4);
		res:=Linux0.Write0(dfd, SYSTEM.ADR(clip^),  (LEN(clip^)+3) DIV 4*4);
	ELSE
		IF trace THEN WriteString("Failed: ") END;
		e[5+3] := None	(*property *)
	END;
	IF trace THEN 
		WriteString("SelectionRequest: "); WriteSH( "Time: ",event.time); 
		WriteSH( "owner: ",event.a); 	WriteSH( "requestor: ",event.b); 	WriteSH( "selection: ",event.c); 
		WriteSH( "target: ", event.d);	WriteSH( "property: ",event.ex+10000H*event.ey);  
	END;
	res:=Linux0.Write0(dfd, SYSTEM.ADR(e),  44);
END SendSelection; 

PROCEDURE ReceiveSelection (VAR event: Event);
BEGIN
	IF trace THEN
		WriteString("SelectionNotify: "); WriteSH( "Time: ", event.time); 
		WriteSH( "owner: ",event.a); 	WriteSH( "requestor: ",event.b); 	WriteSH( "selection: ",event.c); 
		WriteSH( "target: ", event.d);	WriteSH( "property: ",event.ex+10000H*event.ey); 
	END;
	IF (event.b = XAPRIMARY) & (event.d=myProperty) THEN
		GetProperty(event);
	END
END ReceiveSelection;

PROCEDURE PollX;
VAR
	detail, code, state, sym, h, i, res, w, sw: LONGINT;
	event: Event;
	c: CHAR;
BEGIN
	WHILE Avail( {dfd}, 0) DO
		res:=Linux0.Read0(dfd, SYSTEM.ADR(event),  32);
		IF res=32 THEN	
			code:= ORD(event.code) MOD 32;
			detail:= ORD( event.detail);
			IF code=2 THEN		(* KeyPress *)
				state:=event.f MOD 10000H;
				IF state MOD 8=2 THEN state:=1;
				ELSIF state MOD 8 =3 THEN state:=2;
				ELSIF ODD(state DIV 10H) & (detail>=4DH) & (detail<=5BH) THEN state:=1;	(* Num-Lock *)
				ELSIF ODD(state DIV 80H) THEN state:= 4;
				ELSIF state>=7 THEN  WriteSH("X11: event.state: ", event.f ); state:= state MOD 8;
				END;
				sym:=Display.X11GetSym(detail, state);
				IF trace THEN 
					Kernel.WriteString("detail: "); Kernel.WriteHex(detail, 8); Kernel.WriteString(" symbol: "); Kernel.WriteHex( sym, 8);  WriteSH(" state: ", event.f);
				END;
				c:= CHR( sym MOD 100H);
				IF detail=024H THEN c:=0DX;	(* cr (enter) *)
				ELSIF detail= 6FH THEN c:=0C1X;	(* ^ *)
				ELSIF detail= 71H THEN c:=0C4X;	(* <- *)
				ELSIF detail= 74H THEN c:=0C2X;	(* v *)
				ELSIF detail= 72H THEN c:=0C3X;	(* -> *)
				ELSIF (detail=25H) OR (detail=69H) THEN
					INCL( keyState, Control); c:=0X;
					IF mmbe THEN	(* middle mouse button emulation *)
						INCL( keyss, 1);		(* LCtrl middle mouse button emulation *)
					END;
				ELSIF sym=0FE52H THEN c:=5EX;		(* ^ *)
				ELSIF sym=0FE53H THEN c:= 7EX;		(*	ntilde	*)
				ELSIF sym=0FE03H THEN c:= 0X;		(*	Alt Gr	*)
				ELSIF sym >=0FF00H THEN
					c:=0X;
					sym:=sym MOD 100H;
					IF sym=063H THEN c:=0A0X;	(* ins *) END;
					IF sym=050H THEN c:=0A8X;	(* home *) END;
					IF sym=055H THEN c:=0A2X;	(* pg-up *) END;
					IF sym=0FFH THEN c:=0A1X;	(* del-key *) END;
					IF sym=057H THEN c:=0A9X;	(* end *) END;
					IF sym=056H THEN c:=0A3X;	(* pg-down *) END;
							
					IF sym=008H THEN c:=7FX;	(* backspace *) END;
					IF sym=01BH THEN c:=0A5X;	(* Esc=1BX, Oberon.Neutralise=0A5X *) END;
					IF sym=009H THEN c:= 09X;	(* Tab *) END;

					IF sym DIV 2=0BEH DIV 2 THEN c:=CHR(0A4H+sym MOD 2);	(* F1, F2 *) END;
					IF sym DIV 2=0C0H DIV 2 THEN c:=CHR(0A6H+sym MOD 2);	(* F3, F4 *) END;
					IF (sym>=0C2H) & (sym<=0C9H) THEN										(* F5 ..F12 ; F7= redraw screen*)
						c:=CHR(sym-0C2H+0F5H)
					END;
			(* keypad *)
					IF sym=0AFH THEN c:="/";	(* / *) END;
					IF sym=0AAH THEN c:="*";	(* * *) END;
					IF sym=0ADH THEN c:="-";	(* - *) END;
					IF sym=0ABH THEN c:="+";	(* + *) END;
					IF sym=0ACH THEN c:=",";	(* , *) END;
					IF sym=09FH THEN c:=0A1X;	(* del *) END;
					IF (sym>=0B0H) & ( sym <=0B9H) THEN	(* 0..9 *)
						c:= CHR(sym MOD 16 + ORD("0"));
					END;
					IF sym=08DH THEN c:=0DX;	(* enter *) END;
					IF sym=097H THEN c:=0C1X;	(* ^ *) END;
					IF sym=096H THEN c:=0C4X;	(* <- *) END;
					IF sym=099H THEN c:=0C2X;	(* v *) END;
					IF sym=098H THEN c:=0C3X;	(* -> *)END;

				ELSE
					IF c=0DFX THEN c:= 96X END;		(*		*)
					IF c=0E1X THEN c:= 94X END;		(*	aacute	*)
					IF c=0E7X THEN c:= 93X END;		(*	ccedilla	*)
					IF c=0EFX THEN c:= 92X END;		(*	idiaeresis	*)
					IF c=0EBX THEN c:= 91X END;		(*	ediaeresis	*)
					IF c=0E9X THEN c:= 90X END;		(*	eacute	*)
					IF c=0F9X THEN c:= 8FX END;		(*	ugrave	*)
					IF c=0F2X THEN c:= 8EX END;		(*	ograve	*)
					IF c=0ECX THEN c:= 8DX END;		(*	igrave	*)
					IF c=0E8X THEN c:= 8CX END;		(*	egrave	*)
					IF c=0E0X THEN c:= 8BX END;		(*	agrave	*)
					IF c=0FBX THEN c:= 8AX END;		(*	ucircumflex	*)
					IF c=0F4X THEN c:= 89X END;		(*	ocircumflex	*)
					IF c=0EEX THEN c:= 88X END;		(*	icircimflex	*)
					IF c=0EAX THEN c:= 87X END;		(*	ecircumflex	*)
					IF c=0E2X THEN c:= 86X END;		(*	acircumflex	*)
					IF c= 0FCX THEN c:= 85X END;		(*	; must be 0xyz if c is  unsigned *)
					IF c= 0F6X THEN c:= 84X END;		(*		*)
					IF c= 0E4X THEN c:= 83X END;		(*		*)
					IF c= 0DCX THEN c:= 82X END;		(*		*)
					IF c= 0D6X THEN c:= 81X END;		(*		*)
					IF c= 0C4X THEN c:= 80X END;		(*		*)
				END;

				IF sym=0AFEH THEN Paste;	(* ctrl-v *)
				ELSIF c#0X THEN
					buf[ cb2 MOD 32]:= c;
					INC( cb2);
				END;
			ELSIF code= 3 THEN	(* KeyRelease *)
				IF (detail=25H) OR (detail=69H) THEN
					EXCL(keyState, Control);
					IF mmbe THEN EXCL( keyss, 1) END; (* LCtrl , RCtrl middle mouse button emulation*)
				END;
			ELSIF code= 4 THEN	(* ButtonPress *)
				IF detail<4 THEN
					INCL( keyss, 3- detail);
					IF detail=2 THEN mmbe:= FALSE END;
				END;
			ELSIF code= 5 THEN
				IF detail<4 THEN	(* ButtonRelease *)
					EXCL( keyss, 3- detail);
				END;
			ELSIF code= 6 THEN	(* MotionNotify, absolute values *)
				mouseX:= SHORT(ASH(event.ex, -Display.EZoom));
				mouseY:= SHORT(ASH(event.ey, -Display.EZoom));
			ELSIF code = 11 THEN	(* KeymapNotify*)
				WriteString("KeymapNotify");
			ELSIF code= 12 THEN	(* Expose *)
				w:= ASH((event.b)  MOD 10000H, -Display.EZoom);
				h:= ASH((event.b DIV 10000H) MOD 10000H, -Display.EZoom);
				IF w> Display.Width THEN w:= Display.Width END;
				IF h> Display.Height THEN h:= Display.Height END;
				Display.PutImage( ASH(event.a MOD 10000H, -Display.EZoom), Display.Height-h- ASH(event.a DIV 10000H, -Display.EZoom), w, h);
			ELSIF code=15 THEN 	(* VisibilityChange *)
			ELSIF code= 28 THEN		(* PropertyNotify *)
			ELSIF code = 29 THEN	(* SelectionClear *)
				WriteString("ClearSelection");
(*				selection:=NIL;	*)
			ELSIF code= 30 THEN	(* SelectionRequest, SendSelection *)
				IF (CopyClip # NIL) & (event.a#event.b) THEN CopyClip;
					SendSelection( event);
					clip:=NIL;
				END;
			ELSIF code= 31 THEN	(* SelectionNotify, ReceiveSelection *)
				IF PasteClip# NIL THEN
					ReceiveSelection( event);
					PasteClip;
					clip:=NIL;
				END;
			ELSIF code=0 THEN	(* error *)
				IF err<32  THEN
					WriteSH("PollX: Received error no. ", detail);
					WriteSH("PollX: error. ", event.time);
					WriteSH("PollX: opcode. ", event.a);
					INC(err);
				END;
	(*			IF detail=0 THEN Kernel.Shutdown( 1) END; *)
			ELSE
				WriteSH("Event Error... ", code);
				WriteSH("Event detail... ", detail);
			END;
(*		ELSE
			WriteSH("Res Error... ", res);*)
		END;
(*	ELSE*)
(*		IF Avail( {dfd}, 0*1000) THEN END;	(* wait... *)*)
	END;
END PollX;

(* ---- Interface ---- *)
	
	(** Returns the number of keystrokes in the keyboard input buffer. *)
PROCEDURE Available*(): INTEGER;
BEGIN
	IF x11 THEN PollX()
	ELSE PollTTY()
	END;
	RETURN SHORT(cb2-cb1);
END Available;

(* GetMouseEvent - Read a mouse event *)

(** Reads the current mouse position x, y and the key state of the mouse buttons 
(also called keys). The mouse buttons are numbered from the right to the left as 
0, 1, 2 (i.e. 1 is the middle mouse button). For example, when the left and middle 
buttons are pressed, keys will be set to {1, 2}. *)

PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
BEGIN
	IF x11 THEN PollX
	ELSE PollMouseFB;
	END;
	IF mouseX>=Display.Width THEN mouseX:=Display.Width-1 END;
	IF mouseX<0 THEN mouseX:=0 END;
	IF mouseY>=Display.Height THEN mouseY:=Display.Height-1 END;
	IF mouseY<0  THEN mouseY:= 0 END;
	x:= (mouseX ); y:= (Display.Height-1-mouseY) ;
	keys:= keyss;
END Mouse;

(** Read a character from the keyboard buffer. Blocks if no character is available. *)
PROCEDURE Read*( VAR ch: CHAR);
BEGIN
	WHILE cb2<= cb1 DO
		Idle(0);
		IF x11 THEN PollX()
		ELSE PollTTY()
		END;
	END;
	ch:= buf[ cb1 MOD 32];
	INC( cb1);
END Read;

(** Returns the elapsed number of timer ticks from Oberon startup. *)
PROCEDURE Time*(): LONGINT;
BEGIN
	IF Kernel.break THEN Kernel.break := FALSE; HALT( 113) END;
	RETURN Kernel.GetTimer() (*MOD 80000000H MIPS compiler does not like this...*);
END  Time;

(** Restricts the extent of the mouse coordinates returned by Mouse. *)
PROCEDURE SetMouseLimits*(x, y, w, h: INTEGER);
BEGIN
END SetMouseLimits;

(** Return the state of the shift keys. *)
PROCEDURE KeyState*(VAR keys: SET);
BEGIN
	keys:= {}; 
	IF ~keywarn THEN WriteString("Warning: KeyState currently not implemented in Display."); keywarn:= TRUE END;
END KeyState;

(*
PROCEDURE *UnsafeBreak;
VAR note1, note2, note3: ARRAY 32 OF CHAR;
BEGIN
	note1 := "Warning: Interrupting a module";
	note2 := "may invalidate its invariants";
	note3 := "and make it unstable.";
	HALT(24)
END UnsafeBreak;
*)

PROCEDURE SwitchConHandler;
CONST VTRELDISP=5605H;
			VTAUTO=0;
			VTPROCESS=01H;
			VTACKACQ= 02H;
VAR res: LONGINT;
BEGIN
	IF switching THEN RETURN END;
	switching:= TRUE;
	IF onoberon THEN
		WriteString("switching to con");
		fdset:={};
		Display.SetClip( 0, 0, 0, 0);
		res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 0);	 (* text mode =0 *)
		res:=Linux0.IOCtl0( kbdfd, VTRELDISP, VTPROCESS);
		onoberon:=FALSE;
	ELSE
		WriteString("switching back to oberon");
		(* ack switch back, mmap framebuffer, restore framebuffer, grab mouse*)
		res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 1);	 (* graphics mode =1 *)
		res:=Linux0.IOCtl0( kbdfd, VTRELDISP, VTACKACQ);
		buf[cb2 MOD 32]:=0F7X;	(* F7, redraw display *)
		INC( cb2);
		Display.ResetClip;
		fdset:={kbdfd, mfd};
		onoberon:= TRUE;
	END;
	switching:= FALSE;
END SwitchConHandler;

PROCEDURE OpenMouse(name: ARRAY OF CHAR; time, date, size: LONGINT; VAR flags: SET);
BEGIN
	IF mfd<=0 THEN
		Kernel.WriteString( "Input: using "); Kernel.WriteString( name); Kernel.WriteLn;
		mfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(name), Linux0.ORDonly, 0);
	END;
END OpenMouse;

PROCEDURE InitMouseFB;
VAR res, i, l: LONGINT; s: ARRAY 32 OF CHAR; c: CHAR;
BEGIN
	Kernel.GetConfig("OMEVENT", s);
	IF s="" THEN
		s:="/dev/input/mice";
		mfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s), Linux0.ORDonly, 0);
		iemouse:=FALSE;
		IF mfd<0 THEN
			s:="/dev/input/by-id/*-event-mouse";
			FileDir.Enumerate(s, {}, OpenMouse);
			iemouse:=TRUE;
		END;
	ELSE
		mfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s), Linux0.ORDonly, 0);
		iemouse:=s[11]#"m";	(* /dev/input/mouseX|mice *)
	END;
	IF mfd<=0 THEN Kernel.WriteString( "Can't open "); Kernel.WriteString(s); Kernel.WriteLn; Kernel.Shutdown( 1) END;
END InitMouseFB;

PROCEDURE TTYtcSetAttr( VAR io: TermIOs);
CONST TCSETSFLUSH= 540EH;	(* MIPS: 5410H ?? ARM, X86: 5404H*)
VAR err: LONGINT;
BEGIN
	err:= Linux0.IOCtl0( kbdfd, Linux0.TCSETSF, SYSTEM.ADR( io));
	IF err#0 THEN WriteSH("Input.tcsetattr:", err) END;
END TTYtcSetAttr;

PROCEDURE TTYtcGetAttr( VAR io: TermIOs);
CONST TCGETS= 540DH;	(* MIPS: 540DH??; ARM, X86: 5401H *)
VAR err: LONGINT;
BEGIN
	err:= Linux0.IOCtl0( kbdfd, Linux0.TCGETS, SYSTEM.ADR( io));
	IF err#0 THEN WriteSH("Input.tcgetattr:", err) END;
END TTYtcGetAttr;

PROCEDURE InitKbdFB;
CONST (*x86, ARM: VMIN=6; MIPS: 4*)
	VTIME=5;
	ICANON= 2H;	ECHO= 8H;
	VTGETMODE=5601H;
	VTSETMODE=5602H;
	KDGETMODE=4B3BH;
	KDSKBMODE= 4B45H;
TYPE 	mode= RECORD mode, waitv: CHAR;
					relsig, acqsig: INTEGER;
					frsig: INTEGER
				END;
VAR kbdtermios: TermIOs; m: mode; res: LONGINT;
BEGIN
	onoberon:=TRUE;
	kbdfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR("/dev/tty"), Linux0.ORDWR, 0); 
	IF kbdfd<0 THEN
		WriteErr("Can't open /dev/tty");
		Kernel.Shutdown(1)
	END;
	res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 1);	 (* graphics mode =1 *)
	TTYtcGetAttr( oldtermios);
	kbdtermios:=oldtermios;
	kbdtermios.clflags := kbdtermios.clflags - SYSTEM.VAL( SET, ICANON + ECHO );
	kbdtermios.ccc[Linux0.VMIN] := 1X;
	kbdtermios.ccc[VTIME] := 0X;
	TTYtcSetAttr( kbdtermios);
	res:=Linux0.IOCtl0( kbdfd, VTGETMODE, SYSTEM.ADR( m));
	IF res#0 THEN WriteSH("Display.InitKbd: res= ", res) END;
(* console switching *)
	res:=Linux0.IOCtl0( kbdfd, KDSKBMODE, 3);	(* 0 raw , 1 xlate, 2 mediaraw, 3 unicode *)
	IF res#0 THEN WriteString("Display.InitKbdFB failed to set mode") END;
	m.mode:=1X;	(* was 1; VT_AUTO=0, VT_PROCESS=1; VT_ACKACQ=2 *)
	m.acqsig:= Linux0.SIGUSR1;
	m.relsig:= Linux0.SIGUSR2;
	res:= Linux0.IOCtl0( kbdfd, VTSETMODE, SYSTEM.ADR( m));
	res:= Linux0.SetSignal( Linux0.SIGUSR1, SwitchConHandler);
	res:= Linux0.SetSignal( Linux0.SIGUSR2, SwitchConHandler);
END InitKbdFB;

PROCEDURE CloseFB;
VAR res: LONGINT;
BEGIN
	res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 0);		(* text mode *)
	TTYtcSetAttr( oldtermios);
	res:= Linux0.Close0( kbdfd);
	res:= Linux0.Close0( mfd);
END CloseFB;

PROCEDURE Init;
VAR v: ARRAY 32 OF CHAR;
BEGIN
	keywarn:= FALSE; err:= 0; mmbe:= FALSE; switching:= FALSE;
	Kernel.GetConfig("TERM", v);
	x11:=v#"linux";
	Kernel.Idle:=Idle;
	IF x11 THEN
		myProperty:=-1;
		dfd:=Display.InitX11();
		fdset:={dfd};
		myProperty:=InternAtom();
	ELSE
		dfd:=Display.InitFB();
		InitMouseFB;
		InitKbdFB;
		fdset:={kbdfd, mfd};
		Kernel.InstallTermHandler( CloseFB);
	END;
END Init;

BEGIN
	trace:=Kernel.trace="Input";
	CopyClip:=NIL; PasteClip:=NIL;
	Init;
END Input.

(** Remarks:

1. Keyboard character codes correspond to the ASCII character set. 
Some other important codes are:

	F1, SETUP	0A4X
	F2, NEUTRALISE	0A5X
	F3, SCRL	0A6X	(used in Draw)
	F4, NOSCRL	0A7X	(used in Draw)
	UP ARROW	0C1X
	RIGHT ARROW	0C3X
	DOWN ARROW	0C2X
	LEFT ARROW	0C4X
	INSERT	0A0X

2. On some platforms, SetMouseLimits may not influence the physical movement 
of the mouse cursor itself, only the magnitude of the coordinates returned by Mouse.
*)
