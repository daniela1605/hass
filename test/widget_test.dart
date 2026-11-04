import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/controllers/saldo_proveedor_controller.dart';
import 'package:flutter_app/models/gestopago_models.dart';
import 'package:flutter_app/services/security_service.dart';
import 'package:flutter_app/services/xml_parser_service.dart';

void main() {
  group('Política de contraseñas por rol', () {
    test('el administrador exige contraseña más fuerte', () {
      expect(PoliticaRol.admin.validarPassword('password123'), isNotNull);
      expect(PoliticaRol.admin.validarPassword('Segura#2026x'), isNull);
    });

    test('el comprador acepta letras y números', () {
      expect(PoliticaRol.lector.validarPassword('password123'), isNull);
      expect(PoliticaRol.lector.validarPassword('corta1'), isNotNull);
    });
  });

  test('los códigos OTP tienen 6 dígitos', () {
    final c = SecurityService.generarCodigo();
    expect(c.length, 6);
    expect(SecurityService.compararCodigo(c, SecurityService.hashCodigo(c)), isTrue);
  });

  group('GestoPago XML Parser y Bolsa de Saldo', () {
    test('parsea nodos <P> y clasifica por idCatTipoServicio', () {
      const sampleXml = '''
      <PRODUCTOS>
        <P servicio="Telcel" producto="Recarga Telcel \$100" idServicio="1" idProducto="103" idCatTipoServicio="13" tipoFront="1" hasDigitoVerificador="false" precio="100.00" showAyuda="false" tipoReferencia="n">Leyenda Telcel</P>
        <P servicio="CFE" producto="CFE Luz" idServicio="10" idProducto="1001" idCatTipoServicio="5" tipoFront="2" hasDigitoVerificador="true" precio="0.00" showAyuda="true" tipoReferencia="a">Leyenda CFE</P>
        <P servicio="Netflix" producto="PIN Netflix \$300" idServicio="20" idProducto="2002" idCatTipoServicio="10" tipoFront="1" hasDigitoVerificador="false" precio="300.00" showAyuda="false" tipoReferencia="a">Leyenda Netflix</P>
      </PRODUCTOS>
      ''';

      final items = XmlParserService.instance.parseProductListXml(sampleXml);
      expect(items.length, 3);
      expect(items[0].categoria, CategoriaGestoPago.recargas);
      expect(items[1].categoria, CategoriaGestoPago.servicios);
      expect(items[2].categoria, CategoriaGestoPago.pines);
      expect(items[2].legend, 'Leyenda Netflix');
    });

    test('SaldoProveedorController inicia en \$2,500.00, abona, descuenta + comisión y simula \$0.00', () async {
      SharedPreferences.setMockInitialValues({});
      final ctrl = SaldoProveedorController.instance;
      await ctrl.reiniciarSaldoDemo();
      expect(ctrl.saldo, 2500.00);

      await ctrl.descontarSaldo(
        monto: 100.00,
        concepto: 'Recarga Telcel \$100',
        folioOficial: 'GP-AUTH-123456',
        metodoPago: 'Saldo GestoPago',
      );
      // 2500 - 100 + 2.50 de comisión = 2402.50
      expect(ctrl.saldo, 2402.50);

      await ctrl.simularSaldoCero();
      expect(ctrl.saldo, 0.00);
      expect(ctrl.cuentaConFondosSuficientes(50.0), isFalse);
    });
  });
}
