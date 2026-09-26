import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/auth_controller.dart';

@injectable
class LoginController extends AuthController {
  LoginController(super.sessionHolder);

  @override
  Future<void> submit(String email, String password) => run(() => sessionHolder.login(email, password));
}
