<# Description 
	Checks to see whether the Bitlocker is XTSAES256, if not triggers remediation.
	Get-BitLockerVolume -MountPoint C | Format-List 
	Command for debug
#>

$BLVI = Get-Bitlockervolume -MountPoint C

try {
	if ($BLVI.VolumeStatus -eq "EncryptionInProgress") {
		Write-Host "C is encrypting at $($BLVI.EncryptionPercentage)%"
		exit 0
	} 
	if ($BLVI.VolumeStatus -eq "DecryptionInProgress") {
		Write-Host "C is decrypting at $($BLVI.EncryptionPercentage)%"
		exit 0
	} 
	if ($BLVI.VolumeStatus -eq "FullyDecrypted") {
		Write-Host "C is decrypted, Policy will enable and encrypt the device (Restart may be required)"
		exit 1
	}
	if ($BLVI.EncryptionMethod -eq "XtsAes256") {
		Write-Host "C is encrypted with $($BLVI.EncryptionMethod)"
		exit 0
	}  elseif ($BLVI.EncryptionMethod -ne "XtsAes256") {
		Write-Host "C is encrypted with: $($BLVI.EncryptionMethod), triggering remediation! (Restart is required)"
		exit 1
	} 
} catch {
	$errMsg = $_.Exception.Message
	write-Error $errMsg
	exit 1
}