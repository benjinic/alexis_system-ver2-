import 'package:flutter/material.dart';

class IconText extends StatelessWidget {
  static final Map<IconData, String> _materialIconLabels = {
    Icons.accessibility_new: '[體型]',
    Icons.add: '[新增]',
    Icons.add_card: '[新增卡片]',
    Icons.analytics: '[分析]',
    Icons.analytics_outlined: '[分析]',
    Icons.apartment_outlined: '[工坊]',
    Icons.archive_outlined: '[封存]',
    Icons.arrow_downward: '[向下]',
    Icons.arrow_drop_down: '[下拉]',
    Icons.arrow_forward: '[前往]',
    Icons.arrow_upward: '[向上]',
    Icons.attach_money: '[金額]',
    Icons.calculate_outlined: '[計算]',
    Icons.calendar_today: '[日期]',
    Icons.call: '[電話]',
    Icons.category: '[分類]',
    Icons.category_outlined: '[分類]',
    Icons.check_circle: '[完成]',
    Icons.checkroom: '[服裝]',
    Icons.chevron_right: '[展開]',
    Icons.circle: '[圓點]',
    Icons.cleaning_services: '[清理]',
    Icons.clear: '[清空]',
    Icons.close: '[關閉]',
    Icons.confirmation_number: '[訂單號]',
    Icons.content_cut: '[裁剪]',
    Icons.content_cut_outlined: '[裁剪]',
    Icons.dashboard: '[儀表板]',
    Icons.dashboard_customize: '[儀表板]',
    Icons.dashboard_outlined: '[儀表板]',
    Icons.delete: '[刪除]',
    Icons.delete_forever: '[永久刪除]',
    Icons.download: '[下載]',
    Icons.edit: '[編輯]',
    Icons.edit_outlined: '[編輯]',
    Icons.email: '[電郵]',
    Icons.email_outlined: '[電郵]',
    Icons.engineering: '[車縫]',
    Icons.engineering_outlined: '[車縫]',
    Icons.expand_more: '[更多]',
    Icons.filter_list: '[篩選]',
    Icons.groups: '[群組]',
    Icons.groups_outlined: '[群組]',
    Icons.history: '[歷史]',
    Icons.image_not_supported: '[無圖片]',
    Icons.image_not_supported_outlined: '[無圖片]',
    Icons.info_outline: '[資訊]',
    Icons.inventory_2_outlined: '[庫存]',
    Icons.language: '[語言]',
    Icons.list_alt: '[清單]',
    Icons.list_alt_outlined: '[清單]',
    Icons.local_fire_department: '[急件]',
    Icons.lock_outline: '[鎖定]',
    Icons.logout: '[登出]',
    Icons.more_vert: '[更多]',
    Icons.notifications_active_outlined: '[通知]',
    Icons.numbers: '[數量]',
    Icons.payments_outlined: '[付款]',
    Icons.people: '[客戶]',
    Icons.person: '[客戶]',
    Icons.person_add: '[新增客戶]',
    Icons.person_off: '[未指派]',
    Icons.person_outlined: '[客戶]',
    Icons.phone: '[電話]',
    Icons.print: '[列印]',
    Icons.print_outlined: '[列印]',
    Icons.public: '[公開]',
    Icons.public_off: '[私密]',
    Icons.receipt_long: '[收據]',
    Icons.receipt_long_outlined: '[收據]',
    Icons.refresh: '[重新整理]',
    Icons.remove_circle_outline: '[移除]',
    Icons.search: '[搜尋]',
    Icons.settings: '[設定]',
    Icons.settings_outlined: '[設定]',
    Icons.shopping_bag_outlined: '[商品]',
    Icons.shopping_cart: '[購物車]',
    Icons.shopping_cart_outlined: '[購物車]',
    Icons.sort_by_alpha: '[排序]',
    Icons.star: '[星號]',
    Icons.store: '[店舖]',
    Icons.storefront: '[店面]',
    Icons.storefront_outlined: '[店面]',
    Icons.straighten: '[尺寸]',
    Icons.table_view_outlined: '[表格]',
    Icons.texture: '[布料]',
    Icons.tune: '[調整]',
    Icons.tune_outlined: '[調整]',
    Icons.unarchive: '[取消封存]',
  };

  const IconText(
    this.icon, {
    super.key,
    this.size,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.color,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling = false,
    this.blendMode,
  });

  final IconData? icon;
  final double? size;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final Color? color;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool applyTextScaling;
  final BlendMode? blendMode;

  /// [2026-10-19] 改返用真 Icon() 嘅版本喺真實瀏覽器度顯示做空白方塊
  /// （唔係方括號文字，而係完全睇唔到），即係 MaterialIcons 字型實際上冇正常
  /// 載入——同 headless Chrome 測試嘅結果唔一致。改返用文字方括號頂住，
  /// 起碼用戶睇到文字知道個掣做乜，唔好再改用 Icon() 除非已經喺真實裝置
  /// 確認個字型檔正常顯示。
  String _resolveLabel() {
    if (semanticLabel != null && semanticLabel!.trim().isNotEmpty) {
      return semanticLabel!;
    }

    final mapped = _materialIconLabels[icon];
    if (mapped != null) {
      return mapped;
    }

    return '[圖示]';
  }

  @override
  Widget build(BuildContext context) {
    final label = _resolveLabel();

    return Text(
      label,
      textDirection: textDirection,
      textScaler: applyTextScaling
          ? MediaQuery.textScalerOf(context)
          : TextScaler.noScaling,
      style: TextStyle(
        fontSize: size ?? 12,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        shadows: shadows,
      ),
    );
  }
}
