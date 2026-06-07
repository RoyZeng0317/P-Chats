import 'dart:io';
import 'dart:convert';

class ClientInfo {
  final WebSocket socket;
  final String userId;
  final String publicKey;

  ClientInfo(this.socket, this.userId, this.publicKey);
}

void main() async {
  final server = await HttpServer.bind('0.0.0.0', 8080);
  print('Chat relay server started on port 8080');
  print('>>> App WebSocket URL: ws://localhost:8080/ws');
  print('>>> On physical device / same LAN: ws://<this-machine-IP>:8080/ws');
  print('No messages are stored - pure relay only');

  final clients = <String, ClientInfo>{};

  await for (final request in server) {
    if (request.uri.path == '/ws') {
      final ws = await WebSocketTransformer.upgrade(request);
      ClientInfo? client;

      ws.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['type'] as String;

            switch (type) {
              case 'register':
                final userId = msg['userId'] as String;
                final publicKey = msg['publicKey'] as String;
                client = ClientInfo(ws, userId, publicKey);
                clients[userId] = client!;
                print('User registered: $userId');
                _broadcastUserList(clients);
                break;

              case 'send': {
                final c = client;
                if (c == null) return;
                final to = msg['to'] as String;
                final target = clients[to];
                if (target != null) {
                  // Preserve client-provided id so burn_ack round-trips correctly
                  final msgId = msg['id'] as String? ??
                      '${c.userId}_${DateTime.now().millisecondsSinceEpoch}';
                  final message = jsonEncode({
                    'type': 'message',
                    'from': c.userId,
                    'payload': msg['payload'],
                    'burnAfterRead': msg['burnAfterRead'] ?? false,
                    'id': msgId,
                  });
                  target.socket.add(message);
                  print('Relayed message: ${c.userId} -> $to');
                }
                break;
              }

              case 'burn_ack': {
                final c = client;
                if (c == null) return;
                final targetId = msg['to'] as String;
                final target = clients[targetId];
                if (target != null) {
                  final ack = jsonEncode({
                    'type': 'burn_ack',
                    'from': c.userId,
                    'messageId': msg['messageId'],
                    'to': targetId,
                  });
                  target.socket.add(ack);
                  print('Burn ack: ${c.userId} -> $targetId');
                }
                break;
              }
            }
          } catch (e) {
            print('Error handling message: $e');
          }
        },
        onDone: () {
          final c = client;
          if (c != null) {
            clients.remove(c.userId);
            print('User disconnected: ${c.userId}');
            _broadcastUserList(clients);
          }
        },
        onError: (e) {
          final c = client;
          if (c != null) {
            clients.remove(c.userId);
            print('User error: ${c.userId}: $e');
            _broadcastUserList(clients);
          }
        },
      );
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }
}

void _broadcastUserList(Map<String, ClientInfo> clients) {
  final userList = clients.entries.map((e) => {
    'userId': e.key,
    'publicKey': e.value.publicKey,
  }).toList();

  final message = jsonEncode({'type': 'users', 'users': userList});

  for (final client in clients.values) {
    client.socket.add(message);
  }
}
