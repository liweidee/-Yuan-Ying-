// lib/modules/action/models/action_config.dart
import 'action_type.dart';
import 'button_type.dart';

/// 输入项配置（用于 MultiInputAction）
class InputItemConfig {
  final String? id;
  final String? name;
  final String? tip;
  final String? value;
  final String? selectData;
  final int inputType;
  final int multiLine;
  final String? validation;
  final String? help;
  final bool quickSelect;
  final bool onlyQuickSelect;
  final bool multiSelect;
  final int selectWidth;
  final int selectColumn;
  final bool required;

  InputItemConfig({
    this.id,
    this.name,
    this.tip,
    this.value,
    this.selectData,
    this.inputType = 0,
    this.multiLine = 1,
    this.validation,
    this.help,
    this.quickSelect = false,
    this.onlyQuickSelect = false,
    this.multiSelect = false,
    this.selectWidth = 200,
    this.selectColumn = 1,
    this.required = false,
  });

  factory InputItemConfig.fromJson(Map<String, dynamic> json) {
    return InputItemConfig(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      tip: json['tip']?.toString(),
      value: json['value']?.toString(),
      selectData: json['selectData']?.toString(),
      inputType: json['inputType'] ?? 0,
      multiLine: json['multiLine'] ?? 1,
      validation: json['validation']?.toString(),
      help: json['help']?.toString(),
      quickSelect: json['quickSelect'] ?? false,
      onlyQuickSelect: json['onlyQuickSelect'] ?? false,
      multiSelect: json['multiSelect'] ?? false,
      selectWidth: json['selectWidth'] ?? 200,
      selectColumn: json['selectColumn'] ?? 1,
      required: json['required'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (tip != null) 'tip': tip,
      if (value != null) 'value': value,
      if (selectData != null) 'selectData': selectData,
      'inputType': inputType,
      'multiLine': multiLine,
      if (validation != null) 'validation': validation,
      if (help != null) 'help': help,
      'quickSelect': quickSelect,
      'onlyQuickSelect': onlyQuickSelect,
      'multiSelect': multiSelect,
      'selectWidth': selectWidth,
      'selectColumn': selectColumn,
      'required': required,
    };
  }
}

/// 菜单选项配置（用于 MenuAction）
class MenuOptionConfig {
  final String name;
  final String? action;
  final String? value;
  final String? description;
  final String? icon;
  final bool selected;
  final bool disabled;

  MenuOptionConfig({
    required this.name,
    this.action,
    this.value,
    this.description,
    this.icon,
    this.selected = false,
    this.disabled = false,
  });

  String get optionValue => value ?? action ?? name;

  factory MenuOptionConfig.fromJson(dynamic json) {
    if (json is String) {
      final parts = json.split('\$');
      if (parts.length == 2) {
        return MenuOptionConfig(
          name: parts[0],
          action: parts[1],
          value: parts[1],
        );
      }
      return MenuOptionConfig(name: json);
    }
    if (json is Map<String, dynamic>) {
      return MenuOptionConfig(
        name: json['name']?.toString() ?? json['title']?.toString() ?? json['label']?.toString() ?? '',
        action: json['action']?.toString() ?? json['value']?.toString(),
        value: json['value']?.toString() ?? json['action']?.toString(),
        description: json['description']?.toString(),
        icon: json['icon']?.toString(),
        selected: json['selected'] ?? false,
        disabled: json['disabled'] ?? false,
      );
    }
    return MenuOptionConfig(name: json.toString());
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (action != null) 'action': action,
      if (value != null) 'value': value,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      'selected': selected,
      'disabled': disabled,
    };
  }
}

/// FAQ 配置（用于 HelpAction）
class FaqConfig {
  final String question;
  final String answer;

  FaqConfig({
    required this.question,
    required this.answer,
  });

  factory FaqConfig.fromJson(Map<String, dynamic> json) {
    return FaqConfig(
      question: json['question']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'answer': answer,
    };
  }
}

/// 链接配置（用于 HelpAction）
class LinkConfig {
  final String title;
  final String url;
  final String? description;
  final String? target;

  LinkConfig({
    required this.title,
    required this.url,
    this.description,
    this.target,
  });

  factory LinkConfig.fromJson(Map<String, dynamic> json) {
    return LinkConfig(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      description: json['description']?.toString(),
      target: json['target']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      if (description != null) 'description': description,
      if (target != null) 'target': target,
    };
  }
}

/// 联系信息配置（用于 HelpAction）
class ContactConfig {
  final String? email;
  final String? phone;
  final String? website;
  final String? address;

  ContactConfig({
    this.email,
    this.phone,
    this.website,
    this.address,
  });

