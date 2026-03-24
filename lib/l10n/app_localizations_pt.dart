// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get instruction => 'Selecione o modo de marcha';

  @override
  String get connectionStatus => 'Status da Conexão';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get connecting => 'Conectando...';

  @override
  String get topic => 'Tópico';

  @override
  String get levantar => 'Levantar';

  @override
  String get andar => 'Andar';

  @override
  String get subir_escada => 'Subir Escada';
}
