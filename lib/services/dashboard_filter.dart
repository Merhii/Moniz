import '../models/asset.dart';

class DashboardFilter {
  const DashboardFilter({this.type, this.tag, this.fromDate, this.toDate});

  final AssetType? type;
  final AssetTag? tag;
  final DateTime? fromDate;
  final DateTime? toDate;

  bool get isActive =>
      type != null || tag != null || fromDate != null || toDate != null;

  DashboardFilter copyWith({
    AssetType? type,
    AssetTag? tag,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearType = false,
    bool clearTag = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return DashboardFilter(
      type: clearType ? null : type ?? this.type,
      tag: clearTag ? null : tag ?? this.tag,
      fromDate: clearFromDate ? null : fromDate ?? this.fromDate,
      toDate: clearToDate ? null : toDate ?? this.toDate,
    );
  }

  List<Asset> apply(List<Asset> assets) {
    return assets.where(_matches).toList();
  }

  bool _matches(Asset asset) {
    if (type != null && asset.type != type) return false;
    if (tag != null && asset.tag != tag) return false;
    if (fromDate == null && toDate == null) return true;

    final activityDates = [
      asset.boughtDate,
      asset.soldDate,
    ].whereType<DateTime>().map(_dayOnly);
    return activityDates.any((date) {
      final afterStart =
          fromDate == null || !date.isBefore(_dayOnly(fromDate!));
      final beforeEnd = toDate == null || !date.isAfter(_dayOnly(toDate!));
      return afterStart && beforeEnd;
    });
  }

  DateTime _dayOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}
