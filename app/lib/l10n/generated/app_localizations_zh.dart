// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String updateIncompleteDownload(String actual, String expected) {
    return '下载不完整（$actual / $expected），已删除，请重试';
  }

  @override
  String get updateEmptyDownload => '下载的文件是空的，请重试';

  @override
  String get updateNotAPackage => '下载到的不是安装包（内容损坏），已删除，请重试';

  @override
  String get updateWaitingForConfirmation => '等待你在系统界面上确认安装';

  @override
  String get updateInstalled => '安装完成';

  @override
  String updateFailedWithMessage(String message) {
    return '安装失败：$message';
  }

  @override
  String get updateFailedNoMessage => '安装失败';

  @override
  String get updateBlockedByPolicy => '系统阻止了安装，通常是「安装未知应用」没有允许';

  @override
  String get updateAborted => '安装被系统取消了：系统的安装确认界面没有完成';

  @override
  String get updateInvalidPackage => '安装包无效（下载可能不完整），请重试';

  @override
  String get updateSignatureConflict => '已安装的版本与安装包冲突：签名不同，需要先卸载旧版本';

  @override
  String get updateNoSpace => '设备存储空间不足，请先清理空间';

  @override
  String get updateIncompatible => '安装包与这台设备不兼容';

  @override
  String updateFailedWithStatus(int status, String message) {
    return '安装失败（$status）：$message';
  }

  @override
  String updateFailedWithStatusNoMessage(int status) {
    return '安装失败（$status）';
  }

  @override
  String updateCheckFailed(String error) {
    return '检查更新失败：$error';
  }

  @override
  String updateDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String updateExtractFailed(String error) {
    return '解压失败：$error';
  }

  @override
  String get updateNeedInstallPermission => '系统还没有允许本应用安装应用，请先打开这个开关';

  @override
  String updateOpenInstallerFailed(String error) {
    return '打开安装界面失败：$error';
  }

  @override
  String get updateHandedToInstaller => '已交给系统安装器，请在系统界面上确认';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsUpdate => '更新';

  @override
  String get settingsCheckUpdate => '检查更新';

  @override
  String settingsNewVersion(String version) {
    return '新版本 v$version';
  }

  @override
  String get settingsOpenReleasePage => '打开发布页';

  @override
  String get settingsStorage => '存储';

  @override
  String get settingsCache => '缓存';

  @override
  String get settingsCacheSubtitle => '查看占用、清除全部缓存、删除单张专辑';

  @override
  String get settingsLan => '局域网';

  @override
  String get settingsLanSubtitle => '跨设备同步';

  @override
  String get settingsLanSubtitleLong => '同一 WiFi 下的设备之间同步收藏、一起播放';

  @override
  String get settingsAbout => '关于';

  @override
  String settingsVersion(String version) {
    return '版本 v$version';
  }

  @override
  String get settingsGitHubRepo => 'GitHub 仓库';

  @override
  String get settingsChecking => '正在检查…';

  @override
  String settingsUpdateFound(String version) {
    return '发现新版本 v$version';
  }

  @override
  String get settingsUpToDate => '已是最新版本';

  @override
  String get settingsFromReleases => '从 GitHub Releases 获取最新版本';

  @override
  String settingsDownloading(String percent) {
    return '下载中 $percent%';
  }

  @override
  String get settingsWillOpenInstaller => '下载完成后会自动打开安装界面';

  @override
  String get settingsExtracting => '正在解压…';

  @override
  String get settingsReadyToRestart => '完成后即可重启更新';

  @override
  String get settingsRestartAndUpdate => '重启并更新';

  @override
  String get settingsReadySubtitle => '新版本已下载完成，重启后生效';

  @override
  String get settingsInstall => '安装';

  @override
  String get settingsRetryInstall => '重试安装';

  @override
  String settingsDownloadedWithSize(String size) {
    return '安装包已下载（$size），点这里打开系统安装界面';
  }

  @override
  String get settingsDownloaded => '安装包已下载，点这里打开系统安装界面';

  @override
  String get settingsUseSystemInstaller => '改用系统安装器';

  @override
  String get settingsUseSystemInstallerSubtitle => '换一种方式把安装包交给系统（安装会话一直失败时用它）';

  @override
  String get settingsAllowUnknownSources => '去允许安装未知应用';

  @override
  String get settingsAllowUnknownSourcesSubtitle => '允许之后回到这里，再点一次「重试安装」';

  @override
  String get settingsDownloadFailed => '下载失败';

  @override
  String get settingsPleaseRetry => '请重试';

  @override
  String get settingsRetry => '重试';

  @override
  String get settingsUseReleasePage => '此平台请从发布页下载';

  @override
  String get settingsNoAutoUpdate => '没有适用于当前平台的自动更新包';

  @override
  String get settingsDownloadAndInstall => '下载并安装';

  @override
  String get settingsUniversalPackage => '通用安装包';

  @override
  String get settingsAutoInstallNote => '下载完成后直接安装，不再询问';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSubtitle => '界面语言';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get cacheClearing => '正在清除…';

  @override
  String cacheCleared(String size) {
    return '已清除 $size';
  }

  @override
  String get cacheNothingToClear => '没有可清除的缓存';

  @override
  String cacheClearFailed(String error) {
    return '清除失败：$error';
  }

  @override
  String get cacheClearingSearch => '正在清除搜索缓存…';

  @override
  String cacheSearchCleared(String size) {
    return '已清除搜索缓存 $size';
  }

  @override
  String get cacheSearchAlreadyEmpty => '搜索缓存本来就是空的';

  @override
  String get cacheClearingImages => '正在清除图片缓存…';

  @override
  String cacheImagesCleared(String size) {
    return '已清除图片缓存 $size';
  }

  @override
  String get cacheImagesAlreadyEmpty => '图片缓存本来就是空的';

  @override
  String cacheDeleting(String album) {
    return '正在删除《$album》…';
  }

  @override
  String cacheDeleted(String album, String size) {
    return '已删除《$album》($size)';
  }

  @override
  String cacheDeleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get cacheTitle => '缓存';

  @override
  String get cacheLocation => '位置';

  @override
  String get cachePublicMusic => '公开的 Music 目录：这里的文件同时是导出到 Music 的专辑';

  @override
  String get cacheAppPrivate => '应用私有目录';

  @override
  String get cacheUsage => '占用';

  @override
  String get cacheNoAlbums => '还没有缓存任何专辑';

  @override
  String cacheAlbumCount(int count, String size) {
    return '$count 张专辑 $size';
  }

  @override
  String cacheSearchUsage(String size) {
    return '搜索 $size';
  }

  @override
  String cacheImageUsage(String size) {
    return '图片 $size';
  }

  @override
  String get cacheClearAll => '清除全部缓存';

  @override
  String get cacheClearAllMusicSubtitle =>
      '一键删除 Music/KHInsider 下的全部内容（包括已导出的专辑）';

  @override
  String get cacheClearAllSubtitle => '一键删除已下载的全部专辑文件';

  @override
  String get cacheOther => '其它缓存';

  @override
  String get cacheSearchAndPages => '搜索与网页缓存';

  @override
  String cacheSearchPagesSubtitle(String size) {
    return '$size · 搜索结果和专辑页面的 HTML';
  }

  @override
  String get cacheClearSearch => '清除搜索缓存';

  @override
  String get cacheImages => '图片缓存';

  @override
  String cacheImagesSubtitle(String size) {
    return '$size · 封面缩略图';
  }

  @override
  String get cacheClearImages => '清除图片缓存';

  @override
  String get cacheCachedAlbums => '已缓存的专辑';

  @override
  String cacheFileCount(int count) {
    return '$count 个文件';
  }

  @override
  String get cacheDownloading => '下载中';

  @override
  String cacheDeleteAlbum(String album) {
    return '删除《$album》的缓存';
  }

  @override
  String get actionBack => '返回';

  @override
  String get searchSettings => '设置';

  @override
  String get searchSettingsWithUpdate => '设置（有可用更新）';

  @override
  String get lanTitle => '跨设备同步';

  @override
  String get lanThisDevice => '本机';

  @override
  String get lanDeviceNameHint => '别的设备会看到这个名字';

  @override
  String lanThisDeviceFavorites(int count) {
    return '本机收藏 $count 张';
  }

  @override
  String get lanEnabled => '局域网同步已开启';

  @override
  String get lanDisabled => '局域网同步已关闭';

  @override
  String get lanEnabledSubtitle => '同一 WiFi 下的设备可以互相发现';

  @override
  String get lanStarting => '正在启动…';

  @override
  String get lanDisabledSubtitle => '关闭后不监听任何端口';

  @override
  String get lanDevicesOnWifi => '同一 WiFi 下的设备';

  @override
  String get lanRefresh => '刷新';

  @override
  String get lanNoDevices => '还没有发现设备';

  @override
  String get lanBothDevicesNote => '两台设备都要打开本应用、连同一个 WiFi；';

  @override
  String get lanManualHint => '如果网络禁止广播，可在下面手动填地址';

  @override
  String get lanAddManually => '手动添加地址';

  @override
  String get lanIpAddress => '对方的 IP 地址';

  @override
  String get lanIpHint => '自动搜索不到时用这个（例如 192.168.1.23）';

  @override
  String get lanAdd => '添加';

  @override
  String lanLocalAddress(String address) {
    return '本机地址：$address —— 两台设备要在同一个网络，且对方的应用还在运行。';
  }

  @override
  String get lanMergeExplain => '普通同步只做「合并」：两边都没有的专辑会补上，已有的收藏都不会被删除。';

  @override
  String get lanOverwriteExplain =>
      '「强制覆盖」会用一边的收藏替换另一边，被覆盖那边的收藏会消失，所以需要连点两次确认。';

  @override
  String lanAddressPending(String host) {
    return '$host（地址待确认）';
  }

  @override
  String lanFavoritesCount(int count) {
    return '收藏 $count 张';
  }

  @override
  String get lanTestConnection => '测试连接';

  @override
  String get lanTestConnectionSubtitle => '只探测这台设备，不改动任何收藏';

  @override
  String lanSendToDevice(String name) {
    return '把本机收藏发送到 $name';
  }

  @override
  String get lanMergeOnly => '只增不减';

  @override
  String lanPullFromDevice(String name) {
    return '把 $name 的收藏合并到本机';
  }

  @override
  String lanForcePush(String name) {
    return '强制：用本机收藏覆盖 $name';
  }

  @override
  String lanForcePushConfirm(String name) {
    return '再点一次：覆盖 $name 的收藏';
  }

  @override
  String get lanPeerLoses => '对方原有的收藏会被删除';

  @override
  String lanForcePull(String name) {
    return '强制：用 $name 的收藏覆盖本机';
  }

  @override
  String get lanForcePullConfirm => '再点一次：覆盖本机的收藏';

  @override
  String get lanLocalLoses => '本机原有的收藏会被删除';

  @override
  String lanRemoveManual(String host) {
    return '移除手动地址 $host';
  }

  @override
  String get lanTapToConfirm => '点击即执行，5 秒内没有再点就取消';

  @override
  String lanDiagAt(int port) {
    return '（端口 $port）';
  }

  @override
  String lanDiagAtVersion(int port, String version) {
    return '（端口 $port，v$version）';
  }

  @override
  String lanDiagNoAnswer(String name, String at) {
    return '$name 的地址探测没有回应$at：对方可能已经退出、不在同一个网络里，或者路由器把 UDP 也挡了。';
  }

  @override
  String lanDiagTcpBlocked(String name, String at) {
    return '$name 的地址探测有回应$at，但连不上它的 API：对方的防火墙、路由器的客户端隔离挡住了 TCP，或者对方的应用刚被系统挂起。';
  }

  @override
  String lanDiagOk(String name, String at, int count) {
    return '$name 一切正常$at，收藏 $count 张。';
  }

  @override
  String lanStartFailed(String error) {
    return '无法启动局域网服务：$error';
  }

  @override
  String get lanEnterAddress => '请输入地址';

  @override
  String lanNoAnswerFrom(String address) {
    return '$address 上没有回应';
  }

  @override
  String get lanUnreadableResponse => '对方返回的数据无法识别';

  @override
  String get lanAnotherDevice => '另一台设备';

  @override
  String get lanRefusedHint =>
      '对方的端口拒绝连接：那个端口上没有服务在听（应用每次启动都会重新分配端口，对方可能刚重启过）。';

  @override
  String get lanTimeoutHint =>
      '对方没有回应 TCP：对方的应用可能已经不在前台（被系统挂起），也可能是防火墙或路由器的\"客户端隔离\"（AP 隔离）—— UDP 能通、TCP 不通正是这两种情况的特征。请在两边都打开这个页面再试。';

  @override
  String lanUnreachableNoPort(String name, String host) {
    return '连不上 $name（$host）：它的地址还没有确认，地址探测也没有回应。请让对方的应用保持运行，并确认两台设备在同一个网络里。';
  }

  @override
  String lanUnreachableSeen(String name, String host, int port, String error) {
    return '连不上 $name（$host:$port）：$error\n它在广播里能看到，但连它的服务端口没有回应。';
  }

  @override
  String lanUnreachableAfterRetry(
    String name,
    String host,
    int port,
    String error,
  ) {
    return '连不上 $name（$host:$port）：$error';
  }

  @override
  String lanBadStatus(int status) {
    return '对方返回 $status';
  }

  @override
  String lanDeviceAndroid(String suffix) {
    return '安卓设备 $suffix';
  }

  @override
  String lanDeviceApple(String suffix) {
    return '苹果设备 $suffix';
  }

  @override
  String lanStatusOverwrittenByPeer(String peer, int total) {
    return '$peer 用它的收藏覆盖了本机：现在有 $total 张';
  }

  @override
  String lanStatusMergedFromPeer(String peer, int added, int total) {
    return '$peer 同步过来 $added 张收藏，本机现有 $total 张';
  }

  @override
  String get lanServiceNotRunning => '局域网服务没有在运行';

  @override
  String lanTestingDevice(String name) {
    return '正在测试 $name…';
  }

  @override
  String get lanSearchingDevices => '正在搜索同一 WiFi 下的设备…';

  @override
  String get lanNoOtherDevices => '没有发现其它设备（对方也要打开本应用）';

  @override
  String lanFoundDevices(int count) {
    return '发现 $count 台设备';
  }

  @override
  String lanAddedDevice(String name) {
    return '已添加 $name';
  }

  @override
  String lanRemovedHost(String host) {
    return '已移除 $host';
  }

  @override
  String lanOverwritingDevice(String name) {
    return '正在用本机收藏覆盖 $name…';
  }

  @override
  String lanSendingToDevice(String name) {
    return '正在发送到 $name…';
  }

  @override
  String lanPushedOverwrite(String peer, int count, int total) {
    return '已用本机的 $count 张收藏覆盖 $peer，对方现在有 $total 张';
  }

  @override
  String lanPushedMerge(String peer, int count, int added, int total) {
    return '已发送 $count 张收藏到 $peer，对方新增 $added 张（现有 $total 张）';
  }

  @override
  String lanOverwritingLocal(String name) {
    return '正在用 $name 的收藏覆盖本机…';
  }

  @override
  String lanReadingFromDevice(String name) {
    return '正在从 $name 读取…';
  }

  @override
  String lanPulledOverwrite(String peer, int total) {
    return '已用 $peer 的收藏覆盖本机：现在有 $total 张';
  }

  @override
  String lanPulledMerge(String peer, int added, int total) {
    return '$peer 的收藏已合并：新增 $added 张，本机现有 $total 张';
  }

  @override
  String get actionPrevious => '上一个';

  @override
  String get actionNext => '下一个';

  @override
  String get actionPlay => '播放';

  @override
  String get actionPause => '暂停';

  @override
  String get actionStop => '停止';

  @override
  String get actionRetry => '重试';

  @override
  String get actionSearch => '搜索';

  @override
  String get actionDone => '完成';

  @override
  String albumLoadFailed(String error) {
    return '加载专辑失败：\n$error';
  }

  @override
  String get albumForceRefresh => '强制刷新（忽略缓存）';

  @override
  String get albumDetailsTab => '详情';

  @override
  String get albumDetailsTitle => '专辑详情';

  @override
  String get albumExportHint => '把已缓存的曲目导出到系统的 Music 目录';

  @override
  String get albumSaveHint => '把缓存保存到系统的 Music 目录';

  @override
  String get albumCopyPath => '复制缓存目录路径';

  @override
  String albumCopied(String path) {
    return '已复制：$path';
  }

  @override
  String get albumExport => '导出到 Music';

  @override
  String get osdAudioQuality => '音质';

  @override
  String get osdTheme => '主题';

  @override
  String osdThemeWithTooltip(String tooltip) {
    return '主题 $tooltip';
  }

  @override
  String get searchHint => '搜索游戏原声…';

  @override
  String get searchClearHistory => '清空历史';

  @override
  String get searchFavorites => '收藏';

  @override
  String get searchRecentlyViewed => '最近查看';

  @override
  String get searchNoResults => '没有找到专辑';

  @override
  String get searchRecentSearches => '最近搜索';

  @override
  String get searchIdleTip => '在 KHInsider 上搜索游戏原声。\n提示：用遥控器方向键 / 手柄导航。';

  @override
  String get musicFolderQuestion => '把歌曲保存到系统的 Music 目录？';

  @override
  String get musicNotNow => '以后再说';

  @override
  String get musicOpenSettings => '打开设置';

  @override
  String albumTrackCount(int count) {
    return '$count 首';
  }

  @override
  String get albumFavorite => '收藏';

  @override
  String get albumInFavorites => '已收藏';

  @override
  String get albumPlayedSavedTo => '播放过的曲目会保存到 Music/KHInsider';

  @override
  String get albumCacheKeptHere => '缓存的文件保存在这里，方便你自己查找、导出、删除，或用别的播放器播放。';

  @override
  String get albumCopyExplain => '把已下载的曲目复制到 Music/KHInsider，不需要任何权限。';

  @override
  String get exportCopyingExplain => '正在把已下载的曲目复制到 Music/KHInsider，不需要任何权限。';

  @override
  String get exportLookingForCached => '正在查找已缓存的曲目…';

  @override
  String exportProgress(int done, int total) {
    return '$done / $total 首';
  }

  @override
  String get musicFolderBody =>
      '安卓只有在授予「所有文件访问权限」之后，应用才能写入 Music/ —— 下一个界面里就有 KHInsider 的这个开关。\n\n之后下载的曲目会直接放进 Music/KHInsider，文件管理器、其它播放器和电脑都能看到。已经下载过的曲目仍然留在应用目录里，直到你删除或移动它们。';

  @override
  String get musicFolderDenied =>
      '打开「所有文件访问权限」再回来：之后新下载的曲目会存到 Music/KHInsider。';
}
