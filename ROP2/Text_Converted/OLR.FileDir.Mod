(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE FileDir;	(* pjm *)

(* Linux FileDir module not based on OFS
		Peter Matthias

	2014-11-25	MLO version, not tested
	2014-11-28	made Enumerate work with qemu-mips
	2015-04-13	added PathChar; made  interface compatible to latest alpha
	2015-10-06	added support for "/" in Filename; fixed matching bug;
							algorithm from http://xoomer.virgilio.it/acantato/wildcard/wildmatch.html
	2015-10-15	using non-recursive Match procedure from Luowy
	2015-11-01	using recursive version because of bug; showing correct file stats for non current files; automatically show all files if name ends with "/"
	2015-11-10	jdk: replaced the Match routine
	2015-12-09	imported Linux0
	2017-04-16	removed adding "/" in Enumerate	

*)

IMPORT Linux0, Kernel, Files, SYSTEM;

CONST
	EnumSize*=0; EnumTime*=1; EnumRecursive*=2; EnumStop*=15; EnumUserMin*=16; EnumUserMax*=31;

TYPE

	EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR flags: SET);

	FileName* = Files.FileName;

	DirEnt32P= POINTER TO RECORD
					dino: LONGINT;
					doff: LONGINT;
					dreclen: INTEGER;
					dname: FileName;
(*					pad, type: CHAR;  type is DirEntP.dname[ DieEntP.dreclen-10-1] *)
				END;

	DirEntP= POINTER TO RECORD
					dinol, dinoh: LONGINT;
					doffl, doffh: LONGINT;
					dreclen: INTEGER;
					dtype: CHAR;
					dname: FileName;
				END;


VAR
	PathChar*: CHAR;

