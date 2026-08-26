import 'package:uuid/uuid.dart';

abstract interface class IdGenerator { String newId(); }
final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();
  static const _uuid = Uuid();
  @override String newId() => _uuid.v7();
}
