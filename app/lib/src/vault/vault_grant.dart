/// A persisted handle to a user-picked folder vault: an opaque provider
/// token ([id] — a base64 security-scoped bookmark on iOS, a
/// `content://` tree URI string on Android) plus the [displayName] shown as
/// the vault label in the Library header (design/README.md §01).
///
/// The bundled sample vault doesn't use a real grant at all (see
/// `SampleVaultProvider.grant`) — this type exists only for the
/// user-picked-folder path.
class VaultGrant {
  const VaultGrant({required this.id, required this.displayName});

  final String id;
  final String displayName;

  Map<String, dynamic> toJson() => {'id': id, 'displayName': displayName};

  /// Parses a persisted grant, returning null for anything that isn't a
  /// well-formed `{id, displayName}` object with non-empty strings.
  /// VaultState treats a null result as "no grant" — never a crash — so a
  /// corrupt/hand-edited persisted blob just loses the vault, not the app.
  static VaultGrant? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final displayName = raw['displayName'];
    if (id is! String || id.isEmpty) return null;
    if (displayName is! String || displayName.isEmpty) return null;
    return VaultGrant(id: id, displayName: displayName);
  }

  @override
  String toString() => 'VaultGrant($displayName)';
}
