import 'dart:math';
import 'package:flutter/material.dart';
import 'theme.dart';

/// A complete local game: human plays X, TideBot plays O with a defensive AI.
class TicTacToePage extends StatefulWidget {
  const TicTacToePage({super.key});

  @override
  State<TicTacToePage> createState() => _TicTacToePageState();
}

class _TicTacToePageState extends State<TicTacToePage> {
  final List<String> _board = List.filled(9, '');
  final _random = Random();
  String _status = '轮到你了（X）';
  bool _finished = false;
  bool _thinking = false;

  List<List<int>> get _lines => const [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
        [0, 3, 6],
        [1, 4, 7],
        [2, 5, 8],
        [0, 4, 8],
        [2, 4, 6],
      ];

  String? _winner() {
    for (final line in _lines) {
      final value = _board[line[0]];
      if (value.isNotEmpty &&
          value == _board[line[1]] &&
          value == _board[line[2]]) {
        return value;
      }
    }
    return _board.every((cell) => cell.isNotEmpty) ? 'draw' : null;
  }

  Future<void> _move(int index) async {
    if (_finished || _thinking || _board[index].isNotEmpty) return;
    setState(() => _board[index] = 'X');
    if (_complete()) return;
    setState(() {
      _thinking = true;
      _status = 'TideBot 正在思考…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    final move = _bestMove();
    setState(() {
      _board[move] = 'O';
      _thinking = false;
    });
    _complete();
  }

  bool _complete() {
    final result = _winner();
    if (result == null) {
      setState(() => _status = '轮到你了（X）');
      return false;
    }
    setState(() {
      _finished = true;
      _status = result == 'draw'
          ? '平局，再来一局吧'
          : result == 'X'
              ? '你赢了！'
              : 'TideBot 赢了！';
    });
    return true;
  }

  int _bestMove() {
    for (final mark in ['O', 'X']) {
      for (var i = 0; i < 9; i++) {
        if (_board[i].isNotEmpty) continue;
        _board[i] = mark;
        final wins = _winner() == mark;
        _board[i] = '';
        if (wins) return i;
      }
    }
    if (_board[4].isEmpty) return 4;
    final corners = [0, 2, 6, 8].where((i) => _board[i].isEmpty).toList();
    final open =
        List.generate(9, (i) => i).where((i) => _board[i].isEmpty).toList();
    return (corners.isNotEmpty
        ? corners
        : open)[_random.nextInt((corners.isNotEmpty ? corners : open).length)];
  }

  void _reset() => setState(() {
        _board.fillRange(0, 9, '');
        _finished = false;
        _thinking = false;
        _status = '轮到你了（X）';
      });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          title: const Text('井字棋', style: TextStyle(fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
                onPressed: _reset,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '重新开始')
          ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('你是 X · TideBot 是 O',
                  style:
                      TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
              const SizedBox(height: 12),
              Text(_status,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 28),
              AspectRatio(
                  aspectRatio: 1,
                  child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 9,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8),
                      itemBuilder: (_, i) => InkWell(
                          onTap: () => _move(i),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                              decoration: BoxDecoration(
                                  color: theme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(18)),
                              child: Center(
                                  child: Text(_board[i],
                                      style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.w700,
                                          color: _board[i] == 'X'
                                              ? theme.primary
                                              : theme.textStrong))))))),
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('再来一局',
                      style: TextStyle(fontFamily: 'TideFont'))),
            ])),
      ))),
    );
  }
}
