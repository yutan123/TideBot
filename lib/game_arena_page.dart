import 'dart:math';

import 'package:flutter/material.dart';

import 'ai.dart';
import 'theme.dart';

/// Shared game room. A room is always bound to the bot chosen on the square.
class GameArenaPage extends StatefulWidget {
  final String game;
  final Map<String, dynamic> bot;

  const GameArenaPage({super.key, required this.game, required this.bot});

  @override
  State<GameArenaPage> createState() => _GameArenaPageState();
}

class _GameArenaPageState extends State<GameArenaPage> {
  final Random _random = Random();
  final TextEditingController _chatController = TextEditingController();
  final List<String> _messages = <String>[];
  final List<String> _gomoku = List<String>.filled(81, '');
  final List<String> _ticTacToe = List<String>.filled(9, '');

  bool _waitingForReply = false;
  String _roundStatus = '轮到你落子';
  int _questionCount = 0;
  int _dice = 0;
  int _botDice = 0;
  String _story = '你和 TA 在雨后的街角相遇。要先做什么？';
  String _truthCard = '';

  String get _botId => widget.bot['id']?.toString() ?? '';
  String get _botName => widget.bot['name']?.toString() ?? 'TideBot';

  String get _activeGame {
    const games = <String, String>{
      '五子棋': 'gomoku',
      '井字棋': 'tic_tac_toe',
      '20问猜物': '20q',
      '好运骰子': 'dice',
      '文字冒险': 'adventure',
      '真心话大冒险': 'truth_dare',
    };
    return games[widget.game] ?? 'game';
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _talk([String? preset]) async {
    final text = (preset ?? _chatController.text).trim();
    if (text.isEmpty || _waitingForReply || _botId.isEmpty) return;

    setState(() {
      _messages.add('你：$text');
      _chatController.clear();
      _waitingForReply = true;
    });

    final result = await AIManager().sendMessage(
      botId: _botId,
      text: '我们正在玩${widget.game}。$text',
      activeGame: _activeGame,
    );
    if (!mounted) return;

    setState(() {
      final reply = result['success'] == true
          ? result['reply']?.toString() ?? '暂时没能回应'
          : result['error']?.toString() ?? '暂时没能回应';
      _messages.add('$_botName：$reply');
      _waitingForReply = false;
    });
  }

  bool _hasLine(List<String> board, String mark, int needed) {
    const directions = <List<int>>[
      <int>[1, 0],
      <int>[0, 1],
      <int>[1, 1],
      <int>[1, -1],
    ];
    final size = sqrt(board.length).toInt();
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        if (board[row * size + column] != mark) continue;
        for (final direction in directions) {
          var count = 1;
          var r = row + direction[0];
          var c = column + direction[1];
          while (r >= 0 &&
              r < size &&
              c >= 0 &&
              c < size &&
              board[r * size + c] == mark) {
            count++;
            r += direction[0];
            c += direction[1];
          }
          if (count >= needed) return true;
        }
      }
    }
    return false;
  }

  void _placePiece(List<String> board, int index, String mine, String theirs) {
    final needed = board.length == 9 ? 3 : 5;
    if (board[index].isNotEmpty || _roundStatus != '轮到你落子') return;

    setState(() {
      board[index] = mine;
      if (_hasLine(board, mine, needed)) {
        _roundStatus = '你赢了！点击重开再来一局';
        return;
      }
      if (!board.contains('')) {
        _roundStatus = '平局，点击重开再来一局';
        return;
      }

      final open = <int>[];
      for (var i = 0; i < board.length; i++) {
        if (board[i].isEmpty) open.add(i);
      }
      board[open[_random.nextInt(open.length)]] = theirs;
      if (_hasLine(board, theirs, needed)) {
        _roundStatus = '$_botName 赢了，点击重开再来一局';
      } else if (!board.contains('')) {
        _roundStatus = '平局，点击重开再来一局';
      }
    });
  }

  Widget _board(TideTheme theme, List<String> cells, int crossAxisCount,
      String mine, String theirs) {
    return Column(
      children: [
        Text(_roundStatus,
            style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: crossAxisCount == 3 ? 6 : 1,
            crossAxisSpacing: crossAxisCount == 3 ? 6 : 1,
          ),
          itemBuilder: (_, index) => InkWell(
            onTap: () => _placePiece(cells, index, mine, theirs),
            child: Container(
              decoration: BoxDecoration(
                color: crossAxisCount == 3
                    ? theme.surfaceVariant
                    : const Color(0xFFD9B56E),
                borderRadius:
                    crossAxisCount == 3 ? BorderRadius.circular(12) : null,
              ),
              child: Center(
                child: Text(
                  cells[index],
                  style: TextStyle(
                    fontSize: crossAxisCount == 3 ? 38 : 18,
                    color: crossAxisCount == 3
                        ? (cells[index] == mine
                            ? theme.primary
                            : theme.textStrong)
                        : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _questionGame(TideTheme theme) {
    const prompts = <String>[
      '它是有生命的吗？',
      '它能被放进口袋吗？',
      '它通常在室内使用吗？',
      '它和食物有关吗？',
      '它会发出声音吗？',
    ];
    final complete = _questionCount >= 20;
    return Column(
      children: [
        Text(complete ? '20 问已完成，轮到 TA 猜答案' : '第 ${_questionCount + 1}/20 问',
            style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
        const SizedBox(height: 12),
        Text(
          complete
              ? '把你心里的答案告诉 $_botName，看看它猜得对不对。'
              : prompts[_questionCount % prompts.length],
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20, color: theme.textStrong, fontFamily: 'TideFont'),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          children: <String>['是', '否', '不确定'].map((answer) {
            return FilledButton(
              onPressed: complete
                  ? null
                  : () {
                      setState(() => _questionCount++);
                      _talk('回答：$answer，请继续提问或在第 20 问后猜答案。');
                    },
              child:
                  Text(answer, style: const TextStyle(fontFamily: 'TideFont')),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _diceGame(TideTheme theme) => Column(
        children: [
          Text(
            _dice == 0 ? '点击骰子开始本局' : '你掷出 $_dice 点，$_botName 掷出 $_botDice 点',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, color: theme.textStrong, fontFamily: 'TideFont'),
          ),
          const SizedBox(height: 14),
          IconButton(
            iconSize: 100,
            color: theme.primary,
            icon: const Icon(Icons.casino_rounded),
            onPressed: () {
              setState(() {
                _dice = _random.nextInt(6) + 1;
                _botDice = _random.nextInt(6) + 1;
              });
              final result = _dice == _botDice
                  ? '我们平局！'
                  : _dice > _botDice
                      ? '这局我赢了！'
                      : '这局你赢了！';
              _talk('我掷出 $_dice 点，你掷出 $_botDice 点。$result');
            },
          ),
        ],
      );

  Widget _adventureGame(TideTheme theme) => Column(
        children: [
          Text(_story,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  color: theme.textStrong,
                  fontFamily: 'TideFont')),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>['走进咖啡店', '沿河散步', '给 TA 发消息'].map((choice) {
              return OutlinedButton(
                onPressed: () {
                  setState(() => _story = '你选择了“$choice”。$_botName 正在等待你的下一步。');
                  _talk('我选择了：$choice，请继续故事，并给我两个可选行动。');
                },
                child: Text(choice,
                    style: const TextStyle(fontFamily: 'TideFont')),
              );
            }).toList(),
          ),
        ],
      );

  Widget _truthGame(TideTheme theme) => Column(
        children: [
          Text(_truthCard.isEmpty ? '点击抽取题目' : _truthCard,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 19,
                  color: theme.textStrong,
                  fontFamily: 'TideFont')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              const cards = <String>[
                '真心话：最近一次开心是什么时候？',
                '大冒险：用三句话夸夸 TA。',
                '真心话：最想拥有哪种超能力？',
                '大冒险：给 TA 取一个昵称。',
              ];
              setState(() => _truthCard = cards[_random.nextInt(cards.length)]);
            },
            child: const Text('抽取题目', style: TextStyle(fontFamily: 'TideFont')),
          ),
        ],
      );

  Widget _gameBody(TideTheme theme) {
    switch (widget.game) {
      case '井字棋':
        return _board(theme, _ticTacToe, 3, 'X', 'O');
      case '五子棋':
        return _board(theme, _gomoku, 9, '●', '○');
      case '20问猜物':
        return _questionGame(theme);
      case '好运骰子':
        return _diceGame(theme);
      case '文字冒险':
        return _adventureGame(theme);
      default:
        return _truthGame(theme);
    }
  }

  void _reset() {
    setState(() {
      _gomoku.fillRange(0, _gomoku.length, '');
      _ticTacToe.fillRange(0, _ticTacToe.length, '');
      _roundStatus = '轮到你落子';
      _questionCount = 0;
      _dice = 0;
      _botDice = 0;
      _truthCard = '';
      _story = '你和 TA 在雨后的街角相遇。要先做什么？';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${widget.game} · $_botName',
            style: const TextStyle(fontFamily: 'TideFont')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _reset)
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(18), child: _gameBody(theme)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _messages.length,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_messages[index],
                      style: TextStyle(
                          color: theme.textStrong, fontFamily: 'TideFont')),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      onSubmitted: (_) => _talk(),
                      decoration: InputDecoration(
                        hintText: '和 $_botName 聊聊游戏…',
                        filled: true,
                        fillColor: theme.surfaceVariant,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _waitingForReply ? null : _talk,
                    icon: Icon(Icons.send_rounded, color: theme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
