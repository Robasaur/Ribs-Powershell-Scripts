<#
This script will disable/enable bitlocker encryption, the intune policy should reencrypt in the correct format.
#>
$BLVI2 = Get-BitLockerVolume -MountPoint C

try {
	if ($BLVI2.VolumeStatus -eq "FullyDecrypted") {
		Enable-Bitlocker -MountPoint C -EncryptionMethod "XtsAes256"
		BackupToAAD-BitLockerKeyProtector -MountPoint C -KeyProtectorId $BLVI2.KeyProtector[1].KeyProtectorId
		exit 0
	}
	if ($BLVI2.EncryptionMethod -ne "XtsAes256") {
		Disable-Bitlocker -MountPoint C
		exit 0
	}
} catch {
	$errMsg = $_.Exception.Message
	write-Error $errMsg
	exit 1
}

