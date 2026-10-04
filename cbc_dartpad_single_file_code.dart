import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.instance.load();
  runApp(const CbcApp());
}

class CbcApp extends StatelessWidget {
  const CbcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBC Community',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B0000),
          primary: const Color(0xFF8B0000),
          secondary: const Color(0xFFF39C12),
          tertiary: const Color(0xFF00A896),
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFDFBF7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF8B0000),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const CbcShell(),
    );
  }
}

// states of an Asset - we use to let user understand the current state of an asset in the CBC inventory
enum AssetStatus { available, limited, unavailable }

enum AvailabilityFilter {
  requestable('Requestable'),
  available('Available'),
  limited('Limited'),
  unavailable('Unavailable'),
  all('Show all');

  const AvailabilityFilter(this.label);

  final String label;

  bool matches(AssetStatus status) => switch (this) {
    AvailabilityFilter.requestable => status != AssetStatus.unavailable,
    AvailabilityFilter.available => status == AssetStatus.available,
    AvailabilityFilter.limited => status == AssetStatus.limited,
    AvailabilityFilter.unavailable => status == AssetStatus.unavailable,
    AvailabilityFilter.all => true,
  };
}

enum AssetSort {
  nameAsc('Name (A–Z)'),
  nameDesc('Name (Z–A)'),
  availability('Availability'),
  category('Category');

  const AssetSort(this.label);

  final String label;

  int compare(Asset a, Asset b) {
    switch (this) {
      case AssetSort.nameAsc:
        return a.name.compareTo(b.name);
      case AssetSort.nameDesc:
        return b.name.compareTo(a.name);
      case AssetSort.availability:
        final byStatus = a.status.index.compareTo(b.status.index);
        if (byStatus != 0) return byStatus;
        final byQuantity = b.quantity.compareTo(a.quantity);
        return byQuantity != 0 ? byQuantity : a.name.compareTo(b.name);
      case AssetSort.category:
        final byCategory = a.category.compareTo(b.category);
        return byCategory != 0 ? byCategory : a.name.compareTo(b.name);
    }
  }
}

class Asset {
  const Asset({
    required this.name,
    required this.category,
    required this.description,
    required this.status,
    required this.quantity,
    required this.icon,
  });

  final String name;
  final String category;
  final String description;
  final AssetStatus status;
  final int quantity;
  final IconData icon;
}

// dummy hardcoded list for assets
const assets = <Asset>[
  Asset(
    name: 'Portable Projector',
    category: 'Audio Visual',
    description:
        'HD projector suitable for community meetings, workshops and presentations.',
    status: AssetStatus.available,
    quantity: 3,
    icon: Icons.videocam_outlined,
  ),
  Asset(
    name: 'Wireless Speaker',
    category: 'Audio',
    description:
        'Portable speaker for indoor and small outdoor community events.',
    status: AssetStatus.limited,
    quantity: 1,
    icon: Icons.speaker_group_outlined,
  ),
  Asset(
    name: 'Folding Chairs',
    category: 'Furniture',
    description:
        'Stackable folding chairs for meetings and community gatherings.',
    status: AssetStatus.available,
    quantity: 40,
    icon: Icons.chair_outlined,
  ),
  Asset(
    name: 'Folding Tables',
    category: 'Furniture',
    description:
        'Portable tables suitable for workshops, food service and events.',
    status: AssetStatus.available,
    quantity: 8,
    icon: Icons.table_restaurant_outlined,
  ),
  Asset(
    name: 'Wireless Microphone',
    category: 'Audio',
    description:
        'Wireless microphone for presentations and community announcements.',
    status: AssetStatus.unavailable,
    quantity: 0,
    icon: Icons.mic_none_outlined,
  ),
];

class RequestRecord {
  const RequestRecord({
    required this.id,
    required this.assetSummary,
    required this.date,
    required this.status,
    required this.location,
  });

  final String id;
  final String assetSummary;
  final String date;
  final String status;
  final String location;

  Map<String, dynamic> toJson() => {
        'id': id,
        'assetSummary': assetSummary,
        'date': date,
        'status': status,
        'location': location,
      };

