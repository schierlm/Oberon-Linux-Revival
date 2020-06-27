(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE MatrixMath;	(** non-portable *)	(* pjm *)

(* Note: Operator overloading and dynamic array values are 
an experimental feature available in Native Oberon only *)

TYPE
	Matrix* = ARRAY *,* OF LONGREAL;
	
PROCEDURE "+"*(a, b: Matrix): Matrix;
VAR i, j: LONGINT;  temp: LONGREAL;  c: Matrix;
BEGIN
	ASSERT(LEN(a, 0) = LEN(b, 0));
	ASSERT(LEN(a, 1) = LEN(b, 1));
	NEW(c, LEN(a, 0), LEN(a, 1));
	FOR i := 0 TO LEN(a, 0)-1 DO
		FOR j := 0 TO LEN(a, 1)-1 DO
			temp := b[i,j] + a[i,j];
			c[i,j] := temp
		END
	END;
	RETURN c
END "+";

PROCEDURE "*"*(a, b: Matrix): Matrix;
VAR i, j, k: LONGINT;  c: Matrix;  sum: LONGREAL;
BEGIN
	ASSERT(LEN(a, 1) = LEN(b, 0));
	NEW(c, LEN(a, 0), LEN(b, 1));
	FOR i := 0 TO LEN(a, 0)-1 DO
		FOR j := 0 TO LEN(a, 1)-1 DO
			sum := 0;
			FOR k := 0 TO LEN(a, 1)-1 DO
				sum := sum + a[i, k] * b[k, j]
			END;
			c[i, j] := sum
		END
	END;
	RETURN c
END "*";

END MatrixMath.
