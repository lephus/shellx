import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/ime_trace.dart';

void main() {
  test('an editing state is described by its shape, never its text', () {
    final d = ImeTrace.describe(
      const MethodCall('TextInputClient.updateEditingState', [
        3,
        {
          'text': 'chào',
          'selectionBase': 4,
          'selectionExtent': 4,
          'composingBase': 0,
          'composingExtent': 4,
        },
      ]),
    );
    expect(
      d,
      'TextInputClient.updateEditingState client=3 len=4 sel=4..4 comp=0..4',
    );
    expect(d, isNot(contains('ch')));
  });

  test('outgoing setEditingState and caret rects', () {
    expect(
      ImeTrace.describe(
        const MethodCall('TextInput.setEditingState', {
          'text': 'secret',
          'selectionBase': 0,
          'selectionExtent': 0,
          'composingBase': -1,
          'composingExtent': -1,
        }),
      ),
      'TextInput.setEditingState len=6 sel=0..0 comp=-1..-1',
    );
    expect(
      ImeTrace.describe(
        const MethodCall('TextInput.setCaretRect', {
          'x': 1.0,
          'y': 2.0,
          'width': 3.0,
          'height': 4.0,
        }),
      ),
      'TextInput.setCaretRect x=1.0 y=2.0',
    );
    expect(
      ImeTrace.describe(const MethodCall('TextInput.clearClient')),
      'TextInput.clearClient',
    );
  });
}
