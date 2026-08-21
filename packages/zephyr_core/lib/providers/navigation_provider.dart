import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

enum ScreenType {
  home,
  search,
  library,
  settings,
  album,
  artist,
  playlist,
  favorites,
  history,
  admin,
  import,
  lyrics,
  queue,
  curator,
  statistics,
}

class ScreenState {
  final ScreenType type;
  final String? id; // browseId, channelId, or jobId
  final int? intId; // playlistId

  const ScreenState({
    required this.type,
    this.id,
    this.intId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenState &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id &&
          intId == other.intId;

  @override
  int get hashCode => type.hashCode ^ id.hashCode ^ intId.hashCode;
}

class NavigationState {
  final ScreenState currentScreen;
  final List<ScreenState> backStack;
  final List<ScreenState> forwardStack;

  NavigationState({
    required this.currentScreen,
    this.backStack = const [],
    this.forwardStack = const [],
  });

  NavigationState copyWith({
    ScreenState? currentScreen,
    List<ScreenState>? backStack,
    List<ScreenState>? forwardStack,
  }) {
    return NavigationState(
      currentScreen: currentScreen ?? this.currentScreen,
      backStack: backStack ?? this.backStack,
      forwardStack: forwardStack ?? this.forwardStack,
    );
  }
}

class NavigationNotifier extends Notifier<NavigationState> {
  @override
  NavigationState build() {
    ref.listen(authProvider, (previous, next) {
      if (next.token == null || next.username != previous?.username) {
        state = NavigationState(currentScreen: const ScreenState(type: ScreenType.home));
      }
    });

    return NavigationState(currentScreen: const ScreenState(type: ScreenType.home));
  }

  void navigateTo(ScreenState screen) {
    if (state.currentScreen == screen) return;

    final updatedBackStack = List<ScreenState>.from(state.backStack)
      ..add(state.currentScreen);

    state = NavigationState(
      currentScreen: screen,
      backStack: updatedBackStack,
      forwardStack: const [], // clear forward stack on new navigation
    );
  }

  void navigateBack() {
    if (state.backStack.isEmpty) return;

    final updatedBackStack = List<ScreenState>.from(state.backStack);
    final previousScreen = updatedBackStack.removeLast();

    final updatedForwardStack = List<ScreenState>.from(state.forwardStack)
      ..add(state.currentScreen);

    state = NavigationState(
      currentScreen: previousScreen,
      backStack: updatedBackStack,
      forwardStack: updatedForwardStack,
    );
  }

  void navigateForward() {
    if (state.forwardStack.isEmpty) return;

    final updatedForwardStack = List<ScreenState>.from(state.forwardStack);
    final nextScreen = updatedForwardStack.removeLast();

    final updatedBackStack = List<ScreenState>.from(state.backStack)
      ..add(state.currentScreen);

    state = NavigationState(
      currentScreen: nextScreen,
      backStack: updatedBackStack,
      forwardStack: updatedForwardStack,
    );
  }

  bool get canGoBack => state.backStack.isNotEmpty;
  bool get canGoForward => state.forwardStack.isNotEmpty;
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationState>(NavigationNotifier.new);
