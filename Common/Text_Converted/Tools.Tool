The Tools Package contains developer's tools

System.Open ^
  NetSystem.Tool  IFS.Tool
  ET.Tool  BootLinker.Tool  Configuration.Tool
  Math.Tool  Greek.Tool  DOS.Tool  FileSystem.Tool

Script.Open OpenType.Text

Decoder.Decode ^
Decoder.Find *  select PC in Trap

Info.Memory ^  select adr in Trap
Info.DeRef ^  select ptr in Trap
Info.ShowLibraries {textfile} ~
Info.ShowImports {objfile} ~
Info.ScanFilenames ^
Info.ShowModules

Edit.Open Keyboard.Mod
