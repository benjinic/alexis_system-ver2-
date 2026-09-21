import 'package:flutter/material.dart';

/// App-wide localizations. Supports: en, zh_TW, zh_CN.
///
/// Usage in widgets:
///   final l10n = AppLocalizations.of(context);
///   Text(l10n.navDashboard)
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  static const delegate = _AppLocalizationsDelegate();

  String _get(String key) {
    final tag = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return (_translations[tag] ?? _translations['en']!)[key] ?? key;
  }

  // ── Navigation ──────────────────────────────────────────────────────────────
  String get navDashboard => _get('navDashboard');
  String get navPOS => _get('navPOS');
  String get navOrders => _get('navOrders');
  String get navClients => _get('navClients');
  String get navFabric => _get('navFabric');
  String get navShop => _get('navShop');
  String get navSettings => _get('navSettings');

  // ── Common ───────────────────────────────────────────────────────────────────
  String get cancelButton => _get('cancelButton');
  String get saveButton => _get('saveButton');
  String get editButton => _get('editButton');
  String get deleteButton => _get('deleteButton');
  String get addButton => _get('addButton');
  String get updateButton => _get('updateButton');
  String get noButton => _get('noButton');
  String get yesButton => _get('yesButton');
  String get errorPrefix => _get('errorPrefix');
  String get nameRequired => _get('nameRequired');
  String get namePlaceholder => _get('namePlaceholder');
  String get phoneLabel => _get('phoneLabel');
  String get emailLabel => _get('emailLabel');
  String get emailPlaceholder => _get('emailPlaceholder');
  String get phonePlaceholder => _get('phonePlaceholder');
  String get nameRequiredError => _get('nameRequiredError');
  String get emailFormatError => _get('emailFormatError');
  String get customerAddedSuccess => _get('customerAddedSuccess');
  String get dateLabel => _get('dateLabel');
  String get addNewCustomer => _get('addNewCustomer');
  String get saveChanges => _get('saveChanges');
  String get noData => _get('noData');

  // ── Dashboard ────────────────────────────────────────────────────────────────
  String get dashboardTitle => _get('dashboardTitle');
  String get overview => _get('overview');
  String get shopDescription => _get('shopDescription');
  String get totalRevenue => _get('totalRevenue');
  String get filterSubtext => _get('filterSubtext');
  String get filterWeek => _get('filterWeek');
  String get filterMonth => _get('filterMonth');
  String get filterYear => _get('filterYear');
  String get filterCustomRange => _get('filterCustomRange');
  String get itemSalesQty => _get('itemSalesQty');
  String get unitsSold => _get('unitsSold');
  String get noSales => _get('noSales');
  String get noPeriod => _get('noPeriod');
  String get activeJobs => _get('activeJobs');
  String get allClear => _get('allClear');
  String get inProduction => _get('inProduction');
  String get urgentTasks => _get('urgentTasks');
  String get outstanding => _get('outstanding');
  String get allPaid => _get('allPaid');
  String get unpaidOrders => _get('unpaidOrders');
  String get totalCustomers => _get('totalCustomers');
  String get lifetimeClients => _get('lifetimeClients');
  String get recentOrders => _get('recentOrders');
  String get viewAll => _get('viewAll');
  String get noOrdersYet => _get('noOrdersYet');
  String get quickActions => _get('quickActions');
  String get newOrder => _get('newOrder');
  String get addCustomerAction => _get('addCustomerAction');
  String get checkWorkshop => _get('checkWorkshop');
  String get costAnalysis => _get('costAnalysis');
  String get productionFlow => _get('productionFlow');
  String get activeTasks => _get('activeTasks');

  // ── Orders ───────────────────────────────────────────────────────────────────
  String get ordersTitle => _get('ordersTitle');
  String get orderDetails => _get('orderDetails');
  String get orderNumber => _get('orderNumber');
  String get itemsLabel => _get('itemsLabel');
  String get internalCostProfit => _get('internalCostProfit');
  String get materialCost => _get('materialCost');
  String get outsourcingCost => _get('outsourcingCost');
  String get fixedCost => _get('fixedCost');
  String get laborCost => _get('laborCost');
  String get totalCost => _get('totalCost');
  String get netProfit => _get('netProfit');
  String get subtotal => _get('subtotal');
  String get discount => _get('discount');
  String get total => _get('total');
  String get depositPaid => _get('depositPaid');
  String get balanceDue => _get('balanceDue');
  String get fabricOrdered => _get('fabricOrdered');
  String get pendingOrder => _get('pendingOrder');
  String get fabricReady => _get('fabricReady');
  String get noFabricRequired => _get('noFabricRequired');
  String get fabricMarkedOrdered => _get('fabricMarkedOrdered');
  String get fabricMarkedNotOrdered => _get('fabricMarkedNotOrdered');
  String get receiptButton => _get('receiptButton');
  String get photosButton => _get('photosButton');
  String get deleteOrder => _get('deleteOrder');
  String get deleteOrderConfirm => _get('deleteOrderConfirm');
  String get deleteOrderWarning => _get('deleteOrderWarning');
  String get cannotUndo => _get('cannotUndo');
  String get searchOrdersHint => _get('searchOrdersHint');
  String get customerLabel => _get('customerLabel');
  String get paymentLabel => _get('paymentLabel');
  String get noFabricImage => _get('noFabricImage');
  String get movedToStatus => _get('movedToStatus');
  String get pendingOrders => _get('pendingOrders');
  String get outstandingOrders => _get('outstandingOrders');
  String get exportCSV => _get('exportCSV');
  String get noMatchingOrders => _get('noMatchingOrders');
  String get createFirstOrder => _get('createFirstOrder');
  String get loadMoreHistory => _get('loadMoreHistory');
  String get markFabricOrdered => _get('markFabricOrdered');
  String loadMoreShowing(int count) => '${_get('loadMoreShowing')} $count+';
  String allOrdersLoaded(int n) =>
      _get('allOrdersLoaded').replaceFirst('{n}', '$n');
  String get unexpectedError => _get('unexpectedError');
  String get confirmOrderButton => _get('confirmOrderButton');
  String get markAsCompleteButton => _get('markAsCompleteButton');
  String get confirmOrderMsg => _get('confirmOrderMsg');
  String get markCompleteMsg => _get('markCompleteMsg');
  String get deliveryDateLabel => _get('deliveryDateLabel');
  String get balancePaymentsLabel => _get('balancePaymentsLabel');

  // ── Workshop ─────────────────────────────────────────────────────────────────
  String get workshopTitle => _get('workshopTitle');
  String get statusMeasuring => _get('statusMeasuring');
  String get statusCutting => _get('statusCutting');
  String get statusSewing => _get('statusSewing');
  String get statusFinishing => _get('statusFinishing');
  String get statusCompleted => _get('statusCompleted');
  String get archivedHistory => _get('archivedHistory');
  String get backToBoard => _get('backToBoard');
  String get archiveButton => _get('archiveButton');
  String get noTasks => _get('noTasks');
  String get editOrderTitle => _get('editOrderTitle');
  String get jobDetails => _get('jobDetails');
  String get ticketNumber => _get('ticketNumber');
  String get itemStyle => _get('itemStyle');
  String get itemStyleHint => _get('itemStyleHint');
  String get fabricItems => _get('fabricItems');
  String get notesLabel => _get('notesLabel');
  String get notesHint => _get('notesHint');
  String get noNotes => _get('noNotes');
  String get changesSaved => _get('changesSaved');
  String get searchWorkshopHint => _get('searchWorkshopHint');
  String get dueDateLabel => _get('dueDateLabel');
  String fabricSyncError(String error) => '${_get('fabricSyncError')}$error';

  // ── Fabric ───────────────────────────────────────────────────────────────────
  String get fabricTitle => _get('fabricTitle');
  String get categoryAll => _get('categoryAll');
  String get categoryCotton => _get('categoryCotton');
  String get categoryLinen => _get('categoryLinen');
  String get categoryWool => _get('categoryWool');
  String get categoryOther => _get('categoryOther');
  String get addFabric => _get('addFabric');
  String get editFabric => _get('editFabric');
  String get availableOnline => _get('availableOnline');
  String get visibleToCustomers => _get('visibleToCustomers');
  String get hiddenFromStore => _get('hiddenFromStore');
  String get categoryLabel => _get('categoryLabel');
  String get colourLabel => _get('colourLabel');
  String get colourPlaceholder => _get('colourPlaceholder');
  String get costPrice => _get('costPrice');
  String get retailPrice => _get('retailPrice');
  String get stockLabel => _get('stockLabel');
  String get unitLabel => _get('unitLabel');
  String get reorderLevel => _get('reorderLevel');
  String get addPhotoAiScan => _get('addPhotoAiScan');
  String get searchFabricHint => _get('searchFabricHint');
  String get savingData => _get('savingData');
  String get duplicateNameError => _get('duplicateNameError');
  String get imageUploadFailed => _get('imageUploadFailed');
  String get sortOrder => _get('sortOrder');
  String get sortNameAZ => _get('sortNameAZ');
  String get sortNameZA => _get('sortNameZA');
  String get switchToList => _get('switchToList');
  String get switchToGrid => _get('switchToGrid');
  String get lowStock => _get('lowStock');
  String get deleteFabric => _get('deleteFabric');
  String get savingButton => _get('savingButton');
  String get nameLabel => _get('nameLabel');
  String get onlineLabel => _get('onlineLabel');
  String get offlineLabel => _get('offlineLabel');

  // ── POS ──────────────────────────────────────────────────────────────────────
  String get selectCustomer => _get('selectCustomer');
  String get searchCustomerHint => _get('searchCustomerHint');
  String get cartItems => _get('cartItems');
  String get cartEmpty => _get('cartEmpty');
  String get addFirstItem => _get('addFirstItem');
  String get printReceiptTitle => _get('printReceiptTitle');
  String get printReceiptQuestion => _get('printReceiptQuestion');
  String get printButton => _get('printButton');
  String get printJobTicketsTitle => _get('printJobTicketsTitle');
  String get orderProcessedSuccess => _get('orderProcessedSuccess');
  String get searchCustomersHint => _get('searchCustomersHint');
  String get depositPaymentMethod => _get('depositPaymentMethod');
  String get costBreakdown => _get('costBreakdown');
  String get estimatedProfit => _get('estimatedProfit');
  String get outstandingBalance => _get('outstandingBalance');
  String get editItemTooltip => _get('editItemTooltip');
  String get addItemButton => _get('addItemButton');
  String get balanceMethod => _get('balanceMethod');
  String get fabricImagesTitle => _get('fabricImagesTitle');
  String get closeButton => _get('closeButton');
  String get customerSection => _get('customerSection');
  String get emailInvalidError => _get('emailInvalidError');
  String get pleaseAddItemsMsg => _get('pleaseAddItemsMsg');
  String get enterAmountHint => _get('enterAmountHint');
  String get noFabricText => _get('noFabricText');
  String get fabricReminderTitle => _get('fabricReminderTitle');
  String get fabricReminderSubtitle => _get('fabricReminderSubtitle');
  String get laterButton => _get('laterButton');
  String printJobTicketsBody(int count) =>
      _get('printJobTicketsBody').replaceFirst('{n}', '$count');

  // ── Customers ────────────────────────────────────────────────────────────────
  String get customersTitle => _get('customersTitle');
  String get exportButton => _get('exportButton');
  String get topVips => _get('topVips');
  String get allCustomers => _get('allCustomers');
  String get spendingInfo => _get('spendingInfo');
  String get noOrdersInPeriod => _get('noOrdersInPeriod');
  String get twoYearSpent => _get('twoYearSpent');
  String get ordersLabel => _get('ordersLabel');
  String get noCustomersFound => _get('noCustomersFound');
  String get noCustomerData => _get('noCustomerData');
  String get exportPreparing => _get('exportPreparing');
  String get exportSuccess => _get('exportSuccess');
  String exportFailedMsg(Object error) => '${_get('exportFailed')}: $error';
  String get requiredField => _get('requiredField');

  // ── Settings ─────────────────────────────────────────────────────────────────
  String get settingsTitle => _get('settingsTitle');
  String get shopInformation => _get('shopInformation');
  String get shopNameLabel => _get('shopNameLabel');
  String get currencyLabel => _get('currencyLabel');
  String get currentPrefix => _get('currentPrefix');
  String get systemConfiguration => _get('systemConfiguration');
  String get nextOrderNumber => _get('nextOrderNumber');
  String get helperSetStartingId => _get('helperSetStartingId');
  String get productsServices => _get('productsServices');
  String get manageServiceItems => _get('manageServiceItems');
  String get manageServiceItemsSub => _get('manageServiceItemsSub');
  String get measurementFieldsLabel => _get('measurementFieldsLabel');
  String get measurementFieldsSub => _get('measurementFieldsSub');
  String get printerHardware => _get('printerHardware');
  String get testPrint => _get('testPrint');
  String get testPrintSub => _get('testPrintSub');
  String get preferencesLabel => _get('preferencesLabel');
  String get languageLabel => _get('languageLabel');
  String get systemLanguage => _get('systemLanguage');
  String get fabricUnit => _get('fabricUnit');
  String get defaultUnit => _get('defaultUnit');
  String get appNotifications => _get('appNotifications');
  String get orderNotificationsLabel => _get('orderNotificationsLabel');
  String get alertDueDate => _get('alertDueDate');
  String get systemInfo => _get('systemInfo');
  String get versionLabel => _get('versionLabel');
  String get versionValue => _get('versionValue');
  String get resetLocalSettings => _get('resetLocalSettings');
  String get dataMaintenance => _get('dataMaintenance');
  String get cleanOrphanedData => _get('cleanOrphanedData');
  String get cleanOrphanedDataSub => _get('cleanOrphanedDataSub');
  String get accountLabel => _get('accountLabel');
  String get logout => _get('logout');
  String get settingsSaved => _get('settingsSaved');
  String get languageSwitchedTo => _get('languageSwitchedTo');
  String get invalidOrderId => _get('invalidOrderId');
  String get appearance => _get('appearance');
  String get accentColor => _get('accentColor');
  String get systemTextColor => _get('systemTextColor');
  String get headingTextColor => _get('headingTextColor');
  String get cardLabelColor => _get('cardLabelColor');
  String get sidebarTextColor => _get('sidebarTextColor');
  String get serviceList => _get('serviceList');
  String get noServices => _get('noServices');
  String get addNewService => _get('addNewService');
  String get newFieldHint => _get('newFieldHint');

  // ── Login ────────────────────────────────────────────────────────────────────
  String get loginTitle => _get('loginTitle');
  String get staffLogin => _get('staffLogin');
  String get passwordLabel => _get('passwordLabel');
  String get loginButton => _get('loginButton');
  String get userNotFound => _get('userNotFound');
  String get incorrectPassword => _get('incorrectPassword');
  String get invalidEmail => _get('invalidEmail');
  String get loginFailed => _get('loginFailed');

  // ── Customer Details ─────────────────────────────────────────────────────────
  String get customerProfile => _get('customerProfile');
  String get editProfileTooltip => _get('editProfileTooltip');
  String get editCustomerProfile => _get('editCustomerProfile');
  String get bodyMeasurements => _get('bodyMeasurements');
  String get editMeasurements => _get('editMeasurements');
  String get measurementsUpdated => _get('measurementsUpdated');
  String get orderHistory => _get('orderHistory');
  String get totalSpent => _get('totalSpent');
  String get noMeasurements => _get('noMeasurements');
  String get noOrdersFound => _get('noOrdersFound');
  String get profileUpdated => _get('profileUpdated');
  String get contactLog => _get('contactLog');
  String get addContactLog => _get('addContactLog');
  String get contactType => _get('contactType');
  String get contactTypeCall => _get('contactTypeCall');
  String get contactTypeFitting => _get('contactTypeFitting');
  String get contactTypeMessage => _get('contactTypeMessage');
  String get contactTypeNote => _get('contactTypeNote');
  String get noContactLogs => _get('noContactLogs');
  String get contactLogAdded => _get('contactLogAdded');
  String get editOrderInPOS => _get('editOrderInPOS');
  String get tapToSet => _get('tapToSet');
  String get timelineTitle => _get('timelineTitle');
  String get filterAll => _get('filterAll');
  String get filterContact => _get('filterContact');
  String get filterFitting => _get('filterFitting');
  String get filterOrder => _get('filterOrder');
  String get tierNew => _get('tierNew');
  String get tierRegular => _get('tierRegular');
  String get tierVip => _get('tierVip');
  String get followUpDate => _get('followUpDate');
  String get followUpDue => _get('followUpDue');
  String get markDone => _get('markDone');

  // ── Translation Tables ────────────────────────────────────────────────────────
  static const Map<String, Map<String, String>> _translations = {
    'en': {
      // Navigation
      'navDashboard': 'Dash',
      'navPOS': 'POS',
      'navOrders': 'Orders',
      'navClients': 'Clients',
      'navFabric': 'Fabric',
      'navShop': 'Shop',
      'navSettings': 'Set',
      // Common
      'cancelButton': 'Cancel',
      'saveButton': 'Save',
      'editButton': 'Edit',
      'deleteButton': 'Delete',
      'addButton': 'Add',
      'updateButton': 'Update',
      'noButton': 'No',
      'yesButton': 'Yes',
      'errorPrefix': 'Error:',
      'nameRequired': 'Name *',
      'namePlaceholder': 'Customer name',
      'phoneLabel': 'Phone',
      'emailLabel': 'Email',
      'emailPlaceholder': 'customer@example.com',
      'phonePlaceholder': 'Customer phone',
      'nameRequiredError': 'Name is required',
      'emailFormatError': 'Enter a valid email',
      'customerAddedSuccess': 'Customer added successfully',
      'dateLabel': 'Date',
      'addNewCustomer': 'Add New Customer',
      'saveChanges': 'Save Changes',
      'noData': 'No Data',
      // Dashboard
      'dashboardTitle': 'Dashboard',
      'overview': 'Overview',
      'shopDescription': "Here is what's happening in your shop.",
      'totalRevenue': 'Total Revenue',
      'filterSubtext': 'Click menu to filter',
      'filterWeek': 'This Week',
      'filterMonth': 'This Month',
      'filterYear': 'This Year',
      'filterCustomRange': 'Custom Range...',
      'itemSalesQty': 'Item Sales Qty',
      'unitsSold': 'units sold',
      'noSales': 'No Sales',
      'noPeriod': 'in this period',
      'activeJobs': 'Active Jobs',
      'allClear': 'All clear',
      'inProduction': 'In production',
      'urgentTasks': 'urgent tasks!',
      'outstanding': 'Outstanding',
      'allPaid': 'All paid',
      'unpaidOrders': 'unpaid orders',
      'totalCustomers': 'Total Customers',
      'lifetimeClients': 'Lifetime clients',
      'recentOrders': 'Recent Orders',
      'viewAll': 'View All',
      'noOrdersYet': 'No orders yet',
      'quickActions': 'Quick Actions',
      'newOrder': 'New Order',
      'addCustomerAction': 'Add Customer',
      'checkWorkshop': 'Check Workshop',
      'costAnalysis': 'Cost Analysis',
      'productionFlow': 'Production Flow',
      'activeTasks': 'active tasks',
      // Orders
      'ordersTitle': 'Orders',
      'orderDetails': 'Order Details',
      'orderNumber': 'Order #',
      'itemsLabel': 'Items',
      'internalCostProfit': 'Internal Cost & Profit',
      'materialCost': 'Material Cost',
      'outsourcingCost': 'Outsourcing Cost',
      'fixedCost': 'Fixed Cost',
      'laborCost': 'Labor Cost',
      'totalCost': 'Total Cost',
      'netProfit': 'Net Profit',
      'subtotal': 'Subtotal',
      'discount': 'Discount',
      'total': 'Total',
      'depositPaid': 'Deposit / Paid',
      'balanceDue': 'Balance Due',
      'fabricOrdered': 'Fabric Ordered',
      'pendingOrder': 'Pending Order',
      'fabricReady': 'Fabric Ready',
      'noFabricRequired': 'No Fabric Required',
      'fabricMarkedOrdered': 'Fabric marked as ordered',
      'fabricMarkedNotOrdered': 'Fabric marked as not ordered',
      'fabricSyncError': 'Fabric sync failed: ',
      'receiptButton': 'Receipt',
      'photosButton': 'Photos',
      'deleteOrder': 'Delete Order',
      'deleteOrderConfirm': 'Delete Order?',
      'deleteOrderWarning': 'Are you sure you want to delete Order #',
      'cannotUndo': 'This action cannot be undone.',
      'searchOrdersHint': 'Search #ID, customer, fabric or service...',
      'customerLabel': 'Customer',
      'paymentLabel': 'Payment',
      'noFabricImage': 'No fabric image',
      'movedToStatus': 'Moved to',
      'pendingOrders': 'Pending Orders',
      'outstandingOrders': 'Outstanding Orders',
      'exportCSV': 'Export Item Details CSV',
      'noMatchingOrders': 'No matching orders in loaded history',
      'createFirstOrder': 'Create First Order',
      'loadMoreHistory': 'Load More History',
      'markFabricOrdered': 'Mark Fabric Ordered',
      'loadMoreShowing': 'Load More (Showing',
      'allOrdersLoaded': 'All {n} orders loaded',
      'unexpectedError': 'An unexpected error occurred.',
      'confirmOrderButton': 'Confirm Order',
      'markAsCompleteButton': 'Mark as Complete',
      'confirmOrderMsg': 'Mark this order as confirmed?',
      'markCompleteMsg': 'Mark this order as completed?\nThis cannot be undone.',
      'deliveryDateLabel': 'Delivery Date',
      'balancePaymentsLabel': 'Balance Payments',
      // Workshop
      'workshopTitle': 'Workshop Board',
      'statusMeasuring': 'Measuring',
      'statusCutting': 'Cutting',
      'statusSewing': 'Sewing',
      'statusFinishing': 'Finishing',
      'statusCompleted': 'Completed',
      'archivedHistory': 'Archived History',
      'backToBoard': 'Back to Board',
      'archiveButton': 'Archive',
      'noTasks': 'No tasks',
      'editOrderTitle': 'Edit Order',
      'jobDetails': 'Job Details',
      'ticketNumber': 'Ticket #',
      'itemStyle': 'Item Style / Description',
      'itemStyleHint': 'e.g. 3-Piece Suit, VBC Fabric...',
      'fabricItems': 'Fabric / Items',
      'notesLabel': 'Notes / Measurements',
      'notesHint': 'Add specific instructions here...',
      'noNotes': 'No notes provided.',
      'changesSaved': 'Changes saved successfully!',
      'searchWorkshopHint': 'Search ticket #ID, customer or item...',
      'dueDateLabel': 'Due Date',
      // Fabric
      'fabricTitle': 'Fabric Inventory',
      'categoryAll': 'All',
      'categoryCotton': 'Cotton',
      'categoryLinen': 'Linen',
      'categoryWool': 'Wool',
      'categoryOther': 'Other',
      'addFabric': 'Add Fabric',
      'editFabric': 'Edit Fabric',
      'availableOnline': 'Available Online',
      'visibleToCustomers': 'Visible to customers',
      'hiddenFromStore': 'Hidden from store',
      'categoryLabel': 'Category',
      'colourLabel': 'Colour',
      'colourPlaceholder': 'e.g. NAVY BLUE',
      'costPrice': 'Cost Price',
      'retailPrice': 'Retail Price',
      'stockLabel': 'Stock',
      'unitLabel': 'Unit',
      'reorderLevel': 'Reorder Level',
      'addPhotoAiScan': 'Add Photo & AI Scan',
      'searchFabricHint': 'Search fabric name...',
      'savingData': 'Saving data...',
      'duplicateNameError': 'A fabric with this name already exists.',
      'imageUploadFailed': 'Image upload failed or timed out. Please try again.',
      'sortOrder': 'Sort Order',
      'sortNameAZ': 'Name (A-Z)',
      'sortNameZA': 'Name (Z-A)',
      'switchToList': 'Switch to List',
      'switchToGrid': 'Switch to Grid',
      'lowStock': 'Low Stock',
      'deleteFabric': 'Delete Fabric',
      'savingButton': 'Saving...',
      'nameLabel': 'Name',
      'onlineLabel': 'Online',
      'offlineLabel': 'Offline',
      // POS
      'selectCustomer': 'Select Customer',
      'searchCustomerHint': 'Search name or phone...',
      'cartItems': 'Cart Items',
      'cartEmpty': 'Cart is empty',
      'addFirstItem': 'Add First Item',
      'printReceiptTitle': 'Print Receipt?',
      'printReceiptQuestion': 'Do you want to print the customer receipt now?',
      'printButton': 'Print',
      'printJobTicketsTitle': 'Print Job Tickets?',
      'orderProcessedSuccess': 'Order processed successfully!',
      'searchCustomersHint': 'Search customers...',
      'depositPaymentMethod': 'Deposit Payment Method',
      'costBreakdown': 'Cost Breakdown',
      'estimatedProfit': 'Estimated Profit',
      'outstandingBalance': 'Outstanding Balance',
      'editItemTooltip': 'Edit Item',
      'addItemButton': 'Add Item',
      'balanceMethod': 'Balance Method',
      'fabricImagesTitle': 'Fabric Images',
      'closeButton': 'Close',
      'customerSection': 'Customer',
      'emailInvalidError': 'Enter a valid email',
      'pleaseAddItemsMsg': 'Please add items and select a customer',
      'enterAmountHint': 'Enter amount',
      'noFabricText': 'No fabric required',
      'fabricReminderTitle': 'Fabric Order Reminder',
      'fabricReminderSubtitle': 'The following fabrics need to be ordered from suppliers:',
      'laterButton': 'Later',
      'printJobTicketsBody': 'Created {n} workshop orders.\nPrint job tickets for the factory?',
      // Customers
      'customersTitle': 'Customers',
      'exportButton': 'Export',
      'topVips': 'Top 10 VIPs',
      'allCustomers': 'All Customers',
      'spendingInfo': 'Ranking based on spending in last 2 years',
      'noOrdersInPeriod': 'No orders in the last 2 years.',
      'twoYearSpent': '2-Year Spent:',
      'ordersLabel': 'Orders',
      'noCustomersFound': 'No customers found.',
      'noCustomerData': 'No customer data found.',
      'exportPreparing': 'Preparing data for export...',
      'exportSuccess': '✅ Export Successful!',
      'exportFailed': '❌ Export failed',
      'requiredField': 'Required',
      // Settings
      'settingsTitle': 'Settings',
      'shopInformation': 'Shop Information',
      'shopNameLabel': 'Shop Name',
      'currencyLabel': 'Currency',
      'currentPrefix': 'Current:',
      'systemConfiguration': 'System Configuration',
      'nextOrderNumber': 'Next Order Number',
      'helperSetStartingId': 'Manually set the starting ID',
      'productsServices': 'Products & Services',
      'manageServiceItems': 'Manage Service Items',
      'manageServiceItemsSub': 'Add, edit prices & fabric usage',
      'measurementFieldsLabel': 'Measurement Fields',
      'measurementFieldsSub': 'Customize body measurement inputs',
      'printerHardware': 'Printer & Hardware',
      'testPrint': 'Test Workshop Ticket Print',
      'testPrintSub': 'Print a sample A4 job ticket to check layout',
      'preferencesLabel': 'Preferences',
      'languageLabel': 'Language',
      'systemLanguage': 'System language',
      'fabricUnit': 'Fabric Unit',
      'defaultUnit': 'Default unit for inventory',
      'appNotifications': 'App Notifications',
      'orderNotificationsLabel': 'Order Notifications',
      'alertDueDate': 'Alert when due date is close',
      'systemInfo': 'System Info',
      'versionLabel': 'Version',
      'versionValue': 'Ver 2.3.0 (Beta)',
      'resetLocalSettings': 'Reset Local Settings',
      'dataMaintenance': 'Data Maintenance',
      'cleanOrphanedData': 'Clean Orphaned Data',
      'cleanOrphanedDataSub': 'Delete order_items and workshop_orders with no matching order',
      'accountLabel': 'Account',
      'logout': 'Logout',
      'settingsSaved': 'Settings Saved Successfully',
      'languageSwitchedTo': 'Language switched to',
      'invalidOrderId': 'Invalid Order ID',
      'appearance': 'Appearance',
      'accentColor': 'Accent Color',
      'systemTextColor': 'System Text Color',
      'headingTextColor': 'Heading Text Color',
      'cardLabelColor': 'Card & Label Color',
      'sidebarTextColor': 'Sidebar Text Color',
      'serviceList': 'Service List',
      'noServices': 'No services found. Add one!',
      'addNewService': 'Add New Service',
      'newFieldHint': 'New Field Name (e.g. Wrist)',
      // Login
      'loginTitle': 'ALEXIS SYSTEM',
      'staffLogin': 'Staff Login',
      'passwordLabel': 'Password',
      'loginButton': 'LOGIN',
      'userNotFound': 'No user found with this email.',
      'incorrectPassword': 'Incorrect password.',
      'invalidEmail': 'Invalid email format.',
      'loginFailed': 'Login failed:',
      // Customer Details
      'customerProfile': 'Customer Profile',
      'editProfileTooltip': 'Edit Profile (Phone/Email)',
      'editCustomerProfile': 'Edit Customer Profile',
      'bodyMeasurements': 'Body Measurements',
      'editMeasurements': 'Edit Measurements',
      'measurementsUpdated': 'Measurements updated!',
      'orderHistory': 'Order History',
      'totalSpent': 'Total Spent',
      'noMeasurements': 'No measurements yet.',
      'noOrdersFound': 'No orders found.',
      'profileUpdated': 'Profile updated successfully',
      // Contact Log
      'contactLog': 'Contact Log',
      'addContactLog': 'Add Log',
      'contactType': 'Type',
      'contactTypeCall': 'Call',
      'contactTypeFitting': 'Fitting',
      'contactTypeMessage': 'Message',
      'contactTypeNote': 'Note',
      'noContactLogs': 'No contact logs yet.',
      'contactLogAdded': 'Log added.',
      'editOrderInPOS': 'Edit Order',
      'tapToSet': 'Tap to set...',
      'timelineTitle': 'Timeline',
      'filterAll': 'All',
      'filterContact': 'Contact',
      'filterFitting': 'Fitting',
      'filterOrder': 'Order',
      'tierNew': 'New',
      'tierRegular': 'Regular',
      'tierVip': 'VIP',
      'followUpDate': 'Follow-up Date',
      'followUpDue': 'Follow-up due',
      'markDone': 'Done',
    },

    'zh_TW': {
      // Navigation
      'navDashboard': '儀表板',
      'navPOS': '收銀',
      'navOrders': '訂單',
      'navClients': '客戶',
      'navFabric': '布料',
      'navShop': '工坊',
      'navSettings': '設定',
      // Common
      'cancelButton': '取消',
      'saveButton': '儲存',
      'editButton': '編輯',
      'deleteButton': '刪除',
      'addButton': '新增',
      'updateButton': '更新',
      'noButton': '否',
      'yesButton': '是',
      'errorPrefix': '錯誤：',
      'nameRequired': '姓名 *',
      'namePlaceholder': '客戶姓名',
      'phoneLabel': '電話',
      'emailLabel': '電子郵件',
      'emailPlaceholder': 'customer@example.com',
      'phonePlaceholder': '客戶電話',
      'nameRequiredError': '請輸入姓名',
      'emailFormatError': '請輸入有效的電子郵件',
      'customerAddedSuccess': '客戶已成功新增',
      'dateLabel': '日期',
      'addNewCustomer': '新增客戶',
      'saveChanges': '儲存設定',
      'noData': '無資料',
      // Dashboard
      'dashboardTitle': '儀表板',
      'overview': '總覽',
      'shopDescription': '以下是您商店的最新動態',
      'totalRevenue': '總營收',
      'filterSubtext': '點擊選單篩選',
      'filterWeek': '本週',
      'filterMonth': '本月',
      'filterYear': '今年',
      'filterCustomRange': '自訂範圍...',
      'itemSalesQty': '商品銷售量',
      'unitsSold': '件已售出',
      'noSales': '無銷售',
      'noPeriod': '在此期間',
      'activeJobs': '進行中工作',
      'allClear': '全部完成',
      'inProduction': '生產中',
      'urgentTasks': '件緊急任務！',
      'outstanding': '未付款',
      'allPaid': '全部已付',
      'unpaidOrders': '張未付訂單',
      'totalCustomers': '總客戶數',
      'lifetimeClients': '終身客戶',
      'recentOrders': '最近訂單',
      'viewAll': '查看全部',
      'noOrdersYet': '尚無訂單',
      'quickActions': '快速操作',
      'newOrder': '新增訂單',
      'addCustomerAction': '新增客戶',
      'checkWorkshop': '查看工坊',
      'costAnalysis': '成本分析',
      'productionFlow': '生產流程',
      'activeTasks': '個進行中任務',
      // Orders
      'ordersTitle': '訂單',
      'orderDetails': '訂單詳情',
      'orderNumber': '訂單 #',
      'itemsLabel': '項目',
      'internalCostProfit': '內部成本與利潤',
      'materialCost': '材料成本',
      'outsourcingCost': '外包成本',
      'fixedCost': '固定成本',
      'laborCost': '人工成本',
      'totalCost': '總成本',
      'netProfit': '淨利潤',
      'subtotal': '小計',
      'discount': '折扣',
      'total': '合計',
      'depositPaid': '訂金 / 已付',
      'balanceDue': '待付餘額',
      'fabricOrdered': '布料已訂購',
      'pendingOrder': '待訂購',
      'fabricReady': '布料已備妥',
      'noFabricRequired': '無需布料',
      'fabricMarkedOrdered': '布料已標記為已訂購',
      'fabricMarkedNotOrdered': '布料已標記為未訂購',
      'fabricSyncError': '布料狀態同步失敗: ',
      'receiptButton': '收據',
      'photosButton': '照片',
      'deleteOrder': '刪除訂單',
      'deleteOrderConfirm': '確認刪除訂單？',
      'deleteOrderWarning': '確定要刪除訂單 #',
      'cannotUndo': '此操作無法復原。',
      'searchOrdersHint': '搜尋 #ID、客戶、布料或服務...',
      'customerLabel': '客戶',
      'paymentLabel': '付款',
      'noFabricImage': '無布料圖片',
      'movedToStatus': '已移至',
      'pendingOrders': '待處理訂單',
      'outstandingOrders': '未付款訂單',
      'exportCSV': '匯出細項 CSV',
      'noMatchingOrders': '已載入記錄中找不到符合的訂單',
      'createFirstOrder': '建立第一筆訂單',
      'loadMoreHistory': '載入更多歷史',
      'markFabricOrdered': '標記布料已訂購',
      'loadMoreShowing': '載入更多（顯示中',
      'allOrdersLoaded': '已載入全部 {n} 筆',
      'unexpectedError': '發生未預期的錯誤。',
      'confirmOrderButton': '確認訂單',
      'markAsCompleteButton': '標記為完成',
      'confirmOrderMsg': '確認此訂單？',
      'markCompleteMsg': '將此訂單標記為完成？\n此操作無法復原。',
      'deliveryDateLabel': '交貨日期',
      'balancePaymentsLabel': '餘款記錄',
      // Workshop
      'workshopTitle': '工坊看板',
      'statusMeasuring': '量度',
      'statusCutting': '裁布',
      'statusSewing': '縫製',
      'statusFinishing': '完工',
      'statusCompleted': '已完成',
      'archivedHistory': '已封存歷史',
      'backToBoard': '返回看板',
      'archiveButton': '封存',
      'noTasks': '無任務',
      'editOrderTitle': '編輯訂單',
      'jobDetails': '工作詳情',
      'ticketNumber': '工單號 #',
      'itemStyle': '款式說明',
      'itemStyleHint': '例：三件套西裝，VBC 布料...',
      'fabricItems': '布料 / 項目',
      'notesLabel': '備注 / 量度',
      'notesHint': '在此新增特別指示...',
      'noNotes': '無備注',
      'changesSaved': '修改已成功儲存！',
      'searchWorkshopHint': '搜尋工單 #ID、客戶或項目...',
      'dueDateLabel': '截止日期',
      // Fabric
      'fabricTitle': '布料庫存',
      'categoryAll': '全部',
      'categoryCotton': '棉',
      'categoryLinen': '麻',
      'categoryWool': '羊毛',
      'categoryOther': '其他',
      'addFabric': '新增布料',
      'editFabric': '編輯布料',
      'availableOnline': '線上可用',
      'visibleToCustomers': '客戶可見',
      'hiddenFromStore': '已隱藏',
      'categoryLabel': '類別',
      'colourLabel': '顏色',
      'colourPlaceholder': '例：NAVY BLUE',
      'costPrice': '成本價',
      'retailPrice': '零售價',
      'stockLabel': '庫存',
      'unitLabel': '單位',
      'reorderLevel': '補貨標準',
      'addPhotoAiScan': '新增照片及 AI 掃描',
      'searchFabricHint': '搜尋布料名稱...',
      'savingData': '儲存中...',
      'duplicateNameError': '已存在相同名稱的布料。',
      'imageUploadFailed': '圖片上傳失敗或逾時，請重試。',
      'sortOrder': '排序',
      'sortNameAZ': '名稱 (A-Z)',
      'sortNameZA': '名稱 (Z-A)',
      'switchToList': '切換到列表',
      'switchToGrid': '切換到網格',
      'lowStock': '庫存不足',
      'deleteFabric': '刪除布料',
      'savingButton': '儲存中...',
      'nameLabel': '名稱',
      'onlineLabel': '在線',
      'offlineLabel': '離線',
      // POS
      'selectCustomer': '選擇客戶',
      'searchCustomerHint': '搜尋姓名或電話...',
      'cartItems': '購物車',
      'cartEmpty': '購物車為空',
      'addFirstItem': '新增第一件商品',
      'printReceiptTitle': '列印收據？',
      'printReceiptQuestion': '是否立即列印客戶收據？',
      'printButton': '列印',
      'printJobTicketsTitle': '列印工單？',
      'orderProcessedSuccess': '訂單處理成功！',
      'searchCustomersHint': '搜尋客戶...',
      'depositPaymentMethod': '訂金付款方式',
      'costBreakdown': '成本明細',
      'estimatedProfit': '預計利潤',
      'outstandingBalance': '待付餘額',
      'editItemTooltip': '編輯項目',
      'addItemButton': '新增項目',
      'balanceMethod': '尾數付款方式',
      'fabricImagesTitle': '布料圖片',
      'closeButton': '關閉',
      'customerSection': '客戶',
      'emailInvalidError': '請輸入有效的電子郵件',
      'pleaseAddItemsMsg': '請新增項目並選擇客戶',
      'enterAmountHint': '輸入金額',
      'noFabricText': '無需布料',
      'fabricReminderTitle': '訂布提醒',
      'fabricReminderSubtitle': '以下布料需要向供應商訂購：',
      'laterButton': '稍後',
      'printJobTicketsBody': '已建立 {n} 張工單。\n是否列印工廠工單？',
      // Customers
      'customersTitle': '客戶',
      'exportButton': '匯出',
      'topVips': '前 10 名 VIP',
      'allCustomers': '所有客戶',
      'spendingInfo': '根據近兩年消費排名',
      'noOrdersInPeriod': '近兩年無訂單',
      'twoYearSpent': '兩年消費：',
      'ordersLabel': '訂單',
      'noCustomersFound': '找不到客戶',
      'noCustomerData': '找不到客戶資料。',
      'exportPreparing': '正在準備匯出資料...',
      'exportSuccess': '✅ 匯出成功！',
      'exportFailed': '❌ 匯出失敗',
      'requiredField': '必填',
      // Settings
      'settingsTitle': '設定',
      'shopInformation': '商店資訊',
      'shopNameLabel': '店名',
      'currencyLabel': '幣別',
      'currentPrefix': '目前：',
      'systemConfiguration': '系統設定',
      'nextOrderNumber': '下一個訂單號碼',
      'helperSetStartingId': '手動設定起始 ID',
      'productsServices': '產品與服務',
      'manageServiceItems': '管理服務項目',
      'manageServiceItemsSub': '新增、編輯價格及布料用量',
      'measurementFieldsLabel': '量度欄位',
      'measurementFieldsSub': '自訂身體量度輸入',
      'printerHardware': '印表機與設備',
      'testPrint': '測試工單列印',
      'testPrintSub': '列印範例 A4 工單以確認版面',
      'preferencesLabel': '偏好設定',
      'languageLabel': '語言',
      'systemLanguage': '系統語言',
      'fabricUnit': '布料單位',
      'defaultUnit': '庫存預設單位',
      'appNotifications': '應用通知',
      'orderNotificationsLabel': '訂單通知',
      'alertDueDate': '截止日期接近時發出警報',
      'systemInfo': '系統資訊',
      'versionLabel': '版本',
      'versionValue': 'Ver 2.3.0 (Beta)',
      'resetLocalSettings': '重設本地設定',
      'dataMaintenance': '資料維護',
      'cleanOrphanedData': '清除孤立資料',
      'cleanOrphanedDataSub': '刪除無對應訂單的 order_items 和 workshop_orders',
      'accountLabel': '帳戶',
      'logout': '登出',
      'settingsSaved': '設定已成功儲存',
      'languageSwitchedTo': '語言已切換至',
      'invalidOrderId': '無效的訂單 ID',
      'appearance': '外觀',
      'accentColor': '主題色',
      'systemTextColor': '系統文字色',
      'headingTextColor': '標題文字色',
      'cardLabelColor': '卡片標籤色',
      'sidebarTextColor': '側邊欄文字色',
      'serviceList': '服務列表',
      'noServices': '找不到服務，請新增！',
      'addNewService': '新增服務',
      'newFieldHint': '新欄位名稱（例：手腕）',
      // Login
      'loginTitle': 'ALEXIS SYSTEM',
      'staffLogin': '員工登入',
      'passwordLabel': '密碼',
      'loginButton': '登入',
      'userNotFound': '找不到此電子郵件的用戶',
      'incorrectPassword': '密碼錯誤',
      'invalidEmail': '電子郵件格式無效',
      'loginFailed': '登入失敗：',
      // Customer Details
      'customerProfile': '客戶資料',
      'editProfileTooltip': '編輯資料（電話/電郵）',
      'editCustomerProfile': '編輯客戶資料',
      'bodyMeasurements': '身體尺寸',
      'editMeasurements': '編輯尺寸',
      'measurementsUpdated': '尺寸已更新！',
      'orderHistory': '訂單記錄',
      'totalSpent': '總消費額',
      'noMeasurements': '尚無尺寸資料',
      'noOrdersFound': '找不到訂單',
      'profileUpdated': '資料已成功更新',
      // Contact Log
      'contactLog': '聯絡記錄',
      'addContactLog': '新增記錄',
      'contactType': '類型',
      'contactTypeCall': '電話',
      'contactTypeFitting': '試身',
      'contactTypeMessage': '信息',
      'contactTypeNote': '備注',
      'noContactLogs': '尚無聯絡記錄',
      'contactLogAdded': '記錄已新增',
      'editOrderInPOS': '編輯訂單',
      'tapToSet': '點擊設定...',
      'timelineTitle': '時間軸',
      'filterAll': '全部',
      'filterContact': '聯絡',
      'filterFitting': '試身',
      'filterOrder': '訂單',
      'tierNew': '新客',
      'tierRegular': '常客',
      'tierVip': 'VIP',
      'followUpDate': '跟進日期',
      'followUpDue': '跟進到期',
      'markDone': '完成',
    },

    'zh_CN': {
      // Navigation
      'navDashboard': '仪表板',
      'navPOS': '收银',
      'navOrders': '订单',
      'navClients': '客户',
      'navFabric': '布料',
      'navShop': '工坊',
      'navSettings': '设置',
      // Common
      'cancelButton': '取消',
      'saveButton': '保存',
      'editButton': '编辑',
      'deleteButton': '删除',
      'addButton': '新增',
      'updateButton': '更新',
      'noButton': '否',
      'yesButton': '是',
      'errorPrefix': '错误：',
      'nameRequired': '姓名 *',
      'namePlaceholder': '客户姓名',
      'phoneLabel': '电话',
      'emailLabel': '电子邮件',
      'emailPlaceholder': 'customer@example.com',
      'phonePlaceholder': '客户电话',
      'nameRequiredError': '请输入姓名',
      'emailFormatError': '请输入有效的电子邮件',
      'customerAddedSuccess': '客户已成功添加',
      'dateLabel': '日期',
      'addNewCustomer': '新增客户',
      'saveChanges': '保存设置',
      'noData': '无数据',
      // Dashboard
      'dashboardTitle': '仪表板',
      'overview': '总览',
      'shopDescription': '以下是您商店的最新动态',
      'totalRevenue': '总营收',
      'filterSubtext': '点击菜单筛选',
      'filterWeek': '本周',
      'filterMonth': '本月',
      'filterYear': '今年',
      'filterCustomRange': '自定义范围...',
      'itemSalesQty': '商品销售量',
      'unitsSold': '件已售出',
      'noSales': '无销售',
      'noPeriod': '在此期间',
      'activeJobs': '进行中工作',
      'allClear': '全部完成',
      'inProduction': '生产中',
      'urgentTasks': '件紧急任务！',
      'outstanding': '未付款',
      'allPaid': '全部已付',
      'unpaidOrders': '张未付订单',
      'totalCustomers': '总客户数',
      'lifetimeClients': '终身客户',
      'recentOrders': '最近订单',
      'viewAll': '查看全部',
      'noOrdersYet': '尚无订单',
      'quickActions': '快速操作',
      'newOrder': '新增订单',
      'addCustomerAction': '新增客户',
      'checkWorkshop': '查看工坊',
      'costAnalysis': '成本分析',
      'productionFlow': '生产流程',
      'activeTasks': '个进行中任务',
      // Orders
      'ordersTitle': '订单',
      'orderDetails': '订单详情',
      'orderNumber': '订单 #',
      'itemsLabel': '项目',
      'internalCostProfit': '内部成本与利润',
      'materialCost': '材料成本',
      'outsourcingCost': '外包成本',
      'fixedCost': '固定成本',
      'laborCost': '人工成本',
      'totalCost': '总成本',
      'netProfit': '净利润',
      'subtotal': '小计',
      'discount': '折扣',
      'total': '合计',
      'depositPaid': '订金 / 已付',
      'balanceDue': '待付余额',
      'fabricOrdered': '布料已订购',
      'pendingOrder': '待订购',
      'fabricReady': '布料已备妥',
      'noFabricRequired': '无需布料',
      'fabricMarkedOrdered': '布料已标记为已订购',
      'fabricMarkedNotOrdered': '布料已标记为未订购',
      'fabricSyncError': '布料状态同步失败: ',
      'receiptButton': '收据',
      'photosButton': '照片',
      'deleteOrder': '删除订单',
      'deleteOrderConfirm': '确认删除订单？',
      'deleteOrderWarning': '确定要删除订单 #',
      'cannotUndo': '此操作无法撤销。',
      'searchOrdersHint': '搜索 #ID、客户、布料或服务...',
      'customerLabel': '客户',
      'paymentLabel': '付款',
      'noFabricImage': '无布料图片',
      'movedToStatus': '已移至',
      'pendingOrders': '待处理订单',
      'outstandingOrders': '未付款订单',
      'exportCSV': '导出细项 CSV',
      'noMatchingOrders': '已载入记录中找不到符合的订单',
      'createFirstOrder': '创建第一笔订单',
      'loadMoreHistory': '载入更多历史',
      'markFabricOrdered': '标记布料已订购',
      'loadMoreShowing': '载入更多（显示中',
      'allOrdersLoaded': '已载入全部 {n} 笔',
      'unexpectedError': '发生意外错误。',
      'confirmOrderButton': '确认订单',
      'markAsCompleteButton': '标记为完成',
      'confirmOrderMsg': '确认此订单？',
      'markCompleteMsg': '将此订单标记为完成？\n此操作无法撤销。',
      'deliveryDateLabel': '交货日期',
      'balancePaymentsLabel': '余款记录',
      // Workshop
      'workshopTitle': '工坊看板',
      'statusMeasuring': '量度',
      'statusCutting': '裁布',
      'statusSewing': '缝制',
      'statusFinishing': '完工',
      'statusCompleted': '已完成',
      'archivedHistory': '已存档历史',
      'backToBoard': '返回看板',
      'archiveButton': '存档',
      'noTasks': '无任务',
      'editOrderTitle': '编辑订单',
      'jobDetails': '工作详情',
      'ticketNumber': '工单号 #',
      'itemStyle': '款式说明',
      'itemStyleHint': '例：三件套西装，VBC 布料...',
      'fabricItems': '布料 / 项目',
      'notesLabel': '备注 / 量度',
      'notesHint': '在此添加特别指示...',
      'noNotes': '无备注',
      'changesSaved': '修改已成功保存！',
      'searchWorkshopHint': '搜索工单 #ID、客户或项目...',
      'dueDateLabel': '截止日期',
      // Fabric
      'fabricTitle': '布料库存',
      'categoryAll': '全部',
      'categoryCotton': '棉',
      'categoryLinen': '麻',
      'categoryWool': '羊毛',
      'categoryOther': '其他',
      'addFabric': '新增布料',
      'editFabric': '编辑布料',
      'availableOnline': '线上可用',
      'visibleToCustomers': '客户可见',
      'hiddenFromStore': '已隐藏',
      'categoryLabel': '类别',
      'colourLabel': '颜色',
      'colourPlaceholder': '例：NAVY BLUE',
      'costPrice': '成本价',
      'retailPrice': '零售价',
      'stockLabel': '库存',
      'unitLabel': '单位',
      'reorderLevel': '补货标准',
      'addPhotoAiScan': '添加照片及 AI 扫描',
      'searchFabricHint': '搜索布料名称...',
      'savingData': '保存中...',
      'duplicateNameError': '已存在相同名称的布料。',
      'imageUploadFailed': '图片上传失败或超时，请重试。',
      'sortOrder': '排序',
      'sortNameAZ': '名称 (A-Z)',
      'sortNameZA': '名称 (Z-A)',
      'switchToList': '切换到列表',
      'switchToGrid': '切换到网格',
      'lowStock': '库存不足',
      'deleteFabric': '删除布料',
      'savingButton': '保存中...',
      'nameLabel': '名称',
      'onlineLabel': '在线',
      'offlineLabel': '离线',
      // POS
      'selectCustomer': '选择客户',
      'searchCustomerHint': '搜索姓名或电话...',
      'cartItems': '购物车',
      'cartEmpty': '购物车为空',
      'addFirstItem': '添加第一件商品',
      'printReceiptTitle': '打印收据？',
      'printReceiptQuestion': '是否立即打印客户收据？',
      'printButton': '打印',
      'printJobTicketsTitle': '打印工单？',
      'orderProcessedSuccess': '订单处理成功！',
      'searchCustomersHint': '搜索客户...',
      'depositPaymentMethod': '订金付款方式',
      'costBreakdown': '成本明细',
      'estimatedProfit': '预计利润',
      'outstandingBalance': '待付余额',
      'editItemTooltip': '编辑项目',
      'addItemButton': '添加项目',
      'balanceMethod': '尾款付款方式',
      'fabricImagesTitle': '布料图片',
      'closeButton': '关闭',
      'customerSection': '客户',
      'emailInvalidError': '请输入有效的电子邮箱',
      'pleaseAddItemsMsg': '请添加项目并选择客户',
      'enterAmountHint': '输入金额',
      'noFabricText': '无需布料',
      'fabricReminderTitle': '订布提醒',
      'fabricReminderSubtitle': '以下布料需要向供应商订购：',
      'laterButton': '稍后',
      'printJobTicketsBody': '已创建 {n} 张工单。\n是否打印工厂工单？',
      // Customers
      'customersTitle': '客户',
      'exportButton': '导出',
      'topVips': '前 10 名 VIP',
      'allCustomers': '所有客户',
      'spendingInfo': '根据近两年消费排名',
      'noOrdersInPeriod': '近两年无订单',
      'twoYearSpent': '两年消费：',
      'ordersLabel': '订单',
      'noCustomersFound': '找不到客户',
      'noCustomerData': '找不到客户资料。',
      'exportPreparing': '正在准备导出资料...',
      'exportSuccess': '✅ 导出成功！',
      'exportFailed': '❌ 导出失败',
      'requiredField': '必填',
      // Settings
      'settingsTitle': '设置',
      'shopInformation': '商店信息',
      'shopNameLabel': '店名',
      'currencyLabel': '货币',
      'currentPrefix': '当前：',
      'systemConfiguration': '系统设置',
      'nextOrderNumber': '下一个订单号码',
      'helperSetStartingId': '手动设置起始 ID',
      'productsServices': '产品与服务',
      'manageServiceItems': '管理服务项目',
      'manageServiceItemsSub': '新增、编辑价格及布料用量',
      'measurementFieldsLabel': '量度字段',
      'measurementFieldsSub': '自定义身体量度输入',
      'printerHardware': '打印机与设备',
      'testPrint': '测试工单打印',
      'testPrintSub': '打印示例 A4 工单以确认版面',
      'preferencesLabel': '偏好设置',
      'languageLabel': '语言',
      'systemLanguage': '系统语言',
      'fabricUnit': '布料单位',
      'defaultUnit': '库存默认单位',
      'appNotifications': '应用通知',
      'orderNotificationsLabel': '订单通知',
      'alertDueDate': '截止日期临近时发出警报',
      'systemInfo': '系统信息',
      'versionLabel': '版本',
      'versionValue': 'Ver 2.3.0 (Beta)',
      'resetLocalSettings': '重置本地设置',
      'dataMaintenance': '数据维护',
      'cleanOrphanedData': '清除孤立数据',
      'cleanOrphanedDataSub': '删除无对应订单的 order_items 和 workshop_orders',
      'accountLabel': '账户',
      'logout': '登出',
      'settingsSaved': '设置已成功保存',
      'languageSwitchedTo': '语言已切换至',
      'invalidOrderId': '无效的订单 ID',
      'appearance': '外观',
      'accentColor': '主题色',
      'systemTextColor': '系统文字色',
      'headingTextColor': '标题文字色',
      'cardLabelColor': '卡片标签色',
      'sidebarTextColor': '侧边栏文字色',
      'serviceList': '服务列表',
      'noServices': '找不到服务，请新增！',
      'addNewService': '新增服务',
      'newFieldHint': '新字段名称（例：手腕）',
      // Login
      'loginTitle': 'ALEXIS SYSTEM',
      'staffLogin': '员工登录',
      'passwordLabel': '密码',
      'loginButton': '登录',
      'userNotFound': '找不到此电子邮件的用户',
      'incorrectPassword': '密码错误',
      'invalidEmail': '电子邮件格式无效',
      'loginFailed': '登录失败：',
      // Customer Details
      'customerProfile': '客户资料',
      'editProfileTooltip': '编辑资料（电话/邮箱）',
      'editCustomerProfile': '编辑客户资料',
      'bodyMeasurements': '身体尺寸',
      'editMeasurements': '编辑尺寸',
      'measurementsUpdated': '尺寸已更新！',
      'orderHistory': '订单记录',
      'totalSpent': '总消费额',
      'noMeasurements': '尚无尺寸数据',
      'noOrdersFound': '找不到订单',
      'profileUpdated': '资料已成功更新',
      // Contact Log
      'contactLog': '联络记录',
      'addContactLog': '新增记录',
      'contactType': '类型',
      'contactTypeCall': '电话',
      'contactTypeFitting': '试衣',
      'contactTypeMessage': '信息',
      'contactTypeNote': '备注',
      'noContactLogs': '暂无联络记录',
      'contactLogAdded': '记录已添加',
      'editOrderInPOS': '编辑订单',
      'tapToSet': '点击设置...',
      'timelineTitle': '时间轴',
      'filterAll': '全部',
      'filterContact': '联络',
      'filterFitting': '试身',
      'filterOrder': '订单',
      'tierNew': '新客',
      'tierRegular': '常客',
      'tierVip': 'VIP',
      'followUpDate': '跟进日期',
      'followUpDue': '跟进到期',
      'markDone': '完成',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
