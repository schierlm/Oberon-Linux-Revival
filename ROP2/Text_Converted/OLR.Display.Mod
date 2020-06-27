(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the systiopoiem and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Display;	(* pjm / January 2, 1999 as *)  (** portable, except where noted *)

(**
Module Display provides the display drawing primitives and the base type of the visual objects, called Frames.

To adjust window size, set OWIDTH=1023 and OHEIGHT=768 as environment variables ( start with "OWIDTH=1023 OHEIGHT=768 ./oberon" *
*)

(* SharkOberon display driver, as, 2.1.99 *)
(*
		2012-12-02	Pi Oberon Version started by Peter Matthias
		2014-03-27	added 16 bpp mode
		2014-03-27	X11 Version
		2014-04-01	re-implemented palette
		2014-04-03	fixed MouseX
		2014-04-21	cleaned up; moved to my own Pattern procedures; KeyStateX not implemented
		2014-04-27	aggressive sleeping; made PutImage safe
		2014-04-30	moved to my own CopyBlock procedures
		2014-05-01	fixed DisplayBlock; ignore clolor in invert mode
		2014-05-02	fixed clipping in ReplConst, DisplayBlock, fixed clipping procedures; removed line buffering in CopyBlock0, not tested well; 
								less agressive sleeping
		2014-05-07	using color mask of visual
		2014-05-23	fixed ReplConst for 16 Bit display depth
		2014-06-11	using fast MIT-SHM remove config, cleaned up kernel calls
		2014-06-22	added keypad characters; todo: add non-Numlock keys!
		2014-06-25	made default window size relative to screen size
		2014-07-06	fixed bug in invert mode of ReplConst in 16 bit
		2014-07-17	made Display working over TCP, see below
		2014-11-14	MIPS Linux Oberon Version
		2015-01-25	really fixed Shmat0
		new version called OLR.Display.Mod
		2015-02-19	shutdown when not connecting to xserver
		2015-02-20	added frambuffer driver, needs read access to "/dev/input/mice", read/write access  to "/dev/tty" and "/dev/fb0"
		2015-03-01	automatic framebuffer detection by Kernel.GetConv, made CopyBlock faster in replace mode, fixed ReadKeyX
		2015-03-03	using /dev/tty
		2015-03-18	cleaned up, made X11 working on ARM and MIPS again
		2015-03-23	using correct color mask in Frambuffer, implemented QueryExtensionX11; 
								evaluating OWIDTH and OHEIGHT environment variables for window size in X11
		2015-04-16	made SHM default, disable via OSHM=NO as environment variable
		2015-04-24	using MIT-MAGIC-COOKIE-1 authorization
		2015-04-25	TransferFormat, TransferBlock implemented (from Displays.Mod); UBottom defaults to 0; 
								allowed negative window sizes to be relative to X11 display size
		2015-04-30	fixed TransferBlock (made upside down)
		2015-05-30	changed GetAuth to use default .Xauthority file and use correct display inside .Xauthority
		2015-06-03	changed adata type in InitX11
		2015-06-05	using f.linelength
		2015-11-30	removed PatternPtr
		2016-03-01	made CopyBlock0 significantly faster on ARM32 in replace mode
		2016-04-19	GetAuth: don't mmap on unopened file
		2016-08-25	Added HiDPI mode (only X11 with SHM)
		2017-02-06	changed Zoom to EZoom for faster multiplication
		2017-04-17	GetAuth: check .Xauthority for size>4
		2017-05-29	fixed EZoom in PutImageX11, framebuffer size must not exceed heap size! 

		ToDo: change bytes to 2^bytes

ToDo:
		- remove UBottom and others...
		- test "ssh -X"	(X11 forwarding with xauth)
	
For different window size set OWIDTH and OHEIGHT envireonment variables.

Using Display over TCP: 

This X11 driver uses xhost authentification. For security reasons, this is not enabled as default for server connetctions over a networt. 
As an alternative method, use following procedure, also see 
"http://smorgasbord.gavagai.nl/2010/01/socat-access-your-x-servers-domain-socket-over-tcp/"	(seems not to be available any more...)

Display over ssh connection:
	on computer with X server, run:
	"socat TCP4-LISTEN:6000,reuseaddr,fork UNIX-CONNECT:/tmp/.X11-unix/X0"
	start ssh (-X option not needed)
	"ssh ci20@10.42.0.66"
	inside ssh, run olm or whatever the connected computer architecture is

*)

IMPORT Linux0, Kernel, Objects, SYSTEM;

CONST
	ETH = "ETH Oberon / ";

(* default window size *)

	defaultWidth=1280-16;	
	defaultHeight=1024-32;

	STDERR=2;

	BG* = 0; FG* = 15; (** Background, foreground color palette indices *)

	(** Drawing operation modes. *)
	replace* = 0;	(** replace destination. *)
	paint* = 1;	(** paint over destination.  *)
	invert* = 2;	(** invert destination. *)
	
	(** Message ids. *)
	remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (** ControlMsg id. *)
	reduce* = 0; extend* = 1; move* = 2; (** ModifyMsg id. *)
	display* = 0; state* = 1; (** ModifyMsg mode. *)
	screen* = 0; printer* = 1; (** DisplayMsg device *)
	full* = 0; area* = 1; contents* = 2; (** DisplayMsg id. *)
	get* = 0; set* = 1; reset* = 2; (** SelectMsg id. *)
	drop* = 0; integrate* = 1; (** ConsumeMsg id. *)
	
	(** TransferFormat() return values.  value DIV 8 = bytes per pixel.  portable, release >= 2.4*)
	unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;
	
	X11SOCKETPATH="/tmp/.X11-unix/X0";
		
(* domain in Socket *)	
	PFUNIX= 1;
	PFINET= 2;

(* old Oberon states
	ScrollLock = 0;  NumLock = 1;  CapsLock = 2;  LAlt = 3;  RAlt = 4;
	LCtrl = 5;  RCtrl = 6;  LShift = 7;  RShift = 8;  GreyEsc = 9;
*)

TYPE
	Color* = LONGINT;	(** portable, release >= 2.4 *)
	
	Pattern* = LONGINT;
(*
	PatternPtr = POINTER TO RECORD
		w, h: CHAR;
		pixmap: ARRAY 8192 OF CHAR
	END;
*)
	List = POINTER TO ListDesc;
	ListDesc = RECORD
		next: List;
		data: POINTER TO ARRAY OF CHAR;
	END;

	Frame* = POINTER TO FrameDesc;	(** Base type of all displayable objects. *)
	FrameDesc* = RECORD (Objects.ObjDesc)
		next*, dsc*: Frame;	(** Sibling, child pointers. *)
		X*, Y*, W*, H*: INTEGER	(** Coordinates. *)
	END;

	FrameMsg* = RECORD (Objects.ObjMsg)	(** Base type of messages sent to frames. *)
		F*: Frame; (** Message target, NIL for broadcast. *)
		x*, y*: INTEGER;	(** Message origin. *)
		res*: INTEGER	(** Result code: <0 = error or no response, >=0 response. *)
	END;

	ControlMsg* = RECORD (FrameMsg)
		id*: INTEGER	(** remove, suspend, restore. *)
	END;

	ModifyMsg* = RECORD (FrameMsg)	(** Change coordinates in container frame. *)
		id*: INTEGER;	(** reduce, extend, move. *)
		mode*: INTEGER;	(** Modes display, state. *)
		dX*, dY*, dW*, dH*: INTEGER;	(** Change from old coordinates (delta). *)
		X*, Y*, W*, H*: INTEGER	(** New coordinates. *)
	END;

	DisplayMsg* = RECORD (FrameMsg)	(** Display a frame, a part of it or its contents. *)
		device*: INTEGER;	(** screen, printer *)
		id*: INTEGER;	(** full, area, contents. *)
		u*, v*, w*, h*: INTEGER	(** Area to be restored. *)
	END;

	LocateMsg* = RECORD (FrameMsg)	(** Locate frame in display space. *)
		loc*: Frame;	(** Result. *)
		X*, Y*: INTEGER;	(** Absolute location. *)
		u*, v*: INTEGER	(** Relative coordinates in loc. *)
	END;

	SelectMsg* = RECORD (FrameMsg)	(** Selection control. *)
		id*: INTEGER;	(** get, set, reset. *)
		time*: LONGINT;	(** Time of selection. *)
		sel*: Frame;	(** Parent of selection. *)
		obj*: Objects.Object	(** List of objects involved, linked with slink. *)
	END;

	ConsumeMsg* = RECORD (FrameMsg)	(** Drop, integrate frames. *)
		id*: INTEGER;	(** drop, integrate. *)
		u*, v*: INTEGER;	(** Relative coordinates in destination when drop. *)
		obj*: Objects.Object	(** List of objects to be consumed, linked with slink. *)
	END;

	MsgProc* = PROCEDURE (VAR M: FrameMsg);

		SetupRes0= RECORD
				res, n: CHAR;
				major, minor: INTEGER;
				len: INTEGER;
		END;
		SetupRes1= RECORD
				rnr, ridbase, ridmask, motionbuffersize: LONGINT;
				lenvendor, maxreqlen: INTEGER;
				noscreens, noformats: CHAR;
				imgbyteorder, bmbitorder: CHAR;
				scanliunrunit, scanlinepad: CHAR;
				minkeycode, maxkeycode: CHAR;
				unused: LONGINT;
		END;

		Format= RECORD
				depth, bpp, slpad: CHAR;
				p0, p1, p2, p3, p4: CHAR;
		END;
		Screen= RECORD
				root*, dcolormap, wpixel, bpixel: LONGINT;
				cimasks: LONGINT;
				width, height: INTEGER;
				wmm, hmm: INTEGER;
				minimaps, maximaps: INTEGER;
				rvisual: LONGINT;
				bstores, sunders, rdepth, ndepth: CHAR;
		END;
		DepthT= RECORD
				depth, pad0: CHAR;
				nvisualtypes: INTEGER;
				pad: LONGINT;
		END;
		VisualT= RECORD
				id: LONGINT;
				class, bprgbvalue: CHAR;
				cmapentries: INTEGER;
				rmask, gmask, bmask: LONGINT;
				pad: LONGINT;
		END;
	
VAR
	Unit*: LONGINT; (** RasterUnit = Unit/36000 mm *)
	EZoom*: LONGINT;	(** 2^Zoom (for shift instead of slow mul) factor for HiDPI displays, currently only X11 with XShm *)
	Left*, (** Left margin of black-and-white screen. *)
	ColLeft*, (** Left margin of secondary display, often same as Left. *)
	Bottom*, (** Bottom of primary map. *)
	UBottom*, (** Bottom of offscreen area (negative), 0 if not supported. *)
	Width*, (** Display width. *)
	Height*: INTEGER; (** Display height. *)

	arrow*, 	(** Oberon cursor. *)
	star*, 	(** Star marker to mark documents and viewers. *)
	cross*, 	(** Insertion marker. *)
	downArrow*, 	(** Marker to indicate disk operation. *)
	hook*,	(** Text caret pattern. *)
	grey0*, grey1*, grey2*, ticks*, solid*: Pattern;	(** Simulated grey levels. *)
	Broadcast*: MsgProc;	(** Message broadcast to all frames in the display space. *) 
	
	clipX, clipY, clipXR, clipYT: LONGINT;	(* bottom left corner & top right corner, in Oberon coordinates *)
	pattern: List;

	bytes, displayFormat, linelength : LONGINT;
	palette: ARRAY 256 OF LONGINT;
	
(* X11 *)
	cid, pid, gcpid, wid*, iwid, gcid, shmseg: LONGINT;
	scn*: Screen;
	r1data: SetupRes1;

	ShmReqCode, BigReqCode, BigReqSize, shmid: LONGINT;

	x11Keymap: POINTER TO ARRAY OF ARRAY OF LONGINT;

	xkspkc: LONGINT;
	tcp, port: LONGINT;		(*	adr and port of x11 server over ssh	*)

	trace: BOOLEAN;
	xfd: LONGINT;	(* X11 socket or frambuffer fd *)
	fbuf: POINTER TO ARRAY OF CHAR;	(* buffer for X11 without SHM *)
	xrv: POINTER TO ARRAY OF LONGINT;	(* X11 request vector *)

(* common OLR	*)
	PutImage*: PROCEDURE( x, y, w, h: LONGINT);	(* argument are in X11 display pixel, not oberon! *)

	fbadr: LONGINT;									(* address of buffer*)
	rmr, rmw, gmr, gmw, bmr, bmw: LONGINT;	(* color mask right, color mask width *)

		DrawPattern: PROCEDURE(pat: Pattern; pX, pY: LONGINT;
										dX, dY: LONGINT;
										W, H, col, mode: LONGINT );
(*		DrawConst:  PROCEDURE( dadr, dw, W, H, col, mode: LONGINT);*)

PROCEDURE WriteSH( str: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Kernel.WriteString( str); Kernel.WriteHex( i, 8); Kernel.WriteLn;
END WriteSH;

PROCEDURE WriteErr( str: ARRAY OF CHAR);
VAR res, len: LONGINT;
BEGIN
	Kernel.WriteString( str); Kernel.WriteLn;
	len:=0;
	WHILE (str[len]#0X) & (len < LEN(str)-1) DO INC( len) END;
	str[len]:=0AX;
	res:=Linux0.Write0(STDERR, SYSTEM.ADR(str), len+1);
END WriteErr;

PROCEDURE Str2Int( str: ARRAY OF CHAR; default: INTEGER): INTEGER;
VAR i, j: INTEGER; neg: BOOLEAN;
BEGIN
	IF str#"" THEN
		i:=0; j:=0;
		neg:=str[0]="-";
		IF neg THEN j:=1 END;
		WHILE (j<LEN(str)) & (str[j]>="0") & (str[j]<="9") DO
			i:=i*10+ORD(str[j])-ORD("0");
			INC(j);
		END;
		IF neg THEN i:=-i END;
		RETURN i;
	END;		
	RETURN  default;
END Str2Int;

PROCEDURE PutImageFB( x, y, w, h: LONGINT);
END PutImageFB;

PROCEDURE PutImageX11( x, y, w, h: LONGINT);
VAR i, j, res, wl, adr, k: LONGINT;
	b: ARRAY 10 OF LONGINT;
BEGIN
	IF y<0 THEN INC(h, y); y:=0 END;
	wl:=(w*bytes+3) DIV 4*4;
	k:=ASH(h, EZoom)*wl DIV 4+7;
	IF k<=BigReqSize THEN
		IF (w>0) & (h>0) THEN
			y:=LONG(Height)-h-y;
			b[ 0]:= 72+2*100H;		(* BIG-REQUESTS *)
			b[ 1]:= ASH(h, EZoom)*wl DIV 4+7;
			b[ 2]:= wid;
			b[ 3]:= gcid;
			b[ 4]:= ASH(w+h*10000H, EZoom);
			b[ 5]:= ASH(x+y*10000H, EZoom);
			b[ 6]:= 0+ORD( scn.rdepth)*100H;
			xrv[0]:=SYSTEM.ADR(b);
			xrv[1]:=28;
			adr:=fbadr+ (x+ASH(y, EZoom)*Width)*bytes;
			i:=ASH(h, EZoom); j:=2; k:=0;
			REPEAT
				xrv[j]:= adr; INC(adr, Width*bytes);
				xrv[j+1]:= wl;
				INC(j, 2); DEC(i);
				IF j MOD 512=0 THEN res:=Linux0.Writev0( xfd, SYSTEM.ADR(xrv[k]), 256); k:=j END;
			UNTIL i=0;
			IF j#k THEN res:=Linux0.Writev0( xfd, SYSTEM.ADR(xrv[k]), j MOD 512 DIV 2) END;
		END;
	ELSE WriteSH("Warning: Size>BigReqSize: ", k);
	END;
END PutImageX11;

PROCEDURE PutImageX11SHM( x, y, w, h: LONGINT);
VAR res: LONGINT;	b: ARRAY 10 OF LONGINT;
BEGIN
	IF y<0 THEN INC(h, y); y:=0 END;
	IF (w>0) & (h>0) THEN
		b[ 0]:= ShmReqCode+3*100H+10*10000H;	(* XShmPutImage = 3 *)
		b[ 1]:= wid;
		b[ 2]:= gcid;
		b[ 3]:= ASH((Width+Height*10000H), EZoom);	(* total w h*)
		b[ 4]:= ASH(x+(Height-h-y)*10000H, EZoom);	(* src x y *)
		b[ 5]:= ASH(w+h*10000H, EZoom);	(* src w h *)
		b[ 6]:= b[4];	(* dst x y *)
		b[ 7]:= ORD(scn.rdepth)+2 (* ZPixmap=2 *)*100H ;		(* depth, format, sendevent, bpad *) 
		b[ 8]:= shmseg;		(* shmseg *)
		b[ 9]:= 0H;		(* offset *)
		res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 40);
	END;
END PutImageX11SHM;

(** Change color palette entry. 0 <= col, red, green, blue < 256. *)
PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);
BEGIN
	IF col>=0 THEN
		palette[col MOD 256] := ASH( ASH(red, rmw-8), rmr)+ ASH( ASH(green, gmw-8), gmr)+ ASH( ASH(blue, bmw-8), bmr)
	END;
END SetColor;

(** Retrieve color palette entry or color components of a true color value. 0 <= red, green, blue < 256. *)
PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
BEGIN
	IF col >= 0 THEN col := palette[col] END;
	red:=SHORT(ASH( ASH(col, -rmr), 8-rmw) MOD 256);
	green:=SHORT(ASH( ASH(col, -gmr), 8-gmw) MOD 256);
	blue:=SHORT(ASH( ASH(col, -bmr), 8-bmw) MOD 256);
END GetColor;

(** Return true color with specified components. 0 <= red, green, blue < 256.  Not all display regions support true color values, see TrueColor(). *)
PROCEDURE RGB*(red, green, blue: LONGINT): Color;	(** portable, release >= 2.4 *)
BEGIN
	RETURN MIN(LONGINT) + ASH( ASH(red, rmw-8), rmr)+ ASH( ASH(green, gmw-8), gmr)+ ASH( ASH(blue, bmw-8), bmr)
END RGB;

(** Returns the color palette depth for the specified display region. Typical values are 1, 4 and 8 (not larger). *)
PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
	RETURN  8
END Depth;

(** Returns TRUE iff the specified display region supports true color values. *)
PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;	(** portable, release >= 2.4 *)
BEGIN
	RETURN TRUE
END TrueColor;

(** Get the current clip rectangle. *)
PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN
	x := SHORT(clipX);  y := SHORT(clipY);
	w := SHORT(clipXR-clipX);  h := SHORT(clipYT-clipY)
END GetClip;
	
(** Set the new clipping rectangle. *)
PROCEDURE SetClip*(x, y, w, h: LONGINT);
BEGIN
	clipX := x;  clipY := y;
	clipXR := clipX+w;  clipYT := clipY+h
END SetClip;
	
(** Intersect with current clip rectangle resulting in a new clip rectangle. *)
PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
VAR x2, y2: LONGINT;
BEGIN
	x2 := x + w;  y2 := y + h;
	IF x > clipX THEN clipX := x END;
	IF y > clipY THEN clipY := y END;
	IF x2 < clipXR THEN clipXR := x2 END;
	IF y2 < clipYT THEN clipYT := y2 END
END AdjustClip;

(** Reset the current clipping rectangle to the whole display, including offscreen area. *)
PROCEDURE ResetClip*;
BEGIN
	clipX := 0;  clipY := UBottom;
	clipXR := Width;  clipYT := Height
END ResetClip;

PROCEDURE Clip( VAR x, y, w, h: LONGINT);
BEGIN
	IF x< clipX THEN INC( w, x-clipX); x:= clipX END;
	IF x+w> clipXR THEN w:= clipXR-x END;
	IF y< clipY THEN INC( h, y-clipY); y:= clipY END;
	IF y+h> clipYT THEN h:= clipYT-y END;
END Clip;

PROCEDURE CopyBlock0( sa, dsx, da, ddx, W, H, mode: LONGINT);		(* no line buffering necessary if done correctly... might not work if horizontally moved...*)
VAR x: LONGINT; c1, c2: INTEGER;
BEGIN
	IF mode= replace THEN
		INC(dsx, W); INC(ddx, W);	(* significantly faster on ARM32; WHY?? *)
		REPEAT
			SYSTEM.MOVE(sa, da, W); INC(sa, dsx); INC(da, ddx);		(* on x86 use SYSTEM.MOVE *)
			DEC( H);
		UNTIL H<=0;
	ELSIF mode= paint THEN
		REPEAT
			x:=W DIV 2;
			REPEAT
				SYSTEM.GET( sa, c1);
				SYSTEM.GET( da, c2);
				SYSTEM.PUT( da, SYSTEM.VAL( INTEGER, SYSTEM.VAL(SET, (c1)) + SYSTEM.VAL(SET, LONG(c2)) ));
				INC( sa, 2);
				INC( da, 2);
				DEC( x);
			UNTIL x<=0;
			INC( sa, dsx);
			INC( da, ddx);
			DEC( H);
		UNTIL H<=0;
	ELSE	(* mode= invert *)
		REPEAT
			x:=W DIV 2;
			REPEAT
				SYSTEM.GET( sa, c1);
				SYSTEM.GET( da, c2);
				SYSTEM.PUT( da, SYSTEM.VAL( INTEGER, SYSTEM.VAL(SET, LONG(c1)) /  SYSTEM.VAL(SET, LONG(c2)) ));
				INC( sa, 2);
				INC( da, 2);
				DEC( x);
			UNTIL x<=0;
			INC( sa, dsx);
			INC( da, ddx);
			DEC( H);
		UNTIL H<=0;
	END;
END CopyBlock0;

PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
VAR DX, DY, W, H: LONGINT;
BEGIN
	DX:= dx; DY:= dy; W:=w; H:=h;
	Clip( dx, dy, w, h);
	IF ( w>0) & ( h>0) THEN
		INC( sx, DX-dx);
		INC( sy,  DY-dy);
		IF ( sy>=dy) THEN
			CopyBlock0( fbadr+(ASH( linelength*( Height-1-sy), EZoom)+sx)*bytes, ( -w-linelength)*bytes, 
					fbadr+( ASH(linelength*( Height-1-dy), EZoom)+dx)*bytes, ( -w-linelength)*bytes, w*bytes, ASH(h, EZoom), mode);
		ELSE
			CopyBlock0( fbadr+( ASH(linelength*( Height-h-sy), EZoom)+sx)*bytes, (linelength-w)*bytes,
					fbadr+( ASH(linelength*( Height-h-dy), EZoom)+dx)*bytes, (linelength-w)*bytes, w*bytes, ASH(h, EZoom), mode);
		END;
		PutImage( dx, dy, w, h);
	END;
END CopyBlock;

PROCEDURE DrawPattern16( pat: Pattern; pX, pY: LONGINT;
										dX, dY: LONGINT;
										W, H, col, mode: LONGINT);
VAR si: CHAR; sj: INTEGER;
		sadr, dadr, pw: LONGINT;
		ex, sx1, mx, ey, my: LONGINT;
BEGIN
		dadr:= fbadr+(( Height- dY-1) *linelength+ dX)*2;
		SYSTEM.GET( pat, si);
		pw:= ( LONG( ORD( si))+7) DIV 8;
		sadr:= pat+2+ pY* pw;
		ey:=0;
		IF col >=0 THEN col:= palette[ col];
		ELSE col:= col MOD 10000H
		END;
		mx:= W+pX; my:= H+pY;
		IF mode#invert THEN
			REPEAT
				SYSTEM.GET(pat+1, si);
				INC( ey, LONG( ORD( si)));
				IF ey>my THEN ey:= my END;
				REPEAT
					sx1:= pX;
					ex:= 8;
					REPEAT
						SYSTEM.GET( sadr+ sx1 DIV 8 MOD pw, si);
						IF ex>mx THEN ex:= mx END;
						REPEAT
							IF sx1 MOD 8 IN SYSTEM.VAL( SET, ORD(si)) THEN SYSTEM.PUT( dadr, SYSTEM.VAL( INTEGER, col)) END;
							INC( sx1); INC( dadr, 2);
						UNTIL sx1>=ex;
						ex:= sx1 + 8;
					UNTIL sx1>=mx;
					DEC( dadr, (linelength+W)*2);
					INC( sadr, pw);
					INC( pY);
				UNTIL pY>=ey;
				sadr:= pat+2;
			UNTIL pY>=my;
		ELSE
			REPEAT
				SYSTEM.GET(pat+1, si);
				INC( ey, LONG( ORD( si)));
				IF ey>my THEN ey:= my END;
				REPEAT
					sx1:= pX;
					ex:= 8;
					REPEAT
						SYSTEM.GET( sadr+ sx1 DIV 8 MOD pw, si);
						IF ex>mx THEN ex:= mx END;
						REPEAT
							IF sx1 MOD 8 IN SYSTEM.VAL( SET, ORD(si)) THEN
								SYSTEM.GET( dadr, sj);
								(*	ignore col	*)
								SYSTEM.PUT( dadr, SYSTEM.VAL( INTEGER, -SYSTEM.VAL( SET, LONG(sj))));
							END;
							INC( sx1); INC( dadr, 2);
						UNTIL sx1>=ex;
						ex:= sx1 + 8;
					UNTIL sx1>=mx;
					DEC( dadr, (linelength+W)*2);
					INC( sadr, pw);
					INC( pY);
				UNTIL pY>= ey;
				sadr:= pat+2;
			UNTIL pY>=my;
		END;
END DrawPattern16;

PROCEDURE DrawPattern32( pat: Pattern; pX, pY: LONGINT;
										dX, dY: LONGINT;
										W, H, col, mode: LONGINT);
VAR si: CHAR; sj: SET;
		sadr, dadr, pw: LONGINT;
		ex, sx, mx: LONGINT; 
BEGIN
		SYSTEM.GET( pat, si);
		pw:= (ORD( si)+7) DIV 8;
		mx:= W+pX;
		IF col >=0 THEN col:= palette[ col MOD 256];
		ELSE col:= col MOD 1000000H
		END;
		IF mode#invert THEN
			REPEAT
				dadr:= fbadr+(( Height- dY- H) *linelength+ dX)*4;
				DEC( H);
				SYSTEM.GET( pat+1, si);
				sadr:= pat+2+ pw*((pY+H) MOD ORD( si));
				sx:= pX;
				REPEAT
					ex:= sx +8;
					IF ex> mx THEN ex:= mx END;
					SYSTEM.GET( sadr+ (sx DIV 8) MOD pw, si);
					REPEAT
						IF sx MOD 8 IN SYSTEM.VAL( SET, LONG(ORD(si))) THEN SYSTEM.PUT( dadr, col) END;
	(*					IF ODD(ASH( ORD(si), -(sx MOD 8))) THEN SYSTEM.PUT( dadr, col) END; *)
						INC( sx); INC( dadr, 4);
					UNTIL sx = ex;					
				UNTIL sx= mx;
			UNTIL H=0;
		ELSE
			REPEAT
				dadr:= fbadr+(( Height- dY- H) *linelength+ dX)*4;
				DEC( H);
				SYSTEM.GET( pat+1, si);
				sadr:= pat+2+ pw*((pY+H) MOD (ORD( si)));
				sx:= pX;
				REPEAT
					ex:= sx +8;
					IF ex> mx THEN ex:= mx END;
					SYSTEM.GET( sadr+ (sx DIV 8) MOD pw, si);
					REPEAT
						IF sx MOD 8 IN SYSTEM.VAL( SET, (ORD(si))) THEN
							SYSTEM.GET( dadr, sj);
(*	ignore col parameter
							SYSTEM.PUT( dadr, sj/( SYSTEM.VAL( SET, col))));
*)
							SYSTEM.PUT( dadr, -sj);
						END;
						INC( sx); INC( dadr, 4);
					UNTIL sx = ex;
				UNTIL sx=mx;
			UNTIL H=0;
		END;
END DrawPattern32;

PROCEDURE DrawPattern64( pat: Pattern; pX, pY: LONGINT;
										dX, dY: LONGINT;
										W, H, col, mode: LONGINT);
VAR si: CHAR; sj: SET;
		sadr, dadr, pw: LONGINT;
		ex, sx, mx: LONGINT; 
BEGIN
		SYSTEM.GET( pat, si);
		pw:= (ORD( si)+7) DIV 8;
		mx:= W+pX;
		IF col >=0 THEN col:= palette[ col MOD 256];
		ELSE col:= col MOD 1000000H
		END;
		IF mode#invert THEN
			REPEAT
				dadr:= fbadr+(2*( Height- dY- H) *linelength+ dX)*8;
				DEC( H);
				SYSTEM.GET( pat+1, si);
				sadr:= pat+2+ pw*((pY+H) MOD ORD( si));
				sx:= pX;
				REPEAT
					ex:= sx +8;
					IF ex> mx THEN ex:= mx END;
					SYSTEM.GET( sadr+ (sx DIV 8) MOD pw, si);
					REPEAT
						IF sx MOD 8 IN SYSTEM.VAL( SET, LONG(ORD(si))) THEN 
							SYSTEM.PUT( dadr, col); SYSTEM.PUT( dadr+4, col);
							SYSTEM.PUT( dadr+linelength*8, col); SYSTEM.PUT( dadr+4+linelength*8, col);
						END;
						INC( sx); INC( dadr, 8);
					UNTIL sx = ex;					
				UNTIL sx= mx;
			UNTIL H=0;
		ELSE
			REPEAT
				dadr:= fbadr+(2*( Height- dY- H) *linelength+ dX)*8;
				DEC( H);
				SYSTEM.GET( pat+1, si);
				sadr:= pat+2+ pw*((pY+H) MOD (ORD( si)));
				sx:= pX;
				REPEAT
					ex:= sx +8;
					IF ex> mx THEN ex:= mx END;
					SYSTEM.GET( sadr+ (sx DIV 8) MOD pw, si);
					REPEAT
						IF sx MOD 8 IN SYSTEM.VAL( SET, (ORD(si))) THEN
							SYSTEM.GET( dadr, sj); SYSTEM.PUT( dadr, -sj);
							SYSTEM.GET( dadr+4, sj); SYSTEM.PUT( dadr+4, -sj);
							SYSTEM.GET( dadr+linelength*8, sj); SYSTEM.PUT( dadr+linelength*8, -sj);
							SYSTEM.GET( dadr+linelength*8+4, sj); SYSTEM.PUT( dadr+linelength*8+4, -sj);
						END;
						INC( sx); INC( dadr, 8);
					UNTIL sx = ex;
				UNTIL sx=mx;
			UNTIL H=0;
		END;
END DrawPattern64;
	
(** Copy pattern pat in color col to x, y using operation mode. *)
PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
VAR	dx, dy, w1, h1: LONGINT; c: CHAR;
BEGIN
	SYSTEM.GET( pat, c);	w1:=ORD( c);
	SYSTEM.GET( pat+1, c);	h1:=ORD( c);
	dx:= x; dy:= y;
	Clip( dx, dy, w1, h1);
	IF ( w1>0) & ( h1>0) THEN
		DrawPattern( pat, ( dx-x), ( dy-y), dx, dy, w1, h1, col, mode);
		PutImage(dx, dy, w1, h1);
	END;
END CopyPattern;

(** Replicate pattern pat in color col into block x, y, w, h using operation mode, proceeding from left to right and from bottom to top, starting at lower left corner. The pattern origin is placed at px, py. *)
PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
VAR dx, dy: LONGINT; c, d: CHAR;
BEGIN
	SYSTEM.GET( pat, c);
	SYSTEM.GET( pat, d);
	dx:= x; dy:= y;
	Clip( dx, dy, w, h);
	IF ( w>0) & ( h>0) THEN
		DrawPattern( pat, ( px+dx-x*2) MOD ORD( c), ( py+dy-y*2) MOD ORD( d), dx, dy, w, h, col, mode);
		PutImage( dx, dy, w, h);
	END;
END FillPattern;

(** Like FillPattern, but the pattern origin is placed at 0, 0. *)
PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
BEGIN
	FillPattern(col, pat, 0, 0, x, y, w, h, mode);
END ReplPattern;

(** Block fill in color col and operation mode.  mode paint and replace are equivalent. *)
PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
VAR dst, w2, h2: LONGINT; cols: SET; coli: INTEGER;
BEGIN
	IF col >=0 THEN col:= palette[ col];
	ELSE col:= col MOD 1000000H
	END;
	IF x< clipX THEN INC( w, ( x-clipX)); x:= ( clipX) END;
	IF x+w>= clipXR THEN w:= ( clipXR-x) END;
	IF y< clipY THEN INC( h, ( y-clipY)); y:= ( clipY) END;
	IF y+h>= clipYT THEN h:= ( clipYT-y) END;
	h2:=h;
	IF (w>0) & (h>0) THEN
		dst:= fbadr+(ASH(LONG(Height)-h-y, EZoom)* linelength + x)*bytes;
		WHILE h>0 DO
			w2:= w;
			IF bytes=4 THEN
				IF mode = invert THEN
					WHILE w2>0 DO
						SYSTEM.GET(dst, cols); SYSTEM.PUT(dst, -cols);
		(*	ignore col			SYSTEM.PUT(dst, cols/ SYSTEM.VAL(SET, col));*)
						SYSTEM.PUT(dst, -cols);

						INC(dst, 4);
						DEC(w2);
					END
				ELSE
					WHILE w2>0 DO
						SYSTEM.PUT(dst, col);
						INC(dst, 4);
						DEC(w2);
					END;
				END
			ELSIF bytes=8 THEN
				IF mode = invert THEN
					WHILE w2>0 DO
						SYSTEM.GET( dst, cols); SYSTEM.PUT( dst, -cols);
						SYSTEM.GET( dst+4, cols); SYSTEM.PUT( dst+4, -cols);
						SYSTEM.GET( dst+linelength*8, cols); SYSTEM.PUT( dst+linelength*8, -cols);
						SYSTEM.GET( dst+linelength*8+4, cols); SYSTEM.PUT( dst+linelength*8+4, -cols);
						INC(dst, 8);
						DEC(w2);
					END
				ELSE
					WHILE w2>0 DO
						SYSTEM.PUT( dst, col);
						SYSTEM.PUT( dst+4, col);
						SYSTEM.PUT( dst+linelength*8, col);
						SYSTEM.PUT( dst+linelength*8+4, col);
						INC(dst, 8);
						DEC(w2);
					END;
				END
			ELSE	(* bytes=2 *)
				IF mode = invert THEN
					WHILE w2>0 DO
						SYSTEM.GET(dst, coli);
		(*				SYSTEM.PUT(dst, SYSTEM.VAL( INTEGER, SYSTEM.VAL(SET, LONG(coli))/ SYSTEM.VAL(SET, col)));*)
						SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, -SYSTEM.VAL(SET, LONG(coli))));
						INC(dst, 2);
						DEC(w2);
					END
				ELSE
					WHILE w2>0 DO
						SYSTEM.PUT(dst, SYSTEM.VAL( INTEGER,col));
						INC(dst, 2);
						DEC(w2);
					END;
				END
			END;
			INC( dst, (linelength-w)*bytes+linelength*(bytes DIV 8*8));
			DEC(h);
		END;
		PutImage( x, y, w, h2);
	END;