  factory ContactConfig.fromJson(Map<String, dynamic> json) {
    return ContactConfig(
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      address: json['address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (website != null) 'website': website,
      if (address != null) 'address': address,
    };
  }
}

/// Action 配置完整模型
/// 严格对应 DrPlayer 的 Action 配置格式
class ActionConfig {
  final String actionId;
  final ActionType? type;
  final String? title;
  final String? msg;
  final double? width;
  final double? height;
  final double? bottom;
  final ButtonType button;
  final int timeout;
  final bool keep;
  final bool canceledOnTouchOutside;
  final int inputType;
  final String? id;
  final String? tip;
  final String? value;
  final String? selectData;
  final bool required;
  final String? validation;
  final String? help;
  final int multiLine;
  final String? imageUrl;
  final double? imageHeight;
  final bool imageClickCoord;
  final String? qrcode;
  final String? qrcodeSize;
  final String? iconType;
  final String? detail;
  final List<String>? list;
  final bool showProgress;
  final int progressDuration;
  final String? progressText;
  final List<MenuOptionConfig>? options;
  final int column;
  final int selectedIndex;
  final bool searchable;
  final bool autoSubmit;
  final List<InputItemConfig>? inputs;
  final bool allowAdd;
  final bool allowBatch;
  final List<Map<String, dynamic>>? steps;
  final List<FaqConfig>? faq;
  final List<LinkConfig>? links;
  final ContactConfig? contact;
  final Map<String, dynamic>? data;
  final String? url;
  final bool showToolbar;
  final bool showAddressBar;
  final bool allowFullscreen;
  final bool allowDevTools;
  final bool showStatus;
  final String? closeText;
  final String? okText;
  final String? cancelText;
  final Map<String, dynamic>? specialParams;

  /// 新增：是否只允许快速选择
  final bool onlyQuickSelect;

  ActionConfig({
    required this.actionId,
    this.type,
    this.title,
    this.msg,
    this.width,
    this.height,
    this.bottom,
    this.button = ButtonType.okCancel,
    this.timeout = 0,
    this.keep = false,
    this.canceledOnTouchOutside = true,
    this.inputType = 0,
    this.id,
    this.tip,
    this.value,
    this.selectData,
    this.required = false,
    this.validation,
    this.help,
    this.multiLine = 1,
    this.imageUrl,
    this.imageHeight,
    this.imageClickCoord = false,
    this.qrcode,
    this.qrcodeSize,
    this.iconType,
    this.detail,
    this.list,
    this.showProgress = false,
    this.progressDuration = 5000,
    this.progressText,
    this.options,
    this.column = 1,
    this.selectedIndex = -1,
    this.searchable = false,
    this.autoSubmit = false,
    this.inputs,
    this.allowAdd = false,
    this.allowBatch = false,
    this.steps,
    this.faq,
    this.links,
    this.contact,
    this.data,
    this.url,
    this.showToolbar = true,
    this.showAddressBar = true,
    this.allowFullscreen = true,
    this.allowDevTools = false,
    this.showStatus = true,
    this.closeText,
    this.okText,
    this.cancelText,
    this.specialParams,
    this.onlyQuickSelect = false,
  });

  bool get isSpecialAction {
    return type == null ||
        (actionId.startsWith('__') && actionId.endsWith('__'));
  }

  String? get specialActionId {
    if (isSpecialAction && actionId.startsWith('__') && actionId.endsWith('__')) {
      return actionId;
    }
    return null;
  }

