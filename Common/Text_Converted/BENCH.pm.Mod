(*/*From - Thu Jul 18 12:12:59 1996
Path: news.fh-wolfenbuettel.de!newsserver.rrzn.uni-hannover.de!news.rwth-aachen.de!uni-paderborn.de!fu-berlin.de!informatik.tu-muenchen.de!lrz-muenchen.de!mistress.informatik.unibw-muenchen.de!klee
From: klee@mistress.informatik.unibw-muenchen.de (Herbert Kleebauer)
Newsgroups: comp.sys.intel,comp.sys.powerpc,comp.sys.sun.hardware,vmsnet.alpha
Subject: i486 faster than SPARC ?!?
Date: Wed, 17 Jul 1996 14:53:55
Organization: Fakultaet fuer Informatik, Universitaet der BW Muenchen
Lines: 46
Distribution: world
Message-ID: <klee.230.000EE67D@mistress.informatik.unibw-muenchen.de>
NNTP-Posting-Host: pc1510a.informatik.unibw-muenchen.de
Xref: news.fh-wolfenbuettel.de comp.sys.intel:79530 comp.sys.powerpc:63069 comp.sys.sun.hardware:31533


To compare the speed of some of our computers, I have written a simple
program to calculate n! (n<120000). The program was compiled with gcc,
optimization enabled (-O2). Here are some (unexpected) results:

                    |   25000!  |   50000!  |  100000!  |
--------------------+-----------+-----------+-----------+
i386      33 MHz    |    421 s  |   1847 s  |   8321 s  |
SPARC 2             |    358 s  |           |           |
i486      33 MHz    |    276 s  |   1201 s  |   5317 s  |
SPARC 10            |    146 s  |    633 s  |   2738 s  |
i486DX2   66 MHz    |    143 s  |    625 s  |   2730 s  |
SPARC 20            |    116 s  |    508 s  |   2210 s  |
PENTIUM   60 MHz    |     70 s  |    302 s  |   1357 s  |
ULTRA SPARC 167MHz  |     46 s  |    206 s  |    897 s  |
PENTIUM  100 MHz    |     43 s  |    186 s  |    819 s  |
PENTIUM  133 MHz    |     32 s  |    141 s  |    630 s  |
> 43P PPC604@120
> cc -O3
>    -qarch=ppc -qtune=601  15 s        69 s          467 s
> 
> 42T PPC604@120
> cc -O3
>    -qarch=ppc -qtune=601  17 s        71 s          360 s
> gcc -O2                   17 s        80 s          369 s
> 
> 25T PPC601@80
> cc -O3
>    -qarch=ppc -qtune=601  36 s       163 s          708 s
> gcc -O2                   47 s       208 s          906 s
> 
> 360 Power@50
> cc -O3
>    -qarch=pwr -qtune=pwr  48 s       219 s          913 s
> gcc -O2                   65 s       282 s         1223 s
> 
> 590 Power2@66
> cc -O3
>    -qarch=pwrx -qtune=pwrx 26 s      109 s          483 s
> 
> BTW: I got 97 s for n=25000 on a Sparc20 and 315 s on a 486@33 (Linux)

> My numbers for an Alpha 8200 (DEC 21164 300MHZ) under OpenVMS are:
>                              13 s       57 s         263 s
> If I change the time function to clock, I get:
>                              12 s       57 s         249 s
> With your code I get:
>   PPC604, 132MHz      |     14 s  |     65 s  |    340 s  |

>Sparc 5: gcc -O2			
	cc -O3			159 s	
DecStation 240			222 s  	*/
/*********************************************************************/
*)
MODULE bench;
IMPORT Texts, Oberon, Input, s:=SYSTEM;
VAR	f: ARRAY 200000 OF LONGINT;
	W: Texts.Writer;