END ReplConst;
	
(** Place a dot of color col in operation mode at x, y. Effect equivalent to ReplConst with a block of size 1, 1. *)
PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
VAR dst: LONGINT;  s: SET; si: INTEGER;
BEGIN
	IF col >=0 THEN col:= palette[ col];
	ELSE col:= col MOD 1000000H
	END;
	IF (x >= clipX) & (x <= clipXR) & (y >= clipY) & (y <= clipYT) THEN
		dst := fbadr+((Height-y-1) * ASH(linelength, EZoom) + x)*bytes;
		IF mode = invert THEN
			IF bytes=4 THEN
				SYSTEM.GET(dst, s); 
				SYSTEM.PUT(dst, SYSTEM.VAL(SET, col) / s)
			ELSIF bytes=8THEN
				SYSTEM.GET( dst, s); s:=SYSTEM.VAL(SET, col) / s;
				SYSTEM.PUT( dst, s);
				SYSTEM.PUT( dst+4, s);
				SYSTEM.PUT( dst+linelength*8, s);
				SYSTEM.PUT( dst+linelength*8+4, s);
			ELSE
				SYSTEM.GET(dst, si); 
				SYSTEM.PUT(dst, SYSTEM.VAL( INTEGER, SYSTEM.VAL(SET, col) / SYSTEM.VAL(SET, LONG(si))))
			END
		ELSE
			IF bytes=4 THEN
				SYSTEM.PUT(dst, col)
			ELSIF bytes=8THEN
				SYSTEM.PUT( dst, col);
				SYSTEM.PUT( dst+4, col);
				SYSTEM.PUT( dst+linelength*8, col);
				SYSTEM.PUT( dst+linelength*8+4, col);
			ELSE
				SYSTEM.PUT(dst, SHORT(col))
			END
		END;
		PutImage( x, y, 1, 1);
	END;
