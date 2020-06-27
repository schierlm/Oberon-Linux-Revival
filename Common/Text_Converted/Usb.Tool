
Native Oberon Usb Support (* version 23.10.2000 *) (* cp *)

Init
===

UsbSystem.Start  (* starts the usb subsystem, loads the lowlevel chipset driver(s) *)

UsbMouse.Init  UsbKeyboard.Init  UsbStorage.Install  (* start a specific device driver *)

ByeBye
======

System.Free UsbSystem UsbBoot UsbMouse UsbStorage UsbKeyboard UsbUhci Usb~

Compile
=======

Compiler.Compile \s Usb.Mod UsbUhci.Mod UsbSystem.Mod UsbMouse.Mod UsbKeyboard.Mod UsbStorage.Mod UsbBoot.Mod ~

Information about the running usb system
=================================

System.OpenKernelLog
Usb.Info    (* show the usb tree on the kernel log/serial *)
UsbUhci.Diag    (* see if the Intel chipset driver is ok, output on kernel log/serial *)

Testing
======

Partitions.Show ~
FileSystem.Mount Sony NatFS USBUFI0#0 ~  FileSystem.Unmount Sony~
FileSystem.Mount Jaz AosFS USBSCSI0#1 ~  FileSystem.Unmount Jaz~
FileSystem.Mount UCD ISOFS USBCD0 ~  FileSystem.Unmount UCD ~

ModuleList
=========

UsbSystem.Mod (* Frontend to the lowlevel driver *) 
Usb.Mod (* Usb core support - similar to SCSI.Mod *)
UsbUhci.Mod (* Low level driver for Intel UHCI compatible chipsets *)
UsbStorage.Mod (* Usb driver for USB mass storage devices *)
UsbMouse.Mod (* Usb mouse driver *)
UsbKeyboard.Mod (* Usb keyboard driver *)
UsbBoot.Mod (* Helper module - Only needed to be able to boot from USB devices *)

Supported devices
===============

Tested: Y-E Data Floppy (the one which comes together with the Sony "Vaio" Laptops), Iomega USB-SCSI Adapter
(I used it with a 2GB Jaz drive), Microsoft Natural Keyboard Pro, Logitech Wheelmouse, no-name hubs

Beta: HP CDWriter 8200e series

The following USB devices SHOULD work, but could not been tested (since I don't have one of them):
HP CDWriter+ series, Mitsumi CD-R/RW drives, Matshita LS-120, Teac Floppy drive, Hagiwara Flashgate series devices, 
In-System USB/IDE bridges, Sandisk Imagemate series, devices that use Shuttle eUSB bridges (these are often ATAPI
devices and Compactflash readers), Sony Hifd, Sony DSC-S30/S70/505V/F505, Sony Memorystick MSAC-US1,
LaCie USB Hard Disk, devices that use the In-System USB/IDE bridge, all sorts of USB mice and keyboards, all sorts of USB hubs.

Traps
====

If you see a Trap 303, then its origin is likely one of the usb modules (they always use this number)
