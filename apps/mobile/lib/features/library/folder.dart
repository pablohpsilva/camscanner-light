/// A flat (non-nested) folder that groups documents. Domain model, decoupled
/// from the generated drift row of the same name.
class Folder {
  final int id;
  final String name;
  final DateTime createdAt;
  const Folder({required this.id, required this.name, required this.createdAt});

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}