END Dot;

(** Returns the dimensions of a pattern. *)
PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR  c: CHAR;
BEGIN
	SYSTEM.GET( pat, c);
	w:=ORD(c);
	SYSTEM.GET( pat+1, c);
	h:=ORD(c);
END GetDim;

(** Define a new pattern. *)
PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
VAR len, src, dest, i: LONGINT;  pl: List;
BEGIN
	len := (w+7) DIV 8;
	NEW(pl);
	NEW(pl.data, 4+len*h);
	pl.data[2]:=CHR(w);
	pl.data[3]:=CHR(h);
	dest := SYSTEM.ADR(pl.data[4]);
	i := 0;
	WHILE i < h DO SYSTEM.PUT(dest, image[i]); INC(dest, len);  INC(i) END;
	pl.next := pattern;  pattern := pl;	(* put in list to avoid GC *)
	RETURN SYSTEM.ADR(pl.data[2])
END NewPattern;
	
(** Return the TransferBlock format of a display region. *)
PROCEDURE TransferFormat*(x: LONGINT): LONGINT;	(** portable, release >= 2.4 *)
BEGIN
	RETURN displayFormat;
END TransferFormat;

(** Transfer a block of pixels in display format to (mode = set) or from (mode = get)  the display.  Pixels in the rectangular area are transferred from bottom to top and left to right.  
The pixels are transferred to or from buf, starting at ofs, and with line increment stride, which may be < 0. *)
PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);	(** portable, release >= 2.4 *)
VAR bufadr, buflow, bufhigh, dispadr, H, W: LONGINT; s: SET;
BEGIN
	IF w > 0 THEN
		w := w * bytes;	(* convert to bytes *)
		bufadr := SYSTEM.ADR(buf[ofs]);
