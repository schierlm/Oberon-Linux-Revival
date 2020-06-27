Desktops.OpenDoc SaveScreen.Text
Desktops.OpenDoc SaveLife.html

SaveScreen.Activate ~ 10 ~
SaveScreen.Deactivate
SaveScreen.Run

SaveTiles.Install ~ speed 64 columnCount 20 rowCount 20 ~
SaveTiles.Configuration

SaveParticles.Install  ~ particleCount  256 particleSize  2 ~
SaveParticles.Configuration

SaveDecay.Install
SaveSisyphus.Install

System.Free SaveDecay SaveParticles SaveTiles 
	SaveSisyphus SaveScreen~

Compiler.Compile SaveScreen.Mod SaveSisyphus.Mod
	SaveTiles.Mod SaveParticles.Mod SaveDecay.Mod ~
Builder.Compile SaveScreen.Mod SaveSisyphus.Mod
	SaveTiles.Mod SaveParticles.Mod SaveDecay.Mod ~
ARMCompiler.Compile SaveScreen.Mod SaveSisyphus.Mod
	SaveTiles.Mod SaveParticles.Mod SaveDecay.Mod ~
