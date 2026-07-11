class VaultSession {
  String? _vaultId;
  List<int>? _vmk;

  bool get isUnlocked => _vaultId != null && _vmk != null && _vmk!.isNotEmpty;
  String? get vaultId => _vaultId;

  List<int> requireVmk() {
    final vmk = _vmk;
    if (_vaultId == null || vmk == null || vmk.isEmpty) {
      throw StateError('Vault session is locked.');
    }
    return List<int>.from(vmk);
  }

  void unlock({required String vaultId, required List<int> vmkBytes}) {
    lock();
    _vaultId = vaultId;
    _vmk = List<int>.from(vmkBytes);
  }

  void lock() {
    final vmk = _vmk;
    if (vmk != null && vmk.isNotEmpty) {
      try {
        vmk.fillRange(0, vmk.length, 0);
      } catch (_) {}
    }
    _vmk = null;
    _vaultId = null;
  }
}
