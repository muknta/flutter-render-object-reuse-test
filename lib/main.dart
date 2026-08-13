import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: ProbePage());
}

/// Leaf render object widget so we can hook create/update directly.
/// This is the only reliable place to answer "same RenderObject or new one".
class ProbeBox extends LeafRenderObjectWidget {
  final String label;
  final String text;
  final Color color;

  const ProbeBox({
    super.key,
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    final ro = _ProbeRenderBox(color: color);
    // ignore: avoid_print
    print('[$label] CREATE   RO id=${identityHashCode(ro)}  text="$text"');
    return ro;
  }

  @override
  void updateRenderObject(BuildContext context, covariant _ProbeRenderBox renderObject) {
    renderObject.color = color;
    // ignore: avoid_print
    print('[$label] REUSE    RO id=${identityHashCode(renderObject)}  text="$text"');
  }

  @override
  void didUnmountRenderObject(covariant _ProbeRenderBox renderObject) {
    // ignore: avoid_print
    print('[$label] DISPOSE  RO id=${identityHashCode(renderObject)}');
  }
}

class _ProbeRenderBox extends RenderBox {
  Color color;
  _ProbeRenderBox({required this.color});

  @override
  void performLayout() {
    size = constraints.constrain(const Size(120, 60));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(offset & size, Paint()..color = color);
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  int _tick = 0;

  void _rebuild() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    print('\n--- rebuild #$_tick ---');
    return Scaffold(
      appBar: AppBar(title: const Text('RenderObject reuse probe')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(onPressed: _rebuild, child: const Text('Rebuild (setState)')),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Watch console: CREATE = new RenderObject, REUSE = same one kept.'),
          ),

          // 1) GOLDEN CASE: const ValueKey, const widget, identical every rebuild.
          //    Same type + same key + const-identical instance -> RenderObject
          //    persists AND updateRenderObject may not even be called (Element
          //    short-circuits on identical widget). Expect CREATE once, then silence.
          const ProbeBox(
            key: ValueKey('golden'),
            label: 'A-golden(constKey+const)',
            text: 'fixed',
            color: Colors.green,
          ),

          // 2) Same const ValueKey, but text/content changes every rebuild
          //    (widget itself is NOT const because it embeds a var). Same
          //    type+key -> canUpdate true -> RenderObject reused, but
          //    updateRenderObject fires every time since widget isn't identical.
          ProbeBox(
            key: const ValueKey('samekey-varying-text'),
            label: 'B-sameKeyVaryingText',
            text: 'tick=$_tick',
            color: Colors.blue,
          ),

          // 3) Two non-const, keyless, "identical-looking" widgets at the same
          //    slot each rebuild. No key -> canUpdate matches purely on
          //    runtimeType + slot position -> RenderObject still reused.
          ProbeBox(
            label: 'C-noKey-nonConst',
            text: 'tick=$_tick',
            color: Colors.orange,
          ),

          // 4) Const identical widget, no key. Const canonicalization means the
          //    exact same widget instance is passed every rebuild -> Element
          //    sees identical(oldWidget, newWidget) and skips update entirely.
          const ProbeBox(
            label: 'D-noKey-const',
            text: 'fixed',
            color: Colors.purple,
          ),

          // 5) CONTRAST CASE: key itself changes every rebuild. Same slot,
          //    same runtimeType, but canUpdate requires matching key too ->
          //    canUpdate=false -> old Element+RenderObject DISPOSED, brand
          //    new one CREATEd each tick. This is the real "different keys"
          //    behavior your other 4 cases don't actually trigger.
          ProbeBox(
            key: ValueKey('k$_tick'),
            label: 'E-changingKey',
            text: 'tick=$_tick',
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}
