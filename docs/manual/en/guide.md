# Using SIMHarbor

SIMHarbor manages removable eUICC cards locally on a jailbroken iPhone. Card operations require the supported CommCenter extension. This Documents section can be read offline.

## Read and manage profiles

- Pull to refresh Profiles to read the EID, profile list and enabled states.
- Tap a profile to enable, disable, rename it or copy its ICCID.
- Enabling switches the removable card's active line and may interrupt cellular service. The app rereads the card to verify the resulting state.
- Only disabled profiles can be deleted. Your operator determines whether they can be downloaded again.

## Download and QR codes

1. Choose Scan QR to use the camera or select an image containing the operator's activation QR code. The camera continuously focuses; tap the QR code to focus and adjust exposure at that point. A yellow box marks the selected point. Move farther away if the image remains blurred. Manual entry is also available.
2. Use `LPA:1$server$activation-token`. Enter a confirmation code if required. An optional IMEI must contain 15 digits.
3. On the first download, allow the app to access the network. HTTPS uses system and GSMA trust without disabling certificate checks.
4. Keep the app in the foreground until download, installation and notification processing finish. Newly downloaded profiles remain disabled.

## Settings and notifications

The information button opens Card info and settings, Notifications and Signal console.

- Card information includes EID, free storage/working memory, firmware, RSP and profile versions.
- Settings include the default SM-DP+, an unauthenticated HTTP CONNECT proxy, APDU MSS and refresh after switching.
- Automatic install, delete and switch notifications have separate settings. Submit notifications individually or in a batch; remove them after successful submission. Remove-only does not notify the operator.
- An entire-card reset checks the EID and requires typing `RESET`. It removes profiles and has not been tested on the existing card.
- App → Language offers Follow system, English and Simplified Chinese. The interface changes immediately; logs remain English.

## Documents and logs

Search Documents by title, summary or article body. Select text to copy examples and offsets, or use Copy to copy an entire article's displayed text. Reading documentation never executes its examples.

Logs shows English raw signaling with copy, clear and `.log` export. See Logs and custom signals for formats and limits.

## About

The About tab shows the installed app version and build number, developer officeyutong, the GitHub profile at https://github.com/officeyutong, offline documentation and bundled open-source licenses. Version information comes from the installed app.
