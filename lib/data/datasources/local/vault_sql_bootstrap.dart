import '../../../storage/local_db/vault_schema.dart';

class VaultSqlBootstrap {
  const VaultSqlBootstrap();

  List<String> createStatements() {
    return VaultSchema.createStatements;
  }
}
