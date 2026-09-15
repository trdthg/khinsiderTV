// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String updateIncompleteDownload(String actual, String expected) {
    return 'The download was incomplete ($actual / $expected), so it was deleted. Please try again.';
  }

  @override
  String get updateEmptyDownload =>
      'The downloaded file is empty. Please try again.';

  @override
  String get updateNotAPackage =>
      'What was downloaded is not an installer (the contents are damaged), so it was deleted. Please try again.';

  @override
  String get updateWaitingForConfirmation =>
      'Waiting for you to confirm the install on the system screen';

  @override
  String get updateInstalled => 'Installed';

  @override
  String updateFailedWithMessage(String message) {
    return 'Install failed: $message';
  }

  @override
  String get updateFailedNoMessage => 'Install failed';

  @override
  String get updateBlockedByPolicy =>
      'The system blocked the install, which usually means \"install unknown apps\" is not allowed yet';

  @override
  String get updateAborted =>
      'The system cancelled the install: its confirmation screen never completed';

  @override
  String get updateInvalidPackage =>
      'The installer is not valid (the download may be incomplete). Please try again.';

  @override
  String get updateSignatureConflict =>
      'The installed version conflicts with this installer: the signatures differ, so the old version has to be uninstalled first';

  @override
  String get updateNoSpace =>
      'There is not enough storage on this device. Free some space first.';

  @override
  String get updateIncompatible =>
      'This installer is not compatible with this device';

  @override
  String updateFailedWithStatus(int status, String message) {
    return 'Install failed ($status): $message';
  }

  @override
  String updateFailedWithStatusNoMessage(int status) {
    return 'Install failed ($status)';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Could not check for updates: $error';
  }

  @override
  String updateDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String updateExtractFailed(String error) {
    return 'Could not unpack the update: $error';
  }

  @override
  String get updateNeedInstallPermission =>
      'Android has not allowed this app to install apps yet. Turn that on first.';

  @override
  String updateOpenInstallerFailed(String error) {
    return 'Could not open the installer: $error';
  }

  @override
  String get updateHandedToInstaller =>
      'Handed to the system installer — confirm it on the system screen';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsUpdate => 'Updates';

  @override
  String get settingsCheckUpdate => 'Check for updates';

  @override
  String settingsNewVersion(String version) {
    return 'New version $version';
  }

  @override
  String get settingsOpenReleasePage => 'Open the release page';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsCache => 'Cache';

  @override
  String get settingsCacheSubtitle =>
      'Usage, clearing everything, deleting one album';

  @override
  String get settingsLan => 'LAN';

  @override
  String get settingsLanSubtitle => 'Sync across devices';

  @override
  String get settingsLanSubtitleLong =>
      'Sync favorites between devices on the same WiFi, or play together';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'Version v$version';
  }

  @override
  String get settingsGitHubRepo => 'GitHub repository';

  @override
  String get settingsChecking => 'Checking…';

  @override
  String settingsUpdateFound(String version) {
    return 'Version $version is available';
  }

  @override
  String get settingsUpToDate => 'Up to date';

  @override
  String get settingsFromReleases =>
      'The latest version comes from GitHub Releases';

  @override
  String settingsDownloading(String percent) {
    return 'Downloading $percent%';
  }

  @override
  String get settingsWillOpenInstaller =>
      'The installer opens by itself when the download finishes';

  @override
  String get settingsExtracting => 'Unpacking…';

  @override
  String get settingsReadyToRestart => 'Restart to apply it once this finishes';

  @override
  String get settingsRestartAndUpdate => 'Restart and update';

  @override
  String get settingsReadySubtitle =>
      'The new version is downloaded: restarting applies it';

  @override
  String get settingsInstall => 'Install';

  @override
  String get settingsRetryInstall => 'Retry install';

  @override
  String settingsDownloadedWithSize(String size) {
    return 'Package downloaded ($size). Tap to open the system installer.';
  }

  @override
  String get settingsDownloaded =>
      'Package downloaded. Tap to open the system installer.';

  @override
  String get settingsUseSystemInstaller => 'Use the system installer';

  @override
  String get settingsUseSystemInstallerSubtitle =>
      'Hand the package over the other way (use this when the install session keeps failing)';

  @override
  String get settingsAllowUnknownSources => 'Allow installing unknown apps';

  @override
  String get settingsAllowUnknownSourcesSubtitle =>
      'Allow it, come back here, then tap \"Retry install\"';

  @override
  String get settingsDownloadFailed => 'Download failed';

  @override
  String get settingsPleaseRetry => 'Please try again';

  @override
  String get settingsRetry => 'Retry';

  @override
  String get settingsUseReleasePage =>
      'On this platform, download from the release page';

  @override
  String get settingsNoAutoUpdate =>
      'There is no automatic update package for this platform';

  @override
  String get settingsDownloadAndInstall => 'Download and install';

  @override
  String get settingsUniversalPackage => 'Universal package';

  @override
  String get settingsAutoInstallNote =>
      'Installs itself once downloaded, no questions asked';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Interface language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get cacheClearing => 'Clearing…';

  @override
  String cacheCleared(String size) {
    return 'Cleared $size';
  }

  @override
  String get cacheNothingToClear => 'There is nothing cached to clear';

  @override
  String cacheClearFailed(String error) {
    return 'Could not clear: $error';
  }

  @override
  String get cacheClearingSearch => 'Clearing the search cache…';

  @override
  String cacheSearchCleared(String size) {
    return 'Search cache cleared: $size';
  }

  @override
  String get cacheSearchAlreadyEmpty => 'The search cache was already empty';

  @override
  String get cacheClearingImages => 'Clearing the image cache…';

  @override
  String cacheImagesCleared(String size) {
    return 'Image cache cleared: $size';
  }

  @override
  String get cacheImagesAlreadyEmpty => 'The image cache was already empty';

  @override
  String cacheDeleting(String album) {
    return 'Deleting $album…';
  }

  @override
  String cacheDeleted(String album, String size) {
    return 'Deleted $album ($size)';
  }

  @override
  String cacheDeleteFailed(String error) {
    return 'Could not delete: $error';
  }

  @override
  String get cacheTitle => 'Cache';

  @override
  String get cacheLocation => 'Location';

  @override
  String get cachePublicMusic =>
      'A public Music folder: these files are also the albums exported to Music';

  @override
  String get cacheAppPrivate => 'A private app folder';

  @override
  String get cacheUsage => 'Usage';

  @override
  String get cacheNoAlbums => 'No albums cached yet';

  @override
  String cacheAlbumCount(int count, String size) {
    return '$count albums · $size';
  }

  @override
  String cacheSearchUsage(String size) {
    return 'Search $size';
  }

  @override
  String cacheImageUsage(String size) {
    return 'Images $size';
  }

  @override
  String get cacheClearAll => 'Clear all caches';

  @override
  String get cacheClearAllMusicSubtitle =>
      'Deletes everything under Music/KHInsider, exported albums included';

  @override
  String get cacheClearAllSubtitle => 'Deletes every downloaded album file';

  @override
  String get cacheOther => 'Other caches';

  @override
  String get cacheSearchAndPages => 'Search and page cache';

  @override
  String cacheSearchPagesSubtitle(String size) {
    return '$size · search results and album pages';
  }

  @override
  String get cacheClearSearch => 'Clear the search cache';

  @override
  String get cacheImages => 'Image cache';

  @override
  String cacheImagesSubtitle(String size) {
    return '$size · cover thumbnails';
  }

  @override
  String get cacheClearImages => 'Clear the image cache';

  @override
  String get cacheCachedAlbums => 'Cached albums';

  @override
  String cacheFileCount(int count) {
    return '$count files';
  }

  @override
  String get cacheDownloading => 'Downloading';

  @override
  String cacheDeleteAlbum(String album) {
    return 'Delete the cache for $album';
  }

  @override
  String get actionBack => 'Back';

  @override
  String get searchSettings => 'Settings';

  @override
  String get searchSettingsWithUpdate => 'Settings (an update is available)';

  @override
  String get lanTitle => 'Sync across devices';

  @override
  String get lanThisDevice => 'This device';

  @override
  String get lanDeviceNameHint => 'This is the name other devices see';

  @override
  String lanThisDeviceFavorites(int count) {
    return '$count favorites on this device';
  }

  @override
  String get lanEnabled => 'LAN sync is on';

  @override
  String get lanDisabled => 'LAN sync is off';

  @override
  String get lanEnabledSubtitle =>
      'Devices on the same WiFi can find each other';

  @override
  String get lanStarting => 'Starting…';

  @override
  String get lanDisabledSubtitle => 'No ports are open while this is off';

  @override
  String get lanDevicesOnWifi => 'Devices on the same WiFi';

  @override
  String get lanRefresh => 'Refresh';

  @override
  String get lanNoDevices => 'No devices found yet';

  @override
  String get lanBothDevicesNote =>
      'Both devices need this app open on the same WiFi;';

  @override
  String get lanManualHint =>
      'if the network blocks broadcasts, type an address below';

  @override
  String get lanAddManually => 'Add an address manually';

  @override
  String get lanIpAddress => 'The other device\'s IP address';

  @override
  String get lanIpHint =>
      'Use this when the search finds nothing (for example 192.168.1.23)';

  @override
  String get lanAdd => 'Add';

  @override
  String lanLocalAddress(String address) {
    return 'This device: $address — both devices must be on the same network with the other app still running.';
  }

  @override
  String get lanMergeExplain =>
      'A normal sync only merges: albums either side is missing are added, and nothing is ever deleted.';

  @override
  String get lanOverwriteExplain =>
      'A force overwrite replaces one side\'s favorites with the other\'s. The replaced side loses its favorites, so it needs a second tap to confirm.';

  @override
  String lanAddressPending(String host) {
    return '$host (address not confirmed)';
  }

  @override
  String lanFavoritesCount(int count) {
    return '$count favorites';
  }

  @override
  String get lanTestConnection => 'Test connection';

  @override
  String get lanTestConnectionSubtitle =>
      'Only probes this device, changes nothing';

  @override
  String lanSendToDevice(String name) {
    return 'Send this device\'s favorites to $name';
  }

  @override
  String get lanMergeOnly => 'Adds only';

  @override
  String lanPullFromDevice(String name) {
    return 'Merge $name\'s favorites into this device';
  }

  @override
  String lanForcePush(String name) {
    return 'Force: replace $name\'s favorites with this device\'s';
  }

  @override
  String lanForcePushConfirm(String name) {
    return 'Tap again: overwrite $name\'s favorites';
  }

  @override
  String get lanPeerLoses => 'The other device\'s favorites are deleted';

  @override
  String lanForcePull(String name) {
    return 'Force: replace this device\'s favorites with $name\'s';
  }

  @override
  String get lanForcePullConfirm =>
      'Tap again: overwrite this device\'s favorites';

  @override
  String get lanLocalLoses => 'This device\'s favorites are deleted';

  @override
  String lanRemoveManual(String host) {
    return 'Remove the manual address $host';
  }

  @override
  String get lanTapToConfirm =>
      'Runs on tap; cancels if it is not tapped again within 5 seconds';

  @override
  String lanDiagAt(int port) {
    return '(port $port)';
  }

  @override
  String lanDiagAtVersion(int port, String version) {
    return '(port $port, v$version)';
  }

  @override
  String lanDiagNoAnswer(String name, String at) {
    return '$name did not answer the address probe$at: the other device may have quit, may be on a different network, or the router is blocking UDP as well.';
  }

  @override
  String lanDiagTcpBlocked(String name, String at) {
    return '$name answered the address probe$at, but its API is unreachable: a firewall, the router\'s client isolation, or the other app having been suspended.';
  }

  @override
  String lanDiagOk(String name, String at, int count) {
    return '$name is fine$at, with $count favorites.';
  }

  @override
  String lanStartFailed(String error) {
    return 'Could not start the LAN service: $error';
  }

  @override
  String get lanEnterAddress => 'Enter an address';

  @override
  String lanNoAnswerFrom(String address) {
    return 'No answer from $address';
  }

  @override
  String get lanUnreadableResponse =>
      'The other device sent something this app cannot read';

  @override
  String get lanAnotherDevice => 'another device';

  @override
  String get lanRefusedHint =>
      'The port refused the connection: nothing is listening there any more (the port is reassigned every time the app starts, so the other device may have just restarted).';

  @override
  String get lanTimeoutHint =>
      'The other device did not answer over TCP: its app may have left the foreground (suspended), or a firewall or the router\'s client isolation is blocking TCP — a working UDP with a failing TCP is exactly that. Open this page on both devices and try again.';

  @override
  String lanUnreachableNoPort(String name, String host) {
    return 'Cannot reach $name ($host): its address is not confirmed yet and the address probe did not answer either. Keep the other app running and make sure both devices are on the same network.';
  }

  @override
  String lanUnreachableSeen(String name, String host, int port, String error) {
    return 'Cannot reach $name ($host:$port): $error\nIt shows up in broadcasts, but its service port does not answer.';
  }

  @override
  String lanUnreachableAfterRetry(
    String name,
    String host,
    int port,
    String error,
  ) {
    return 'Cannot reach $name ($host:$port): $error';
  }

  @override
  String lanBadStatus(int status) {
    return 'The other device answered $status';
  }

  @override
  String lanDeviceAndroid(String suffix) {
    return 'Android device $suffix';
  }

  @override
  String lanDeviceApple(String suffix) {
    return 'Apple device $suffix';
  }

  @override
  String lanStatusOverwrittenByPeer(String peer, int total) {
    return '$peer replaced this device\'s favorites: $total now';
  }

  @override
  String lanStatusMergedFromPeer(String peer, int added, int total) {
    return '$peer synced $added favorites over; this device now has $total';
  }

  @override
  String get lanServiceNotRunning => 'The LAN service is not running';

  @override
  String lanTestingDevice(String name) {
    return 'Testing $name…';
  }

  @override
  String get lanSearchingDevices => 'Looking for devices on the same WiFi…';

  @override
  String get lanNoOtherDevices =>
      'No other devices found (the other one needs this app open too)';

  @override
  String lanFoundDevices(int count) {
    return 'Found $count devices';
  }

  @override
  String lanAddedDevice(String name) {
    return 'Added $name';
  }

  @override
  String lanRemovedHost(String host) {
    return 'Removed $host';
  }

  @override
  String lanOverwritingDevice(String name) {
    return 'Replacing $name\'s favorites with this device\'s…';
  }

  @override
  String lanSendingToDevice(String name) {
    return 'Sending to $name…';
  }

  @override
  String lanPushedOverwrite(String peer, int count, int total) {
    return 'Replaced $peer with this device\'s $count favorites; it now has $total';
  }

  @override
  String lanPushedMerge(String peer, int count, int added, int total) {
    return 'Sent $count favorites to $peer, which added $added (it now has $total)';
  }

  @override
  String lanOverwritingLocal(String name) {
    return 'Replacing this device\'s favorites with $name\'s…';
  }

  @override
  String lanReadingFromDevice(String name) {
    return 'Reading from $name…';
  }

  @override
  String lanPulledOverwrite(String peer, int total) {
    return 'Replaced this device\'s favorites with $peer\'s: $total now';
  }

  @override
  String lanPulledMerge(String peer, int added, int total) {
    return 'Merged $peer\'s favorites: $added new, $total now on this device';
  }

  @override
  String get actionPrevious => 'Previous';

  @override
  String get actionNext => 'Next';

  @override
  String get actionPlay => 'Play';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionDone => 'Done';

  @override
  String albumLoadFailed(String error) {
    return 'Failed to load album:\n$error';
  }

  @override
  String get albumForceRefresh => 'Force refresh (bypass cache)';

  @override
  String get albumDetailsTab => 'Details';

  @override
  String get albumDetailsTitle => 'Album details';

  @override
  String get albumExportHint =>
      'Export cached tracks to the system Music folder';

  @override
  String get albumSaveHint => 'Save the cache in the system Music folder';

  @override
  String get albumCopyPath => 'Copy cache folder path';

  @override
  String albumCopied(String path) {
    return 'Copied: $path';
  }

  @override
  String get albumExport => 'Export to Music';

  @override
  String get osdAudioQuality => 'Audio quality';

  @override
  String get osdTheme => 'Theme';

  @override
  String osdThemeWithTooltip(String tooltip) {
    return 'Theme $tooltip';
  }

  @override
  String get searchHint => 'Search game soundtracks…';

  @override
  String get searchClearHistory => 'Clear history';

  @override
  String get searchFavorites => 'Favorites';

  @override
  String get searchRecentlyViewed => 'Recently viewed';

  @override
  String get searchNoResults => 'No albums found.';

  @override
  String get searchRecentSearches => 'Recent searches';

  @override
  String get searchIdleTip =>
      'Search KHInsider for game soundtracks.\nTip: navigate with the D-Pad / gamepad.';

  @override
  String get musicFolderQuestion => 'Save songs in the system Music folder?';

  @override
  String get musicNotNow => 'Not now';

  @override
  String get musicOpenSettings => 'Open settings';

  @override
  String albumTrackCount(int count) {
    return '$count tracks';
  }

  @override
  String get albumFavorite => 'Favorite';

  @override
  String get albumInFavorites => 'In favorites';

  @override
  String get albumPlayedSavedTo => 'Played tracks are saved to Music/KHInsider';

  @override
  String get albumCacheKeptHere =>
      'Cached files are kept here so you can find, export, delete or play them with any other player.';

  @override
  String get albumCopyExplain =>
      'Copy the downloaded tracks into Music/KHInsider. No permission needed.';

  @override
  String get exportCopyingExplain =>
      'Copying the downloaded tracks into Music/KHInsider. No permission needed.';

  @override
  String get exportLookingForCached => 'Looking for cached tracks…';

  @override
  String exportProgress(int done, int total) {
    return '$done / $total tracks';
  }

  @override
  String get musicFolderBody =>
      'Android only lets an app write into Music/ once you grant it \"all files access\" — the next screen has that switch for KHInsider.\n\nDownloads then land in Music/KHInsider, where your file manager, other players and your computer can see them. Tracks that are already downloaded stay in the app folder until you delete or move them.';

  @override
  String get musicFolderDenied =>
      'Turn on \"all files access\", then come back: new downloads go to Music/KHInsider.';

  @override
  String get syncHostTitle => 'Share this device\'s playback';

  @override
  String get syncHostSubtitle =>
      'Other devices can follow this one and stay in step';

  @override
  String get syncHosting => 'Sharing playback';

  @override
  String syncFollowers(int count) {
    return '$count following';
  }

  @override
  String syncFollowDevice(String name) {
    return 'Follow $name';
  }

  @override
  String get syncFollowSubtitle => 'Play the same thing, in step';

  @override
  String get syncStopFollowing => 'Stop following';

  @override
  String get syncDelayMinus => '10 ms earlier';

  @override
  String get syncDelayPlus => '10 ms later';

  @override
  String syncConnecting(String name) {
    return 'Connecting to $name…';
  }

  @override
  String syncFollowing(String name, String drift, String delay) {
    return 'Following $name · $drift ms off$delay';
  }

  @override
  String syncDelaySuffix(String ms) {
    return ' · this device $ms ms late';
  }

  @override
  String get syncHostStopped => 'The other device stopped sharing its playback';

  @override
  String get syncInviteAll => 'Make every other device follow this one';

  @override
  String get syncInviteAllSubtitle =>
      'Remote control: they switch over without you touching them';

  @override
  String syncInvited(int count) {
    return '$count devices are following now';
  }

  @override
  String get syncInvitedNone => 'No other device answered';

  @override
  String syncFailed(String why) {
    return 'Sync problem: $why';
  }
}
