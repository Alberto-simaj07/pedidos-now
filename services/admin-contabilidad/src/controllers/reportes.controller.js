const reportesService = require('../services/reportes.service');

const getPagosPorFecha = async (req, res) => {
    try {
        const { inicio, fin } = req.query;

        const data = await reportesService.getPagosPorFecha(inicio, fin);

        res.json(data);
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({ error: 'Error al obtener reporte' });
    }
} 

const getVentas = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getVentas(inicio, fin);
        res.json({
            total_ventas: Number(data.total_ventas)
        });
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({error: 'Error en ventas'});
    }
};

const getPedidos = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getPedidos(inicio, fin);
        res.json(data);
        console.log("inicio:", inicio, "fin", fin);
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });       
        res.status(500).json({error: 'Error en pedidos'});
    }
};

const getPropinas = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getPropinas(inicio, fin);
        res.json({
            total_propinas: Number(data.total_propinas)
        });
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({error:'Error en propinas'});
    }
};

const getCostos = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getCostos(inicio, fin);
        res.json({
            total_costos: Number(data.total_costos)
        });
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({error: 'Error en costos'});
    }
};

const getCrecimiento = async (req, res) => {
    console.log("Entrada de crecimiento")
    try {
        const data = await reportesService.getCrecimiento();
        res.json(data);
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });        
        res.status(500).json({error: 'Error en crecimiento'})
    }
};

const getChats = async (req, res) => {
    try {
        const data = await reportesService.getChats();
        res.json(data);
    } catch (error) {
        console.error({
            mensaje: error.message,
            stack: error.stack
        });
        res.status(500).json({error:'Error en chats'});
    }
};

const getUsuarios = async (req, res) => {
    try {
        const data = await reportesService.getUsuarios();
        res.json(data);
    } catch (error) {
        res.status(500).json({error: 'Error en usuarios'});
    }
};

const getPedidosExternos = async (req, res) => {
    const data = await reportesService.getPedidosExternos();
    res.json(data);
};

const getEstadisticasPorEntidad = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getEstadisticasPorEntidad(inicio, fin);
        const resultado = data.map(item => ({
            id: item.id,
            nombre_comercial: item.nombre_comercial,
            total_pedidos: Number(item.total_pedidos),
            total_descuentos: Number(item.total_descuentos)
        }));
        res.json(resultado);
    } catch (error) {
        res.status(500).json({error: 'Error en estadísticas por entidad'});
    }
};

const getReembolsosYCompensaciones = async (req, res) => {
    try {
        const {inicio, fin} = req.query;
        const data = await reportesService.getReembolsosYCompensaciones(inicio, fin);
        res.json(data);
    } catch (error) {
        res.status(500).json({error: 'Error en reembolsos/compensaciones'});
    }
}

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
    getReembolsosYCompensaciones,
    getEstadisticasPorEntidad
};