PROCEDURE compute( n: LONGINT; VAR f: ARRAY OF LONGINT);
VAR i, j, k, l, m: LONGINT;
BEGIN
	i:= 1; m:=1; f[1]:=1;
	FOR j:= 2 TO n DO
		l:= 0;
		FOR k:=m TO i DO
			l:= j*f[ k]+l;
			f[ k]:= s.VAL( LONGINT, s.VAL( SET, l)* { 0..14} );
			l:= s.LSH( l, -15);
		END;
		IF l# 0 THEN
			INC( i);
			f[ i]:= s.VAL( LONGINT, s.VAL( SET, l)* { 0..14} );
			IF s.LSH( l, -15)# 0 THEN INC( i); f[ i]:= s.LSH( l, -15); END;
		END;
		IF f[ m]= 0 THEN INC( m) END;
	END;
	f[ 0]:= i;
END compute;

PROCEDURE Print( n: LONGINT; VAR f: ARRAY OF LONGINT);
VAR i, j, k, l, m: LONGINT;
BEGIN
	i:= f[ 0];
	l:=0;
	m:= (i-1) MOD 4 +15;
	WHILE i#0 DO
		j:=0;
		FOR k:=0 TO 3 DO
			j:=j*2+s.VAL( LONGINT, s.VAL( SET, s.LSH( f[ i], -m) )*{0});
			IF m=0 THEN m:= 14; DEC( i)
			ELSE DEC( m)
			END;
		END;
		IF j<10 THEN Texts.Write( W, CHR( j+ORD('0')));
		ELSE Texts.Write( W, CHR(  j-10+ORD('A')))
		END;
		INC( l);
		IF l MOD 64=0 THEN Texts.WriteLn( W); (* Texts.Append( Oberon.Log, W.buf);*) END;
	END;
	Texts.WriteLn( W);
	Texts.WriteInt( W, n, 0);
	Texts.WriteString( W, "! has ");
	Texts.WriteInt( W, l, 0);
	Texts.WriteString( W, " hex digits.");
	Texts.WriteLn( W);
	Texts.Append( Oberon.Log, W.buf);
END Print;

PROCEDURE Do*;
CONST n= 50000;
VAR t: LONGINT;
BEGIN
	t:=Input.Time();
	compute( n, f);
	t:= Input.Time()-t;
	Texts.WriteString( W, " Time: "); Texts.WriteInt( W, t *(1000 DIV Input.TimeUnit), 6); Texts.WriteString( W, " ms"); Texts.WriteLn( W);
	Texts.Append( Oberon.Log, W.buf);
(*	Print( n, f); *)
END Do;

BEGIN Texts.OpenWriter( W);
END bench.Do

int main()    /* int must be >= 4 byte */
{ unsigned int n, f[200000]; unsigned long t1,t2; 
 do {
   printf("calculate n! (n<=120000) n=? ");
   scanf("%d",&n);
 } while (n>120000);
 time(&t1); compute(n,f); time(&t2);
/*print_result(n,f);*/ 
printf("time = %d s\n",(int)(t2-t1));} 

int compute(n,f) unsigned int n, *f;
{unsigned int i=1,j,k,l,m=1; f[1]=1; 
	for (j=2; j<=n; j++) 
	{
		l=0;
		for (k=m; k<=i; k++) 
		{
			l=j*f[k]+l;
			f[k]=l&0x7FFF;
			l=l>>15;
		} 
    	if (l) 
			{f[++i]=l&0x7FFF; 
	  	  if (l>>15) f[++i]=l>>15;
			} 
 		if (!f[m]) m++;
	} 
	*f=i;
}

int print_result(n,f) unsigned int n, *f;
{unsigned int i=*f,j,k,l=0,m=(i-1)%4+15; 
 while(i) 
	{j=0;
	for (k=0;k<4;k++) 
		{j=(j<<1)+((f[i]>>m)&1);
		if(!m--) {m=14; i--;}
		} 
		if (!(l&0x3F)) putchar('\n');
		putchar(j<10?j+'0':j-10+'A'); l++;
	} 
	printf("\n\n%d! has %d hex digits\n",n,l);
}

/*********************************************************************/


