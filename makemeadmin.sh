#!/bin/bash
jamfURL="Your Jamf URL"
jUser="Jamf API Username"
jPass="Jamf API Password"
authTokenResponse=$(curl -su "$jUser:$jPass" -H "Accept: application/json" -H "Content-type: application/json" -X POST "$jamfURL/api/v1/auth/token")
justTheToken=$(plutil -extract token raw - <<< $authTokenResponse)
serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
computerID=$(curl -su "$jUser:$jPass" -H "Accept: text/xml" -H "Content-type" text/xml "${jamfURL}/JSSResource/computers/serialnumber/{$serialNumber}" | xmllint --xpath '/computer/general/id/text()' -)
ldPath=/Library/LaunchDaemons/yourORG.adminprocess.plist
scriptPath="/private/var/tmp/removeadmin.sh"
loggedInUser="$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )"


if [[ -f "$scriptPath" ]]; then
	rm $scriptPath
fi

tee "$scriptPath" << EndOFScript
#!/bin/bash

#Remove admin rights from the user
#dseditgroup -o edit -d "$loggedInUser" admin

#Logging Section
/usr/bin/log collect --last 15m --output /private/var/tmp/
zip -r /private/var/tmp/${loggedInUser}.zip /private/var/tmp/system_logs.logarchive
rm -rf /private/var/tmp/system_logs.logarchive
zipFile=/private/var/tmp/$loggedInUser.zip

#Upload the zip to Jamf
curl -k -H "Authorization: Bearer $justTheToken" $jamfURL/JSSResource/fileuploads/computers/id/$computerID -F name=@/private/var/tmp/${loggedInUser}.zip -X POST

#Run a recon
/usr/local/bin/jamf recon

#User Notification
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -heading "Access Removed" -title "Access Removed" -description "Your administrative access has been removed and logs have been uploaded for review. " -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/LockedIcon.icns" -button1 "Ok"

#Cleanup
rm -f /Library/LaunchDaemons/com.compucom.adminprocess.plist
rm -f /private/var/tmp/${loggedInUser}.zip
rm -f /private/var/tmp/Process_Has_Started.txt
rm -f /private/var/tmp/Process_Has_Completed.txt
rm -f /private/var/tmp/removeadmin.sh
EndOFScript

#Set Ownership
/usr/sbin/chown root:wheel $scriptPath
#Set Permissions (make sure everyone can execute)
/bin/chmod 755 $scriptPath

#Check if LD exists already, boot it out, and delete it
if [[ -f "$ldPath" ]]; then
	/bin/launchctl bootout system $ldPath 2>/dev/null
	rm -f $ldPath
fi

tee "$ldPath" << EoLD
<?xml version="1.0" encoding="UTF-8"?> 
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"> 
<plist version="1.0"> 
<dict> 
	<key>Label</key> 
	<string>$(basename "$ldPath" | sed 's/.plist//')</string> 
	<key>ProgramArguments</key> 
	<array> 
		<string>/bin/bash</string> 
		<string>$scriptPath</string> 
	</array> 
	<key>StartInterval</key>
	<integer>10</integer>
</dict> 
</plist>
EoLD

#Set Permissions
/bin/chmod 644 $ldPath
#Set Ownership
/usr/sbin/chown root:wheel $ldPath
#Load the job (Bootstrap and Bootout)
/bin/launchctl bootstrap system $ldPath

#dseditgroup -o edit -a "$loggedInUser" admin

#Display message that admin has been granted
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -heading "Access Granted" -title "Access Granted" -description "You have been granted access for 15 minutes. Everything you do will be logged and sent for review. Please ONLY perform the function you were granted access for." -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/UnlockedIcon.icns" -button1 "Ok"
