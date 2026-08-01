-- HDRHeic.app — control panel for the hdrheic engine
-- Double-click to convert on demand, install/remove the background watcher,
-- or change the watched folder and debounce delay.

property agentLabel : "com.zoltanpalotai.hdrheic"

on binaryPath()
	return quoted form of (POSIX path of (path to resource "hdrheic"))
end binaryPath

on agentPlistPath()
	return (POSIX path of (path to home folder)) & "Library/LaunchAgents/" & agentLabel & ".plist"
end agentPlistPath

on watcherInstalled()
	set plist to agentPlistPath()
	tell application "System Events" to return (exists file plist)
end watcherInstalled

on run
	set bin to binaryPath()
	repeat
		if watcherInstalled() then
			set watcherItem to "Remove background watcher"
			set statusLine to "Background watcher: ON"
		else
			set watcherItem to "Install background watcher"
			set statusLine to "Background watcher: off"
		end if
		set folderNow to do shell script bin & " get watchFolder"
		set delayNow to do shell script bin & " get debounceSeconds"
		set prompt to "HDRHeic — HDR JPEG → 10-bit HEIC" & return & ¬
			"Folder: " & folderNow & "   Delay: " & delayNow & "s   " & statusLine

		set choice to choose from list ¬
			{"Convert now", "Settings…", watcherItem, "Show log", "Quit"} ¬
			with prompt prompt default items {"Convert now"} without empty selection allowed
		if choice is false then return
		set choice to item 1 of choice

		if choice is "Convert now" then
			doConvertNow(bin)
		else if choice is "Settings…" then
			doSettings(bin)
		else if choice is "Install background watcher" then
			installWatcher(bin)
		else if choice is "Remove background watcher" then
			removeWatcher()
		else if choice is "Show log" then
			do shell script "open -a Console " & quoted form of ((POSIX path of (path to home folder)) & "Library/Logs/HDRHeic.log")
		else if choice is "Quit" then
			return
		end if
	end repeat
end run

on doConvertNow(bin)
	try
		set summary to do shell script bin & " scan | tail -n 1"
		display notification summary with title "HDRHeic — conversion finished"
		display dialog summary buttons {"OK"} default button "OK" with title "HDRHeic"
	on error errMsg
		display dialog "Conversion error:" & return & errMsg buttons {"OK"} default button "OK" with icon stop
	end try
end doConvertNow

on doSettings(bin)
	-- Folder (the engine returns an absolute path)
	set currentFolder to do shell script bin & " get watchFolder"
	try
		set chosen to choose folder with prompt "Which folder should be watched / converted?" default location (POSIX file currentFolder)
		set newFolder to POSIX path of chosen
		do shell script bin & " set watchFolder " & quoted form of newFolder
	on error number -128
		-- user cancelled folder choice; keep current
	end try
	-- Delay
	set currentDelay to do shell script bin & " get debounceSeconds"
	try
		set answer to text returned of (display dialog ¬
			"Delay in seconds before converting after new files appear (quiet period):" ¬
			default answer currentDelay buttons {"Cancel", "Save"} default button "Save")
		do shell script bin & " set debounceSeconds " & quoted form of answer
	on error number -128
		-- cancelled; keep current
	end try
	-- If the watcher is running, restart it so it picks up the new settings.
	if watcherInstalled() then
		removeWatcher()
		installWatcher(bin)
		display notification "Settings saved and watcher restarted" with title "HDRHeic"
	else
		display notification "Settings saved" with title "HDRHeic"
	end if
end doSettings

on installWatcher(bin)
	set uid to do shell script "id -u"
	set plist to agentPlistPath()
	set rawBinary to POSIX path of (path to resource "hdrheic")
	set plistText to "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key><string>" & agentLabel & "</string>
	<key>ProgramArguments</key>
	<array>
		<string>" & rawBinary & "</string>
		<string>watch</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ProcessType</key><string>Background</string>
	<key>StandardErrorPath</key><string>" & (POSIX path of (path to home folder)) & "Library/Logs/HDRHeic.log</string>
</dict>
</plist>"
	-- write the plist
	set plistFile to open for access (POSIX file plist) with write permission
	set eof of plistFile to 0
	write plistText to plistFile
	close access plistFile
	-- (re)load it
	do shell script "launchctl bootout gui/" & uid & " " & quoted form of plist & " 2>/dev/null; launchctl bootstrap gui/" & uid & " " & quoted form of plist
	display notification "Background watcher installed and running" with title "HDRHeic"
end installWatcher

on removeWatcher()
	set uid to do shell script "id -u"
	set plist to agentPlistPath()
	do shell script "launchctl bootout gui/" & uid & " " & quoted form of plist & " 2>/dev/null; rm -f " & quoted form of plist
	display notification "Background watcher removed" with title "HDRHeic"
end removeWatcher
