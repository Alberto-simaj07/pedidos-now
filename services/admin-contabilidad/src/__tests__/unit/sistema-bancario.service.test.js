const axios = require('axios');
const sistemaBancarioService = require('../../services/sistema-bancario.service');

jest.mock('axios');

describe('Sistema Bancario Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('transferencia', () => {
    it('debe realizar una transferencia correctamente', async () => {
      const transferencia = {
        cuenta_origen: '123456',
        cuenta_destino: '654321',
        monto: 500,
        concepto: 'pago a repartidor'
      };

      const mockResponse = {
        data: { id: 1, ...transferencia, estado: 'exitosa', fecha: '2026-04-27' }
      };

      axios.post.mockResolvedValue(mockResponse);

      const result = await sistemaBancarioService.transferencia(transferencia);

      expect(result).toEqual(mockResponse.data);
      expect(axios.post).toHaveBeenCalled();
    });

    it('debe rechazar transferencia sin fondos suficientes', async () => {
      const error = new Error('Fondos insuficientes');
      axios.post.mockRejectedValue(error);

      const transferencia = {
        cuenta_origen: '123456',
        cuenta_destino: '654321',
        monto: 999999
      };

      await expect(
        sistemaBancarioService.transferencia(transferencia)
      ).rejects.toThrow('Fondos insuficientes');
    });
  });

  describe('consultarSaldo', () => {
    it('debe consultar saldo de una cuenta', async () => {
      const mockResponse = {
        data: { cuenta: '123456', saldo: 1000, moneda: 'USD' }
      };

      axios.get.mockResolvedValue(mockResponse);

      const result = await sistemaBancarioService.consultarSaldo('123456');

      expect(result).toEqual(mockResponse.data);
      expect(axios.get).toHaveBeenCalledWith(
        expect.stringContaining('123456')
      );
    });
  });
});