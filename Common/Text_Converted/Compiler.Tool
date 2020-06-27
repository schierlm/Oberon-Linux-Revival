The Oberon compiler

Compiler.Compile *	Compiler.Compile *\f
Compiler.Compile *\s	Compiler.Compile ^	
Compiler.Compile @	Compiler.Compile ~	

Compiler Options: (default values in parenthesis)
	f	find error position (select PC line in Trap viewer)
	s	allow generation of new symbol file (off)
	e	allow extension of symbol file (off)
	x	index check (on)
	v	overflow check (off)
	t	type check (on)
	a	ASSERT evaluation (on)
	p	initialize local pointer variables (on)
	z	also initialize other local variables (on)
	w	show warnings (off)
	1	compile only Oberon-1 with dyn. arrays (off)
	2	compile Oberon-2 extensions (off)
	S	allow importing of SYSTEM (on)
	Px	prefix input & output .Obj files with x
	Ox	prefix output .Obj file with x
	
The Oberon Definition Browser

Browser.ShowDef  ^
Browser.ShowDef \e ^
Browser.ShowDef \d ^

Browser Options:
	\e: expand types
	\d: show detailed information (entry numbers, offsets, keys, etc)
