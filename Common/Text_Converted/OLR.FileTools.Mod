MODULE FileTools;
(*
	Peter Matthias
	2015-07-22	using Kernel rourines in CopyTo and allowed \x option to set execute permissions
	2015-12-09	importing Linux0

*)


IMPORT Linux0, Kernel, FileDir, Texts, Oberon, SYSTEM;
VAR W: Texts.Writer;

PROCEDURE ModifyName(in, prefix: ARRAY OF CHAR;  add: BOOLEAN;  VAR out: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	IF add THEN
		i := 0; WHILE prefix[i] # 0X DO out[i] := prefix[i]; INC(i) END;
		j := 0; WHILE in[j] # 0X DO out[i] := in[j]; INC(i); INC(j) END;
		out[i] := 0X
	ELSE
		i := 0; WHILE (prefix[i] # 0X) & (in[i] = prefix[i]) DO INC(i) END;
		IF prefix[i] # 0X THEN i := 0 END;
		j := 0; WHILE in[i] # 0X DO out[j] := in[i]; INC(i); INC(j) END;
		out[j] := 0X
	END
END ModifyName;

PROCEDURE StartScan(VAR S: Texts.Scanner);
VAR beg, end, time: LONGINT;  T: Texts.Text;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
	END
END StartScan;

PROCEDURE *List(name: ARRAY OF CHAR;  time, date, size: LONGINT; VAR flags: SET);
BEGIN
	Texts.WriteString(W, name);
	Texts.WriteLn(W)
END List;

PROCEDURE GenCopyFiles*;	(** remprefix addprefix ( "mask" | &file | { file [=> file] } ) ~ *)
VAR s: Texts.Scanner; t: Texts.Text; prefix1, prefix2, name: FileDir.FileName;
BEGIN
	StartScan(s);
	IF s.class IN {Texts.Name, Texts.String} THEN COPY(s.s, prefix1); Texts.Scan(s) END;
	IF s.class IN {Texts.Name, Texts.String} THEN COPY(s.s, prefix2); Texts.Scan(s) END;
	IF s.class = Texts.String THEN	(* directory mask *)
		FileDir.Enumerate(s.s, {}, List);
		NEW(t);  Texts.Open(t, "");
		Texts.Append(t, W.buf);
		Texts.OpenScanner(s, t, 0);  Texts.Scan(s)
	ELSIF (s.class = Texts.Char) & (s.c = "&") THEN
		Texts.Scan(s);
		IF s.class = Texts.Name THEN
			NEW(t);  Texts.Open(t, s.s);
			Texts.OpenScanner(s, t, 0);  Texts.Scan(s)
		END
	END;
	Texts.WriteString(W, "System.CopyFiles");  Texts.WriteLn(W);
	WHILE s.class = Texts.Name DO
		Texts.WriteString(W, "  ");  Texts.WriteString(W, s.s);  Texts.WriteString(W, " => ");
		COPY(s.s, name);
		Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "=") THEN
			Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = ">") THEN
				Texts.Scan(s);
				IF s.class = Texts.Name THEN
					COPY(s.s, name);
					Texts.Scan(s)
				ELSE
					(* skip *)
				END
			ELSE
				(* skip *)
			END
		END;
		ModifyName(name, prefix1, FALSE, name);
		ModifyName(name, prefix2, TRUE, name);
		Texts.WriteString(W, name);  Texts.WriteLn(W)
	END;
	Texts.Write(W, "~");
	NEW(t);  Texts.Open(t, "");
	Texts.Append(t, W.buf);
	Oberon.OpenText("", t, 200, 200)
END GenCopyFiles;

PROCEDURE CopyTo*;	(** dstprefix srcprefix ( &file | { file [=> file]} ) ~ *)
VAR
	S: Texts.Scanner;   t: Texts.Text;
	status: Linux0.Status;
	i, sf, df, res, sadr: LONGINT;
	sLen, dLen: INTEGER;
	src, dest: ARRAY 64 OF CHAR; 
	exe: SET;
	ch: CHAR;
BEGIN
	StartScan(S);
	IF ~(S.class IN {Texts.Name, Texts.String}) THEN
		Texts.WriteString(W, "Missing destination prefix");  Texts.WriteLn(W)
	ELSE
		dLen := 0;  WHILE S.s[dLen] # 0X DO  dest[dLen] := S.s[dLen];  INC(dLen)  END;
		Texts.Scan(S);
		IF ~(S.class IN {Texts.Name, Texts.String}) THEN
			Texts.WriteString(W, "Missing source prefix");  Texts.WriteLn(W)
		ELSE
			sLen := 0;  WHILE S.s[sLen] # 0X DO  src[sLen] := S.s[sLen];  INC(sLen)  END;
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "&") THEN
				Texts.Scan(S);
				IF S.class IN {Texts.Name, Texts.String} THEN
					NEW(t);  Texts.Open(t, S.s);
					Texts.OpenScanner(S, t, 0);  Texts.Scan(S)
				END
			END;
			WHILE S.class IN {Texts.Name, Texts.String} DO
				i := 0;  ch := S.s[i];
				WHILE ch # 0X DO  src[sLen+i] := ch;  dest[dLen+i] := ch;  INC(i);  ch := S.s[i]  END;
				src[sLen+i] := 0X;  dest[dLen+i] := 0X;
				Texts.WriteString(W, src);
				sf := Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR( src[0]), Linux0.ORDonly, 0);
				res:=Linux0.FStat0( sf, SYSTEM.ADR(status));
				sadr:=Linux0.Mmap20( 0, status.size, 1, Linux0.MAPSHARED, sf, 0);
				exe:={};
				IF sf >0 THEN
					Texts.Scan(S);
					IF (S.class = Texts.Char) & (S.c = "=") THEN
						Texts.Scan(S);
						IF (S.class = Texts.Char) & (S.c = ">") THEN
							Texts.Scan(S);
							IF S.class IN {Texts.Name, Texts.String} THEN
								i := 0;  ch := S.s[i];
								WHILE (ch # 0X)  DO  dest[dLen+i] := ch;  INC(i);  ch := S.s[i]  END;
								dest[dLen+i] := 0X;
								Texts.Scan(S);
								IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
									Texts.Scan(S);
									IF (S.class IN {Texts.Name, Texts.String}) & (S.s[0]="x") THEN exe:={ 6, 3, 0}; Texts.Scan(S); END;
								END;
							ELSE
								(* skip *)
							END
						ELSE
							(* skip *)
						END
					END;
					Texts.WriteString(W, " => ");  Texts.WriteString(W, dest);
					IF exe #{} THEN Texts.WriteString(W, "\x") END;
					df := Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR( dest[0]), Linux0.ORDWR+Linux0.OTRUNC+Linux0.OCREAT, SYSTEM.VAL( LONGINT, { 8, 7, 5, 2}+exe));
					IF df >0 THEN
						Texts.WriteString(W, " copying");
						Texts.Append(Oberon.Log, W.buf);
						res:= Linux0.Write0( df, sadr, status.size);
						res:= Linux0.Close0( df);
					ELSE
						Texts.WriteString(W, " create failed");
						S.class := Texts.Inval
					END;
					res:= Linux0.Munmap0( sadr, status.size);
					res:= Linux0.Close0( sf);
				ELSE
					Texts.WriteString(W, " open failed");
					S.class := Texts.Inval
				END;
				Texts.WriteLn(W)
			END
		END
	END;
	Texts.Append(Oberon.Log, W.buf)
END CopyTo;

BEGIN
	Texts.OpenWriter(W)
END FileTools.
