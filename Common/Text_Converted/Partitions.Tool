The Partitions tool displays and modifies hard disk partition tables

Partitions.Show ~	Display partition table(s)
Partitions.Show detail ~	Display partition table(s) verbosely
Partitions.Check ^	Check partition's sectors for readability
Partitions.GetConfig ^	Display configuration strings
Partitions.SetConfig dev#part { str = "val" } ~	Set configuration strings
Partitions.ShowBlocks dev#part block [blocks] ~	Display blocks
Partitions.PartitionToFile dev#part file [block blocks] ~	Block copy a partition to a file
Partitions.FileToPartition dev#part file [block blocks] ~	Block copy a file to a partition
Partitions.Eject ^ ~	Eject media from selected device
!Partitions.Activate ^	Make partition bootable
!Partitions.Deactivate ^	Make partition non-bootable
!Partitions.ChangeType dev#part from to ~	Change partition type
!Partitions.Create dev#part sizeMB	Create a primary AosFS partition (unformatted)
!Partitions.Format dev#part [ AosFS|NatFS [ FSRes [ Native.Bin ] ] ] ~
!Partitions.Unsafe ~	Enable some unsafe commands
!Partitions.UpdateBootFile dev#part [ BootFile ] ~
!Partitions.PartitionToFile dev#0 MBR.Bin 0 1 ~	Read MBR
!Partitions.WriteMBR dev#0 MBR.Bin ~	Write MBR (be careful)
!Partitions.Delete dev#part type	Delete a primary partition
Partitions.Safe ~	Disable unsafe commands (default)
Partitions.ShowAosFSLimits ~	Display some limits of the AosFS

Long-running commands can be aborted with Esc.
Create and Delete do not work on disks with mounted partitions.
