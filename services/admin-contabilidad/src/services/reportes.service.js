const reportesRepo = require('../repositories/reportes.repository');
const cobrosService = require('./cobros.service');

const getPagosPorFecha = (inicio, fin) => {
    return reportesRepo.getPagosPorFecha(inicio, fin);
};

const getVentas = (inicio, fin) => {
    return reportesRepo.getVentas(inicio, fin);
};

const getPedidos = (inicio, fin) => {
    return reportesRepo.getPedidos(inicio, fin);
}

const getPropinas = (inicio, fin) => {
    return reportesRepo.getPropinas(inicio, fin);
};

const getCostos = (inicio, fin) => {
    return reportesRepo.getCostos(inicio, fin);
};

const getCrecimiento = async() => {
    const data = await reportesRepo.getCrecimientoVentas();

    const hoy = Number(data.hoy);
    const ayer = Number(data.ayer);

    const crecimiento = data.ayer === 0
        ? 100
        : ((hoy - ayer) / ayer) * 100;
    
    return {
        hoy,
        ayer,
        crecimiento
    };
};

const getChats = async () => {
    try {
        const response = await axios.get('http://localhost:5000/chats');
        return response.data;
    } catch (error) {
        return {
            mensaje: 'Servicio de chats no disponible',
            fallback: true
        };
    }
};

const getUsuarios = async () => {
    try {
        const response = await axios.get('http://localhost:5001/usuarios');
        return response.data;
    } catch (error) {
        return {
            mensaje: 'Servicio de usuarios no disponible',
            fallback: true
        };
    }
};

const axios = require('axios');

const getPedidosExternos = async () => {
    try {
        const response = await axios.get('http://localhost:4000/pedidos');
        return response.data;
    } catch (error) {
        return {
            mensaje: 'Servicio externo no disponible',
            fallback: true
        };
    }
};

const getEstadisticasPorEntidad = (inicio, fin) => {
    return reportesRepo.getEstadisticasPorEntidad(inicio, fin);
};

const getReembolsosYCompensaciones = (inicio, fin) => {
    return reportesRepo.getReembolsosYCompensaciones(inicio, fin);
};

const getVentasConCobros = async (inicio, fin) => {
    // Obtengo datos locales
    const ventasLocales = await reportesRepo.getVentas(inicio, fin);
    
    // Obtengo datos de cobros (para validar)
    const cobros = await cobrosService.obtenerCobros(inicio, fin);
    
    // Concilio: ¿coinciden?
    return {
        ventas_locales: ventasLocales,
        cobros_externos: cobros,
        conciliado: ventasLocales.total === cobros.total
    };
};

module.exports = {
    getPagosPorFecha,
    getVentas,
    getPedidos,
    getPropinas,
    getCostos,
    getCrecimiento,
    getChats,
    getUsuarios,
    getPedidosExternos,
    getEstadisticasPorEntidad,
    getReembolsosYCompensaciones,
    getVentasConCobros
};