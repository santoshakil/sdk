// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// All imports must be in all FFI patch files to not depend on the order
// the patches are applied.
import 'dart:_internal';
import 'dart:isolate';
import 'dart:typed_data';

@patch
@pragma("vm:entry-point")
abstract interface class Finalizable {}

@patch
@pragma("vm:entry-point")
abstract final class NativeFinalizer {
  @patch
  factory NativeFinalizer(Pointer<NativeFinalizerFunction> callback) =
      _NativeFinalizer;
}

@pragma("vm:entry-point")
final class _NativeFinalizer extends FinalizerBase implements NativeFinalizer {
  @pragma("vm:recognized", "other")
  @pragma("vm:prefer-inline")
  external Pointer<NativeFinalizerFunction> get _callback;
  @pragma("vm:recognized", "other")
  @pragma("vm:prefer-inline")
  external set _callback(Pointer<NativeFinalizerFunction> value);

  _NativeFinalizer(Pointer<NativeFinalizerFunction> callback) {
    allEntries = <FinalizerEntry>{};
    _callback = callback;
    setIsolate();
    isolateRegisterFinalizer();
  }

  void attach(
    Finalizable value,
    Pointer<Void> token, {
    Object? detach,
    int? externalSize,
  }) {
    externalSize ??= 0;
    RangeError.checkNotNegative(externalSize, 'externalSize');
    if (value == null) {
      throw ArgumentError.value(value, 'value', "Cannot be a null");
    }
    if (detach != null) {
      checkValidWeakTarget(detach, 'detach');
    }

    final entry = FinalizerEntry.allocate(value, token, detach, this);
    allEntries.add(entry);

    if (externalSize > 0) {
      entry.setExternalSize(externalSize);
    }

    if (detach != null) {
      (detachments[detach] ??= <FinalizerEntry>{}).add(entry);
    }

    // The `value` stays reachable till here because the static type is
    // `Finalizable`.
  }

  @override
  void detach(Object detach) {
    final entries = detachments[detach];
    if (entries != null) {
      for (final entry in entries) {
        entry.token = entry;
        final externalSize = entry.externalSize;
        if (externalSize > 0) {
          entry.setExternalSize(0);
          assert(entry.externalSize == 0);
        }
        allEntries.remove(entry);
      }
      detachments[detach] = null;
    }
  }

  void _removeEntries() {
    FinalizerEntry? entry = exchangeEntriesCollectedWithNull();
    while (entry != null) {
      assert(entry.externalSize == 0);
      allEntries.remove(entry);
      final detach = entry.detach;
      if (detach != null) {
        detachments[detach]?.remove(entry);
      }
      entry = entry.next;
    }
  }

  @pragma("vm:entry-point", "call")
  static _handleNativeFinalizerMessage(_NativeFinalizer finalizer) {
    finalizer._removeEntries();
  }
}