(*		dispadr := fbadr + (((Height-y-h)* linelength)+x)*bytes;*)
		dispadr := fbadr + (ASH(((Height-y-1)* linelength), EZoom)+x)*bytes;

		IF h>= Height THEN h:=Height-1 END;
		CASE mode OF
			set:
				H:=h;
				IF EZoom=0 THEN
					WHILE h > 0 DO
						SYSTEM.MOVE(bufadr, dispadr, w);
						INC(bufadr, stride); DEC(dispadr, linelength*bytes);
						DEC(h)
					END;
				ELSIF EZoom=1 THEN
					WHILE h > 0 DO
						W:=0;
						REPEAT
							SYSTEM.GET(bufadr+W DIV 2, s);
							SYSTEM.PUT(dispadr+W, s); SYSTEM.PUT(dispadr+W+4, s);
							SYSTEM.PUT(dispadr+linelength*8+W, s); SYSTEM.PUT(dispadr+linelength*8+W+4, s);
							INC(W, 8);
						UNTIL w=W;
						INC(bufadr, stride); DEC(dispadr, linelength*16);
						DEC(h)
					END;
				END;
				PutImage( x, y, w DIV bytes, H);
			|get:
				buflow := SYSTEM.ADR(buf[0]); bufhigh := buflow + LEN(buf);
				IF EZoom=0 THEN
					WHILE h > 0 DO
						ASSERT((bufadr >= buflow) & (bufadr+w <= bufhigh));	(* index check *)
						SYSTEM.MOVE(dispadr, bufadr, w);
						INC(bufadr, stride); DEC(dispadr, linelength*bytes);
						DEC(h)
					END
				ELSIF EZoom=1 THEN
					WHILE h > 0 DO
						ASSERT((bufadr >= buflow) & (bufadr+w  DIV 2 <= bufhigh));	(* index check *)
						W:=0;
						REPEAT
							SYSTEM.GET(dispadr+W, s); 
							SYSTEM.PUT(bufadr+W DIV 2, s);
							INC(W, 8);
						UNTIL w=W;
						INC(bufadr, stride); DEC(dispadr, linelength*16);
						DEC(h)
					END;
				END;
		ELSE (* skip *)
		END
	END
END TransferBlock;

(** Change display mode. s is driver-specific. *)
PROCEDURE SetMode*(x: LONGINT; s: SET);	(** non-portable *)
BEGIN
END SetMode;

(* DisplayBlock0 - Display a line in replace mode. *)

PROCEDURE DisplayBlock0(src, dst, w: LONGINT);
VAR ch: CHAR;  s: SET; i: INTEGER;
BEGIN
	IF bytes=4 THEN
		WHILE w # 0 DO
			SYSTEM.GET(src, ch);
			SYSTEM.PUT(dst, palette[ORD(ch)]);
			INC(src );  INC(dst, 4);  DEC(w)
		END
	ELSIF bytes=8 THEN
		WHILE w # 0 DO
			SYSTEM.GET(src, ch);
			s:=SYSTEM.VAL( SET, palette[ORD(ch)]);
			SYSTEM.PUT(dst, s); SYSTEM.PUT(dst+4, s);
			SYSTEM.PUT(dst+linelength*8, s); SYSTEM.PUT(dst+linelength*8+4, s);
			INC(src );  INC(dst, 8);  DEC(w)
		END
	ELSE
		WHILE w # 0 DO
			SYSTEM.GET(src, ch);
			SYSTEM.PUT(dst, SHORT(palette[ORD(ch)]));
			INC(src);  INC(dst, 2);  DEC(w)
		END
	END;
END DisplayBlock0;

(* DisplayBlock2 - Display a line in invert mode. *)

PROCEDURE DisplayBlock2(src, dst, w: LONGINT); (* to be fixed *)
VAR s, t: SET;  left, right: LONGINT;
BEGIN
	IF EZoom=0 THEN
		left := dst MOD 4;
		DEC(dst, left);  DEC(src, left);  INC(w, left);
		right := w MOD 4;
		IF w < 4 THEN
			SYSTEM.GET(src, t);  SYSTEM.GET(dst, s);
			SYSTEM.PUT(dst, s / (t * {left*8..31} * {0..right*8-1}))
		ELSE	(* w >= 4 *)
			DEC(w, right);
			SYSTEM.GET(src, t);  SYSTEM.GET(dst, s);
			SYSTEM.PUT(dst, s / (t * {left*8..31}));
			INC(dst, 4);  INC(src, 4);  DEC(w, 4);
			WHILE w > 0 DO
				SYSTEM.GET(src, t);  SYSTEM.GET(dst, s);
				SYSTEM.PUT(dst, s / t);
				INC(dst, 4);  INC(src, 4);  DEC(w, 4)
			END;
			IF right > 0 THEN
				SYSTEM.GET(src, t);  SYSTEM.GET(dst, s);
				SYSTEM.PUT(dst, s / (t * {0..right*8-1}))
			END
		END
	END;
END DisplayBlock2;

(** Display a picture.  Used internally by Pictures module only. sx, sy  and dx, dy changed!*)
PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);	(** non-portable *)
VAR pw, pd, src, dst, h1 : LONGINT;
BEGIN
(* sX is DESTINATION *)
	IF sx< clipX THEN INC( w, sx-clipX); sx:= clipX END;
	IF sx+w> clipXR THEN w:= clipXR-sx END;
	IF sy< clipY THEN INC( h, sy-clipY); sy:= clipY END;
	IF sy+h> clipYT THEN h:= clipYT-sy END;
(* not clipping at source
	IF dx< clipX THEN INC( w, dx-clipX); dx:= clipX END;
	IF dx+w> clipXR THEN w:= clipXR-dx END;
	IF dy< clipY THEN INC( h, dy-clipY); dy:= clipY END;
	IF dy+h> clipYT THEN h:= clipYT-dy END;
*)
	h1:=h;
	IF (w > 0) & (h > 0) THEN
		pd := 0;  SYSTEM.GET(adr+4, SYSTEM.VAL(INTEGER, pd));
		IF pd = 8 THEN
			SYSTEM.GET(adr+8, pw);
			SYSTEM.GET(adr+12, src);
			INC(src, (dy+h-1)*pw + dx);	(* top left corner *)
			sy := Height-sy-h;	(* convert to screen coordinate *)
			dst := fbadr+(ASH(sy*linelength, EZoom) + sx)*bytes;
			IF mode = invert THEN
				REPEAT
					DisplayBlock2(src, dst, w);
					DEC(h);  DEC(src, pw);  INC(dst, ASH(linelength*bytes, EZoom))
				UNTIL h = 0
			ELSE
				REPEAT
					DisplayBlock0(src, dst, w);
					DEC(h);  DEC(src, pw);  INC(dst, ASH(linelength*bytes, EZoom))
				UNTIL h = 0
			END;
			PutImage( sx, (Height-sy-h1), w, h1);
		ELSE	(* depth not supported *)
			ReplConst(3, sx, sy, w, h, mode)
		END;
	END;