  factory RequestRecord.fromJson(Map<String, dynamic> json) => RequestRecord(
        id: json['id'] as String,
        assetSummary: json['assetSummary'] as String,
        date: json['date'] as String,
        status: json['status'] as String,
        location: json['location'] as String,
      );

  bool get isActive => status != 'Completed';
}

class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _kName = 'profile.name';
  static const _kEmail = 'profile.email';
  static const _kPhone = 'profile.phone';
  static const _kRequests = 'requests.v1';

  SharedPreferences? _prefs;

  bool persistenceAvailable = false;

  String name = 'Sarah Mitchell';
  String email = 'sarah@example.com';
  String phone = '+61 412 345 678';
  List<RequestRecord> requests = [];

  List<RequestRecord> get activeRequests =>
      requests.where((r) => r.isActive).toList();
  List<RequestRecord> get pastRequests =>
      requests.where((r) => !r.isActive).toList();

  Future<void> load() async {
    requests = [];

    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
      _prefs = prefs;
      persistenceAvailable = true;

      name = prefs.getString(_kName) ?? name;
      email = prefs.getString(_kEmail) ?? email;
      phone = prefs.getString(_kPhone) ?? phone;

      final raw = prefs.getString(_kRequests);
      if (raw != null) {
        requests = (jsonDecode(raw) as List)
            .map((e) => RequestRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('AppStore.load failed: $e');
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _prefs?.setString(key, value);
    } catch (e) {
      debugPrint('AppStore write failed for $key: $e');
    }
  }

  Future<void> saveProfile({
    required String name,
    required String email,
    required String phone,
  }) async {
    this.name = name;
    this.email = email;
    this.phone = phone;
    notifyListeners();
    await _write(_kName, name);
    await _write(_kEmail, email);
    await _write(_kPhone, phone);
  }

  Future<RequestRecord> addRequest({
    required String assetSummary,
    required String location,
  }) async {
    final highest = requests
        .map((r) => int.tryParse(r.id.replaceFirst('CBC-', '')) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    final record = RequestRecord(
      id: 'CBC-${highest + 1}',
      assetSummary: assetSummary,
      date: _formatDate(DateTime.now()),
      status: 'Submitted',
      location: location,
    );

    requests = [record, ...requests];
    notifyListeners();
    await _write(
      _kRequests,
      jsonEncode(requests.map((r) => r.toJson()).toList()),
    );
    return record;
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

final phoneInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
  LengthLimitingTextInputFormatter(16),
];

class Validators {
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$',
  );

  static final RegExp _auPhonePattern = RegExp(
    r'^(?:\+61|0)(?:4\d{8}|[2378]\d{8})$',
  );

  static String? notEmpty(String? value, String label, {int minLength = 1}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required';
    if (text.length < minLength) {
      return '$label must be at least $minLength characters';
    }
    return null;
  }

  static String? fullName(String? value) =>
      notEmpty(value, 'Full name', minLength: 2);

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(text)) {
      return 'Enter a valid email address, e.g. name@example.com';
    }
    return null;
  }

  static String? phone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Phone number is required';
    final digits = text.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_auPhonePattern.hasMatch(digits)) {
      return 'Enter a valid Australian phone number, '
          'e.g. 0412 345 678 or +61 412 345 678';
    }
    return null;
  }
}

class CbcShell extends StatefulWidget {
  const CbcShell({super.key});

  @override
  State<CbcShell> createState() => _CbcShellState();
}

// BaseScreen handles the navigation for all the pages
// all screens are opened on the basescreen with bottom navigation or side navigation
class _CbcShellState extends State<CbcShell> {
  // we are handling side/ bottom screen navigation
  int selectedIndex = 0;

