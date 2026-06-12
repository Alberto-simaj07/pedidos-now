const axios = require('axios');

const transferencia = async (data) => {
    try {
        const response = await axios.post(
            `${process.env.SISTEMA_BANCARIO_URL}/api/transferencias`,
            {
                cuenta_origen: data.cuenta_origen,
                cuenta_destino: data.cuenta_destino,
                monto: data.monto,
                concepto: data.concepto
            }
        );
        return response.data;
    } catch (error) {
        throw error;
    }
};

const consultarSaldo = async (cuenta_id) => {
    try {
        const response = await axios.get(
            `${process.env.SISTEMA_BANCARIO_URL}/api/cuentas/${cuenta_id}`
        );
        return response.data;
    } catch (error) {
        throw error;
    }
};

module.exports = { transferencia, consultarSaldo };