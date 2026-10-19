# Claude Tracker

Natywna aplikacja macOS w pasku menu (plus widget na biurko), która pokazuje stan wszystkich
otwartych sesji [Claude Code](https://docs.claude.com/en/docs/claude-code): co czeka na Ciebie,
co pracuje, co już skończyło i jaka była ostatnia odpowiedź. Do tego limity 5 h / tygodniowe
i ile bieżący miesiąc kosztowałby według cennika API.

> **English summary:** a native macOS menu bar app and desktop widget that tracks local Claude Code
> sessions (waiting / working / done), shows rate limits and API-equivalent cost, sends notifications,
> and jumps to the session's tab in Warp. Everything runs locally; nothing is sent anywhere.
> The UI is in Polish.

## Co potrafi

- **Pasek menu**: liczniki „czeka / pracuje / gotowe”; panel z listą sesji, animowaną maskotką,
  tytułem i ostatnią odpowiedzią, kosztem i zajętością kontekstu.
- **Zakładki**: aktywne sesje, sesje zakończone dziś (klik kopiuje komendę `--resume`), koszty
  miesiąca (wykres dzienny, projekty, prognoza).
- **Powiadomienia**: „✅ skończył” i „⏳ czeka na Ciebie”, alerty przy 80 % / 90 % limitu.
  Klik przenosi do sesji.
- **Skok do terminala**: klik w sesję otwiera okno Warpa (także pływające okno „hotkey”)
  na właściwej karcie.
- **Widget** na biurko w trzech rozmiarach.
- **Wiele kont**: obserwuje każdy katalog `~/.claude` i `~/.claude-*` (np. `~/.claude-work`)
  oraz `CLAUDE_CONFIG_DIR`.

## Wymagania

- macOS 14 lub nowszy (sprawdzane na macOS 26).
- Pełny Xcode z Swift 6 (same Command Line Tools nie mają SDK potrzebnego dla WidgetKit).
- Claude Code 2.1+ (aplikacja czyta jego pliki sesji).
- Opcjonalnie [Warp](https://www.warp.dev): bez niego klik w sesję otwiera Terminal.app.

## Instalacja

```bash
git clone <adres-repo> claude-tracker && cd claude-tracker
scripts/bundle.sh --install            # buduje dist/Claude Tracker.app i kopiuje do ~/Applications
open ~/Applications/Claude\ Tracker.app
```

Aplikacja nie ma okna ani ikony w Docku. Szukaj kraba w pasku menu.

### Podpis aplikacji

`bundle.sh` podpisuje aplikację pierwszym certyfikatem „Apple Development” z Twojego pęku kluczy.
Taki certyfikat daje każde konto Apple ID, także darmowe: Xcode → Settings → Accounts → dodaj konto
→ Manage Certificates → „+” → Apple Development.

- Bez certyfikatu (`SIGN_IDENTITY=-`, podpis ad-hoc) aplikacja działa, ale **bez widgetu**
  (WidgetKit wymaga Team ID), a zgodę na Dostępność trzeba dawać po każdym przebudowaniu.
- Team ID i grupa aplikacji (`<TeamID>.dev.claude-tracker`) są wyliczane z certyfikatu przy budowaniu.
  Nic z tego nie jest zapisane w repozytorium.

### Jednorazowe uprawnienia

| Uprawnienie | Po co | Gdzie |
|---|---|---|
| Powiadomienia | „✅ skończył”, „⏳ czeka”, alerty limitów | pyta przy pierwszym starcie; potem Ustawienia → Powiadomienia → Claude Tracker |
| Dostępność (Accessibility) | przełączanie kart Warpa | pyta przy pierwszym kliknięciu sesji; Ustawienia → Prywatność i ochrona → Dostępność |
| Rzeczy otwierane podczas logowania | autostart (ikona ⏻ w stopce panelu) | Ustawienia → Ogólne |

Gdy macOS blokuje powiadomienia, w stopce panelu pojawia się pomarańczowy przycisk prowadzący
do ustawień. Prawy klik na dzwonku wysyła próbne powiadomienie.

### Limity 5 h / tygodniowe (opcjonalnie)

Claude Code przekazuje limity tylko skryptowi statusline. Mały „tap” zapisuje ten JSON lokalnie,
a aplikacja go czyta. Instalator dopisuje jedną linię do Twojego skryptu statusline:

```bash
scripts/install-statusline-tap.sh              # podgląd zmian, niczego nie zmienia
scripts/install-statusline-tap.sh --apply      # dopisuje linię po `input=$(cat)`, kopia *.bak-claude-tracker
scripts/install-statusline-tap.sh --uninstall  # usuwa linię, kopia *.bak-claude-tracker-uninstall
```

Wymaga skonfigurowanego `statusLine` w `settings.json` (skrypt czytający JSON ze stdin).
Bez tapa panel pokazuje podpowiedź zamiast limitów, reszta działa normalnie.

## Konfiguracja

Aplikacja nie potrzebuje kluczy API, tokenów ani pliku `.env`. Wszystko, co da się ustawić:

| Zmienna | Gdzie | Znaczenie |
|---|---|---|
| `SIGN_IDENTITY` | `scripts/bundle.sh` | nazwa certyfikatu do podpisu; `-` = ad-hoc (bez widgetu) |
| `CLAUDE_CONFIG_DIR` | środowisko aplikacji | dodatkowy katalog konfiguracji Claude Code do obserwowania |
| `CLAUDE_TRACKER_SNAPSHOT`, `CLAUDE_TRACKER_SNAPSHOT_TAB`, `CLAUDE_TRACKER_MASCOT_SNAPSHOT`, `CLAUDE_TRACKER_ICON` | tylko do rozwoju | renderują panel / maskotkę / ikonę do PNG i kończą działanie |

Konta (`private`, `work`, …) to po prostu nazwy katalogów `~/.claude-<konto>`. Komenda „wznów sesję”
zakłada launcher `claude-<konto>` (alias lub skrypt ustawiający `CLAUDE_CONFIG_DIR`), dla `~/.claude`
zwykłe `claude`.

## Warp

Warp nie ma API do wyboru karty, więc tracker składa to z tego, co jest dostępne:

1. Pokazuje okno: jeśli masz włączony tryb „hotkey window” (Quake), wysyła Twój skrót z ustawień
   Warpa. Kody klawiszy zakładają układ ANSI (US / polski programisty).
2. Przełącza karty przez menu „Tab → Switch to Next Tab” (Accessibility) i porównuje tytuł okna:
   najpierw z tytułem sesji, a gdy Claude Code nie zmienił tytułu karty, obchodzi wszystkie karty
   i wybiera tę z nazwą folderu projektu, pomijając karty innych sesji.

Z innymi terminalami klik w sesję tylko aktywuje Warp lub uruchamia Terminal.app.

## Prywatność i bezpieczeństwo

- **Nic nie wychodzi z komputera.** Aplikacja nie łączy się z siecią.
- **Czyta**: `~/.claude*/sessions/*.json` i transkrypty `~/.claude*/projects/**/*.jsonl`
  (koszt, tytuł, ostatnia odpowiedź), ustawienia Warpa (`defaults read dev.warp.Warp-Stable`).
- **Zapisuje** w `~/Library/Application Support/ClaudeTracker/`:
  - `usage-ledger.json`: identyfikatory wiadomości, dzień, model, koszt, ścieżka projektu;
  - `unread.json`;
  - `limit-alerts.json`;
  - `statusline/`: dane z tapa.

  Treść rozmów nie jest zapisywana na dysku.
- **Widget** dostaje w kontenerze App Group tytuły sesji, nazwy projektów, statusy, limity i koszty.
- **Powiadomienia** zawierają fragment ostatniej odpowiedzi, więc trafia on do historii Centrum powiadomień.
- **Schemat `claudetracker://`**: `session/<id>` przenosi do istniejącej sesji, `test-notification`
  wysyła próbne powiadomienie. Każda aplikacja lub strona może otworzyć taki link, ale nie uruchomi
  nim żadnej komendy.
- **Komenda „wznów sesję”** w schowku: ścieżka jest cytowana, a identyfikator sesji i nazwa konta
  muszą być zwykłymi tokenami (`[A-Za-z0-9._-]`), inaczej komenda nie powstaje.

## Skąd dane

| Dane | Źródło |
|---|---|
| Lista i status sesji | `~/.claude*/sessions/<pid>.json` (pisze Claude Code; martwe procesy odrzucane po czasie startu) |
| Tytuł, ostatnia odpowiedź | koniec transkryptu `~/.claude*/projects/<slug>/<sessionId>.jsonl` |
| Koszt | `message.usage` ze wszystkich transkryptów miesiąca (z subagentami), deduplikacja po `message.id`, liczone przyrostowo |
| Limity, zajętość kontekstu | dane statusline zapisane przez tap |

## Ograniczenia

- Format `sessions/*.json` jest wewnętrzny dla Claude Code i może się zmienić z wersją CLI.
- Koszt to szacunek według cennika API (bez rabatów batch i specjalnych umów). Na planie Max/Pro
  nie płacisz tych kwot. To miara zużycia.
- Widget odświeża się najwyżej co minutę (budżet WidgetKit).
- Dwie karty Warpa z identycznym tytułem mogą zmylić wyszukiwanie karty.
- Interfejs jest po polsku.

## Odinstalowanie

```bash
scripts/install-statusline-tap.sh --uninstall   # jeśli instalowałeś tap
rm -rf ~/Applications/Claude\ Tracker.app ~/Library/Application\ Support/ClaudeTracker
```

## Rozwój

```bash
swift test                                    # testy TrackerCore
swift build && .build/debug/ClaudeTracker     # bez bundla: bez powiadomień, widgetu i autostartu
CLAUDE_TRACKER_SNAPSHOT=/tmp/panel.png .build/debug/ClaudeTracker   # render panelu do PNG
scripts/make-icon.sh                          # odtwarza Resources/AppIcon.icns z maskotki
```

- `Sources/TrackerCore`: logika bez UI (parsowanie, statusy, koszty, limity, dopasowanie kart), pokryta testami.
- `Sources/ClaudeTracker`: aplikacja SwiftUI/AppKit (pasek menu, powiadomienia, Warp, widget).
- `Widget/`: rozszerzenie WidgetKit. `scripts/bundle.sh` kompiluje je `swiftc` razem ze źródłami
  TrackerCore, bo SwiftPM nie buduje rozszerzeń aplikacji.

### Ręczny test

1. Ikona w pasku menu pokazuje liczniki, klik otwiera panel, maskotki się animują.
2. Sesja kończy turę → niebieska kropka i powiadomienie „✅ …”; klik w wiersz lub powiadomienie → Warp na właściwej karcie, panel się zamyka.
3. Sesja prosi o zgodę → kafelek „czeka”, powiadomienie „⏳ …”.
4. Po `install-statusline-tap.sh --apply` i odświeżeniu statusline → paski limitów w panelu.
5. Edycja widżetów → „Claude Tracker”; klik w sesję w widżecie → Warp.

## Licencja

MIT, zobacz [LICENSE](LICENSE).