END DisplayBlock;

(** Return address of display located at x, or 0 if not supported. *)
PROCEDURE Map*(x: LONGINT): LONGINT;	(** non-portable *)
BEGIN
	RETURN fbadr
END Map;

(* Define standard patterns. *)
PROCEDURE CreatePatterns;
VAR image: ARRAY 16 OF SET;
BEGIN
	image[0] := {13};
	image[1] := {12..14};
	image[2] := {11..13};
	image[3] := {10..12};
	image[4] := {9..11};
	image[5] := {8..10};
	image[6] := {7..9};
	image[7] := {0, 6..8};
	image[8] := {0, 1, 5..7};
	image[9] := {0..2, 4..6};
	image[10] := {0..5};
	image[11] := {0..4};
	image[12] := {0..5};
	image[13] := {0..6};
	image[14] := {0..7};
	arrow := NewPattern(15, 15, image);
	
	image[0] := {0, 10};
	image[1] := {1, 9};
	image[2] := {2, 8};
	image[3] := {3, 7};
	image[4] := {4, 6};
	image[5] := {};
	image[6] := {4, 6};
	image[7] := {3, 7};
	image[8] := {2, 8};
	image[9] := {1, 9};
	image[10] := {0, 10};
	cross := NewPattern(11, 11, image); 
	
	image[0] := {6};
	image[1] := {5..7};
	image[2] := {4..8};
	image[3] := {3..9};
	image[4] := {2..10};
	image[5] := {5..7};
	image[6] := {5..7};
	image[7] := {5..7};
	image[8] := {5..7};
	image[9] := {5..7};
	image[10] := {5..7};
	image[11] := {5..7};
	image[12] := {5..7};
	image[13] := {5..7};
	image[14] := {};
	downArrow := NewPattern(11, 15, image);
	
	image[0] := {0, 4, 8, 12};
	image[1] := {};
	image[2] := {2, 6, 10, 14};
	image[3] := {};
	image[4] := {0, 4, 8, 12};
	image[5] := {};
	image[6] := {2, 6, 10, 14};
	image[7] := {};
	image[8] := {0, 4, 8, 12};
	image[9] := {};
	image[10] := {2, 6, 10, 14};
	image[11] := {};
	image[12] := {0, 4, 8, 12};
	image[13] := {};
	image[14] := {2, 6, 10, 14};
	image[15] := {};
	grey0 := NewPattern(16, 16, image);
	
	image[0] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[1] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[2] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[3] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[4] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[5] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[6] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[7] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[8] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[9] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[10] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[11] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[12] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[13] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[14] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[15] := {1, 3, 5, 7, 9, 11, 13, 15};
	grey1 := NewPattern(16, 16, image);
	
	image[0] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[1] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[2] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[3] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[4] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[5] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[6] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[7] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[8] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[9] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[10] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[11] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[12] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[13] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[14] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[15] := {2, 3, 6, 7, 10, 11, 14, 15};
	grey2 := NewPattern(16, 16, image);
	
	image[0] := {0..2, 8..11};
	image[1] := {0..2, 7..10};
	image[2] := {0..2, 6..9};
	image[3] := {0..2, 5..8};
	image[4] := {0..2, 4..7};
	image[5] := {0..6};
	image[6] := {0..5};
	image[7] := {0..4};
	image[8] := {0..3};
	image[9] := {0..2};
	image[10] := {0, 1};
	image[11] := {0};
	hook := NewPattern(12, 12, image);
	
	image[0] := {7};
	image[1] := {7};
	image[2] := {2, 7, 12};
	image[3] := {3, 7, 11};
	image[4] := {4, 7, 10};
	image[5] := {5, 7, 9};
	image[6] := {6..8};
	image[7] := {0..6, 8..14};
	image[8] := {6..8};
	image[9] := {5, 7, 9};
	image[10] := {4, 7, 10};
	image[11] := {3, 7, 11};
	image[12] := {2, 7, 12};
	image[13] := {7};
	image[14] := {7};
	star := NewPattern(15, 15, image);
	
	image[0] := {};
	image[1] := {};
	image[2] := {0};
	image[3] := {};
	image[4] := {};
	image[5] := {};
	image[6] := {};
	image[7] := {};
	image[8] := {};
	image[9] := {};
	image[10] := {};
	image[11] := {};
	image[12] := {};
	image[13] := {};
	image[14] := {};
	image[15] := {};
	ticks := NewPattern(16, 16, image);
	
	image[0] := -{};
	image[1] := -{};
	image[2] := -{};
	image[3] := -{};
	image[4] := -{};
	image[5] := -{};
	image[6] := -{};
	image[7] := -{};
	solid := NewPattern(16, 8, image)	
END CreatePatterns;

(* --------------------- X11 Initialization ---------------------------------*)

PROCEDURE Avail( fd: SET; usec: LONGINT): BOOLEAN;
TYPE	TimeVal= RECORD tvsec, tvusec: LONGINT END;
VAR num: LONGINT; timeout: TimeVal;
BEGIN
	timeout.tvsec:=0; timeout.tvusec:= usec;		(* don't block at all *)
	num:= Linux0.Select0( 16, SYSTEM.ADR( fd), 0, 0, SYSTEM.ADR( timeout));
	RETURN num>0;
END Avail;

PROCEDURE X11Err( n: LONGINT);
VAR b: ARRAY 8 OF LONGINT; i, res: LONGINT;
BEGIN
	IF Avail( {xfd}, 0) THEN
		res:=Linux0.Read0( xfd, SYSTEM.ADR(b), 32);
		WriteSH("ERROR: X11Err:", n);
		FOR i:=0 TO 7 DO
			WriteSH("X11Err:", b[i]);
		END;
	END;
END X11Err;

PROCEDURE QueryExtensionX11( name: ARRAY OF CHAR; VAR opcode: LONGINT);
VAR xr: ARRAY 32 OF CHAR; i, res:LONGINT; b: ARRAY 8 OF LONGINT;
BEGIN;
	xr[0]:= 62X; xr[1]:= 0X;	(* 62X=98D *)
	xr[2]:= CHR((LEN( name)+2) DIV 4+2); xr[3]:= 0X;
	xr[4]:= CHR(LEN( name)-1); xr[5]:= 0X;
	xr[6]:= 0X; xr[7]:= 0X;
	i:=0;
	REPEAT
		xr[8+i]:= name[i];
		INC(i);
	UNTIL i=LEN(name);
	res:=Linux0.Write0( xfd, SYSTEM.ADR(xr), ORD(xr[2])*4);
	res:=Linux0.Read0( xfd, SYSTEM.ADR(b), 32);
	opcode:= b[2] DIV 256 MOD 256;
	IF TRUE THEN
		Kernel.WriteHex(opcode, 8); Kernel.WriteChar( " "); Kernel.WriteString( name);
	END;
END QueryExtensionX11;

PROCEDURE OpenWindowX11;
VAR b: ARRAY 24 OF LONGINT; i, res: LONGINT; str: ARRAY 8 OF CHAR;
BEGIN
	iwid:= r1data.ridbase+11235H;
	pid:= iwid+1;	gcpid:=pid+1;
	cid:= gcpid+1;	wid:= cid+1;
	gcid:=wid+1;	shmseg:=gcid+1;

	QueryExtensionX11("BIG-REQUESTS", BigReqCode);
	IF BigReqCode=0 THEN
		Kernel.WriteString( " failed"); Kernel.WriteLn;
	ELSE
		b[ 0]:= BigReqCode+0*100H+1*10000H;
		res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 4);
		res:=Linux0.Read0( xfd, SYSTEM.ADR(b), 32);
		WriteSH(" size= ", b[2]);
		BigReqSize:=b[2];
	END;

(* needed create win for cursor pixmap *)
	b[ 0]:= 1+0*100H+8*10000H;
	b[ 1]:= iwid;
	b[ 2]:= scn.root;
	b[ 3]:= 0+0*10000H;
	b[ 4]:= 1+1*10000H;
	b[ 5]:= 0+2*10000H;
	b[ 6]:= 0;
	b[ 7]:= 0;
	res:=Linux0.Write0(  xfd, SYSTEM.ADR(b), 32);
	X11Err(1);

(* needed create pixmap for cursor *)
	b[ 0]:=53+ 1*100H+4*10000H;
	b[ 1]:= pid;
	b[ 2]:= iwid;
	b[ 3]:= 1+1*10000H;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 16);
	X11Err(2);
(*
(* create gc for cursor pixmap *)
	b[ 0]:= 55+4*10000H;
	b[ 1]:= gcpid;
	b[ 2]:= iwid;
	b[ 3]:= 0;
	res:=Kernel.Write0( xfd, SYSTEM.ADR(b), 16);
	WriteSH("create gc ", res);

(* ClearArea, draw cursor *)
	b[ 0]:= 61+4*10000H;
	b[ 1]:= iwid;
	b[ 2]:= 0+0*10000H;
	b[ 3]:= 1+1*10000H;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 16);
	WriteSH("create dc ", res);
*)
(* needed create cursor *)
	b[ 0]:= 93+8*10000H;
	b[ 1]:= cid;
	b[ 2]:= pid;
	b[ 3]:= pid;
	b[ 4]:= 0FFFFFFFFH;
	b[ 5]:= 0;
	b[ 6]:= 0FFFFFFFFH;
	b[ 7]:= 0;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 32);
	X11Err(3);

(* CreateWindow *)
	b[ 0]:= 1+ORD(scn.rdepth)*100H+10*10000H;
	b[ 1]:= wid;
	b[ 2]:= scn.root;
	b[ 3]:= 0;  (* x+y*10000H;*)
	b[ 4]:= ASH((Width+LONG(Height)*10000H), EZoom);
	b[ 5]:= 1+0*10000H;
	b[ 6]:= 0;			(*visual, was 0*)
	b[ 7]:= 4800H;	(* value-mask: was 4800H, Cursor=4000H, Event Mask=800H ToDo: AddBackgroundPixmap??*)
(*	b[ 8]:= 40804FH;	(* was 804FH  todo: EventMask *)*)
	b[ 8]:= 0804FH;
	b[ 9]:= cid;		(* was cid Cursor , 0=default cursor*)
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 40);
	X11Err(4);

(* ChangeProperty name Window *)
	b[ 0]:= 18+0*100H+13*10000H;
	b[ 1]:= wid;
	b[ 2]:= 39;	(* WM_NAME *)
	b[ 3]:= 31;	(* String *)
	b[ 4]:= 8;
	b[ 5]:= 25;
	SYSTEM.MOVE( SYSTEM.ADR( Kernel.version), SYSTEM.ADR(b[ 6]), 19);
	SYSTEM.MOVE( SYSTEM.ADR( Linux0.ARCH), SYSTEM.ADR(b[ 10])+3, 6);

(*
	b[ 6]:= ORD("E")+ORD("T")*100H+ORD("H")*10000H+ORD(" ")*1000000H;
	b[ 7]:= ORD("O")+ORD("b")*100H+ORD("e")*10000H+ORD("r")*1000000H;
	b[ 8]:= ORD("o")+ORD("n")*100H+ORD(" ")*10000H+ORD("/")*1000000H;
	b[ 9]:= ORD(" ")+ORD(Linux0.VERSION[0])*100H+ORD(Linux0.VERSION[1])*10000H+ORD(Linux0.VERSION[2])*1000000H;
	b[10]:= ORD(Linux0.VERSION[3])+ORD(Linux0.VERSION[4])*100H+ORD(Linux0.VERSION[5])*10000H+ORD(Kernel.version[6])*1000000H;
	b[11]:= ORD(Kernel.version[7])+ORD(Kernel.version[8])*100H+ORD(Kernel.version[9])*10000H+0;
*)
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b),  52);
	X11Err(5);