  factory ActionConfig.fromJson(Map<String, dynamic> json) {
    return ActionConfig(
      actionId: json['actionId']?.toString() ?? '',
      type: json['type'] != null ? ActionTypeExtension.fromString(json['type'].toString()) : null,
      title: json['title']?.toString(),
      msg: json['msg']?.toString(),
      width: json['width'] != null ? (json['width'] is int ? (json['width'] as int).toDouble() : json['width']) : null,
      height: json['height'] != null ? (json['height'] is int ? (json['height'] as int).toDouble() : json['height']) : null,
      bottom: json['bottom'] != null ? (json['bottom'] is int ? (json['bottom'] as int).toDouble() : json['bottom']) : null,
      button: ButtonTypeExtension.fromInt(normalizeButtonType(json['button'])),
      timeout: json['timeout'] ?? 0,
      keep: json['keep'] ?? false,
      canceledOnTouchOutside: json['canceledOnTouchOutside'] ?? true,
      inputType: json['inputType'] ?? 0,
      id: json['id']?.toString(),
      tip: json['tip']?.toString(),
      value: json['value']?.toString(),
      selectData: json['selectData']?.toString(),
      required: json['required'] ?? false,
      validation: json['validation']?.toString(),
      help: json['help']?.toString(),
      multiLine: json['multiLine'] ?? 1,
      imageUrl: json['imageUrl']?.toString(),
      imageHeight: json['imageHeight'] != null ? (json['imageHeight'] is int ? (json['imageHeight'] as int).toDouble() : json['imageHeight']) : null,
      imageClickCoord: json['imageClickCoord'] ?? false,
      qrcode: json['qrcode']?.toString(),
      qrcodeSize: json['qrcodeSize']?.toString(),
      iconType: json['icon']?.toString(),
      detail: json['detail']?.toString(),
      list: json['list'] != null ? List<String>.from(json['list']) : null,
      showProgress: json['showProgress'] ?? false,
      progressDuration: json['progressDuration'] ?? 5000,
      progressText: json['progressText']?.toString(),
      options: json['option'] != null
          ? List<MenuOptionConfig>.from(json['option'].map((e) => MenuOptionConfig.fromJson(e)))
          : (json['options'] != null
              ? List<MenuOptionConfig>.from(json['options'].map((e) => MenuOptionConfig.fromJson(e)))
              : null),
      column: json['column'] ?? 1,
      selectedIndex: json['selectedIndex'] ?? -1,
      searchable: json['searchable'] ?? false,
      autoSubmit: json['autoSubmit'] ?? false,
      inputs: json['input'] != null
          ? List<InputItemConfig>.from(json['input'].map((e) => InputItemConfig.fromJson(e)))
          : (json['inputs'] != null
              ? List<InputItemConfig>.from(json['inputs'].map((e) => InputItemConfig.fromJson(e)))
              : null),
      allowAdd: json['allowAdd'] ?? false,
      allowBatch: json['allowBatch'] ?? false,
      steps: json['steps'] != null ? List<Map<String, dynamic>>.from(json['steps']) : null,
      faq: json['faq'] != null ? List<FaqConfig>.from(json['faq'].map((e) => FaqConfig.fromJson(e))) : null,
      links: json['links'] != null ? List<LinkConfig>.from(json['links'].map((e) => LinkConfig.fromJson(e))) : null,
      contact: json['contact'] != null ? ContactConfig.fromJson(json['contact']) : null,
      data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : null,
      url: json['url']?.toString(),
      showToolbar: json['showToolbar'] ?? true,
      showAddressBar: json['showAddressBar'] ?? true,
      allowFullscreen: json['allowFullscreen'] ?? true,
      allowDevTools: json['allowDevTools'] ?? false,
      showStatus: json['showStatus'] ?? true,
      closeText: json['closeText']?.toString(),
      okText: json['okText']?.toString(),
      cancelText: json['cancelText']?.toString(),
      specialParams: json,
      onlyQuickSelect: json['onlyQuickSelect'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'actionId': actionId,
      if (type != null) 'type': type!.toJson,
      if (title != null) 'title': title,
      if (msg != null) 'msg': msg,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (bottom != null) 'bottom': bottom,
      'button': button.toInt,
      'timeout': timeout,
      'keep': keep,
      'canceledOnTouchOutside': canceledOnTouchOutside,
      'inputType': inputType,
      if (id != null) 'id': id,
      if (tip != null) 'tip': tip,
      if (value != null) 'value': value,
      if (selectData != null) 'selectData': selectData,
      'required': required,
      if (validation != null) 'validation': validation,
      if (help != null) 'help': help,
      'multiLine': multiLine,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (imageHeight != null) 'imageHeight': imageHeight,
      'imageClickCoord': imageClickCoord,
      if (qrcode != null) 'qrcode': qrcode,
      if (qrcodeSize != null) 'qrcodeSize': qrcodeSize,
      if (iconType != null) 'icon': iconType,
      if (detail != null) 'detail': detail,
      if (list != null) 'list': list,
      'showProgress': showProgress,
      'progressDuration': progressDuration,
      if (progressText != null) 'progressText': progressText,
      if (options != null) 'option': options!.map((e) => e.toJson()).toList(),
      'column': column,
      'selectedIndex': selectedIndex,
      'searchable': searchable,
      'autoSubmit': autoSubmit,
      if (inputs != null) 'input': inputs!.map((e) => e.toJson()).toList(),
      'allowAdd': allowAdd,
      'allowBatch': allowBatch,
      if (steps != null) 'steps': steps,
      if (faq != null) 'faq': faq!.map((e) => e.toJson()).toList(),
      if (links != null) 'links': links!.map((e) => e.toJson()).toList(),
      if (contact != null) 'contact': contact!.toJson(),
      if (data != null) 'data': data,
      if (url != null) 'url': url,
      'showToolbar': showToolbar,
      'showAddressBar': showAddressBar,
      'allowFullscreen': allowFullscreen,
      'allowDevTools': allowDevTools,
      'showStatus': showStatus,
      if (closeText != null) 'closeText': closeText,
      if (okText != null) 'okText': okText,
      if (cancelText != null) 'cancelText': cancelText,
      'onlyQuickSelect': onlyQuickSelect,
    };
  }
}