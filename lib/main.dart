import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void main() => runApp(const ProbeApp());

/// Shared GlobalKey instance used by BOTH pages for probe F. A GlobalKey is
/// the one mechanism that can carry an Element (and its RenderObject) across
/// a parent change / route boundary, via Element.moveTo reparenting, instead
/// of disposing the old one and creating a new one.
final GlobalKey globalProbeKey = GlobalKey();

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
  void updateRenderObject(
    BuildContext context,
    covariant _ProbeRenderBox renderObject,
  ) {
    renderObject.color = color;
    // ignore: avoid_print
    print(
      '[$label] REUSE    RO id=${identityHashCode(renderObject)}  text="$text"',
    );
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
  bool _swapped = false;
  List<int> _order = [0, 1, 2];

  void _rebuild() => setState(() => _tick++);
  void _swapParent() => setState(() => _swapped = !_swapped);
  void _reorderList() => setState(() => _order = _order.reversed.toList());

  static const _itemColors = [Colors.green, Colors.blue, Colors.orange];

  @override
  Widget build(BuildContext context) {
    print('\n--- rebuild #$_tick ---');
    return Scaffold(
      appBar: AppBar(title: const Text('RenderObject reuse probe')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _rebuild,
              child: const Text('Rebuild (setState)'),
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Watch console: CREATE = new RenderObject, REUSE = same one kept.',
              ),
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

            // 6) GlobalKey probe, reparented between two different PARENTS in
            //    the SAME page/build, via a toggle. canUpdate normally requires
            //    matching slot under the SAME parent Element; moving a widget
            //    to a genuinely different parent is otherwise an insert+delete
            //    (CREATE+DISPOSE). A GlobalKey bypasses that: as long as the
            //    old Element is deactivated in the same frame the new one with
            //    a matching GlobalKey appears, Element.moveTo reparents it in
            //    place -> expect REUSE with the SAME RO id across the swap,
            //    not CREATE+DISPOSE.
            //    (Note: this does NOT hold across a Navigator route push -
            //    the push transition keeps old+new route mounted in the same
            //    overlapping frame, so two GlobalKeys would coexist at once
            //    and Flutter throws "Duplicate GlobalKey detected" instead.
            //    GlobalKey reparenting only works within a single build pass.)
            Container(
              color: Colors.black12,
              padding: const EdgeInsets.all(4),
              child: _swapped
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: ProbeBox(
                        key: globalProbeKey,
                        label: 'F-globalKey(parentB)',
                        text: 'tick=$_tick',
                        color: Colors.teal,
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: ProbeBox(
                        key: globalProbeKey,
                        label: 'F-globalKey(parentA)',
                        text: 'tick=$_tick',
                        color: Colors.teal,
                      ),
                    ),
            ),

            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _swapParent,
              child: const Text('Swap GlobalKey probe to other parent'),
            ),

            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SecondPage())),
              child: const Text('Navigate to new page (push route)'),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Multiple ValueKeys under the SAME parent, reordered on setState:\n'
                'G (keyed) - watch each RO id follow its logical item across the swap.\n'
                'H (no key) - watch RO ids stay pinned to their index; color/text swap\n'
                'instead, meaning the same RenderObject silently becomes a different\n'
                'logical item.',
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                // Key MUST be on the direct child of Row (the widget Row's own
                // reconciliation compares), not on some wrapper further down.
                // Padding carries the key here; ProbeBox itself is unkeyed.
                for (final id in _order)
                  Padding(
                    key: ValueKey('g-item-$id'),
                    padding: const EdgeInsets.only(right: 8),
                    child: ProbeBox(
                      label: 'G-item$id',
                      text: 'logical=$id',
                      color: _itemColors[id],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final id in _order)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ProbeBox(
                      label: 'H-item$id',
                      text: 'logical=$id',
                      color: _itemColors[id],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _reorderList,
              child: const Text('Reverse list order (G/H)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Second page: same probe declarations (same runtimeType, same ValueKey
/// strings as page 1) but mounted under a completely different parent
/// Element tree (a fresh route). Tests whether ValueKey/no-key reuse
/// transcends a parent/route boundary - it doesn't, since key matching only
/// happens among siblings under a SAME still-mounted parent Element, and a
/// fresh route never had that parent Element before.
class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) {
    print('\n--- SecondPage build ---');
    return Scaffold(
      appBar: AppBar(title: const Text('Second page (new route)')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Same ValueKey strings as page 1, but under a new parent Element tree.\n'
              'Expect CREATE for A2/B2 despite matching keys - key matching only\n'
              'happens among siblings under the SAME still-mounted parent Element.',
            ),
          ),

          // A2: same key string as page1's golden case ('golden'). Different
          // parent Element -> no prior sibling to compare against -> CREATE,
          // not REUSE, even though the key literally matches.
          const ProbeBox(
            key: ValueKey('golden'),
            label: 'A2-sameValueKeyString-newRoute',
            text: 'fixed',
            color: Colors.green,
          ),

          // B2: no key at all, same as C-noKey-nonConst on page 1. Still a
          // fresh parent -> CREATE, not REUSE.
          const ProbeBox(
            label: 'B2-noKey-newRoute',
            text: 'fixed',
            color: Colors.orange,
          ),

          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Pop back to page 1'),
          ),
        ],
      ),
    );
  }
}
