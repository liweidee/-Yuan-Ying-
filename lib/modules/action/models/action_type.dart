/// Action 类型枚举
/// 严格对应 DrPlayer 的 ActionType
enum ActionType {
  /// 单项输入
  input,

  /// 多行编辑
  edit,

  /// 多项输入
  multiInput,

  /// 增强多项输入
  multiInputX,

  /// 单选菜单
  menu,

  /// 多选菜单
  select,

  /// 消息弹窗
  msgbox,

  /// 网页视图
  webview,

  /// 帮助信息
  help,

  /// 浏览器（webview 的别名）
  browser,
}

extension ActionTypeExtension on ActionType {
  /// 从字符串解析 ActionType
  static ActionType? fromString(String value) {
    switch (value.trim()) {
      case 'input':
        return ActionType.input;
      case 'edit':
        return ActionType.edit;
      case 'multiInput':
        return ActionType.multiInput;
      case 'multiInputX':
        return ActionType.multiInputX;
      case 'menu':
        return ActionType.menu;
      case 'select':
        return ActionType.select;
      case 'msgbox':
        return ActionType.msgbox;
      case 'webview':
      case 'browser':
        return ActionType.webview;
      case 'help':
        return ActionType.help;
      default:
        return null;
    }
  }

  /// 转换为字符串
  String get toJson {
    switch (this) {
      case ActionType.input:
        return 'input';
      case ActionType.edit:
        return 'edit';
      case ActionType.multiInput:
        return 'multiInput';
      case ActionType.multiInputX:
        return 'multiInputX';
      case ActionType.menu:
        return 'menu';
      case ActionType.select:
        return 'select';
      case ActionType.msgbox:
        return 'msgbox';
      case ActionType.webview:
        return 'webview';
      case ActionType.help:
        return 'help';
      case ActionType.browser:
        return 'browser';
    }
  }
}