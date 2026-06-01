import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/shop_balance.dart';
import 'dart:io';

class CollectionBalanceScreen extends StatefulWidget {
  const CollectionBalanceScreen({super.key});

  @override
  State<CollectionBalanceScreen> createState() => _CollectionBalanceScreenState();
}

class _CollectionBalanceScreenState extends State<CollectionBalanceScreen> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _areaScrollController = ScrollController();
  List<ShopBalance> _allBalances = [];
  List<ShopBalance> _filteredBalances = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  
  // Filter state
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  
  String _selectedArea = 'All Areas';
  List<String> _availableAreas = ['All Areas'];

  String _activeChip = ''; 
  String _sortBy = 'Name (A-Z)'; 

  @override
  void initState() {
    super.initState();
    _fetchBalances();
    _searchController.addListener(_applyFilters);
    _minAmountController.addListener(_applyFilters);
    _maxAmountController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    _scrollController.dispose();
    _areaScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchBalances() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final data = await ApiService.getShopBalances(auth.user!.token!);
      if (mounted) {
        setState(() {
          _allBalances = data.map((e) => ShopBalance.fromJson(e)).toList();
          
          final Map<String, int> termCounts = {};
          final List<String> stopWords = ['NEAR', 'OPP', 'OPPOSITE', 'THE', 'IN', 'AT', 'OF', 'STREET', 'ROAD', 'NEW', 'OLD', 'STAND', 'STORE', 'THEATRE', 'MAIN', 'ST', 'RD', 'BACKSIDE', 'BEHIND', 'BESIDE', 'NEXT'];
          
          final RegExp exp = RegExp(r'\((.*?)\)');
          for (var b in _allBalances) {
            final rawName = b.shopName.toUpperCase()
                .replaceAll('THIMARAJAPURAM', 'THIMMARAJAPURAM')
                .replaceAll('STAAND', 'STAND')
                .replaceAll(RegExp(r'BUS\s+STAND'), 'BUS STAND');

            List<String> potentialAreas = [];
            final match = exp.firstMatch(rawName);
            
            if (match != null && match.group(1) != null) {
               potentialAreas.addAll(match.group(1)!.split(','));
            } else if (rawName.contains(',')) {
               final commaParts = rawName.split(',');
               if (commaParts.length > 1) {
                 potentialAreas.addAll(commaParts.sublist(1));
               }
            }

            for (var areaStr in potentialAreas) {
               final content = areaStr.replaceAll(RegExp(r'[^A-Z\s]'), '');
               
               final p = content.trim();
               if (p.isNotEmpty) {
                 termCounts[p] = (termCounts[p] ?? 0) + 1;
               }
               
               final words = p.split(RegExp(r'\s+'));
               for (var word in words) {
                 if (word.length > 2 && !stopWords.contains(word)) {
                   termCounts[word] = (termCounts[word] ?? 0) + 1;
                 }
               }
            }
          }
          
          final Set<String> areas = {'All Areas'};
          
          // Guaranteed explicit overrides if they exist in data
          final List<String> explicitOverrides = ['THIMMARAJAPURAM', 'NEW BUS STAND', 'BUS STAND'];
          for (var override in explicitOverrides) {
             if (_allBalances.any((b) {
               final normalized = b.shopName.toUpperCase()
                   .replaceAll('THIMARAJAPURAM', 'THIMMARAJAPURAM')
                   .replaceAll('STAAND', 'STAND')
                   .replaceAll(RegExp(r'BUS\s+STAND'), 'BUS STAND');
               return normalized.contains(override);
             })) {
               areas.add(override);
             }
          }
          
          final List<String> landmarks = ['BUS STAND', 'STATION', 'HOSPITAL', 'COLONY', 'VILLAGE', 'NAGAR', 'PURAM', 'PALAYAM', 'PETTAI', 'JUNCTION'];
          
          final validTerms = termCounts.keys.where((t) {
            if (termCounts[t]! > 1) return true;
            for (var landmark in landmarks) {
              if (t.contains(landmark)) return true;
            }
            return false;
          }).toList();
          
          validTerms.sort((a, b) => b.length.compareTo(a.length));
          
          for (var term in validTerms) {
            bool isSubset = false;
            for (var added in areas) {
              if (added != 'All Areas' && added.contains(term) && (termCounts[added] ?? 0) >= (termCounts[term] ?? 0)) {
                isSubset = true;
                break;
              }
            }
            if (!isSubset) {
              areas.add(term);
            }
          }
          
          _availableAreas = areas.toList()..sort();
          
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching balances: $e'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _minAmountController.clear();
      _maxAmountController.clear();
      _selectedArea = 'All Areas';
      _sortBy = 'Name (A-Z)';
      _activeChip = '';
    });
    _applyFilters();
  }

  bool _hasActiveFilters() {
    return _searchController.text.isNotEmpty || 
           _minAmountController.text.isNotEmpty || 
           _maxAmountController.text.isNotEmpty || 
           _selectedArea != 'All Areas' ||
           _activeChip.isNotEmpty || 
           _sortBy != 'Name (A-Z)';
  }

  void _applyFilters() {
    List<ShopBalance> temp = List.from(_allBalances);
    
    // 1. Search (Smart Word-Boundary & Prefix Match)
    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      temp = temp.where((b) {
        final RegExp exp = RegExp(r'\((.*?)\)');
        final match = exp.firstMatch(b.shopName);
        final area = match != null && match.group(1) != null ? match.group(1)!.toLowerCase() : '';
        return _smartMatch(query, b.shopName) || _smartMatch(query, area);
      }).toList();
    }

    // 2. Area Filter
    if (_selectedArea != 'All Areas') {
      temp = temp.where((b) {
        final raw = b.shopName.toUpperCase()
            .replaceAll('THIMARAJAPURAM', 'THIMMARAJAPURAM')
            .replaceAll('STAAND', 'STAND')
            .replaceAll(RegExp(r'BUS\s+STAND'), 'BUS STAND');
        return raw.contains(_selectedArea);
      }).toList();
    }

    // 3. Amount Filter
    final minAmount = double.tryParse(_minAmountController.text);
    final maxAmount = double.tryParse(_maxAmountController.text);
    
    if (minAmount != null) {
      temp = temp.where((b) => b.amount >= minAmount).toList();
    }
    if (maxAmount != null) {
      temp = temp.where((b) => b.amount <= maxAmount).toList();
    }

    // 4. Sort & Top N
    final searchQuery = _searchController.text.toLowerCase().trim();
    
    if (searchQuery.isNotEmpty) {
      temp.sort((a, b) {
        final areaA = RegExp(r'\((.*?)\)').firstMatch(a.shopName)?.group(1)?.toLowerCase() ?? '';
        final areaB = RegExp(r'\((.*?)\)').firstMatch(b.shopName)?.group(1)?.toLowerCase() ?? '';
        
        int scoreA = _calculateRelevance(searchQuery, a.shopName.toLowerCase());
        int scoreAArea = _calculateRelevance(searchQuery, areaA);
        int finalScoreA = scoreA > scoreAArea ? scoreA : scoreAArea;

        int scoreB = _calculateRelevance(searchQuery, b.shopName.toLowerCase());
        int scoreBArea = _calculateRelevance(searchQuery, areaB);
        int finalScoreB = scoreB > scoreBArea ? scoreB : scoreBArea;
        
        if (finalScoreA != finalScoreB) {
           return finalScoreB.compareTo(finalScoreA); // Higher score first
        }
        return _compareBySortOption(a, b);
      });
      if (_activeChip == 'Top 10' && temp.length > 10) temp = temp.sublist(0, 10);
    } else {
      if (_activeChip == 'Top 10') {
        temp.sort((a, b) => b.amount.compareTo(a.amount));
        if (temp.length > 10) temp = temp.sublist(0, 10);
      } else {
        temp.sort((a, b) => _compareBySortOption(a, b));
      }
    }

    setState(() {
      _filteredBalances = temp;
    });
  }

  void _showFilterSortSheet() {
    final TextEditingController areaSearchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = areaSearchController.text.toLowerCase().trim();
            final filteredAreas = query.isEmpty 
                ? _availableAreas 
                : _availableAreas.where((a) => _smartMatch(query, a)).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20, right: 20, top: 20
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sort & Filter', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),

                    // Area Filter (Searchable)
                    const Text('Area / Location', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: areaSearchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search Area...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (val) {
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    if (filteredAreas.isNotEmpty)
                      Container(
                        height: 250,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Scrollbar(
                          thumbVisibility: true,
                          controller: _areaScrollController,
                          child: ListView.builder(
                            controller: _areaScrollController,
                            padding: EdgeInsets.zero,
                            itemCount: filteredAreas.length,
                            itemBuilder: (context, index) {
                              final area = filteredAreas[index];
                              final isSelected = _selectedArea == area;
                              return ListTile(
                                dense: true,
                                title: Text(area, style: TextStyle(color: isSelected ? Colors.cyanAccent : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Colors.cyanAccent, size: 20) : null,
                                onTap: () {
                                  setSheetState(() => _selectedArea = area);
                                  _applyFilters();
                                },
                              );
                            },
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No matching areas found.', style: TextStyle(color: Colors.white54)),
                      ),
                    const SizedBox(height: 24),

                    // Sort Options
                    const Text('Sort By', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Name (A-Z)', 'Name (Z-A)', 'Amount (High-Low)', 'Amount (Low-High)'].map((sortOption) {
                        final isSelected = _sortBy == sortOption;
                        return ChoiceChip(
                          label: Text(sortOption, style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white)),
                          selected: isSelected,
                          selectedColor: Colors.cyanAccent,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          onSelected: (val) {
                            setSheetState(() {
                              _sortBy = sortOption;
                              _activeChip = ''; 
                            });
                            _applyFilters();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Custom Amount Filter
                    const Text('Custom Amount Range', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minAmountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Min ₹',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('to', style: TextStyle(color: Colors.white54)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _maxAmountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Max ₹',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _clearFilters();
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: const Color(0xFF1A1A2E),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showUpdateDataBottomSheet() {
    final TextEditingController dataController = TextEditingController();
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24, right: 24, top: 32
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sync Balances', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Quickly sync your latest data from Excel or text files.', style: TextStyle(color: Colors.white60, fontSize: 14)),
                  const SizedBox(height: 24),
                  
                  // Action Buttons (Paste & Clear)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data != null && data.text != null) {
                              setSheetState(() {
                                dataController.text = data.text!;
                              });
                            }
                          },
                          icon: const Icon(Icons.content_paste_rounded, size: 18),
                          label: const Text('Paste Clipboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () {
                            setSheetState(() => dataController.clear());
                          },
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          tooltip: 'Clear Text',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Text Area
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: dataController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: "NAME\tAMOUNT\nJJ HOTEL\t1340\nASM SUBBIAH\t2572\n...",
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontFamily: 'monospace'),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Sync Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isUpdating ? null : () async {
                        final rawText = dataController.text;
                        if (rawText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please paste some data first')));
                          return;
                        }
                        
                        setSheetState(() => isUpdating = true);
                        await Future.delayed(const Duration(milliseconds: 100)); // Allow UI to render loading spinner
                        
                        try {
                          List<Map<String, dynamic>> parsedBalances = [];
                          final lines = rawText.split('\n');
                          for (String line in lines) {
                            line = line.trim();
                            if (line.isEmpty) continue;
                            if (line.toLowerCase().contains('name') && line.toLowerCase().contains('amount')) continue;
                            
                            List<String> parts = line.split('\t');
                            if (parts.length < 2) parts = line.split(RegExp(r'\s{2,}|,\s*')); 
                            
                            if (parts.length >= 2) {
                              String name = parts.sublist(0, parts.length - 1).join(' ').trim();
                              String amountStr = parts.last.trim().replaceAll(RegExp(r'[^0-9.]'), '');
                              double? amount = double.tryParse(amountStr);
                              
                              if (name.isNotEmpty && amount != null) {
                                parsedBalances.add({'shop_name': name, 'amount': amount});
                              }
                            }
                          }

                          if (parsedBalances.isEmpty) throw Exception("Could not parse any valid data from the text provided.");

                          final auth = Provider.of<AuthProvider>(context, listen: false);
                          await ApiService.bulkUpdateShopBalances(auth.user!.token!, parsedBalances);
                          
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Successfully synced ${parsedBalances.length} shop balances'), backgroundColor: Colors.green)
                            );
                            _fetchBalances();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent)
                            );
                            setSheetState(() => isUpdating = false);
                          }
                        }
                      },
                      icon: isUpdating 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1A2E)))
                        : const Icon(Icons.sync_rounded),
                      label: Text(isUpdating ? 'Syncing...' : 'Sync Data', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isAdmin = auth.user?.role == 'admin';
    double totalBalance = _filteredBalances.fold(0.0, (sum, item) => sum + item.amount);
    final bool hasFilters = _hasActiveFilters();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Collection Balance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.cyanAccent),
            onPressed: _fetchBalances,
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.upload_file_rounded, color: Colors.greenAccent),
              tooltip: 'Bulk Update',
              onPressed: _showUpdateDataBottomSheet,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
            decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search Shop or Area...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _showFilterSortSheet,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: hasFilters ? Colors.cyanAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: hasFilters ? Colors.cyanAccent.withOpacity(0.5) : Colors.transparent),
                    ),
                    child: Icon(Icons.tune_rounded, color: hasFilters ? Colors.cyanAccent : Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          
          // Quick Preset Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (hasFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ActionChip(
                      label: const Text('Clear', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      avatar: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                      backgroundColor: Colors.redAccent.withOpacity(0.1),
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                      onPressed: _clearFilters,
                    ),
                  ),
                ...['< ₹1k', '₹1k - ₹5k', '> ₹5k', '< ₹10k', '> ₹10k', 'Top 10'].map((chip) {
                  final isSelected = _activeChip == chip;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(chip, style: TextStyle(color: isSelected ? const Color(0xFF1A1A2E) : Colors.white70, fontWeight: FontWeight.bold)),
                      selected: isSelected,
                      selectedColor: Colors.cyanAccent,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (val) {
                        setState(() {
                          if (!val) {
                            _activeChip = '';
                            _minAmountController.clear();
                            _maxAmountController.clear();
                          } else {
                            _activeChip = chip;
                            if (chip == '< ₹1k') {
                              _minAmountController.clear();
                              _maxAmountController.text = '1000';
                            } else if (chip == '₹1k - ₹5k') {
                              _minAmountController.text = '1000';
                              _maxAmountController.text = '5000';
                            } else if (chip == '> ₹5k') {
                              _minAmountController.text = '5000';
                              _maxAmountController.clear();
                            } else if (chip == '< ₹10k') {
                              _minAmountController.clear();
                              _maxAmountController.text = '10000';
                            } else if (chip == '> ₹10k') {
                              _minAmountController.text = '10000';
                              _maxAmountController.clear();
                            } else if (chip == 'Top 10') {
                              _minAmountController.clear();
                              _maxAmountController.clear();
                              _sortBy = 'Amount (High-Low)';
                            }
                          }
                        });
                        _applyFilters();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          
          // Total Summary Bar
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF16213E), Colors.cyanAccent.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Outstanding', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${_filteredBalances.length} Shops', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Text('₹${totalBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
          ),

          // List View
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : _filteredBalances.isEmpty
                ? const Center(
                    child: Text('No balances found matching your filters', style: TextStyle(color: Colors.white54, fontSize: 16)),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _filteredBalances.length,
                      itemBuilder: (context, index) {
                        final balance = _filteredBalances[index];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213E),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, 2), blurRadius: 4),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  balance.shopName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '₹${balance.amount.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- Smart Search Helpers ---
  int _compareBySortOption(ShopBalance a, ShopBalance b) {
    if (_sortBy == 'Name (A-Z)') {
      return a.shopName.toLowerCase().compareTo(b.shopName.toLowerCase());
    } else if (_sortBy == 'Name (Z-A)') {
      return b.shopName.toLowerCase().compareTo(a.shopName.toLowerCase());
    } else if (_sortBy == 'Amount (High-Low)') {
      return b.amount.compareTo(a.amount);
    } else if (_sortBy == 'Amount (Low-High)') {
      return a.amount.compareTo(b.amount);
    }
    return 0;
  }

  int _calculateRelevance(String query, String target) {
    if (query.isEmpty) return 0;
    
    if (target == query) return 100;
    if (target.startsWith(query)) return 80;
    
    try {
      if (RegExp('\\b${RegExp.escape(query)}\\b').hasMatch(target)) return 70;
    } catch (e) {}
    
    try {
      if (RegExp('\\b${RegExp.escape(query)}').hasMatch(target)) return 60;
    } catch (e) {}
    
    if (target.contains(query)) return 40;
    
    return 20;
  }

  bool _smartMatch(String query, String target) {
    if (query.isEmpty) return true;
    
    query = query.toLowerCase().trim();
    target = target.toLowerCase();
    
    try {
      if (RegExp('\\b${RegExp.escape(query)}').hasMatch(target)) return true;
    } catch (e) {
      if (target.contains(query)) return true;
    }
    
    final cleanQuery = query.replaceAll(RegExp(r'[^\w\s]'), ' ');
    final cleanTarget = target.replaceAll(RegExp(r'[^\w\s]'), ' ');
    
    final qWords = cleanQuery.split(RegExp(r'\s+'));
    final tWords = cleanTarget.split(RegExp(r'\s+')); 
    
    for (var qw in qWords) {
      if (qw.isEmpty) continue;
      bool wordMatched = false;
      
      for (var tw in tWords) {
        if (tw.isEmpty) continue;
        
        if (tw.startsWith(qw)) {
          wordMatched = true; break;
        }
        
        if (qw.length >= 4 && (qw.length - tw.length).abs() <= 1) {
           if (_levenshteinDistance(qw, tw) <= 2) {
             wordMatched = true; break;
           }
        }
      }
      if (!wordMatched) return false;
    }
    return true;
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    
    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);
    
    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        int min = v1[j] + 1;
        if (v0[j + 1] + 1 < min) min = v0[j + 1] + 1;
        if (v0[j] + cost < min) min = v0[j] + cost;
        v1[j + 1] = min;
      }
      List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }
    return v0[s2.length];
  }
}