  final pages = const [
    HomePage(),
    AssetCataloguePage(),
    RequestsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    // To keep application responseibve and adaptable
    // NavigationBar is used on mobile devices, while NavigationRail is used for bigger devices (foldables)
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBC Community'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No new notifications')),
              );
            },
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: Text('Discover'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: Text('Assets'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.assignment_outlined),
                  selectedIcon: Icon(Icons.assignment),
                  label: Text('Requests'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Profile'),
                ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(selectedIndex),
                child: pages[selectedIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => selectedIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Assets',
                ),
                NavigationDestination(
                  icon: Icon(Icons.assignment_outlined),
                  selectedIcon: Icon(Icons.assignment),
                  label: 'Requests',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child, this.maxWidth = 1100});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // Handles the page screen to make it scrollable during overlap and constraint the screen max to 1100px and centers the content in big wide screens.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: child,
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // user greeting to understand the current user logged in
          ListenableBuilder(
            listenable: AppStore.instance,
            builder: (context, _) {
              final first = AppStore.instance.name.trim().split(' ').first;
              return Text(
                'Welcome, $first',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Everything you need to discover, request and manage CBC assets.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: 'Quick actions'),
          const SizedBox(height: 12),
          // Design Decision => Quick navigation to the important part of our application from homescreen on a single click
          // This will help Sarah to go through simple flow => Discover -> Request -> Manage
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 700 ? 3 : 1;

              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 3.1 : 1.5,
                children: [
                  _ActionCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'Browse assets',
                    subtitle: 'See availability before requesting.',
                    onTap: () => _openAssetCatalogue(context),
                  ),
                  _ActionCard(
                    icon: Icons.add_task_outlined,
                    title: 'Make a request',
                    subtitle: 'Start a new request form.',
                    onTap: () => _openNewRequest(context),
                  ),
                  _ActionCard(
                    icon: Icons.track_changes,
                    title: 'Track requests',
                    subtitle: 'See the latest request status.',
                    onTap: () => _openRequests(context),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          const _SectionTitle(title: 'CBC information'),
          const SizedBox(height: 12),
          // A simple about us card for user to explore more about CBC
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(Icons.groups_outlined, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cairns Bhutanese Community',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Connect with the community, access CBC information '
                          'and request shared assets for community activities.',
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonal(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const AlertDialog(
                              title: Text('About CBC'),
                              content: Text(
                                'CBC supports Bhutanese people in Cairns by '
                                'creating community connections and preserving '
                                'Bhutanese/Nepali culture.',
                              ),
                            ),
                          ),
                          child: const Text('Learn more'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _StatusBanner(),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        // showing recent updates on user request via this section
        final active = AppStore.instance.activeRequests;
        if (active.isEmpty) return const SizedBox.shrink();
        final latest = active.first;

        return Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.update),
            title: Text(
              active.length == 1
                  ? '1 active request'
                  : '${active.length} active requests',
            ),
            subtitle: Text(
              '${latest.id} is currently ${latest.status.toLowerCase()}.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openRequests(context),
          ),
        );
      },
    );
  }
}

class AssetCataloguePage extends StatefulWidget {
  const AssetCataloguePage({super.key});

  @override
  State<AssetCataloguePage> createState() => _AssetCataloguePageState();
}

class _AssetCataloguePageState extends State<AssetCataloguePage> {
  static const categories = ['All', 'Audio Visual', 'Audio', 'Furniture'];

  String query = '';
  String category = 'All';

  AvailabilityFilter availability = AvailabilityFilter.requestable;
  AssetSort sort = AssetSort.nameAsc;

  bool get _isDefaultAvailability =>
      availability == AvailabilityFilter.requestable;

  bool get _isDefaultCategory => category == 'All';

  int get _activeFilterCount =>
      (_isDefaultAvailability ? 0 : 1) + (_isDefaultCategory ? 0 : 1);

  List<Asset> get _visibleAssets {
    final result = assets.where((asset) {
      final q = query.toLowerCase();
      final matchesQuery =
          asset.name.toLowerCase().contains(q) ||
          asset.category.toLowerCase().contains(q);
      final matchesCategory = category == 'All' || asset.category == category;
      return matchesQuery &&
          matchesCategory &&
          availability.matches(asset.status);
    }).toList();

    result.sort(sort.compare);
    return result;
  }

