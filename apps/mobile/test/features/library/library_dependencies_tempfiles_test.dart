import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/io/temp_file_writer.dart';
import 'package:mobile/features/library/library_dependencies.dart';

void main() {
  test('default LibraryDependencies expose a TempFileWriter', () {
    const deps = LibraryDependencies();
    expect(deps.tempFiles(), isA<TempFileWriter>());
  });

  test('an injected tempFiles override is honored', () {
    const fake = TempFileWriter();
    final deps = LibraryDependencies(tempFiles: () => fake);
    expect(deps.tempFiles(), same(fake));
  });
}
