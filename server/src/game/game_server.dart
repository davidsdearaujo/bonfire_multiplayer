import 'dart:math';

import 'package:shared_events/shared_events.dart';

import '../../main.dart';
import '../core/game.dart';
import '../core/game_component.dart';
import '../core/game_map.dart';
import '../infrastructure/websocket/polo_websocket.dart';
import '../infrastructure/websocket/websocket_provider.dart';
import 'player.dart';

class GameServer extends Game {
  GameServer({required this.server, required this.maps}) {
    _registerTypes();
  }
  final List<GameMap> maps;
  bool mapLoaded = false;
  List<PoloClient> clients = [];

  final WebsocketProvider<PoloClient> server;

  void enterClient(PoloClient client) {
    clients.add(client);
    logger.i('Client(${client.id}) Connected!');
    client.onEvent<JoinEvent>(EventType.JOIN.name, (message) {
      logger.i('JoinEvent: ${message.toMap()}');
      _joinPlayerInTheGame(client, message);
    });
  }

  void leaveClient(PoloClient client) {
    clients.remove(client);
    for (final map in maps) {
      map.components
          .whereType<Player>()
          .where((element) => element.id == client.id)
          .forEach((element) => element.removeFromParent());
    }
    requestUpdate();
    logger.i('Client(${client.id}) Disconnected!');
  }

  @override
  void onUpdateState(GameComponent comp) {
    final stateList = statePlayerList(comp);
    for (final player in comp.components.whereType<Player>()) {
      player.client.send(
        EventType.UPDATE_STATE.name,
        GameStateModel(
          players: stateList,
          npcs: [],
        ),
      );
    }
  }

  List<ComponentStateModel> statePlayerList(GameComponent? comp) {
    if (comp == null) return [];
    return comp.components.whereType<Player>().map((e) => e.state).toList();
  }

  void _joinPlayerInTheGame(PoloClient client, JoinEvent message) {
    if (components
        .whereType<Player>()
        .any((element) => element.id == client.id)) {
      return;
    }

    const tileSize = 16.0;

    // Create initial position
    final position = GameVector(
      x: (8 + Random().nextInt(3)) * tileSize,
      y: 5 * tileSize,
    );
    // Adds Player

    final player = Player(
      state: ComponentStateModel(
        id: client.id,
        name: message.name,
        skin: message.skin,
        position: position,
        life: 100,
      ),
      client: client,
    );

    const initialMap = 0;

    maps[initialMap].add(player);

    // send ACK to client that request join.
    client.send(
      EventType.JOIN_ACK.name,
      JoinAckEvent(
        state: player.state,
        players: statePlayerList(player.parent),
        map: maps[initialMap].path,
      ),
    );

    // send to others players that this player is joining
    requestUpdate();
  }

  @override
  Future<void> start() async {
    await _loadMaps();
    return super.start();
  }

  void _registerTypes() {
    server
      ..registerType<JoinEvent>(
        TypeAdapter(
          toMap: (type) => type.toMap(),
          fromMap: JoinEvent.fromMap,
        ),
      )
      ..registerType<JoinAckEvent>(
        TypeAdapter(
          toMap: (type) => type.toMap(),
          fromMap: JoinAckEvent.fromMap,
        ),
      )
      ..registerType<GameStateModel>(
        TypeAdapter(
          toMap: (type) => type.toMap(),
          fromMap: GameStateModel.fromMap,
        ),
      )
      ..registerType<PlayerEvent>(
        TypeAdapter(
          toMap: (type) => type.toMap(),
          fromMap: PlayerEvent.fromMap,
        ),
      )
      ..registerType<MoveEvent>(
        TypeAdapter(
          toMap: (type) => type.toMap(),
          fromMap: MoveEvent.fromMap,
        ),
      );
  }

  Future<void> _loadMaps() async {
    if (!mapLoaded) {
      logger.d('Loading maps...');
      for (final map in maps) {
        await map.load();
        add(map);
      }
      mapLoaded = true;
    }
  }
}