  Future<void> _openFilterSheet() async {
    var tempAvailability = availability;
    var tempCategory = category;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final titleStyle = Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold);

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(title: 'Filter assets'),
                    const SizedBox(height: 16),
                    Text('Availability', style: titleStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: AvailabilityFilter.values
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item.label),
                              selected: tempAvailability == item,
                              onSelected: (_) =>
                                  setSheetState(() => tempAvailability = item),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('Category', style: titleStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: categories
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item),
                              selected: tempCategory == item,
                              onSelected: (_) =>
                                  setSheetState(() => tempCategory = item),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => setSheetState(() {
                              tempAvailability = AvailabilityFilter.requestable;
                              tempCategory = 'All';
                            }),
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (applied == true) {
      setState(() {
        availability = tempAvailability;
        category = tempCategory;
      });
    }
  }

  Future<void> _openSortSheet() async {
    final chosen = await showModalBottomSheet<AssetSort>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(title: 'Sort by'),
                const SizedBox(height: 8),
                ...AssetSort.values.map(
                  (option) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label),
                    trailing: option == sort ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(sheetContext, option),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null) setState(() => sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    // Asset filtering basis of search string and category
    final filtered = _visibleAssets;

    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assets',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Showing assets you can request. '
            'Use Filter to see others.',
          ),
          const SizedBox(height: 16),
          // Design Decision => Search functionality for faster asset finding.
          // Sarah can easily search the asset list by typing a few letters.
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search assets',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          // Design Decision => Categroy wise searching for faster asset finding on basis of category.
          // Sarah can narrow down the asset list by choosing her asset category.
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _openFilterSheet,
                icon: Badge(
                  isLabelVisible: _activeFilterCount > 0,
                  label: Text('$_activeFilterCount'),
                  child: const Icon(Icons.filter_list),
                ),
                label: const Text('Filter'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _openSortSheet,
                icon: const Icon(Icons.sort),
                label: const Text('Sort'),
              ),
            ],
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!_isDefaultAvailability)
                  InputChip(
                    label: Text(availability.label),
                    onDeleted: () => setState(
                      () => availability = AvailabilityFilter.requestable,
                    ),
                  ),
                if (!_isDefaultCategory)
                  InputChip(
                    label: Text(category),
                    onDeleted: () => setState(() => category = 'All'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '${filtered.length} '
            '${filtered.length == 1 ? 'asset' : 'assets'} • '
            'Sorted by ${sort.label.toLowerCase()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.search_off),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No assets match your search and filters. '
                        'Try changing the filter.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 600
                    ? 2
                    : 1;

                return GridView.builder(
                  itemCount: filtered.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: columns == 1 ? 3.0 : 1.25,
                  ),
                  itemBuilder: (context, index) {
                    return _AssetCard(asset: filtered[index]);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    // Design Decision => Showing the available quantity and asset status directly in the asset list cards.
    // Sarah can quickly see the availability and make a request if an asset is limited.
    final available = asset.status != AssetStatus.unavailable;

    final statusText = switch (asset.status) {
      AssetStatus.available => 'Available • ${asset.quantity} units',
      AssetStatus.limited => 'Limited • ${asset.quantity} unit',
      AssetStatus.unavailable => 'Currently unavailable',
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AssetDetailsPage(asset: asset)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(radius: 28, child: Icon(asset.icon, size: 28)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(asset.category),
                    const SizedBox(height: 8),
                    Text(statusText),
                  ],
                ),
              ),
              if (available) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class AssetDetailsPage extends StatelessWidget {
  const AssetDetailsPage({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    // Design Decision => Showing a simple asset detail page for user
    // Sarah can quickly determine whether the asset is suitable for her event by going through asset details
    final available = asset.status != AssetStatus.unavailable;

    return Scaffold(
      appBar: AppBar(title: const Text('Asset details')),
      body: PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 34, child: Icon(asset.icon, size: 34)),
                    const SizedBox(height: 18),
                    Text(
                      asset.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(asset.category),
                    const SizedBox(height: 16),
                    Text(asset.description),
                    const SizedBox(height: 20),
                    _AvailabilityChip(
                      status: asset.status,
                      quantity: asset.quantity,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Design Decision => Simple "request this asset" button takes user directly to asset request form for faster request creation.
            if (available)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RequestPage(initialAsset: asset),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Request this asset'),
                ),
              )
            else
              // if the asset is not available, a simple unavailablity message is shown to user.
              const Text(
                'This asset is currently unavailable. Please check again later.',
              ),
          ],
        ),
      ),
    );
  }
}

class RequestPage extends StatefulWidget {
  const RequestPage({super.key, this.initialAsset});

  final Asset? initialAsset;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final formKey = GlobalKey<FormState>();

