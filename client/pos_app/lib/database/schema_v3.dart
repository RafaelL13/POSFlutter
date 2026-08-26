const List<String> schemaV3Statements = [
  r'''ALTER TABLE devices ADD COLUMN mode TEXT NOT NULL DEFAULT 'PointOfSale' CHECK(mode IN ('PointOfSale','AdminReadOnly'))''',
  r"""UPDATE devices SET mode='PointOfSale' WHERE mode IS NULL OR mode=''""",
];