(* Change Property disable resize *)
	b[ 0]:= 18+0*100H+24*10000H;
	b[ 1]:= wid;
	b[ 2]:= 40;	(* WM_Normal_Hints=40 *)
	b[ 3]:= 41;	(* WM_SIZE_Hints=41 *)
	b[ 4]:= 32;
	b[ 5]:= 18;
	b[ 6]:= 038H; (* location, programm specified size, minsize, maxsize *)
	b[ 7]:= 0;	(* b[7]..b[ 10] is ignored *)
	b[ 8]:= 0;
	b[ 9]:= ASH(Width, EZoom);
	b[ 10]:= ASH(Height, EZoom);
	b[ 11]:= b[ 9];
	b[12]:= b[10];
	b[13]:= b[ 9];
	b[14]:= b[10];
	b[ 15]:= 0;
	b[ 16]:= 0;
	b[ 17]:= 0;
	b[ 18]:= 0;
	b[ 19]:=0;
	b[ 20]:=0;
	b[ 21]:=0;
	b[ 22]:=0;
	b[ 23]:=0;
	res:=Linux0.Write0(xfd, SYSTEM.ADR(b),  96);
	X11Err(6);

(* CreateGC *)
	b[ 0]:= 55+4*10000H;
	b[ 1]:= gcid;
	b[ 2]:= wid;
	b[ 3]:= 0;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b),  16);
	X11Err(7);

(* use MIT-SHM if available *)
	Kernel.GetConfig("OSHM", str);
	ShmReqCode:=0;
	IF (str#"NO") & ( tcp=0) THEN QueryExtensionX11("MIT-SHM", ShmReqCode) END;
	IF ShmReqCode=0 THEN
		Kernel.WriteString( " failed");
		NEW( xrv, ASH(LONG(Height),  EZoom)*2+2);
		NEW( fbuf, ASH(LONG(Height), EZoom)* LONG(Width)*bytes);
		fbadr:=SYSTEM.ADR( fbuf[0]);
		PutImage:=PutImageX11;
	ELSE
		Kernel.WriteString( " success ");
		shmid:= Linux0.Shmget0( 0, LONG(Height)* Width*ASH(bytes, EZoom), 3FFH);
		fbadr:= Linux0.Shmat0(shmid, 0, 0);  
		b[ 0]:= ShmReqCode+1*100H+4*10000H;	(* X_ShmAttach = 1 *)
		b[ 1]:= shmseg; (*ShmSeg;*)
		b[ 2]:= shmid;
		b[ 3]:= 0;
		res:=Linux0.Write0( xfd, SYSTEM.ADR(b), 16);
		X11Err(8);
		PutImage:=PutImageX11SHM;
	END;
	Kernel.WriteLn;
	IF trace THEN WriteSH("shmid= ",  shmid); WriteSH("fbadr= ",  fbadr) END;

(* MapWindow *)
	b[ 0]:= 8+2*10000H;
	b[ 1]:= wid;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b),  8);
(*	generates exposure event: X11Err(9);*)

END OpenWindowX11;

PROCEDURE CloseWindowX11;	(* not used ? *)
VAR b: ARRAY 2 OF LONGINT;
	res: LONGINT;
BEGIN
(* Bell *)	
	b[ 0]:= 104+ 1*100H+1*10000H;
	res:=Linux0.Write0( xfd, SYSTEM.ADR(b),  4);
(* unmap *)
	b[0]:= 10+2*10000H;
	b[1]:= wid;
	res:=Linux0.Write0(  xfd, SYSTEM.ADR(b), 8);
	Kernel.WriteString("Closing Display"); Kernel.WriteLn;
END CloseWindowX11;

PROCEDURE CloseFB;
VAR res: LONGINT;
BEGIN
	Kernel.WriteString("Closing Display."); Kernel.WriteLn;
	res:= Linux0.Close0( xfd);
END CloseFB;

PROCEDURE MaskShift( mask: LONGINT; VAR right, width: LONGINT);
BEGIN
	right:=0;
	ASSERT(mask>0);
	WHILE ~ODD( mask) DO
		INC( right); mask:=mask DIV 2;
	END;
	width:=0;
	WHILE ODD(mask) DO
		INC(width); mask:= mask DIV 2;
	END;
	IF trace THEN
		Kernel.WriteString("MaskShift"); Kernel.WriteHex( right, 9); Kernel.WriteHex( width, 9); Kernel.WriteLn;
	END
END MaskShift;

PROCEDURE InitFB*(): LONGINT;
CONST 
	FBIOGETVSCREENINFO= 4600H;
	FBIOPUTVSCREENINFO= 4601H;
	FBIOGETFSCREENINFO= 4602H;
TYPE 
	fbfixscreeninfo= RECORD
		id: ARRAY 16 OF CHAR;
		smemstart: LONGINT;
		smemlen: LONGINT;
		type, typeaux, visual: LONGINT;
		xpanstep, ypanstep, ywrapstep: INTEGER;
		linelength: LONGINT;
		mmiostart, mmiolen: LONGINT;
		accel: LONGINT;
		reserved: ARRAY 3 OF INTEGER;
	END;
	fbbitfield= RECORD offset, length, msbright: LONGINT END;
	fbvarscreeninfo= RECORD
		xres, yres, xresvirtual, yresvirtual, xoffset, yoffset,
		bitsperpixel, grayscale: LONGINT;
		red, green, blue, transp: fbbitfield;
		nonstd, activate, height, width, accelflags: LONGINT;
		timing: ARRAY 9 OF LONGINT;
		reserved: ARRAY 6 OF LONGINT;
	END;
VAR res: LONGINT; v: fbvarscreeninfo; f: fbfixscreeninfo;
BEGIN
	xfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR("/dev/fb0"), Linux0.ORDWR, 0);
	IF xfd<=0 THEN
		WriteErr("Can't open '/dev/fb0'"); WriteSH("xfd: ",xfd);
		Kernel.Shutdown(0); RETURN 0
	END;
	Kernel.InstallTermHandler( CloseFB);
	res:=Linux0.IOCtl0( xfd, FBIOGETFSCREENINFO, SYSTEM.ADR( f));
	res:=Linux0.IOCtl0( xfd, FBIOGETVSCREENINFO, SYSTEM.ADR( v));
	rmr:=v.red.offset; rmw:=v.red.length;
	gmr:=v.green.offset; gmw:=v.green.length;
	bmr:=v.blue.offset; bmw:=v.blue.length;
	Width:=SHORT(v.xres); Height:=SHORT(v.yres); UBottom:= SHORT(v.yres-v.yresvirtual);
	fbadr:=Linux0.Mmap20( 0, f.smemlen, 3 (* prot: protRead+protWrite=3*), Linux0.MAPSHARED (* flags: MapShared=1*) , xfd, 0);
	IF (fbadr>-100) & (fbadr<0 ) THEN WriteSH("Can't mmap framebuffer device ", -fbadr); WriteSH(" f.smemlen=  ", f.smemlen);Kernel.Shutdown(0) END;
	IF v.bitsperpixel=16 THEN displayFormat:=color565; bytes:=2; DrawPattern:=DrawPattern16;
	ELSIF v.bitsperpixel=24 THEN displayFormat:=color8888; bytes:=4; DrawPattern:=DrawPattern32;
	ELSIF v.bitsperpixel=32 THEN displayFormat:=color8888; bytes:=4; DrawPattern:=DrawPattern32;
	ELSE WriteErr("Error: no FB visual currently supported");Kernel.Shutdown(0);
	END;
	linelength:=f.linelength DIV bytes;
	IF trace THEN
		Kernel.WriteInt(Width, 9); Kernel.WriteInt(Height, 9); Kernel.WriteInt(linelength, 9); Kernel.WriteInt(UBottom, 9); Kernel.WriteLn;
		WriteSH("mmap framebuffer device ", fbadr);
		WriteSH("displayFormat: ", displayFormat);
	END;
	RETURN xfd;
END InitFB;

(*
PROCEDURE GetAdr( s: ARRAY OF CHAR; VAR tcp, port: LONGINT);
VAR i, j: LONGINT; ch: CHAR;
BEGIN
	i:=0; tcp:=0;
	ch:=s[i];
	WHILE ch#" " DO
		j:=0;
		WHILE (ch >="0") & (ch<="9") & (i< LEN(s)) DO
			j:=j*10+ORD(ch)-ORD("0");
			INC(i);
			ch:=s[i];
		END;
		tcp:=tcp*256+j;
		IF ch="." THEN INC(i); ch:=s[i]; END;
	END;
	port:=0;
	INC(i); ch:=s[i];
	WHILE (ch >="0") & (ch<="9") & (i< LEN(s)) DO
		port:=port*10+ORD(ch)-ORD("0");
		INC(i);
		ch:=s[i];
	END;
	port:= 6000;
END GetAdr;
*)

PROCEDURE X11GetSym*(detail, state: LONGINT): LONGINT;
VAR sym: LONGINT;
BEGIN
	IF detail=ORD(r1data.minkeycode) THEN RETURN 0 END;
	RETURN x11Keymap[ detail-ORD(r1data.minkeycode), state];

