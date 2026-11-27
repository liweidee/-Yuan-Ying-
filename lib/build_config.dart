abstract final class BuildConfig {
  static const int versionCode = int.fromEnvironment(
    'pili.code',
    defaultValue: 1,
  );
  static const String versionName = String.fromEnvironment(
    'pili.name',
    defaultValue: 'SNAPSHOT',
  );

  static const int buildTime = int.fromEnvironment('pili.time');
  static const String commitHash = String.fromEnvironment(
    'pili.hash',
    defaultValue: 'N/A',
  );

  /// GitHub Actions 的 GITHUB_RUN_NUMBER；本地构建为 -1。
  static const int runNumber = int.fromEnvironment(
    'pili.run',
    defaultValue: -1,
  );
}
