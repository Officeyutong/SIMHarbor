# Using SIMHarbor

SIMHarbor manages removable eUICC cards locally on a jailbroken iPhone. Card operations require the supported CommCenter extension. This user guide can be read offline.

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
- Automatic operator notification submission is enabled by default. In Card and settings → Notifications and switching, turn off Automatically submit notifications to disable it, or disable individual install/delete/switch categories. After a successful install, deletion or profile switch, the app submits all pending notifications of enabled categories on that same eUICC, including the old profile’s disable notification during a switch. Submission stops on the first error, keeps unsubmitted notifications, and reports a warning without undoing the completed profile operation. Merely selecting a management slot does not send notifications. Submit notifications individually or in a batch; remove them after successful submission. Remove-only does not notify the operator.
- An entire-card reset checks the EID and requires typing `RESET`. It removes profiles and has not been tested on the existing card.
- App → Language offers Follow system, English and Simplified Chinese. The interface changes immediately; logs remain English.

## User guide, logs and custom signals

The User guide tab opens these instructions directly. Select text or use Copy to copy the guide. Reading it sends no card commands and requires no network connection.

Logs shows English raw signaling with copy, clear and `.log` export. Logs can contain activation credentials and card identifiers; review them before sharing.

Signal console accepts raw APDU batches or an ES10 DER request and shows the response. Start with its read-only Get EID example when checking the connection. The console defaults to ES10 DER, and filling the example selects that mode so `61xx` follow-up data is collected. In raw mode, `61xx` means more response data is available; `6Cxx` requests a corrected response length. Neither is silently retried. Sending requires confirmation; commands can modify card data. Raw APDU mode does not automatically retry commands or fetch follow-up responses. DER mode handles the configured request fragmentation and response collection.

## About

The About tab shows the installed app version and build number, developer officeyutong, the GitHub profile at https://github.com/officeyutong, the user guide and bundled open-source licenses. Version information comes from the installed app.