(* recursive Version 
PROCEDURE Match( p, s: LONGINT; VAR pat, str: ARRAY OF CHAR): BOOLEAN;
BEGIN
	WHILE str[s]#0X DO
		IF str[s]=pat[p] THEN INC(p); INC(s)
		ELSIF pat[p]="?" THEN
			IF str[s]="." THEN RETURN FALSE END;
			INC(p); INC(s);
		ELSIF pat[p]="*"THEN
			REPEAT INC(p) UNTIL pat[p]#"*";
			IF pat[p]=0X THEN RETURN TRUE END;
			WHILE str[s]#0X DO
				IF  Match( p, s, pat, str) THEN RETURN TRUE END;
				INC(s);
			END;
			RETURN FALSE;
		ELSE
			RETURN FALSE;
		END;
	END;
	WHILE pat[p]="*" DO INC(p) END;
	RETURN pat[p]=0X
END Match;
*)
(* non-recursive version from Jan de Kruyf *)

   PROCEDURE Match(VAR mask, name: ARRAY OF CHAR): BOOLEAN;
      VAR
         m, mo, mmax, n, no, nmax : LONGINT;
         f                        : BOOLEAN;
   BEGIN
      m:= 0;
      mo:= 0;
      mmax:= 0;
      n:= 0;
      no:= 0;
      nmax:= 0;
      f:= TRUE;
      WHILE mask [mmax] > 0X DO INC (mmax) END; (* end of mask *)
      WHILE name [nmax] > 0X DO INC (nmax) END; (* end of name *)
      LOOP
         IF (mask [m] = "*") THEN
            REPEAT INC(m) UNTIL mask[m] # '*';
            IF (m = mmax) THEN
               n  := nmax (* end of story *)
            ELSE
               mo := m;
               no := n
            END;
         ELSIF ((name [n] = mask [m]) OR (mask [m] = "?")) & (n < nmax) THEN
            INC (m); INC (n);
         ELSIF (mo > 0) & (n < nmax) THEN (* backtrack *)
            m := mo - 1;
            n := no + 1;
         ELSIF f & ((m # mmax) OR (n # nmax)) THEN
            (* last chance. Only when no match *)
            f := FALSE;
         ELSE EXIT 
         END
      END;
      RETURN f
   END Match;

(** Enumerate files matching the mask.  proc is upcalled for every file.  If detail is TRUE, the time, date and size parameters will be valid.  Recursive calls to Enumerate are not allocated in proc. *)
PROCEDURE Enumerate*(mask: ARRAY OF CHAR; flags: SET; proc: EntryHandler);
VAR res, time, date, size: LONGINT;
	diff, pos: LONGINT;
	status: Linux0.Status;
	i, j, k, num, min, dir, rbytes: LONGINT;
	dbuf: ARRAY 256 OF CHAR;
	buf: ARRAY 128000 OF CHAR;
	i1: ARRAY 10000 OF DirEntP;
	de: DirEntP;
BEGIN
	i:=0; j:=0;
	WHILE mask[i]#0X DO
		dbuf[i]:=mask[i];
		IF mask[i]="/" THEN j:=i END;
		INC(i)
	END;
	dbuf[j+1]:=0X; k:=0; 
	IF (j=0) & (dbuf[0]#"/") THEN dbuf[0]:=".";
	ELSE
		INC(j);
		WHILE k<=i-j DO
			mask[k]:=mask[k+j];
			INC(k);
		END;
	END; k:=j;
	IF mask="" THEN COPY( "*", mask) END;
	dir:=Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(dbuf[0]), Linux0.ORDonly, 0);
	rbytes:= Linux0.GetDents0( dir, SYSTEM.ADR( buf[0]), LEN( buf));
	res:=Linux0.Close0( dir);
	IF dir<=0 THEN
		i:=0;
		buf:="<can't open ";
		WHILE dbuf[i]#0X DO
			buf[ 12+i]:=dbuf[i]; INC(i);
		END;
		buf[12+i]:=">"; buf[13+i]:=0X;
		flags:={}; proc( buf, 0, 0, 0, flags);
	ELSIF rbytes<=0 THEN flags:={}; proc( "<error getting direntries>", 0, 0, 0, flags);
	ELSE
		i:=0; num:=0;
		de:=SYSTEM.VAL( DirEntP, SYSTEM.ADR( buf[ i]));
		WHILE (de.dname[0]#0X) & (num<LEN(i1)) DO
			IF Match( mask, de.dname) THEN
				i1[ num]:= de;
				INC( num);
			END;
			i:=i+de.dreclen;
			de:=SYSTEM.VAL( DirEntP, SYSTEM.ADR( buf[ i]));
		END;
		IF num>=LEN(i1) THEN num:=0 END;
		i1[ num]:=NIL;
		(* using cripplesort, might be fast enough*)
		i:=0;
		WHILE i<num DO
			min:=i;
			j:=min+1;
			WHILE j<num DO
				IF (i1[ j].dname<i1[min].dname) THEN
					min:=j;
				END;
				INC( j);
			END;
			de:=i1[ i];
			i1[ i]:= i1[ min];
			i1[ min]:= de;
			INC( i);
		END;
	
		j:=0;
		de:= i1[ 0];
		WHILE de#NIL DO
			i:=0;
			WHILE de.dname[i]#0X DO
				dbuf[k+i]:=de.dname[i];
				INC(i);
			END;
(*			IF de.dname[de.dreclen-11]=4X THEN dbuf[k+i]:="/"; INC(i) END;*)
			dbuf[k+i]:=0X;
			time:=0; date:=0; size:= MIN( LONGINT);
			IF flags#{}  THEN
				res:=Linux0.FStatat0( Linux0.ATFDCWD, SYSTEM.ADR(dbuf[0]), SYSTEM.ADR(status), 0);
				IF res=0 THEN
					size:= status.size;
					Kernel.U2OTime( status.mtime, date, time);
				END;
			END;
			proc( dbuf, time, date, size, flags);
			INC( j);
			de:= i1[ j];
		END;
	END;
END Enumerate;

BEGIN
	PathChar := "/"
END FileDir.