  late final Map<String, int> quantities = {
    if (widget.initialAsset != null) widget.initialAsset!.name: 1,
  };

  bool submitAttempted = false;

  // Design Decision => user data is fetched from profile and prefilled here for preventing repeated task
  // Sarah frequently submits the asset requests and this will help us reduce her repeatative task of filling contact details everytime.
  final nameController = TextEditingController(text: AppStore.instance.name);
  final emailController = TextEditingController(text: AppStore.instance.email);
  final phoneController = TextEditingController(text: AppStore.instance.phone);
  final locationController = TextEditingController();
  final purposeController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    locationController.dispose();
    purposeController.dispose();
    super.dispose();
  }

  List<Asset> get _requestable =>
      assets.where((a) => a.status != AssetStatus.unavailable).toList();

  List<Asset> get _selectedAssets => quantities.keys
      .map((name) => assets.firstWhere((a) => a.name == name))
      .toList();

  List<Asset> get _otherAssets =>
      _requestable.where((a) => !quantities.containsKey(a.name)).toList();

  void _showAddAssetSheet() {
    // Design Decision => All the available assets are listed alongside user selected asset
    // Sarah can quickly add other assets or modify the quantities without leaving the request flow.
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final options = _otherAssets;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(title: 'Add asset'),
                    const SizedBox(height: 4),
                    const Text('Other assets available to request.'),
                    const SizedBox(height: 12),
                    if (options.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'You have added every asset that can be requested.',
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: options
                              .map(
                                (asset) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    child: Icon(asset.icon),
                                  ),
                                  title: Text(asset.name),
                                  subtitle: Text(
                                    '${asset.category} • '
                                    '${_availabilityLabel(asset)}',
                                  ),
                                  trailing: FilledButton.tonal(
                                    onPressed: () {
                                      setState(
                                        () => quantities[asset.name] = 1,
                                      );
                                      setSheetState(() {});
                                    },
                                    child: const Text('Add'),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectedAssets(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedAssets;
    final showAssetError = submitAttempted && selected.isEmpty;

    if (selected.isEmpty) {
      return Card(
        color: showAssetError ? scheme.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                showAssetError
                    ? Icons.error_outline
                    : Icons.inventory_2_outlined,
                color: showAssetError ? scheme.error : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  showAssetError
                      ? 'Select at least one asset to continue. '
                            'Use “Add asset” below.'
                      : 'No assets selected yet. Use “Add asset” to '
                            'choose what you need.',
                  style: showAssetError
                      ? TextStyle(color: scheme.onErrorContainer)
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: selected.map((asset) {
        final qty = quantities[asset.name]!;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 28, child: Icon(asset.icon, size: 28)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('Available: ${asset.quantity}'),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${asset.name}',
                      onPressed: () =>
                          setState(() => quantities.remove(asset.name)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Quantity'),
                    IconButton(
                      tooltip: 'Decrease quantity',
                      onPressed: qty <= 1
                          ? null
                          : () => setState(
                              () => quantities[asset.name] = qty - 1,
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$qty'),
                    IconButton(
                      tooltip: 'Increase quantity',
                      onPressed: qty >= asset.quantity
                          ? null
                          : () => setState(
                              () => quantities[asset.name] = qty + 1,
                            ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOtherAssets = _otherAssets.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Create request')),
      body: PageFrame(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(title: '1. Selected assets'),
              const SizedBox(height: 10),
              _buildSelectedAssets(context),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: hasOtherAssets ? _showAddAssetSheet : null,
                  icon: const Icon(Icons.add),
                  label: Text(
                    hasOtherAssets ? 'Add asset' : 'All available assets added',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle(title: '2. Contact details'),
              const SizedBox(height: 10),
              // Design Decision => A simple message to let user know details are prefilled but are editable if required.
              // Inform Sarah that her profile details have been pre-filled, while allowing her to modify the details.
              const Text(
                'Your saved profile details have been filled in. '
                'You can edit them if needed. Fields marked * are required.',
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: nameController,
                label: 'Full name',
                validator: Validators.fullName,
                keyboardType: TextInputType.name,
              ),
              _FormField(
                controller: emailController,
                label: 'Email',
                hint: 'name@example.com',
                validator: Validators.email,
                keyboardType: TextInputType.emailAddress,
              ),
              _FormField(
                controller: phoneController,
                label: 'Phone',
                hint: '0412 345 678',
                validator: Validators.phone,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneInputFormatters,
              ),
              _FormField(
                controller: locationController,
                label: 'Event location',
                validator: (v) => Validators.notEmpty(v, 'Event location'),
              ),
              _FormField(
                controller: purposeController,
                label: 'Event purpose',
                maxLines: 2,
                validator: (v) =>
                    Validators.notEmpty(v, 'Event purpose', minLength: 5),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _reviewRequest(context),
                  child: const Text('Review request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reviewRequest(BuildContext context) {
    // Design Decision => Providing a simple screen for user to review their request before sending it.
    // Sarah can quickly verify her selected assets, quantities and details before submitting the request.
    final formValid = formKey.currentState!.validate();
    final assetsValid = quantities.isNotEmpty;

    setState(() => submitAttempted = true);

    if (!formValid || !assetsValid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Please complete the highlighted fields before continuing.',
            ),
          ),
        );
      return;
    }

    final selected = quantities.entries
        .map((entry) => '${entry.value} × ${entry.key}')
        .join('\n');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewRequestPage(
          selectedAssets: selected,
          name: nameController.text.trim(),
          email: emailController.text.trim(),
          phone: phoneController.text.trim(),
          location: locationController.text.trim(),
          purpose: purposeController.text.trim(),
        ),
      ),
    );
  }
}

class ReviewRequestPage extends StatelessWidget {
  const ReviewRequestPage({
    super.key,
    required this.selectedAssets,
    required this.name,
    required this.email,
    required this.phone,
    required this.location,
    required this.purpose,
  });

  final String selectedAssets;
  final String name;
  final String email;
  final String phone;
  final String location;
  final String purpose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review request')),
      body: PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check before submitting',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _SummaryCard(
              title: 'Requested assets',
              child: Text(selectedAssets),
            ),
            _SummaryCard(
              title: 'Contact details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  Text(email),
                  Text(phone),
                  Text(location),
                ],
              ),
            ),
            _SummaryCard(title: 'Purpose', child: Text(purpose)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final record = await AppStore.instance.addRequest(
                    assetSummary: selectedAssets.replaceAll('\n', ', '),
                    location: location,
                  );
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RequestConfirmationPage(requestId: record.id),
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RequestConfirmationPage extends StatelessWidget {
  const RequestConfirmationPage({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    // Design Decision => A confirmation screen is shown to user to confirm them about their request submission to CBC system.
    // Sarah can immediately confirm that her request has been successfully submitted to CBC.
    return Scaffold(
      appBar: AppBar(title: const Text('Request submitted')),
      body: PageFrame(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      child: Icon(Icons.check, size: 36),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Request submitted',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your request $requestId has been received. '
                      'You can track its status from My Requests.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const CbcShell()),
                          (route) => false,
                        );
                      },
                      child: const Text('Back to CBC'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Design Decision => The page provides user overview of their active and past requests
    // Provide Sarah with an overview of active and past requests and can quickly monitor event-related active and past requests.
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) {
        final store = AppStore.instance;
        final titleStyle = Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold);

        return PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'My requests',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _openNewRequest(context),
                    icon: const Icon(Icons.add),
                    label: const Text('New request'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Track active requests and review previous requests.'),
              const SizedBox(height: 20),
              Text('Active', style: titleStyle),
              const SizedBox(height: 10),
              if (store.activeRequests.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No active requests.'),
                  ),
                )
              else
                ...store.activeRequests.map((r) => _RequestCard(request: r)),
              const SizedBox(height: 24),
              Text('Past requests', style: titleStyle),
              const SizedBox(height: 10),
              if (store.pastRequests.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No past requests yet.'),
                  ),
                )
              else
                ...store.pastRequests.map((r) => _RequestCard(request: r)),
            ],
          ),
        );
      },
    );
  }
}

class RequestDetailsPage extends StatelessWidget {
  const RequestDetailsPage({super.key, required this.request});

  final RequestRecord request;

  @override
  Widget build(BuildContext context) {
    // Design Decision => Request detail page provides user with the details of their request
    // Sarah can quickly understand how her request is progressing and its current stage without contacting the CBC admin office.
    return Scaffold(
      appBar: AppBar(title: Text(request.id)),
      body: PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryCard(
              title: 'Request details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.assetSummary),
                  const SizedBox(height: 8),
                  Text('Date: ${request.date}'),
                  Text('Location: ${request.location}'),
                ],
              ),
            ),
            _SummaryCard(
              title: 'Current status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusTimeline(currentStatus: request.status),
                  const SizedBox(height: 8),
                  const Text(
                    'Status updates are shown here so you do not need '
                    'to contact the CBC office for routine updates.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final RequestRecord request;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestDetailsPage(request: request),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.assignment_outlined)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.id,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(request.assetSummary),
                    const SizedBox(height: 6),
                    Text(request.date),
                  ],
                ),
              ),
              _StatusPill(status: request.status),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

// Design Decision => user details are stored and updated using this screen
// Sarah can modify her profile details so they can be automatically pre-filled when she submits future asset requests,
class _ProfilePageState extends State<ProfilePage> {
  final formKey = GlobalKey<FormState>();
  bool editing = false;

  final name = TextEditingController(text: AppStore.instance.name);
  final email = TextEditingController(text: AppStore.instance.email);
  final phone = TextEditingController(text: AppStore.instance.phone);

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _toggleEditing() async {
    if (!editing) {
      setState(() => editing = true);
      return;
    }

    if (formKey.currentState!.validate()) {
      await AppStore.instance.saveProfile(
        name: name.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim(),
      );
      if (!mounted) return;
      setState(() => editing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the highlighted fields before saving.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'My profile',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleEditing,
                  icon: Icon(editing ? Icons.check : Icons.edit_outlined),
                  label: Text(editing ? 'Save' : 'Edit'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      child: Icon(Icons.person, size: 34),
                    ),
                    const SizedBox(height: 18),
                    _FormField(
                      controller: name,
                      label: 'Full name',
                      enabled: editing,
                      validator: Validators.fullName,
                      keyboardType: TextInputType.name,
                    ),
                    _FormField(
                      controller: email,
                      label: 'Email',
                      enabled: editing,
                      validator: Validators.email,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _FormField(
                      controller: phone,
                      label: 'Phone',
                      enabled: editing,
                      validator: Validators.phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: phoneInputFormatters,
                    ),
                    if (!editing)
                      // Design Decision => Showing a simple message to inform user that these details will be prefilled directly during the request creation.
                      // Inform Sarah that her saved profile details will be automatically pre-filled in future requests, reducing repetitive data entry.
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'These saved details can be automatically used '
                          'when creating a request.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
    this.hint,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? hint;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: validator != null ? '$label *' : label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.status, required this.quantity});

  final AssetStatus status;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final data = switch (status) {
      AssetStatus.available => (
        'Available • $quantity units',
        Icons.check_circle_outline,
      ),
      AssetStatus.limited => (
        'Limited • $quantity unit',
        Icons.warning_amber_outlined,
      ),
      AssetStatus.unavailable => ('Unavailable', Icons.block_outlined),
    };

    return Chip(avatar: Icon(data.$2, size: 18), label: Text(data.$1));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(status));
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.currentStatus});

  final String currentStatus;

  @override
  Widget build(BuildContext context) {
    const statuses = [
      'Submitted',
      'Under review',
      'Approved',
      'Ready',
      'Completed',
    ];

    final current = statuses.indexOf(currentStatus);
    final currentIndex = current < 0 ? 1 : current;

    return Column(
      children: List.generate(statuses.length, (index) {
        final active = index <= currentIndex;

        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
          title: Text(
            statuses[index],
            style: TextStyle(
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }),
    );
  }
}

void _openAssetCatalogue(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Assets')),
        body: const AssetCataloguePage(),
      ),
    ),
  );
}

void _openRequests(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Requests')),
        body: const RequestsPage(),
      ),
    ),
  );
}

void _openNewRequest(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const RequestPage()),
  );
}

String _availabilityLabel(Asset asset) => switch (asset.status) {
  AssetStatus.available => 'Available • ${asset.quantity} units',
  AssetStatus.limited => 'Limited • ${asset.quantity} left',
  AssetStatus.unavailable => 'Currently unavailable',
};