import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/asset.dart';

class AssetNotifier extends StateNotifier<List<Asset>> {
  AssetNotifier({Box<Asset>? assetBox})
    : assetBox = assetBox ?? Hive.box<Asset>('assets'),
      super((assetBox ?? Hive.box<Asset>('assets')).values.toList());

  final Box<Asset> assetBox;

  void loadAssets() {
    state = assetBox.values.toList();
  }

  Future<void> addAsset(Asset asset) async {
    await assetBox.put(asset.id, asset);
    loadAssets();
  }

  Future<void> removeAsset(String id) async {
    await assetBox.delete(id);
    loadAssets();
  }

  Future<void> updateAsset(Asset updatedAsset) async {
    await assetBox.put(updatedAsset.id, updatedAsset);
    loadAssets();
  }

  List<Asset> get activeAssets {
    return state.where((asset) => !asset.isSold).toList();
  }

  double get totalWealth {
    return activeAssets.fold(0, (sum, asset) => sum + asset.amount);
  }

  double get zakat {
    return totalWealth * 0.025;
  }
}

final assetProvider = StateNotifierProvider<AssetNotifier, List<Asset>>(
  (ref) => AssetNotifier(),
);
