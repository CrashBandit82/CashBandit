import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'services/app_lock.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('overridden in main'));

final repoProvider = Provider<CashRepository>((ref) => CashRepository(ref.watch(dbProvider)));

final appLockProvider = Provider<AppLock>((ref) => throw UnimplementedError('overridden in main'));

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(repoProvider).watchCategories());

final bookingsProvider = StreamProvider.autoDispose.family<List<BookingRow>, BookingQuery>(
  (ref, q) => ref.watch(repoProvider).watchBookings(q),
);

final recurringProvider = StreamProvider<List<RecurringRow>>((ref) => ref.watch(repoProvider).watchRecurring());
