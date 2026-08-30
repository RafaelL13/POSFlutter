import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/sync/sync_operation.dart';

enum SyncErrorCategory {
  networkError('NETWORK_ERROR'),
  authenticationRequired('AUTHENTICATION_REQUIRED'),
  authorizationRejected('AUTHORIZATION_REJECTED'),
  validationRejected('VALIDATION_REJECTED'),
  conflict('CONFLICT'),
  serverError('SERVER_ERROR'),
  unsupportedOperation('UNSUPPORTED_OPERATION');

  const SyncErrorCategory(this.storageValue);
  final String storageValue;

  static SyncErrorCategory? tryParse(String? value) {
    for (final category in values) {
      if (category.storageValue == value) return category;
    }
    return null;
  }
}

enum SyncFailureDisposition { transient, terminal, actionRequired }

final class SyncFailure {
  const SyncFailure({
    required this.category,
    required this.code,
    required this.disposition,
    required this.message,
  });

  final SyncErrorCategory category;
  final String code;
  final SyncFailureDisposition disposition;
  final String message;

  bool get retryable => disposition == SyncFailureDisposition.transient;
  bool get requiresAction => !retryable;

  static SyncFailure fromOperationResult(SyncOperationResult result) {
    final code = result.errorCode;
    if (result.status == 'Conflict' || code == 'Conflict') {
      return _conflict(code ?? 'Conflict');
    }
    return switch (code) {
      'AuthorizationDenied' ||
      'DeviceReadOnly' ||
      'RoleDenied' => _authorization(code!),
      'ValidationFailed' => _validation(code!),
      'UnsupportedOperation' => _unsupported(code!),
      'ServerError' => _server(code!),
      _ when result.status == 'Retry' => _server(code ?? 'ServerError'),
      _ => _unsupported(code ?? 'UnknownRejection'),
    };
  }

  static SyncFailure fromException(Object exception) {
    if (exception case final CloudApiException cloud) {
      return switch (cloud.failure) {
        CloudFailure.unauthorized => const SyncFailure(
          category: SyncErrorCategory.authenticationRequired,
          code: 'AuthenticationRequired',
          disposition: SyncFailureDisposition.actionRequired,
          message: 'Vuelve a iniciar sesión para continuar sincronizando.',
        ),
        CloudFailure.forbidden => _authorization(
          cloud.errorCode ?? 'AuthorizationDenied',
        ),
        CloudFailure.validation => _validation(
          cloud.errorCode ?? 'ValidationFailed',
        ),
        CloudFailure.conflict => _conflict(cloud.errorCode ?? 'Conflict'),
        CloudFailure.network || CloudFailure.timeout => const SyncFailure(
          category: SyncErrorCategory.networkError,
          code: 'NetworkError',
          disposition: SyncFailureDisposition.transient,
          message: 'Sin conexión; los cambios permanecen pendientes.',
        ),
        CloudFailure.server ||
        CloudFailure.rateLimited => _server(cloud.errorCode ?? 'ServerError'),
        CloudFailure.notFound || CloudFailure.unexpected => _unsupported(
          cloud.errorCode ?? 'ProtocolError',
        ),
      };
    }
    return _server('UnexpectedError');
  }

  static SyncFailure fromPullException(Object exception) {
    if (exception is CloudApiException) return fromException(exception);
    return const SyncFailure(
      category: SyncErrorCategory.validationRejected,
      code: 'PullProtocolInvalid',
      disposition: SyncFailureDisposition.terminal,
      message: 'La respuesta remota requiere revisión antes de continuar.',
    );
  }

  static SyncFailure _authorization(String code) => SyncFailure(
    category: SyncErrorCategory.authorizationRejected,
    code: code,
    disposition: SyncFailureDisposition.actionRequired,
    message: code == 'DeviceReadOnly'
        ? 'Este dispositivo ya no puede sincronizar cambios operativos.'
        : 'Esta operación ya no está autorizada para sincronizarse.',
  );

  static SyncFailure _validation(String code) => SyncFailure(
    category: SyncErrorCategory.validationRejected,
    code: code,
    disposition: SyncFailureDisposition.terminal,
    message: 'La operación requiere revisión antes de sincronizarse.',
  );

  static SyncFailure _conflict(String code) => SyncFailure(
    category: SyncErrorCategory.conflict,
    code: code,
    disposition: SyncFailureDisposition.actionRequired,
    message: 'Existe un conflicto pendiente de resolución.',
  );

  static SyncFailure _server(String code) => SyncFailure(
    category: SyncErrorCategory.serverError,
    code: code,
    disposition: SyncFailureDisposition.transient,
    message: 'El servidor no pudo procesar el cambio; se reintentará.',
  );

  static SyncFailure _unsupported(String code) => SyncFailure(
    category: SyncErrorCategory.unsupportedOperation,
    code: code,
    disposition: SyncFailureDisposition.terminal,
    message: 'Esta operación requiere actualización o revisión del sistema.',
  );
}
