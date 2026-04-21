import 'dart:ffi';
import 'dart:io';

typedef _ApiVersionNative = Uint32 Function();
typedef _ApiVersionDart = int Function();

final class RawCullBindings {
  RawCullBindings._(this._lib)
      : _apiVersion = _lib
            .lookup<NativeFunction<_ApiVersionNative>>('rawcull_ffi_api_version')
            .asFunction();

  final DynamicLibrary _lib;
  final _ApiVersionDart _apiVersion;

  static RawCullBindings open() => RawCullBindings._(_openLibrary());

  int apiVersion() => _apiVersion();

  static DynamicLibrary _openLibrary() {
    final overridePath = Platform.environment['RAWCULL_FFI_LIB'];
    if (overridePath != null && overridePath.isNotEmpty) {
      return DynamicLibrary.open(overridePath);
    }

    if (Platform.isWindows) {
      // Standard location during local Windows development:
      // apps/flutter_desktop/windows/runner/Debug/rawcull_ffi.dll
      return DynamicLibrary.open('rawcull_ffi.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('librawcull_ffi.dylib');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('librawcull_ffi.so');
    }

    throw UnsupportedError('Unsupported platform for RawCull FFI');
  }
}
