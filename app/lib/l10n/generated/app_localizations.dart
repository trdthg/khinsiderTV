import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @updateIncompleteDownload.
  ///
  /// In en, this message translates to:
  /// **'The download was incomplete ({actual} / {expected}), so it was deleted. Please try again.'**
  String updateIncompleteDownload(String actual, String expected);

  /// No description provided for @updateEmptyDownload.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file is empty. Please try again.'**
  String get updateEmptyDownload;

  /// No description provided for @updateNotAPackage.
  ///
  /// In en, this message translates to:
  /// **'What was downloaded is not an installer (the contents are damaged), so it was deleted. Please try again.'**
  String get updateNotAPackage;

  /// No description provided for @updateWaitingForConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to confirm the install on the system screen'**
  String get updateWaitingForConfirmation;

  /// No description provided for @updateInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get updateInstalled;

  /// No description provided for @updateFailedWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Install failed: {message}'**
  String updateFailedWithMessage(String message);

  /// No description provided for @updateFailedNoMessage.
  ///
  /// In en, this message translates to:
  /// **'Install failed'**
  String get updateFailedNoMessage;

  /// No description provided for @updateBlockedByPolicy.
  ///
  /// In en, this message translates to:
  /// **'The system blocked the install, which usually means \"install unknown apps\" is not allowed yet'**
  String get updateBlockedByPolicy;

  /// No description provided for @updateAborted.
  ///
  /// In en, this message translates to:
  /// **'The system cancelled the install: its confirmation screen never completed'**
  String get updateAborted;

  /// No description provided for @updateInvalidPackage.
  ///
  /// In en, this message translates to:
  /// **'The installer is not valid (the download may be incomplete). Please try again.'**
  String get updateInvalidPackage;

  /// No description provided for @updateSignatureConflict.
  ///
  /// In en, this message translates to:
  /// **'The installed version conflicts with this installer: the signatures differ, so the old version has to be uninstalled first'**
  String get updateSignatureConflict;

  /// No description provided for @updateNoSpace.
  ///
  /// In en, this message translates to:
  /// **'There is not enough storage on this device. Free some space first.'**
  String get updateNoSpace;

  /// No description provided for @updateIncompatible.
  ///
  /// In en, this message translates to:
  /// **'This installer is not compatible with this device'**
  String get updateIncompatible;

  /// No description provided for @updateFailedWithStatus.
  ///
  /// In en, this message translates to:
  /// **'Install failed ({status}): {message}'**
  String updateFailedWithStatus(int status, String message);

  /// No description provided for @updateFailedWithStatusNoMessage.
  ///
  /// In en, this message translates to:
  /// **'Install failed ({status})'**
  String updateFailedWithStatusNoMessage(int status);

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates: {error}'**
  String updateCheckFailed(String error);

  /// No description provided for @updateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String updateDownloadFailed(String error);

  /// No description provided for @updateExtractFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not unpack the update: {error}'**
  String updateExtractFailed(String error);

  /// No description provided for @updateNeedInstallPermission.
  ///
  /// In en, this message translates to:
  /// **'Android has not allowed this app to install apps yet. Turn that on first.'**
  String get updateNeedInstallPermission;

  /// No description provided for @updateOpenInstallerFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the installer: {error}'**
  String updateOpenInstallerFailed(String error);

  /// No description provided for @updateHandedToInstaller.
  ///
  /// In en, this message translates to:
  /// **'Handed to the system installer — confirm it on the system screen'**
  String get updateHandedToInstaller;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdate;

  /// No description provided for @settingsCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckUpdate;

  /// No description provided for @settingsNewVersion.
  ///
  /// In en, this message translates to:
  /// **'New version {version}'**
  String settingsNewVersion(String version);

  /// No description provided for @settingsOpenReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Open the release page'**
  String get settingsOpenReleasePage;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @settingsCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get settingsCache;

  /// No description provided for @settingsCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Usage, clearing everything, deleting one album'**
  String get settingsCacheSubtitle;

  /// No description provided for @settingsLan.
  ///
  /// In en, this message translates to:
  /// **'LAN'**
  String get settingsLan;

  /// No description provided for @settingsLanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync across devices'**
  String get settingsLanSubtitle;

  /// No description provided for @settingsLanSubtitleLong.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites between devices on the same WiFi, or play together'**
  String get settingsLanSubtitleLong;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version v{version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsGitHubRepo.
  ///
  /// In en, this message translates to:
  /// **'GitHub repository'**
  String get settingsGitHubRepo;

  /// No description provided for @settingsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsChecking;

  /// No description provided for @settingsUpdateFound.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String settingsUpdateFound(String version);

  /// No description provided for @settingsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsUpToDate;

  /// No description provided for @settingsFromReleases.
  ///
  /// In en, this message translates to:
  /// **'The latest version comes from GitHub Releases'**
  String get settingsFromReleases;

  /// No description provided for @settingsDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String settingsDownloading(String percent);

  /// No description provided for @settingsWillOpenInstaller.
  ///
  /// In en, this message translates to:
  /// **'The installer opens by itself when the download finishes'**
  String get settingsWillOpenInstaller;

  /// No description provided for @settingsExtracting.
  ///
  /// In en, this message translates to:
  /// **'Unpacking…'**
  String get settingsExtracting;

  /// No description provided for @settingsReadyToRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart to apply it once this finishes'**
  String get settingsReadyToRestart;

  /// No description provided for @settingsRestartAndUpdate.
  ///
  /// In en, this message translates to:
  /// **'Restart and update'**
  String get settingsRestartAndUpdate;

  /// No description provided for @settingsReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The new version is downloaded: restarting applies it'**
  String get settingsReadySubtitle;

  /// No description provided for @settingsInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get settingsInstall;

  /// No description provided for @settingsRetryInstall.
  ///
  /// In en, this message translates to:
  /// **'Retry install'**
  String get settingsRetryInstall;

  /// No description provided for @settingsDownloadedWithSize.
  ///
  /// In en, this message translates to:
  /// **'Package downloaded ({size}). Tap to open the system installer.'**
  String settingsDownloadedWithSize(String size);

  /// No description provided for @settingsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Package downloaded. Tap to open the system installer.'**
  String get settingsDownloaded;

  /// No description provided for @settingsUseSystemInstaller.
  ///
  /// In en, this message translates to:
  /// **'Use the system installer'**
  String get settingsUseSystemInstaller;

  /// No description provided for @settingsUseSystemInstallerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hand the package over the other way (use this when the install session keeps failing)'**
  String get settingsUseSystemInstallerSubtitle;

  /// No description provided for @settingsAllowUnknownSources.
  ///
  /// In en, this message translates to:
  /// **'Allow installing unknown apps'**
  String get settingsAllowUnknownSources;

  /// No description provided for @settingsAllowUnknownSourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow it, come back here, then tap \"Retry install\"'**
  String get settingsAllowUnknownSourcesSubtitle;

  /// No description provided for @settingsDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get settingsDownloadFailed;

  /// No description provided for @settingsPleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'Please try again'**
  String get settingsPleaseRetry;

  /// No description provided for @settingsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsRetry;

  /// No description provided for @settingsUseReleasePage.
  ///
  /// In en, this message translates to:
  /// **'On this platform, download from the release page'**
  String get settingsUseReleasePage;

  /// No description provided for @settingsNoAutoUpdate.
  ///
  /// In en, this message translates to:
  /// **'There is no automatic update package for this platform'**
  String get settingsNoAutoUpdate;

  /// No description provided for @settingsDownloadAndInstall.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get settingsDownloadAndInstall;

  /// No description provided for @settingsUniversalPackage.
  ///
  /// In en, this message translates to:
  /// **'Universal package'**
  String get settingsUniversalPackage;

  /// No description provided for @settingsAutoInstallNote.
  ///
  /// In en, this message translates to:
  /// **'Installs itself once downloaded, no questions asked'**
  String get settingsAutoInstallNote;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get settingsLanguageSubtitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChinese;

  /// No description provided for @cacheClearing.
  ///
  /// In en, this message translates to:
  /// **'Clearing…'**
  String get cacheClearing;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared {size}'**
  String cacheCleared(String size);

  /// No description provided for @cacheNothingToClear.
  ///
  /// In en, this message translates to:
  /// **'There is nothing cached to clear'**
  String get cacheNothingToClear;

  /// No description provided for @cacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear: {error}'**
  String cacheClearFailed(String error);

  /// No description provided for @cacheClearingSearch.
  ///
  /// In en, this message translates to:
  /// **'Clearing the search cache…'**
  String get cacheClearingSearch;

  /// No description provided for @cacheSearchCleared.
  ///
  /// In en, this message translates to:
  /// **'Search cache cleared: {size}'**
  String cacheSearchCleared(String size);

  /// No description provided for @cacheSearchAlreadyEmpty.
  ///
  /// In en, this message translates to:
  /// **'The search cache was already empty'**
  String get cacheSearchAlreadyEmpty;

  /// No description provided for @cacheClearingImages.
  ///
  /// In en, this message translates to:
  /// **'Clearing the image cache…'**
  String get cacheClearingImages;

  /// No description provided for @cacheImagesCleared.
  ///
  /// In en, this message translates to:
  /// **'Image cache cleared: {size}'**
  String cacheImagesCleared(String size);

  /// No description provided for @cacheImagesAlreadyEmpty.
  ///
  /// In en, this message translates to:
  /// **'The image cache was already empty'**
  String get cacheImagesAlreadyEmpty;

  /// No description provided for @cacheDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting {album}…'**
  String cacheDeleting(String album);

  /// No description provided for @cacheDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {album} ({size})'**
  String cacheDeleted(String album, String size);

  /// No description provided for @cacheDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete: {error}'**
  String cacheDeleteFailed(String error);

  /// No description provided for @cacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cacheTitle;

  /// No description provided for @cacheLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get cacheLocation;

  /// No description provided for @cachePublicMusic.
  ///
  /// In en, this message translates to:
  /// **'A public Music folder: these files are also the albums exported to Music'**
  String get cachePublicMusic;

  /// No description provided for @cacheAppPrivate.
  ///
  /// In en, this message translates to:
  /// **'A private app folder'**
  String get cacheAppPrivate;

  /// No description provided for @cacheUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get cacheUsage;

  /// No description provided for @cacheNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums cached yet'**
  String get cacheNoAlbums;

  /// No description provided for @cacheAlbumCount.
  ///
  /// In en, this message translates to:
  /// **'{count} albums · {size}'**
  String cacheAlbumCount(int count, String size);

  /// No description provided for @cacheSearchUsage.
  ///
  /// In en, this message translates to:
  /// **'Search {size}'**
  String cacheSearchUsage(String size);

  /// No description provided for @cacheImageUsage.
  ///
  /// In en, this message translates to:
  /// **'Images {size}'**
  String cacheImageUsage(String size);

  /// No description provided for @cacheClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all caches'**
  String get cacheClearAll;

  /// No description provided for @cacheClearAllMusicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes everything under Music/KHInsider, exported albums included'**
  String get cacheClearAllMusicSubtitle;

  /// No description provided for @cacheClearAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes every downloaded album file'**
  String get cacheClearAllSubtitle;

  /// No description provided for @cacheOther.
  ///
  /// In en, this message translates to:
  /// **'Other caches'**
  String get cacheOther;

  /// No description provided for @cacheSearchAndPages.
  ///
  /// In en, this message translates to:
  /// **'Search and page cache'**
  String get cacheSearchAndPages;

  /// No description provided for @cacheSearchPagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{size} · search results and album pages'**
  String cacheSearchPagesSubtitle(String size);

  /// No description provided for @cacheClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear the search cache'**
  String get cacheClearSearch;

  /// No description provided for @cacheImages.
  ///
  /// In en, this message translates to:
  /// **'Image cache'**
  String get cacheImages;

  /// No description provided for @cacheImagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{size} · cover thumbnails'**
  String cacheImagesSubtitle(String size);

  /// No description provided for @cacheClearImages.
  ///
  /// In en, this message translates to:
  /// **'Clear the image cache'**
  String get cacheClearImages;

  /// No description provided for @cacheCachedAlbums.
  ///
  /// In en, this message translates to:
  /// **'Cached albums'**
  String get cacheCachedAlbums;

  /// No description provided for @cacheFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String cacheFileCount(int count);

  /// No description provided for @cacheDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get cacheDownloading;

  /// No description provided for @cacheDeleteAlbum.
  ///
  /// In en, this message translates to:
  /// **'Delete the cache for {album}'**
  String cacheDeleteAlbum(String album);

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @searchSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get searchSettings;

  /// No description provided for @searchSettingsWithUpdate.
  ///
  /// In en, this message translates to:
  /// **'Settings (an update is available)'**
  String get searchSettingsWithUpdate;

  /// No description provided for @lanTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync across devices'**
  String get lanTitle;

  /// No description provided for @lanThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get lanThisDevice;

  /// No description provided for @lanDeviceNameHint.
  ///
  /// In en, this message translates to:
  /// **'This is the name other devices see'**
  String get lanDeviceNameHint;

  /// No description provided for @lanThisDeviceFavorites.
  ///
  /// In en, this message translates to:
  /// **'{count} favorites on this device'**
  String lanThisDeviceFavorites(int count);

  /// No description provided for @lanEnabled.
  ///
  /// In en, this message translates to:
  /// **'LAN sync is on'**
  String get lanEnabled;

  /// No description provided for @lanDisabled.
  ///
  /// In en, this message translates to:
  /// **'LAN sync is off'**
  String get lanDisabled;

  /// No description provided for @lanEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Devices on the same WiFi can find each other'**
  String get lanEnabledSubtitle;

  /// No description provided for @lanStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get lanStarting;

  /// No description provided for @lanDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No ports are open while this is off'**
  String get lanDisabledSubtitle;

  /// No description provided for @lanDevicesOnWifi.
  ///
  /// In en, this message translates to:
  /// **'Devices on the same WiFi'**
  String get lanDevicesOnWifi;

  /// No description provided for @lanRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get lanRefresh;

  /// No description provided for @lanNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices found yet'**
  String get lanNoDevices;

  /// No description provided for @lanBothDevicesNote.
  ///
  /// In en, this message translates to:
  /// **'Both devices need this app open on the same WiFi;'**
  String get lanBothDevicesNote;

  /// No description provided for @lanManualHint.
  ///
  /// In en, this message translates to:
  /// **'if the network blocks broadcasts, type an address below'**
  String get lanManualHint;

  /// No description provided for @lanAddManually.
  ///
  /// In en, this message translates to:
  /// **'Add an address manually'**
  String get lanAddManually;

  /// No description provided for @lanIpAddress.
  ///
  /// In en, this message translates to:
  /// **'The other device\'s IP address'**
  String get lanIpAddress;

  /// No description provided for @lanIpHint.
  ///
  /// In en, this message translates to:
  /// **'Use this when the search finds nothing (for example 192.168.1.23)'**
  String get lanIpHint;

  /// No description provided for @lanAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get lanAdd;

  /// No description provided for @lanLocalAddress.
  ///
  /// In en, this message translates to:
  /// **'This device: {address} — both devices must be on the same network with the other app still running.'**
  String lanLocalAddress(String address);

  /// No description provided for @lanMergeExplain.
  ///
  /// In en, this message translates to:
  /// **'A normal sync only merges: albums either side is missing are added, and nothing is ever deleted.'**
  String get lanMergeExplain;

  /// No description provided for @lanOverwriteExplain.
  ///
  /// In en, this message translates to:
  /// **'A force overwrite replaces one side\'s favorites with the other\'s. The replaced side loses its favorites, so it needs a second tap to confirm.'**
  String get lanOverwriteExplain;

  /// No description provided for @lanAddressPending.
  ///
  /// In en, this message translates to:
  /// **'{host} (address not confirmed)'**
  String lanAddressPending(String host);

  /// No description provided for @lanFavoritesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} favorites'**
  String lanFavoritesCount(int count);

  /// No description provided for @lanTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get lanTestConnection;

  /// No description provided for @lanTestConnectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only probes this device, changes nothing'**
  String get lanTestConnectionSubtitle;

  /// No description provided for @lanSendToDevice.
  ///
  /// In en, this message translates to:
  /// **'Send this device\'s favorites to {name}'**
  String lanSendToDevice(String name);

  /// No description provided for @lanMergeOnly.
  ///
  /// In en, this message translates to:
  /// **'Adds only'**
  String get lanMergeOnly;

  /// No description provided for @lanPullFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Merge {name}\'s favorites into this device'**
  String lanPullFromDevice(String name);

  /// No description provided for @lanForcePush.
  ///
  /// In en, this message translates to:
  /// **'Force: replace {name}\'s favorites with this device\'s'**
  String lanForcePush(String name);

  /// No description provided for @lanForcePushConfirm.
  ///
  /// In en, this message translates to:
  /// **'Tap again: overwrite {name}\'s favorites'**
  String lanForcePushConfirm(String name);

  /// No description provided for @lanPeerLoses.
  ///
  /// In en, this message translates to:
  /// **'The other device\'s favorites are deleted'**
  String get lanPeerLoses;

  /// No description provided for @lanForcePull.
  ///
  /// In en, this message translates to:
  /// **'Force: replace this device\'s favorites with {name}\'s'**
  String lanForcePull(String name);

  /// No description provided for @lanForcePullConfirm.
  ///
  /// In en, this message translates to:
  /// **'Tap again: overwrite this device\'s favorites'**
  String get lanForcePullConfirm;

  /// No description provided for @lanLocalLoses.
  ///
  /// In en, this message translates to:
  /// **'This device\'s favorites are deleted'**
  String get lanLocalLoses;

  /// No description provided for @lanRemoveManual.
  ///
  /// In en, this message translates to:
  /// **'Remove the manual address {host}'**
  String lanRemoveManual(String host);

  /// No description provided for @lanTapToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Runs on tap; cancels if it is not tapped again within 5 seconds'**
  String get lanTapToConfirm;

  /// No description provided for @lanDiagAt.
  ///
  /// In en, this message translates to:
  /// **'(port {port})'**
  String lanDiagAt(int port);

  /// No description provided for @lanDiagAtVersion.
  ///
  /// In en, this message translates to:
  /// **'(port {port}, v{version})'**
  String lanDiagAtVersion(int port, String version);

  /// No description provided for @lanDiagNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'{name} did not answer the address probe{at}: the other device may have quit, may be on a different network, or the router is blocking UDP as well.'**
  String lanDiagNoAnswer(String name, String at);

  /// No description provided for @lanDiagTcpBlocked.
  ///
  /// In en, this message translates to:
  /// **'{name} answered the address probe{at}, but its API is unreachable: a firewall, the router\'s client isolation, or the other app having been suspended.'**
  String lanDiagTcpBlocked(String name, String at);

  /// No description provided for @lanDiagOk.
  ///
  /// In en, this message translates to:
  /// **'{name} is fine{at}, with {count} favorites.'**
  String lanDiagOk(String name, String at, int count);

  /// No description provided for @lanStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the LAN service: {error}'**
  String lanStartFailed(String error);

  /// No description provided for @lanEnterAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter an address'**
  String get lanEnterAddress;

  /// No description provided for @lanNoAnswerFrom.
  ///
  /// In en, this message translates to:
  /// **'No answer from {address}'**
  String lanNoAnswerFrom(String address);

  /// No description provided for @lanUnreadableResponse.
  ///
  /// In en, this message translates to:
  /// **'The other device sent something this app cannot read'**
  String get lanUnreadableResponse;

  /// No description provided for @lanAnotherDevice.
  ///
  /// In en, this message translates to:
  /// **'another device'**
  String get lanAnotherDevice;

  /// No description provided for @lanRefusedHint.
  ///
  /// In en, this message translates to:
  /// **'The port refused the connection: nothing is listening there any more (the port is reassigned every time the app starts, so the other device may have just restarted).'**
  String get lanRefusedHint;

  /// No description provided for @lanTimeoutHint.
  ///
  /// In en, this message translates to:
  /// **'The other device did not answer over TCP: its app may have left the foreground (suspended), or a firewall or the router\'s client isolation is blocking TCP — a working UDP with a failing TCP is exactly that. Open this page on both devices and try again.'**
  String get lanTimeoutHint;

  /// No description provided for @lanUnreachableNoPort.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {name} ({host}): its address is not confirmed yet and the address probe did not answer either. Keep the other app running and make sure both devices are on the same network.'**
  String lanUnreachableNoPort(String name, String host);

  /// No description provided for @lanUnreachableSeen.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {name} ({host}:{port}): {error}\nIt shows up in broadcasts, but its service port does not answer.'**
  String lanUnreachableSeen(String name, String host, int port, String error);

  /// No description provided for @lanUnreachableAfterRetry.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {name} ({host}:{port}): {error}'**
  String lanUnreachableAfterRetry(
    String name,
    String host,
    int port,
    String error,
  );

  /// No description provided for @lanBadStatus.
  ///
  /// In en, this message translates to:
  /// **'The other device answered {status}'**
  String lanBadStatus(int status);

  /// No description provided for @lanDeviceAndroid.
  ///
  /// In en, this message translates to:
  /// **'Android device {suffix}'**
  String lanDeviceAndroid(String suffix);

  /// No description provided for @lanDeviceApple.
  ///
  /// In en, this message translates to:
  /// **'Apple device {suffix}'**
  String lanDeviceApple(String suffix);

  /// No description provided for @lanStatusOverwrittenByPeer.
  ///
  /// In en, this message translates to:
  /// **'{peer} replaced this device\'s favorites: {total} now'**
  String lanStatusOverwrittenByPeer(String peer, int total);

  /// No description provided for @lanStatusMergedFromPeer.
  ///
  /// In en, this message translates to:
  /// **'{peer} synced {added} favorites over; this device now has {total}'**
  String lanStatusMergedFromPeer(String peer, int added, int total);

  /// No description provided for @lanServiceNotRunning.
  ///
  /// In en, this message translates to:
  /// **'The LAN service is not running'**
  String get lanServiceNotRunning;

  /// No description provided for @lanTestingDevice.
  ///
  /// In en, this message translates to:
  /// **'Testing {name}…'**
  String lanTestingDevice(String name);

  /// No description provided for @lanSearchingDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices on the same WiFi…'**
  String get lanSearchingDevices;

  /// No description provided for @lanNoOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'No other devices found (the other one needs this app open too)'**
  String get lanNoOtherDevices;

  /// No description provided for @lanFoundDevices.
  ///
  /// In en, this message translates to:
  /// **'Found {count} devices'**
  String lanFoundDevices(int count);

  /// No description provided for @lanAddedDevice.
  ///
  /// In en, this message translates to:
  /// **'Added {name}'**
  String lanAddedDevice(String name);

  /// No description provided for @lanRemovedHost.
  ///
  /// In en, this message translates to:
  /// **'Removed {host}'**
  String lanRemovedHost(String host);

  /// No description provided for @lanOverwritingDevice.
  ///
  /// In en, this message translates to:
  /// **'Replacing {name}\'s favorites with this device\'s…'**
  String lanOverwritingDevice(String name);

  /// No description provided for @lanSendingToDevice.
  ///
  /// In en, this message translates to:
  /// **'Sending to {name}…'**
  String lanSendingToDevice(String name);

  /// No description provided for @lanPushedOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Replaced {peer} with this device\'s {count} favorites; it now has {total}'**
  String lanPushedOverwrite(String peer, int count, int total);

  /// No description provided for @lanPushedMerge.
  ///
  /// In en, this message translates to:
  /// **'Sent {count} favorites to {peer}, which added {added} (it now has {total})'**
  String lanPushedMerge(String peer, int count, int added, int total);

  /// No description provided for @lanOverwritingLocal.
  ///
  /// In en, this message translates to:
  /// **'Replacing this device\'s favorites with {name}\'s…'**
  String lanOverwritingLocal(String name);

  /// No description provided for @lanReadingFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Reading from {name}…'**
  String lanReadingFromDevice(String name);

  /// No description provided for @lanPulledOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Replaced this device\'s favorites with {peer}\'s: {total} now'**
  String lanPulledOverwrite(String peer, int total);

  /// No description provided for @lanPulledMerge.
  ///
  /// In en, this message translates to:
  /// **'Merged {peer}\'s favorites: {added} new, {total} now on this device'**
  String lanPulledMerge(String peer, int added, int total);

  /// No description provided for @actionPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get actionPrevious;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionPlay;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @albumLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load album:\n{error}'**
  String albumLoadFailed(String error);

  /// No description provided for @albumForceRefresh.
  ///
  /// In en, this message translates to:
  /// **'Force refresh (bypass cache)'**
  String get albumForceRefresh;

  /// No description provided for @albumDetailsTab.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get albumDetailsTab;

  /// No description provided for @albumDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Album details'**
  String get albumDetailsTitle;

  /// No description provided for @albumExportHint.
  ///
  /// In en, this message translates to:
  /// **'Export cached tracks to the system Music folder'**
  String get albumExportHint;

  /// No description provided for @albumSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Save the cache in the system Music folder'**
  String get albumSaveHint;

  /// No description provided for @albumCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy cache folder path'**
  String get albumCopyPath;

  /// No description provided for @albumCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied: {path}'**
  String albumCopied(String path);

  /// No description provided for @albumExport.
  ///
  /// In en, this message translates to:
  /// **'Export to Music'**
  String get albumExport;

  /// No description provided for @osdAudioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get osdAudioQuality;

  /// No description provided for @osdTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get osdTheme;

  /// No description provided for @osdThemeWithTooltip.
  ///
  /// In en, this message translates to:
  /// **'Theme {tooltip}'**
  String osdThemeWithTooltip(String tooltip);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search game soundtracks…'**
  String get searchHint;

  /// No description provided for @searchClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get searchClearHistory;

  /// No description provided for @searchFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get searchFavorites;

  /// No description provided for @searchRecentlyViewed.
  ///
  /// In en, this message translates to:
  /// **'Recently viewed'**
  String get searchRecentlyViewed;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No albums found.'**
  String get searchNoResults;

  /// No description provided for @searchRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchRecentSearches;

  /// No description provided for @searchIdleTip.
  ///
  /// In en, this message translates to:
  /// **'Search KHInsider for game soundtracks.\nTip: navigate with the D-Pad / gamepad.'**
  String get searchIdleTip;

  /// No description provided for @musicFolderQuestion.
  ///
  /// In en, this message translates to:
  /// **'Save songs in the system Music folder?'**
  String get musicFolderQuestion;

  /// No description provided for @musicNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get musicNotNow;

  /// No description provided for @musicOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get musicOpenSettings;

  /// No description provided for @albumTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String albumTrackCount(int count);

  /// No description provided for @albumFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get albumFavorite;

  /// No description provided for @albumInFavorites.
  ///
  /// In en, this message translates to:
  /// **'In favorites'**
  String get albumInFavorites;

  /// No description provided for @albumPlayedSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Played tracks are saved to Music/KHInsider'**
  String get albumPlayedSavedTo;

  /// No description provided for @albumCacheKeptHere.
  ///
  /// In en, this message translates to:
  /// **'Cached files are kept here so you can find, export, delete or play them with any other player.'**
  String get albumCacheKeptHere;

  /// No description provided for @albumCopyExplain.
  ///
  /// In en, this message translates to:
  /// **'Copy the downloaded tracks into Music/KHInsider. No permission needed.'**
  String get albumCopyExplain;

  /// No description provided for @exportCopyingExplain.
  ///
  /// In en, this message translates to:
  /// **'Copying the downloaded tracks into Music/KHInsider. No permission needed.'**
  String get exportCopyingExplain;

  /// No description provided for @exportLookingForCached.
  ///
  /// In en, this message translates to:
  /// **'Looking for cached tracks…'**
  String get exportLookingForCached;

  /// No description provided for @exportProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} tracks'**
  String exportProgress(int done, int total);

  /// No description provided for @musicFolderBody.
  ///
  /// In en, this message translates to:
  /// **'Android only lets an app write into Music/ once you grant it \"all files access\" — the next screen has that switch for KHInsider.\n\nDownloads then land in Music/KHInsider, where your file manager, other players and your computer can see them. Tracks that are already downloaded stay in the app folder until you delete or move them.'**
  String get musicFolderBody;

  /// No description provided for @musicFolderDenied.
  ///
  /// In en, this message translates to:
  /// **'Turn on \"all files access\", then come back: new downloads go to Music/KHInsider.'**
  String get musicFolderDenied;

  /// No description provided for @syncHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Share this device\'s playback'**
  String get syncHostTitle;

  /// No description provided for @syncHostSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Other devices can follow this one and stay in step'**
  String get syncHostSubtitle;

  /// No description provided for @syncHosting.
  ///
  /// In en, this message translates to:
  /// **'Sharing playback'**
  String get syncHosting;

  /// No description provided for @syncFollowers.
  ///
  /// In en, this message translates to:
  /// **'{count} following'**
  String syncFollowers(int count);

  /// No description provided for @syncFollowDevice.
  ///
  /// In en, this message translates to:
  /// **'Follow {name}'**
  String syncFollowDevice(String name);

  /// No description provided for @syncFollowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play the same thing, in step'**
  String get syncFollowSubtitle;

  /// No description provided for @syncStopFollowing.
  ///
  /// In en, this message translates to:
  /// **'Stop following'**
  String get syncStopFollowing;

  /// No description provided for @syncDelayMinus.
  ///
  /// In en, this message translates to:
  /// **'10 ms earlier'**
  String get syncDelayMinus;

  /// No description provided for @syncDelayPlus.
  ///
  /// In en, this message translates to:
  /// **'10 ms later'**
  String get syncDelayPlus;

  /// No description provided for @syncConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}…'**
  String syncConnecting(String name);

  /// No description provided for @syncFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following {name} · {drift} ms off{delay}'**
  String syncFollowing(String name, String drift, String delay);

  /// No description provided for @syncDelaySuffix.
  ///
  /// In en, this message translates to:
  /// **' · this device {ms} ms late'**
  String syncDelaySuffix(String ms);

  /// No description provided for @syncHostStopped.
  ///
  /// In en, this message translates to:
  /// **'The other device stopped sharing its playback'**
  String get syncHostStopped;

  /// No description provided for @syncInviteAll.
  ///
  /// In en, this message translates to:
  /// **'Make every other device follow this one'**
  String get syncInviteAll;

  /// No description provided for @syncInviteAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remote control: they switch over without you touching them'**
  String get syncInviteAllSubtitle;

  /// No description provided for @syncInvited.
  ///
  /// In en, this message translates to:
  /// **'{count} devices are following now'**
  String syncInvited(int count);

  /// No description provided for @syncInvitedNone.
  ///
  /// In en, this message translates to:
  /// **'No other device answered'**
  String get syncInvitedNone;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync problem: {why}'**
  String syncFailed(String why);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