(*
	sym:= (detail-ORD(r1data.minkeycode))*xkspkc;
	IF (state MOD 4 #0) & (sym#196H) & (sym#244H) THEN INC( sym) END;
	IF ODD(state DIV 128) THEN INC( sym, 4) END;	(* ALT was 2 *)

	RETURN x11Keymap[ sym, state];
*)
END X11GetSym;

PROCEDURE KeyboardMappingX11;
VAR b: ARRAY 8 OF LONGINT;
	res: LONGINT;
	i, j: LONGINT;
BEGIN
	b[ 0]:= 101+2*10000H;
	b[ 1]:= ORD(r1data.minkeycode)+(ORD(r1data.maxkeycode)-ORD(r1data.minkeycode))*100H;
(*	res:= Kernel.Write0( dfd, SYSTEM.ADR(b[0]), 8);*)
WHILE Avail({xfd}, 0) DO
	res:= Linux0.Read0( xfd, SYSTEM.ADR(b[0]), 32);
END;

	b[ 0]:= 101+2*10000H;
	b[ 1]:= ORD(r1data.minkeycode)+(ORD(r1data.maxkeycode)-ORD(r1data.minkeycode))*100H;
	res:= Linux0.Write0( xfd, SYSTEM.ADR(b[0]), 8);
	res:= Linux0.Read0( xfd, SYSTEM.ADR(b[0]), 32);

	xkspkc:= (b[0] DIV 100H) MOD 100H;
	IF b[1] DIV 10000H #0 THEN
		WriteErr("Internal X11 server error, exiting");
		Kernel.Shutdown( 1)
	END;		
	NEW( x11Keymap, b[1] DIV xkspkc , xkspkc);
	res:= Linux0.Read0( xfd, SYSTEM.ADR(x11Keymap^[0]), b[ 1]*4);
	IF trace THEN WriteSH("keysyms-per-keycode:", xkspkc) END;
(*
	FOR i:=0 TO (b[1] DIV xkspkc -1) DO
		FOR j:=0 TO xkspkc-1 DO
			Kernel.WriteHex( x11Keymap[i,j], 9);
		END;
		Kernel.WriteLn
	END
*)
END KeyboardMappingX11;

PROCEDURE CloseX11;
CONST IPCRMID=100H; (* ORI in libc for MIPS*)
VAR i, res: LONGINT;
	b: ARRAY 2 OF LONGINT;
BEGIN
	Kernel.WriteString("Closing Display."); Kernel.WriteLn;
	IF ShmReqCode#0 THEN
		b[0]:=ShmReqCode+2*100H+2*10000H;	(* X_ShmDetach = 2 *)
		b[1]:= shmseg; (*ShmSeg;*)
		res:=Linux0.Write0(xfd, SYSTEM.ADR(b),  8);

(*	Xdestroyimage	*)
		res:=Linux0.Shmdt0( fbadr);
		res:=Linux0.ShmCtl0( shmid, IPCRMID, 0);
	END;
	res:= Linux0.Close0( xfd);
END CloseX11;

PROCEDURE GetAuth(VAR s: ARRAY OF CHAR): BOOLEAN;
VAR t, t2: ARRAY 256 OF CHAR; disp1, disp2, fd, adr, i2, j: LONGINT; c, c2 : CHAR; n0, n1: SHORTINT; status: Linux0.Status;
BEGIN
	Kernel.GetConfig("XAUTHORITY", t);
	IF t="" THEN	(* use default *)
		Kernel.GetConfig("HOME", t);
		i2:=0;
		WHILE t[i2]#0X DO INC(i2) END;
		j:=0;
		t2:="/.Xauthority";
		WHILE t2[j]#0X DO t[i2]:=t2[j]; INC(i2); INC(j) END;
	END;
	Kernel.GetConfig("DISPLAY", t2);
	i2:=0;
	WHILE (t2[i2]#0X) & (t2[i2]#":") DO INC(i2) END;	(* skip adr *)
	disp1:=0; INC(i2);
	WHILE (t2[i2]>="0") & (t2[i2]<="9") DO disp1:=disp1*10+ORD(t2[i2])-ORD("0"); INC(i2) END;
	fd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(t), Linux0.ORDonly, 0);
	IF fd<=0 THEN Kernel.WriteString("Can't open Xauth file "); Kernel.WriteString(t); Kernel.WriteLn; RETURN FALSE END;
	j:=Linux0.FStat0( fd, SYSTEM.ADR(status));
	IF status.size<5 THEN RETURN FALSE END;
	IF trace THEN Kernel.WriteString("opening Xauth file: "); Kernel.WriteString(t); Kernel.WriteString(" disp1= "); Kernel.WriteInt( disp1, 1); Kernel.WriteLn END;
	adr:=Linux0.Mmap20( 0, 4096, 1 (* PROT_READ*), Linux0.MAPSHARED, fd, 0);
	IF adr MOD 1000H =0 THEN
		n0:=10;
		WHILE n0>0 DO
			INC(adr, 2);
			DEC(n0);
			REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
			INC(adr, LONG(ORD(c)));				(* skip name *)
			REPEAT INC(adr); SYSTEM.GET(adr, n1) UNTIL n1#0;
			disp2:=0;
			WHILE n1>0 DO INC(adr); SYSTEM.GET(adr, c); disp2:=disp2*10+ORD(c)-ORD("0"); DEC(n1) END;
			IF trace THEN	Kernel.WriteString("disp2= "); Kernel.WriteInt( disp2, 3); Kernel.WriteLn END;
			REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
			IF disp1=disp2 THEN
				IF c=12X THEN	(* MIT-MAGIC-COOKIE-1 *)	
					s[ 6]:= c;
					i2:=ORD(c);
					j:=12;
					REPEAT
						INC(adr);
						SYSTEM.GET(adr, c2);
						s[j]:= c2;
						INC(j); DEC(i2);
					UNTIL i2=0;
					REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
					s[ 8]:= c;
					i2:=ORD(c);
					j:= 32;
					REPEAT
						INC(adr);
						SYSTEM.GET(adr, c2);
						s[j]:= c2;
						INC(j); DEC(i2);
					UNTIL i2=0;
					adr:=Linux0.Munmap0(ASH( ASH(adr, -12),12), 4096);
					fd:=Linux0.Close0(fd);
					RETURN TRUE;
				END;
			ELSE
				INC(adr, LONG(ORD(c)));				(* skip protocol *)
				REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
				INC(adr, LONG(ORD(c)));				(* skip cookie *)
			END;
		END; (*WHILE*)
		adr:=Linux0.Munmap0( adr, 4096);
	ELSE
		Kernel.WriteString("Display.GetAuth mmap failed "); Kernel.WriteHex( -adr, 9); Kernel.WriteLn;
	END;
	fd:=Linux0.Close0(fd);
	RETURN FALSE;
END GetAuth; 	

PROCEDURE InitX11*(): LONGINT;
VAR	i, w, h, res, lw: LONGINT;
	sa1: Linux0.SockAddrUn;
	r0data: SetupRes0;
	format: Format;
	depth: DepthT;
	visual: VisualT;
	bdata: ARRAY 64 OF CHAR;
	adata: ARRAY 128 OF CHAR;
BEGIN
	Kernel.GetConfig("SSH_CONNECTION", bdata);
	IF bdata="" THEN
		xfd:=Linux0.Socket0( PFUNIX, Linux0.SOCKSTREAM, 0);		(* PFUNIX, PFINET, 800H = nonblock *)
		IF trace THEN WriteSH("Socket no.: ", xfd) END;
		IF xfd <=0 THEN Kernel.Shutdown(1) END;
		IF xfd >=16 THEN WriteSH("Error: fbfd>=16:", xfd); Kernel.Shutdown(1) END;
		sa1.pf:= PFUNIX;
		sa1.path:= X11SOCKETPATH;
		res:= Linux0.Connect0( xfd, SYSTEM.ADR( sa1), SIZE(Linux0.SockAddrUn));
	ELSE		(* we are on an SSH connection ... *)
		Kernel.WriteString(bdata); Kernel.WriteLn;
(*
		GetAdr(bdata, tcp, port);
*)
		tcp:=7F000001H;	(* 127.0.0.1, localhost *)
		port:=6010;
		WriteSH("tcp adr: ", tcp);
		WriteSH("tcp port ", port);

		xfd:=Linux0.Socket0( PFINET, Linux0.SOCKSTREAM, 0);		(* PFUNIX, PFINET, 800H = nonblock *)
		IF trace THEN WriteSH("Socket no.: ", xfd) END;
		IF (xfd<=0) OR (xfd >=16) THEN WriteSH("Error: fbfd>=16:", xfd); Kernel.Shutdown(1) END;
		sa1.pf:= PFINET;
		sa1.path[0]:=CHR(port DIV 256);
		sa1.path[1]:=CHR(port MOD 256);
		sa1.path[2]:=CHR(ASH(tcp, -24) MOD 256);
		sa1.path[3]:=CHR(ASH(tcp, -16) MOD 256);
		sa1.path[4]:=CHR(ASH(tcp, -8) MOD 256);
		sa1.path[5]:=CHR(tcp MOD 256);
		res:= Linux0.Connect0(xfd, SYSTEM.ADR( sa1),  16);
	END;
	IF res#0 THEN (*  Linux0.Connect failed *)
		WriteSH("X11: can't connect ", -res );
		Kernel.Shutdown(1);
	END;
	bdata[ 0]:= "l";	bdata[ 1]:= 0X;										(* pad  *)
	bdata[ 2]:= 0BX;	bdata[ 3]:=0X;	(* protocol major *)
	bdata[ 4]:=0X;	bdata[ 5]:=0X;		(* ptotocol minor *)
	bdata[ 6]:=0X;	bdata[ 7]:=0X;	(* auth protocol len *)
	bdata[ 8]:=0X;	bdata[ 9]:=0X;	(* auth prot data len *)
	bdata[ 10]:=0X;	bdata[ 11]:=0X;	(* pad *)
	IF GetAuth(bdata) THEN res:=Linux0.Write0( xfd, SYSTEM.ADR(bdata), 48);
	ELSE res:=Linux0.Write0( xfd, SYSTEM.ADR(bdata), 12);
	END;

	res:=Linux0.Read0( xfd, SYSTEM.ADR(r0data), 8);
	lw:=0;
	IF r0data.res = 1X(* success *) THEN
		res:=Linux0.Read0(  xfd, SYSTEM.ADR(r1data), 32);
		INC(lw, res);
		IF trace THEN
			WriteSH("r1data.maxreqlen: ", LONG(r1data.maxreqlen) MOD 10000H);
			WriteSH("r1data.lenvendor: ", r1data.lenvendor);
		END;
		res:=Linux0.Read0( xfd, SYSTEM.ADR(adata[0]), (r1data.lenvendor+3) DIV 4 *4);
		INC(lw, res);
		adata[r1data.lenvendor]:=0X;
		Kernel.WriteString( adata); Kernel.WriteLn;
		FOR i:= 1 TO ORD( r1data.noformats) DO
			res:=Linux0.Read0(xfd, SYSTEM.ADR(format),  SIZE(Format));
			INC(lw, res);
			IF trace THEN 
				Kernel.WriteString("Format:"); 
				Kernel.WriteHex(ORD(format.depth), 9); Kernel.WriteHex(ORD(format.bpp), 9); Kernel.WriteHex(ORD(format.slpad), 9); 
				Kernel.WriteLn;
			END;
		END;
		res:=Linux0.Read0(xfd, SYSTEM.ADR(scn),  SIZE(Screen));
		INC(lw, res);
		IF trace THEN WriteSH("Screen: ", ORD(scn.ndepth)) END;
		FOR i:= 1 TO ORD(scn.ndepth) DO
			res:=Linux0.Read0( xfd, SYSTEM.ADR(depth), SIZE(DepthT));
			INC(lw, res);
			IF scn.rdepth=depth.depth THEN
				res:=Linux0.Read0( xfd, SYSTEM.ADR(visual), SIZE(VisualT));
				INC(lw, res);
				IF trace THEN 
					Kernel.WriteString("Depth:"); 
					Kernel.WriteHex(ORD(depth.depth), 9); Kernel.WriteHex( depth.nvisualtypes, 9); Kernel.WriteLn;
					Kernel.WriteString("using Visual:"); 
					Kernel.WriteHex(visual.id, 9); Kernel.WriteHex(ORD(visual.class), 9); Kernel.WriteHex( visual.rmask, 9);  Kernel.WriteHex( visual.gmask, 9);  Kernel.WriteHex( visual.bmask, 9); 
					Kernel.WriteLn;
				END;
				DEC(depth.nvisualtypes);
				MaskShift(visual.rmask, rmr, rmw);
				MaskShift(visual.gmask, gmr, gmw);
				MaskShift(visual.bmask, bmr, bmw);
			END;
			WHILE depth.nvisualtypes > 0 DO
				res:=Linux0.Read0(xfd, SYSTEM.ADR(visual),  SIZE(VisualT));
				INC(lw, res);
				DEC(depth.nvisualtypes);
			END;
		END;
		IF lw DIV 4# r0data.len THEN
			WriteSH("X11: warning: Size mismatch, Longwords read: ", lw DIV 4);
			WriteSH("X11: warning: Size mismatch, r0data.len    : ", r0data.len);
		END;
		IF ORD(scn.rdepth)= 32 THEN	displayFormat:= color8888; bytes:=4; DrawPattern:=DrawPattern32;
		ELSIF ORD(scn.rdepth)= 24 THEN	displayFormat:= color8888; bytes:=4; DrawPattern:=DrawPattern32;
		ELSIF ORD(scn.rdepth)= 16 THEN	displayFormat:= color565; bytes:=2; DrawPattern:=DrawPattern16;
		ELSE WriteErr("Error: no X11 visual currently supported");Kernel.Shutdown(0);
		END;
		KeyboardMappingX11;
		IF scn.width >=3000 THEN displayFormat:= color8888; bytes:=8; DrawPattern:=DrawPattern64; EZoom:=1 END;

(* Use Kernel.GetConfig for default Width, Height *)
		Kernel.GetConfig("OWIDTH", bdata);
		Width:=defaultWidth;
		IF scn.width < ASH(defaultWidth+16, EZoom) THEN Width:=SHORT(ASH(scn.width, -EZoom) -16) END;
		Width:=Str2Int(bdata, defaultWidth);
		IF Width<0 THEN INC(scn.width, Width); Width:=scn.width END;
		linelength:=Width;
		Height:=defaultHeight;
		IF scn.height  < ASH(defaultHeight+32, EZoom) THEN Height:= SHORT(ASH(scn.height, -EZoom) -32) END;
		Kernel.GetConfig("OHEIGHT", bdata);
		Height:=Str2Int(bdata, defaultHeight);
		IF Height<0 THEN INC(scn.height, Height); Height:=scn.height END;
		OpenWindowX11;
	ELSE
		res:=Linux0.Read0(xfd, SYSTEM.ADR(adata[0]),  r0data.len*4);
		adata[ r0data.len*4-1]:=0X; Kernel.WriteString(adata); Kernel.WriteLn;
		WriteSH("X11 error: ", ORD(r0data.res ));		(* rdata.res  =2X authenticate *)
		IF r0data.res  =0X THEN											(* rdata.res  =0X failed *)
			WriteErr("Can't connect to xhost:");
			WriteErr("Please execute 'xhost local:', 'xhost +', 'xhost +si:localuser:$USER' or start xserver with -ac option");
			Kernel.Shutdown(1);
		END;
	END;
	Kernel.InstallTermHandler( CloseX11);
	RETURN xfd;
END InitX11;

BEGIN
	EZoom:=0;
	trace:=Kernel.trace="Display";
	Left := 0;  ColLeft := 0;	Bottom := 0;  UBottom := 0; Unit := 10000;
	tcp:=0;ShmReqCode:=0;
	pattern := NIL;
	PutImage:=PutImageFB;
	CreatePatterns;
	ResetClip;
END Display.

(** Remarks:

1. Background and Foreground colors
Oberon can either be used with white text on a black background, or inverted with black text on a white background (the so-called 
paper model). To reduce confusion you should use the FG and BG constants in your code.

2. Screen Organization
Oberon supports multiple displays that are placed next to each other in increasing X coordinates. The X coordinate thus uniquely 
determines the screen, hence the single parameter of the Depth and TransferFormat procedures. Each screen contains a set of nested 
frames. Historically, the first screen (at Left) is the black and white screen, and the second screen is the color screen (at ColLeft). Today 
Left and ColLeft are typically set to 0, as only a few computers still use black and white displays. The screen origin is located at the 
bottom-left corner of the display (i.e. Y decrease from the top to the bottom of the display).

3. The Frames and the Frame messages
Frames are the visual entities of Oberon. The frames are placed in the display space to make them visible. This involves inserting frames 
using the dsc and next fields into a container already located in the display space. All frames of a container are linked together in 
priority sequence using the next field. The dsc field points to the first child frame of a container. Note that this is only a convention 
and certain frames might decide to manage their contents in different ways. The frame messages are used to manipulate Frames 
(remember that frames also respond to the object message defined in module Objects).

4. Target or Destination frames
The Frame messages are often broadcasted into the display space rather than sending them directly to a frame. This is useful when 
many frames are to be informed of an event. It is also a means to determine the exact location (in coordinates and nesting) of a frame 
in the display space by following the message thread from the display root object to the frame itself (see module Objects). It is also 
possible to address a broadcasted message to a certain frame. This is called a directed broadcast. The target or destination of a 
broadcasted message is identified by the F field in the FrameMsg. It is set to NIL when all frames are to receive the message (true 
broadcast) and to a specific frame if only that frame is interested in the message (directed broadcast).

5. Frame Coordinates and Message origin
The coordinates of a frame are specified relative to its container or parent frame. The frame messages pass the absolute position of 
the top-left corner of the parent frame to their children in the x and y fields (called the message origin). Thus the absolute display 
position of a frame F is determined when it receives a frame message M:

	M.x + F.X, M.y + F.Y, F.W, F.H
	
6. Invalidating Messages
Often a frame knows that a message broadcast need not pass through the remainder of display space because it has already been 
handled. In such cases the res field of the frame message is set to zero or positive to indicate an action has been completed and that 
the message should be regarded as invalidated. Setting the res field in this way is called invalidating a message and will terminate 
the message broadcast.

7. Broadcasting Frame Messages
The Broadcast procedure broadcasts a message through the display space. The procedure initializes fields in the frame message. The 
message origin is set to (0, 0), the message is time stamped, the res field is set to a negative value, and the dlink field is initialized to 
NIL. In addition, the clipping rectangle is set to the whole display area.

8. Clipping
To prevent the clipping rectangle clipping the wrong display primitives, it is reset on each message broadcast or when a trap occurs. 
Clipping does not affect the drawing of cursors. The Gadget system uses "display masks" that hide the management of the clipping 
rectangle from the programmer.

9. NewPattern
The NewPattern procedure allows you to define patterns in a machine portable way. The sets contain 32 bits, each specifying a single 
pixel, with {0} the left-most pixel of the pattern. Each pattern line must be filled with empty bits so that it is a multiple of 32 pixels 
long. The first SET of the array contains the bottom line of the pattern.

10. ControlMsg
The ControlMsg is primarily used to remove a frame from the display space. When id is set to remove, the destination frame should be 
removed from its current location. This done by the container the frame is contained in (and is thus a slight misinterpretation of F as a 
destination frame). More than one frame are removed if the destination is a list of frames (connected by the slink field). In this case, 
they should at all belong to the same parent. This message should always be broadcast.
When the message id is set to suspend or restore it indicates that all frames from the destination downwards in the display space will 
be temporarily removed from the display space, or will be restored to the display space. This allow frames to update their internal data 
structures as they may have missed messages while suspended (this is because only those frames located in the display space receive 
message broadcasts). This message is sent to the top-most frame of that part of the display space involved (with the destination set to NIL).

11. ModifyMsg
The ModifyMsg broadcasts resize request to the destination frame. This allows you to move the relative position or change the size of 
a child in a container. When the mode is set to state, the frame should not display itself immediately but only update its size and 
position (possibly indicating changes to its children in turn). It is then the task of the sender to send a follow up Display message to 
the frame. The latter way of using the ModifyMsg allows a container to influence its children without having them draw themselves 
for each change made. This message must never be invalidated (i.e. it must travel throughout the whole display space). The dX, dY, 
dW, dH coordinates should always be set correctly to indicate the change in position and size from the original position and size. The 
id field of the ModifyMsg is ignored by most frames in the system.

12. DisplayMsg
The DisplayMsg sends either a redraw request or a print request to a destination frame, depending on the value of device (screen or 
printer). When the destination is NIL, a whole DAG of gadgets are implied. When id is set to area, the area u, v, w, h inside the 
destination frame should be redrawn. Gadgets assume that these coordinates are relative to the top left-most corner of the destination 
gadget (thus v is negative).
When printing, the x, y coordinates indicate the absolute printer coordinates of the left-bottom corner of the frame on paper (and 
not the left-bottom corner of the container). When the id is set to full, the frame has to print itself in the form it looks on the display. 
When the id is set to contents it should print its complete contents (for example a multi-page text that it is displaying). The frame 
may assume that the printer driver has been initialized already. Readying the printer is the task of the sender, and is done by calling 
Printer.Open.

13. LocateMsg
This message is broadcast to locate the frame positioned at the absolute coordinates X, Y on the display. The result, if any, is found in 
the loc field. The frame should return the relative position u, v of X, Y inside itself. Gadgets return these coordinates relative to their 
top-left corner (i.e. v is typically negative). By convention, the message is invalidated when the loc field is set.

14. SelectMsg
When id is set to get, the message is used to return the current object selection (a list) in obj. The parent of the selected objects is 
returned in the sel field. This message is broadcast with the destination set to NIL. The time of the selection is returned in the time 
field. Each container frame in the display space typically compares the time of its selection with the time field in the message, 
updating the returned selection when it is after the time set in the message field. When id is set to set or reset, the destination 
frame should select or unselect itself. It should never draw itself at this point. This is the task of the message sender.

15. ConsumeMsg
When the id is set to drop, the destination frame is requested to consume the list of objects found in the obj field. This is the way 
how objects can be added dynamically to a container. The relative u, v coordinates indicate where inside of this gadget (note that v 
is typically negative). When id is set to integrate, the message is broadcast to all and indicates that the frame owning the focus (caret) 
should consume the list of objects.

16. The Broadcast procedure is installed by module Viewers to the default message broadcasting procedure found it that module.

17. TransferBlock
TransferBlock is a fast way to read or write the display in a format as close as possible to the native format of the driver.  If the driver 
does not directly use one of the supported formats, it must select one and translate on-the-fly.  The caller must be prepared to handle 
any of the supported return formats.  The value returned by TransferFormat is constant, unless the display mode is changed.  
TransferBlock performs clipping using the normal clipping rectangle.  When reading from the display, the pixels falling outside the 
clipping rectangle have undefined values.

18. TransferFormat returns
	unknown - TransferBlock not supported
	index8 - 8 bits per pixel indexed
	color555 - 16 bits per pixel XRGB 1x5x5x5
	color565 - 16 bits per pixel RGB 5x6x5
	color664 - 16 bits per pixel RGB 6x6x4
	color888 - 24 bits per pixel RGB 8x8x8
	color8888 - 32 bits per pixel XRGB 8x8x8x8
color components: R = red, G = green, B = blue, X = undefined.
multibyte values are stored in little-endian order in buf (least-significant byte first).
color components are stored in XRGB bit order (B in least-significant bits).
	
19. Color
There are two types of display drivers.  "Minimal" drivers that support only indexed color, and "full-featured" drivers that support 
indexed color and true color.  The TrueColor() function can be used to determine what kind of driver is active in a display region.  
A minimal driver only supports color values from 0 to 255 (0 to 0FFH), which are entries into the palette, and color values outside 
this range produce undefined results (e.g. garbage, index out of range trap).  A full-featured driver also supports 24-bit true color 
values that range from MIN(LONGINT) to MIN(LONGINT)+2^24-1 (80000000H to 80FFFFFFH).  
The driver translates the color values to the internal format of the display buffer on-the-fly.

20. The RGB() function can be used to construct true color values.  The RGB components are defined as:
	R = ASH(col, -16) MOD 256, G = ASH(col, -8) MOD 256, B = col MOD 256, and
	col = MIN(LONGINT) + ASH(R, 16) + ASH(G, 8) + B, where 0 <= R,G,B <= 255
The RGB function can be used to compose color values, and GetColor can be used to decompose them, as well as to read from the 
palette.

21. Depth() returns the depth of the color palette.
	1 - recommend use of color indices BG and FG only.
	4 - color indices 0 to 16 supported.
	8 - color indices 0 to 255 supported.
No driver will support a color palette larger than 8 bits.  Instead it might support true color values generated by function RGB().  
The TrueColor() function can be used to check if a driver supports such values.
*)
