/// 业务提示异常
///
/// 与普通 Exception 的区别：
/// - 普通 Exception 被视为"系统异常"，由 ErrorFormatter 分类后展示
/// - BusinessException 被视为"用户可操作的业务提示"，文案原样展示
///
/// 使用场景：
/// - 插件未安装（"请前往插件中心安装 py 插件"）
/// - 前置条件不满足（"py 源路径未设置"）
/// - 用户需要采取行动的场景
///
/// 反例（不该用 BusinessException）：
/// - 网络异常、解析失败、脚本语法错误 → 用普通 Exception，交给 ErrorFormatter 分类
class BusinessException implements Exception {
  final String message;
  const BusinessException(this.message);

  @override
  String toString() => message;
}